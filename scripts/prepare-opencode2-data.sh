#!/bin/sh

set -eu
LC_ALL=C
export LC_ALL

usage() {
    cat <<'EOF'
Usage: prepare-opencode2-data.sh SOURCE_VOLUME DESTINATION_VOLUME HELPER_IMAGE

Prepare and verify a whole-volume copy for a later OpenCode v2 startup. This
script does not run OpenCode or perform schema migration. Migration has not run on
success; it occurs when v2 starts with the prepared destination.

Host requirements: a POSIX shell and Docker CLI connected to the intended
daemon. Helper-image requirements (inside Linux container): /bin/sh, cp -a,
diff -qr --no-dereference, mkdir, ln, rm, mktemp, and writable /tmp. The helper
is run as root with no network and must already exist locally; it is never
pulled or built.

Before running, stop OpenCode and all other writers of the source volume and
keep them stopped through copying. Docker has no atomic cross-container volume
lock. The destination must be a new, unused name. Existing or partial
destinations are refused and never deleted or resumed; after a failed copy,
inspect the partial destination and choose another new name for a retry.
Docker cannot atomically combine the destination absence check with volume
creation. Another actor can create that name in the interval; exclusive
operator control of the destination name is required, and the helper still
refuses any destination found populated at mount time.

Example:
  sh /path/to/prepare-opencode2-data.sh other-repo-v1 other-repo-v2 local-helper:fixture

Check host CLI requirements with:
  command -v sh
  command -v docker

The helper image must provide these container-side commands/capabilities:
  /bin/sh
  cp -a
  diff -qr --no-dereference
  mkdir, ln, rm, mktemp
  writable /tmp

The script uses the active Docker connection. Endpoint precedence is
DOCKER_CONTEXT (selects that context and overrides DOCKER_HOST), then
DOCKER_HOST (overrides the selected context endpoint), then the selected
context's Docker endpoint. Verify the effective endpoint is the intended host,
not an unintended nested daemon.
EOF
}

usage_error() {
    printf '%s\n' "Error: $1" >&2
    printf '%s\n' 'Run with --help for usage.' >&2
    exit 2
}

if [ "$#" -eq 1 ] && [ "$1" = '--help' ]; then
    usage
    exit 0
fi
[ "$#" -eq 3 ] || usage_error 'expected exactly three arguments'
[ -n "$1" ] || usage_error 'source volume must not be empty'
[ -n "$2" ] || usage_error 'destination volume must not be empty'
[ -n "$3" ] || usage_error 'helper image must not be empty'

source_volume=$1
destination_volume=$2
helper_image=$3
[ "$source_volume" != "$destination_volume" ] || usage_error 'source and destination volumes must differ'

valid_volume_name() {
    case "$1" in
        [!a-zA-Z0-9]*|'') return 1 ;;
        *[!a-zA-Z0-9_.-]*) return 1 ;;
    esac
    [ "${#1}" -ge 2 ]
}

valid_volume_name "$source_volume" || usage_error 'invalid source Docker volume name'
valid_volume_name "$destination_volume" || usage_error 'invalid destination Docker volume name'

destination_may_be_partial=0
failure_reported=0
# Invoked indirectly by the EXIT trap below.
# shellcheck disable=SC2329
on_exit() {
    exit_status=$?
    if [ "$destination_may_be_partial" -eq 1 ] && [ "$exit_status" -ne 0 ] && [ "$failure_reported" -eq 0 ]; then
        failure_reported=1
        printf 'Warning: destination volume %s may be partial; it was not deleted. Inspect it and use a new destination name to retry.\n' "$destination_volume" >&2
    fi
    exit "$exit_status"
}
trap on_exit 0
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

docker_context=$(docker context show) || {
    printf '%s\n' 'Error: unable to determine the active Docker context.' >&2
    exit 1
}
[ -n "$docker_context" ] || {
    printf '%s\n' 'Error: Docker returned an empty active context.' >&2
    exit 1
}
context_endpoint=$(docker context inspect --format '{{ (index .Endpoints "docker").Host }}' "$docker_context") || {
    printf 'Error: unable to inspect the Docker endpoint for context %s.\n' "$docker_context" >&2
    exit 1
}
[ -n "$context_endpoint" ] || {
    printf 'Error: Docker returned an empty endpoint for context %s.\n' "$docker_context" >&2
    exit 1
}
if [ -n "${DOCKER_CONTEXT:-}" ]; then
    effective_endpoint=$context_endpoint
    endpoint_source='DOCKER_CONTEXT (overrides DOCKER_HOST)'
elif [ -n "${DOCKER_HOST:-}" ]; then
    effective_endpoint=$DOCKER_HOST
    endpoint_source='DOCKER_HOST (overrides selected context endpoint)'
else
    effective_endpoint=$context_endpoint
    endpoint_source='selected Docker context endpoint'
fi
docker_daemon=$(docker info --format '{{.Name}}') || {
    printf '%s\n' 'Error: cannot access the Docker daemon for the active context.' >&2
    exit 1
}
[ -n "$docker_daemon" ] || {
    printf '%s\n' 'Error: Docker returned an empty daemon identity for the active connection.' >&2
    exit 1
}
printf 'Docker context: %s\n' "$docker_context"
printf 'Selected context endpoint: %s\n' "$context_endpoint"
printf 'Effective Docker endpoint: %s (%s)\n' "$effective_endpoint" "$endpoint_source"
printf 'Docker daemon: %s (active Docker CLI connection; DOCKER_CONTEXT/DOCKER_HOST may override defaults)\n' "$docker_daemon"
printf 'Source volume: %s\nDestination volume: %s\n' "$source_volume" "$destination_volume"
printf '%s\n' 'Ensure OpenCode and all other writers of the source remain stopped; Docker does not provide an atomic volume lock.'

if ! docker volume inspect "$source_volume" >/dev/null; then
    printf 'Error: source volume %s does not exist or cannot be inspected.\n' "$source_volume" >&2
    exit 1
fi

volume_exists() {
    volume_listing=$(docker volume ls --format '{{.Name}}') || {
        printf '%s\n' 'Error: unable to list Docker volumes; destination absence cannot be established.' >&2
        return 2
    }
    newline=$(printf '\n_')
    newline=${newline%_}
    case "$newline$volume_listing$newline" in
        *"$newline$1$newline"*) return 0 ;;
        *) return 1 ;;
    esac
}

if volume_exists "$destination_volume"; then
    printf 'Error: destination volume %s already exists; existing destinations are never merged or reused.\n' "$destination_volume" >&2
    exit 1
else
    volume_status=$?
    [ "$volume_status" -eq 1 ] || exit 1
fi

check_consumers() {
    consumer_names=$(docker ps --filter "volume=$1" --format '{{.Names}}') || {
        printf 'Error: unable to check running containers using volume %s.\n' "$1" >&2
        return 1
    }
    if [ -n "$consumer_names" ]; then
        printf 'Error: stop these running containers using volume %s before continuing:\n%s\n' "$1" "$consumer_names" >&2
        return 1
    fi
}

check_consumers "$source_volume" || exit 1
check_consumers "$destination_volume" || exit 1

image_id=$(docker image inspect --format '{{.Id}}' "$helper_image") || {
    printf 'Error: helper image %s is unavailable locally or cannot be inspected; no image is pulled.\n' "$helper_image" >&2
    exit 1
}
case "$image_id" in
    sha256:*) image_digest=${image_id#sha256:} ;;
    *) image_digest= ;;
esac
case "$image_digest" in
    ''|*[!0123456789abcdefABCDEF]*)
        printf 'Error: helper image %s did not resolve to a valid immutable sha256 image ID.\n' "$helper_image" >&2
        exit 1
        ;;
esac
[ "${#image_digest}" -eq 64 ] || {
    printf 'Error: helper image %s did not resolve to a valid immutable sha256 image ID.\n' "$helper_image" >&2
    exit 1
}

# This is literal code passed to the isolated helper shell; defer expansion there.
# shellcheck disable=SC2016
preflight_script='set -eu
probe=$(mktemp -d /tmp/data-copy-preflight.XXXXXX)
trap '\''rm -rf "$probe"'\'' 0
mkdir "$probe/source" "$probe/destination"
printf probe > "$probe/source/.hidden"
ln -s missing-target "$probe/source/dangling-link"
cp -a "$probe/source/." "$probe/destination/"
diff -qr --no-dereference "$probe/source" "$probe/destination" >/dev/null 2>&1
'
if ! docker run --rm --pull=never --network=none --user 0:0 --entrypoint /bin/sh "$image_id" -c "$preflight_script" DATA_COPY_PREFLIGHT; then
    printf '%s\n' 'Error: helper image failed the required cp -a and recursive symlink-aware diff preflight.' >&2
    exit 1
fi

if volume_exists "$destination_volume"; then
    printf 'Error: destination volume %s appeared during preflight; refusing to use it.\n' "$destination_volume" >&2
    exit 1
else
    volume_status=$?
    [ "$volume_status" -eq 1 ] || exit 1
fi

destination_may_be_partial=1
if ! docker volume create "$destination_volume" >/dev/null; then
    printf 'Error: unable to create destination volume %s.\n' "$destination_volume" >&2
    exit 1
fi

check_consumers "$source_volume" || exit 1
check_consumers "$destination_volume" || exit 1

# This is literal code passed to the isolated helper shell; defer expansion there.
# shellcheck disable=SC2016
transfer_script='set -eu
for path in /destination/* /destination/.[!.]* /destination/..?*; do
    if [ -e "$path" ] || [ -L "$path" ]; then
        printf "%s\\n" "Error: destination must be empty before copy" >&2
        exit 1
    fi
done
cp -a /source/. /destination/
diff -qr --no-dereference /source /destination >/dev/null 2>&1
'
if ! docker run --rm --pull=never --network=none --user 0:0 --entrypoint /bin/sh \
    --mount "type=volume,src=$source_volume,dst=/source,readonly,volume-nocopy" \
    --mount "type=volume,src=$destination_volume,dst=/destination,volume-nocopy" \
    "$image_id" -c "$transfer_script" DATA_COPY_TRANSFER; then
    printf 'Error: copy or verification failed for destination volume %s.\n' "$destination_volume" >&2
    exit 1
fi

destination_may_be_partial=0
printf 'Preparation complete: verified copy in %s.\n' "$destination_volume"
printf '%s\n' 'OpenCode schema migration has not run; it occurs only when v2 starts with this volume.'
exit 0
