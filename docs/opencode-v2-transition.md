# OpenCode v1 to v2 data transition

This runbook describes a one-time, host-side, copy-then-migrate transition for
Docker-volume-backed OpenCode installations. It is reusable in downstream
repositories: the preparation script takes explicit volume and image arguments
and does not require this repository's checkout when run. Each consumer still
needs its own recipe/image and mount update.

The preparation script copies data only. It does not start OpenCode or migrate
the database. The pinned v2 application performs its built-in migration the
first time it starts with the copied destination volume. Keep the original v1
volume untouched for rollback.

## 1. Identify the host daemon, source, and consumers

Run these commands on the Docker host, outside the devcontainer. The devcontainer
may use Docker-in-Docker; its nested daemon is not the host daemon that owns the
data volume. Select and verify the intended host Docker context before continuing:

```sh
docker context show
docker info --format '{{.Name}} {{.DockerRootDir}}'
```

Set `V1_CONTAINER` to the currently running v1 devcontainer for this workspace.
Inspect its actual mount and image rather than assuming a volume name:

```sh
V1_CONTAINER=replace-with-container-name-or-id
docker inspect --format '{{json .Mounts}}' "$V1_CONTAINER"
docker inspect --format '{{.Config.Image}}' "$V1_CONTAINER"
```

Find the mount whose destination is `/root/.local/share/opencode`. Record its
named Docker volume as `SOURCE_VOLUME`. Stop and investigate if the data is a
bind mount, an external credential store, or a custom database location rather
than the supported named-volume layout. Record the host workspace path with
`pwd`; use that same path for the v2 reopen so OpenCode can retain project
association. Before stopping the container, write down several known session
IDs and identify important conversations, including archived and child
sessions, if present.

List every running container that mounts the discovered volume:

```sh
SOURCE_VOLUME=replace-with-discovered-volume
docker ps --filter "volume=$SOURCE_VOLUME" --format 'table {{.ID}}\t{{.Names}}\t{{.Image}}'
```

A source volume may be shared by multiple projects and devcontainers. Identify
all of them, including consumers of other repositories, and record the
workspace paths and representative session IDs for each. A single source is
copied once for a shared destination; consumers that need independent histories
must use distinct destination volumes. Changing an image or devcontainer
configuration in another repository is a separate, manual change outside this
rollout.

## 2. Prepare a standalone script and local helper image

Obtain a standalone copy of `scripts/prepare-opencode2-data.sh` before stopping
containers. For this repository, from its checkout on the host:

```sh
cp scripts/prepare-opencode2-data.sh "$HOME/prepare-opencode2-data.sh"
```

For a downstream repository, copy or transfer that one script to a host path
before shutdown; running it later does not require the devcontainer repository
checkout. Read its usage with:

```sh
sh "$HOME/prepare-opencode2-data.sh" --help
```

Choose a helper image already present in the intended host daemon. The running
v1 container's immutable image ID is a useful local choice and avoids depending
on a registry tag being available:

```sh
HELPER_IMAGE=$(docker inspect --format '{{.Image}}' "$V1_CONTAINER")
docker image inspect --format '{{.Id}}' "$HELPER_IMAGE"
```

The script resolves and uses that local image ID, preflights the container-side
tools before creating a destination, and runs its helper with no network. It
does not pull or build an image. The helper must provide `/bin/sh`, `cp -a`,
recursive `diff` with `--no-dereference`, `mkdir`, `ln`, `rm`, `mktemp`, and a
writable `/tmp`. Confirm the active Docker context/connection is the host daemon
that owns the source, including any `DOCKER_CONTEXT` or `DOCKER_HOST` overrides.

## 3. Quiesce all source writers and copy

Close OpenCode and stop each container that uses the source volume, including
consumers in other repositories. Stop any other process that can write the
volume. Keep the workspace checkout and its host path intact. Keep all writers
stopped until the copy and pre-cutover inventory are complete: a live copy is
not a SQLite-consistent backup, and Docker has no atomic cross-container volume
lock.

Set all three explicit operands. For a downstream consumer, use the discovered
source, a genuinely new destination name, and the local helper image:

```sh
SOURCE_VOLUME=replace-with-discovered-volume
DESTINATION_VOLUME=replace-with-new-volume-name
HELPER_IMAGE=replace-with-local-image-id
sh "$HOME/prepare-opencode2-data.sh" "$SOURCE_VOLUME" "$DESTINATION_VOLUME" "$HELPER_IMAGE"
```

For this repository, the configured pair is:

```sh
SOURCE_VOLUME=devcontainer-opencode-data
DESTINATION_VOLUME=devcontainer-opencode2-data
HELPER_IMAGE=$(docker inspect --format '{{.Image}}' "$V1_CONTAINER")
sh "$HOME/prepare-opencode2-data.sh" "$SOURCE_VOLUME" "$DESTINATION_VOLUME" "$HELPER_IMAGE"
```

The script copies the whole volume tree, including hidden entries, credentials,
the database and any SQLite WAL/SHM sidecars, then compares the copied tree. It
does not copy only `opencode.db`. Success means the copy was prepared and
verified; schema migration has not run. A failure after destination creation
means the destination may be partial. The script deliberately leaves it in
place: inspect it, then choose another new destination name for a retry. It
never merges into or automatically removes a destination or alters the source.
Docker cannot atomically combine checking that a destination name is unused
with creating it, so retain exclusive operator control of that name throughout
the operation.

If v2 was reopened prematurely, Docker may have created or initialized an
empty destination. Do not copy over or reuse that name. Stop that v2 consumer,
leave both volumes for inspection, choose a different new destination, and
update the v2 mount to that exact name before reopening. Do not open the source
with v2.

## 4. Inventory and cut over

Before the v2 start, record a complete v1 session inventory from the stopped
source volume. The read-only SQLite examples below require a local Linux helper
image with `/bin/sh` and `sqlite3`; set `SQLITE_HELPER_IMAGE` to its local image ID and
verify it with `docker image inspect`. This is a separate inventory helper, not
a host Python requirement or an extra requirement for the copy script. Run
these only after all OpenCode servers using the relevant volume have stopped.
The queries return session IDs and counts only; they do not read credentials.

For v1, list every `session` ID (including archived and child sessions) and
record the count:

```sh
set -eu
SOURCE_VOLUME=replace-with-discovered-volume
SQLITE_HELPER_IMAGE=replace-with-local-sqlite-helper-image-id
docker run --rm --pull=never --network=none \
  --mount "type=volume,src=$SOURCE_VOLUME,dst=/data,readonly,volume-nocopy" \
  --entrypoint /bin/sh "$SQLITE_HELPER_IMAGE" -c \
  "sqlite3 -readonly -noheader /data/opencode.db 'SELECT id FROM session ORDER BY id;'" \
  > v1-session-ids.txt
wc -l < v1-session-ids.txt
docker run --rm --pull=never --network=none \
  --mount "type=volume,src=$SOURCE_VOLUME,dst=/data,readonly,volume-nocopy" \
  --entrypoint /bin/sh "$SQLITE_HELPER_IMAGE" -c \
  "sqlite3 -readonly -noheader /data/opencode.db 'SELECT count(*) FROM session;'"
```

Because each query is a simple command under `set -e`, a failed ID query exits
before `wc` can run or report a count. The count query also stops the sequence
if it fails.

Do not start v2 until the preparation script succeeds and the copy/source
inventory is recorded. Switch the image recipe and data mount together, then
rebuild/reopen the same workspace. For this repository the v2 selection is
`../Dockerfile.OpenCode2`, build context `..`, and mount
`devcontainer-opencode2-data` at `/root/.local/share/opencode`. In VS Code use
**Dev Containers: Rebuild and Reopen in Container** (or **Rebuild Container**
if already attached). Downstream consumers must select their own v2
recipe/image and new destination mount using their normal devcontainer workflow;
this repository's configuration does not update them.

## 5. Wait for migration and verify continuity

In the reopened v2 container, verify the installed pin and data/database paths:

```sh
opencode --version
opencode debug paths
opencode debug paths db
```

The expected pin in this repository's `Dockerfile.OpenCode2` is `2.0.29`. The
reported data directory must correspond to the mounted persistent volume, and
the database path must be the location being checked. Stop if a custom
`OPENCODE_DB` override or another database location is in use.

Run the following from the workspace/repository directory inside the reopened
v2 devcontainer, using the background service for that v2 workspace. First
check that the service is running; if it is stopped, start it and check again.
Service startup may perform migration, so do this only after the verified copy
and v2 cutover:

```sh
opencode service status
opencode service start  # only if status reports stopped
opencode service status
```

Once the v2 service reports running, query its migration status and inspect
startup/server logs for migration warnings or errors:

```sh
opencode api experimental.migration.v1.status
opencode debug paths log
```

Review the Dev Containers startup output and OpenCode server logs at the
reported log directory. Treat a completed marker as necessary but not
sufficient: malformed rows can be skipped with warnings. The CLI command form
is `opencode api <operation>`; it sends the operation to the running service.
If the service is not ready or the operation is unavailable, record the exact
status/response and investigate rather than assuming migration completed. Do
not replace the migrated destination with a v1 copy after v2 has started.

For an exact ID comparison, stop the v2 server again before querying its
database, then inventory every `session_v2` ID in the destination with the same
read-only helper image:

```sh
set -eu
DESTINATION_VOLUME=replace-with-prepared-v2-volume
SQLITE_HELPER_IMAGE=replace-with-local-sqlite-helper-image-id
docker run --rm --pull=never --network=none \
  --mount "type=volume,src=$DESTINATION_VOLUME,dst=/data,readonly,volume-nocopy" \
  --entrypoint /bin/sh "$SQLITE_HELPER_IMAGE" -c \
  "sqlite3 -readonly -noheader /data/opencode.db 'SELECT id FROM session_v2 ORDER BY id;'" \
  > v2-session-ids.txt
wc -l < v2-session-ids.txt
docker run --rm --pull=never --network=none \
  --mount "type=volume,src=$DESTINATION_VOLUME,dst=/data,readonly,volume-nocopy" \
  --entrypoint /bin/sh "$SQLITE_HELPER_IMAGE" -c \
  "sqlite3 -readonly -noheader /data/opencode.db 'SELECT count(*) FROM session_v2;'"
diff -u v1-session-ids.txt v2-session-ids.txt
```

As with the v1 inventory, each query is a simple command under `set -e`; a
failed ID query exits before `wc` can run, and a failed count query stops before
the ID comparison.

Compare complete ID sets, not only the default session list, which may omit
archived or child sessions. Investigate any missing or extra ID. Do not use
message or part counts as a one-for-one migration measure. After inventory,
reopen v2 and inspect representative known conversations and transcripts,
including relevant tool output and attachments, in OpenCode.

Check that saved account entries are present without printing secrets:

```sh
opencode auth list
```

Then interactively confirm access with a small, read-only provider request.
Never use `opencode auth export` or display credential values as a verification
step. The migration imports recognized legacy API-key and OAuth credential
forms, but provider acceptance and token refresh are provider-dependent. Sign
in again only if the provider interaction fails.

Finally, recreate/rebuild the v2 devcontainer using the same destination volume
and workspace path. Recheck the known migrated sessions and a newly created
session to confirm persistence.

The locally installed `sst-dev.opencode` 1.0.0 extension package declares
**Cmd+Option+K** on macOS and **Ctrl+Alt+K** on Windows/Linux for inserting a
file reference. Verify the shortcut in VS Code after cutover; extension
metadata/source inspection does not replace interactive verification.

**Human GUI verification remains pending.** In VS Code, run the extension's
**Open opencode** command to launch v2, inspect a representative migrated
conversation, and verify file-reference insertion with the declared shortcut.
If no provider is connected or the read-only request cannot authenticate, use
`/connect` to connect an account, then submit a small read-only prompt (for
example, ask for a brief summary of the current repository without requesting
changes). Confirm the response and account access without exposing credentials.
Record the actual VS Code/extension behavior; the command and shortcut names
above come from installed extension metadata and are not evidence of interactive
success.

## Migration limitations

The pinned `2.0.29` migration is a transformation, not a lossless database
copy. In particular:

- Saved session permissions and pending revert state are cleared.
- Incomplete tools become interrupted-tool errors.
- Malformed messages or parts can be skipped with warnings even if migration
  reports completion.
- Embedded attachments are converted; non-embedded attachments can become
  unavailable notices.
- Compaction and synthetic history are transformed, and message/part counts
  need not match one-for-one. Older cleared tool output cannot be recovered.
- Recognized saved API keys and OAuth tokens are imported, but token refresh
  and successful authentication depend on the provider.

The verified copy spike supports migration of representative history and
credential presence, not every real history, attachment, or OAuth refresh case.
Retaining the original volume is the recovery path for the original v1 data.

## Rollback

Stop the v2 consumers explicitly. Restore both the v1 image/recipe selection
and the original data mount; changing only one can pair an incompatible binary
and database. For this repository restore:

```text
Dockerfile: ../Dockerfile.OpenCode
Context:    ..
Mount:      devcontainer-opencode-data → /root/.local/share/opencode
```

Downstream consumers restore their own prior v1 recipe/image and original
source mount. Preserve both volumes, keep the original workspace path, and
rebuild/reopen. Verify the v1 version and several known pre-cutover sessions.
Never mount the migrated v2 volume into v1. Do not remove either volume as part
of rollback.

The v1 source and v2 destination are cutover snapshots, not synchronized
histories. V2 sessions created after cutover remain only in the v2 volume; v1
activity after cutover is absent from the v2 copy. There is no automatic reverse
migration or history merge. OAuth refresh or revocation may affect credentials
in the retained snapshot even when its volume bytes are unchanged, so rollback
may require signing in again.
