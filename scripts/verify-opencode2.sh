#!/bin/sh
set -eu

usage() {
    printf 'Usage: sh %s IMAGE_REFERENCE\n' "$0" >&2
}

if [ "$#" -ne 1 ] || [ -z "$1" ]; then
    usage
    exit 2
fi

image_reference=$1
script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
dockerfile="$script_dir/../Dockerfile.OpenCode2"

if [ ! -f "$dockerfile" ]; then
    printf 'verify-opencode2: Dockerfile not found: %s\n' "$dockerfile" >&2
    exit 1
fi

if ! expected=$(awk '
    /^ARG OPENCODE_VERSION=/ {
        count++
        value = substr($0, index($0, "=") + 1)
    }
    END {
        if (count != 1 || value == "") {
            exit 1
        }
        print value
    }
' "$dockerfile"); then
    printf 'verify-opencode2: expected exactly one non-empty OPENCODE_VERSION pin in %s\n' "$dockerfile" >&2
    exit 1
fi

if [ -z "$expected" ]; then
    printf 'verify-opencode2: OPENCODE_VERSION pin is empty in %s\n' "$dockerfile" >&2
    exit 1
fi

if ! image_id=$(docker image inspect --format '{{.Id}}' "$image_reference"); then
    printf 'verify-opencode2: failed to inspect local image %s\n' "$image_reference" >&2
    exit 1
fi
case "$image_id" in
    sha256:*) image_digest=${image_id#sha256:} ;;
    *) image_digest= ;;
esac
if [ "${#image_digest}" -ne 64 ]; then
    printf 'verify-opencode2: invalid or empty image ID for %s: %s\n' "$image_reference" "$image_id" >&2
    exit 1
fi
case "$image_digest" in
    *[!0123456789abcdef]*)
        printf 'verify-opencode2: invalid or empty image ID for %s: %s\n' "$image_reference" "$image_id" >&2
        exit 1
        ;;
esac

if ! docker run --rm --pull=never "$image_id" cat /usr/local/share/asdf-tool-versions; then
    printf 'verify-opencode2: metadata check failed for image %s\n' "$image_id" >&2
    exit 1
fi

if ! actual=$(docker run --rm --pull=never "$image_id" opencode --version); then
    printf 'verify-opencode2: version check failed for image %s\n' "$image_id" >&2
    exit 1
fi
actual=${actual##* }
actual=${actual#v}

if [ -z "$actual" ]; then
    printf 'verify-opencode2: version output was empty; expected %s\n' "$expected" >&2
    exit 1
fi
if [ "$actual" != "$expected" ]; then
    printf 'verify-opencode2: version mismatch: expected %s, actual %s\n' "$expected" "$actual" >&2
    exit 1
fi

printf 'OpenCode v2 image verified: %s\n' "$actual"
