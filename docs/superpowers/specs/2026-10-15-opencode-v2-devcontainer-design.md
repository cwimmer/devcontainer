# OpenCode V2 Repository Devcontainer and Copy-Then-Migrate Transition

**Date:** 2026-10-15
**Status:** Approved by the user on 2026-10-15
**Repository:** `cwimmer/devcontainer`

## Intent

Complete part three of the rollout: develop this repository in its existing
Dockerfile-based devcontainer using pinned OpenCode v2, carrying existing v1
sessions and saved authentication forward through a verified copy, and retaining
an untouched v1 rollback source.

This repository's images support devcontainers in many other repositories. The
one-time transition must therefore be documented in prose and provided as a
portable, repository-independent shell script. Changing this repository's own
devcontainer does not switch downstream repositories automatically.

## Decisions and scope

The user approved copy-then-migrate in principle and requested this written spec
for approval before implementation. The user explicitly excluded global-config
persistence from this rollout. There will be no configuration-volume addition,
configuration-directory migration, or further global-settings work.

Required changes:

- Select the existing `../Dockerfile.OpenCode2`, retaining build context `..`.
- Replace this repository's v1 data mount with independent v2 data persistence.
- Provide an explicitly invoked, portable script that copies the whole stopped
  v1 volume to a new v2 volume and verifies the copy before OpenCode can migrate it.
- Document the complete operational transition, acceptance checks, and rollback.
- Verify the actual devcontainer, including features and mounts, and inspect the
  repository command/editor integration for demonstrated compatibility issues.

Preserve Docker-in-Docker, unrelated editor customizations, and existing feature
lock resolutions. Preserve unrelated working-tree changes. Do not change image
recipes, pins, upgrade selection, image workflows, registry tags, other
repositories, or v1 availability. Do not introduce a general migration framework,
plugin migration, dependency refresh, or automatic lifecycle migration hook.

## Inspected context

- `.devcontainer/devcontainer.json` builds `../Dockerfile.OpenCode` with context
  `..` and mounts `devcontainer-opencode-data` at `/root/.local/share/opencode`.
- Docker-in-Docker feature options are `version: latest`, `moby: false`, and
  `enableNonRootDocker: "true"`. The feature lock resolves version `2.17.0` at
  digest `sha256:25b9f05705ffba7dbe503230ac76081419306f8c8bc88e0ce78c4ecd99a0c78c`.
- VS Code extensions include `sst-dev.opencode` and three unrelated editor tools.
- `Dockerfile.OpenCode2` installs standalone OpenCode `2.0.29` and asserts its
  version. `Dockerfile.OpenCode` currently pins v1 `1.19.0`.
- `.opencode/commands/update-devcontainer.md` has a model override and documents
  all three image variants. The tracked `.opencode/package-lock.json` references
  v1 plugin dependencies; the manifest and Bun lock are ignored generated files.
  No repository plugin implementation or explicit plugin loading config was found.
- Inspected installed `sst-dev.opencode` `1.0.0` launches `opencode` in a terminal
  and inserts file references; it has no demonstrated v1 API requirement.
- Preliminary v2 server startup succeeded, but API command discovery returned an
  empty registry despite recognizing the repository configuration directory.
  Discovery remains an investigation item, not proof that the command works.
- Reviewed test fixes are committed in `6ea2629`. At inspection, the working tree
  contains an unrelated Superpowers submodule pointer change and untracked
  `.DS_Store` files.
- The available Docker daemon is ARM64 and has no real
  `devcontainer-opencode-data` volume. This limits actual-user-data verification.

Repository instructions, README, tests/helpers, OpenCode metadata, recent commits,
and the preceding v2 rollout designs and test-refactor design were inspected.
The repository-local Superpowers brainstorming skill was consulted. The
wiki-context skill is unavailable; repository documentation was read directly.
These documents provide context without overriding the user's scope.

## Upstream evidence and migration limits

### Paths and migration implementation

Observed `opencode debug paths` in pinned `2.0.29` reports the data directory as
`/root/.local/share/opencode` and database as `opencode.db` beneath it. This agrees
with the official [v2 CLI paths documentation](https://opencode.ai/v2/docs/cli/)
and [troubleshooting documentation](https://opencode.ai/v2/docs/troubleshooting/).
V1 and v2 sharing a default path does not imply database backward compatibility.

Inspected pinned upstream source:

- [V1 session migration](https://github.com/anomalyco/opencode/blob/v2.0.29/packages/core/src/database/v1-migration.bun.ts)
- [Legacy credential import](https://github.com/anomalyco/opencode/blob/v2.0.29/packages/core/src/database/migration/20260805200742_import_legacy_credentials.ts)
- [Session-permission reset](https://github.com/anomalyco/opencode/blob/v2.0.29/packages/core/src/database/migration/20260910120000_clear_v1_session_permission.ts)

V2 starts the built-in migration when its server initializes. It transforms
legacy sessions/messages, maintains a migration progress/completion marker, and
imports recognized legacy credentials from `auth.json` into its database.
Recognized credential forms include API keys and OAuth tokens. Authentication
success and token refresh still depend on the external provider.

Known transformations must be disclosed in the transition instructions:

- Saved session permissions and pending revert state are cleared.
- Incomplete tools become interrupted-tool errors.
- Malformed messages/parts can be skipped with warnings even when migration
  ultimately reports completion.
- Embedded file attachments are converted; non-embedded attachments can become
  attachment-unavailable notices.
- Compaction and synthetic history are transformed; message/part counts are not
  expected to match one-for-one. Older cleared tool output cannot be recovered.

Do not promise lossless preservation of every internal v1 setting or history
representation. Retaining the original volume preserves the original data.

### Isolated investigation results

On the available native ARM64 daemon, disposable volumes and existing v1/v2
images were used to test the transition. No real credentials or user data were
used. V1's API created a session and user message with `noReply`; synthetic
assistant/tool database fixtures supplied additional history without model calls.

Observed:

- The whole-directory copy matched source file hashes before migration.
- V2 reported `2.0.29` and migration status `completed`.
- Session ID/title, user text, assistant text, completed tool output, agent/model
  selection, and token totals survived migration.
- A synthetic saved v1 API key was imported.
- Migrated history remained accessible from a recreated v2 container.
- No migration skip/failure warnings were observed for that fixture.
- The original volume's file hashes remained unchanged after migration.

Probe containers and volumes were removed after investigation. The probe script
was temporary, outside the repository. These are standalone migration-spike
results, not actual-devcontainer or interactive dogfooding evidence. OAuth
renewal, complex real histories, attachments, and actual user-volume migration
remain unverified.

## Approaches considered

1. **Copy the whole volume, then run built-in migration (chosen).** Carries
   sessions and saved authentication forward and preserves a v1 rollback source.
2. **Migrate the original volume in place.** Fewer preparation steps, but changes
   the rollback source and requires restoring a separate backup to return to v1.
3. **Export/import individual sessions.** Does not replace a complete data copy
   and adds per-session handling for no demonstrated benefit.

## Detailed design

### 1. This repository's devcontainer

Change only the relevant selection and data mount:

```json
"build": {
    "context": "..",
    "dockerfile": "../Dockerfile.OpenCode2"
}
```

```text
source=devcontainer-opencode2-data,target=/root/.local/share/opencode,type=volume
```

Keep the existing Docker-in-Docker feature/options, extension list, and feature
lock byte-for-byte unless actual compatibility evidence requires a narrowly
scoped change. Any consequential change to these decisions returns for approval.
Do not add migration to initialize/post-create/post-start lifecycle commands.

Docker creates an empty named volume when a missing mount source is used.
Documentation must therefore place the copy step **before** first v2 reopen or
startup. A premature reopen must not lead to overwriting an existing destination;
use a new destination name and update the mount deliberately instead.

### 2. Portable preparation script

Add `scripts/prepare-opencode2-data.sh`, executable and runnable with POSIX `sh`:

```sh
sh /path/to/prepare-opencode2-data.sh SOURCE_VOLUME DESTINATION_VOLUME HELPER_IMAGE
```

All three arguments are required. `--help` explains requirements and examples.
There are no repository-derived defaults. The script must work from any working
directory and when copied independently to another machine or repository.

The host needs a POSIX shell and Docker CLI with access to the intended daemon.
The script does not require host Bash, Python, Node.js, GNU utilities, or a local
checkout. It does not require OpenCode in the helper image. The supplied local
Linux helper image must provide `/bin/sh`, `cp -a`, and recursive `diff` including
`--no-dereference`; the existing devcontainer images supply these tools. The
helper requirements are container-side, so host portability includes macOS and
Linux and a POSIX environment with Docker access on Windows.

Contract:

1. Validate exactly three nonempty arguments; reject equal source/destination
   names and invalid Docker volume names. Treat image references as quoted
   arguments, never evaluated shell text.
2. Check daemon access. Print the selected Docker context and volume names, and
   explain that operations use the active Docker connection, including Docker's
   normal environment overrides. Do not select another daemon/context implicitly.
3. Require the source volume to exist, using `docker volume inspect` before any
   mount, so a typo cannot silently create an empty source.
4. Require the destination not to exist. Refuse both empty and populated existing
   destinations; never merge, replace, delete, or resume into one.
5. Reject running containers mounting the source or destination. Name the
   containers so the operator can stop them explicitly. Never stop containers
   itself. State that all other writers must remain stopped for the operation;
   Docker offers no atomic cross-container volume lock.
6. Resolve the supplied helper image to a local immutable image ID. Fail if
   missing. Preflight the required helper tools before creating the destination.
   All helper runs use `--pull=never`, the resolved ID, root user, and an explicit
   `/bin/sh` entrypoint. No image pull, build, OpenCode startup, network access, or
    database migration is performed by the script. Use `--network=none` for
    helper containers so copying cannot initiate external connections.
7. Create the new destination volume, then recheck running consumers before
   copying. Mount the source read-only and destination read-write, using explicit
    `--mount type=volume` arguments with volume copy-up disabled (`volume-nocopy`).
    Require the mounted destination to be empty immediately before copying;
    never overlay contents if another actor created or populated it meanwhile.
8. Copy `/source/.` to `/destination/` with `cp -a`, retaining hidden entries,
   directory structure, modes, ownership, symlinks, timestamps, databases, WAL/SHM
   files, credentials, and other data files. Never copy just `opencode.db`.
9. Compare the directory trees using recursive, symlink-aware `diff`, without
   displaying file contents. A difference or failed copy fails the command.
   Verification establishes equal names, regular-file contents, and symlink
   targets; archive copying preserves metadata, but the comparison does not claim
   comprehensive ACL/xattr or metadata identity.
10. Report success only after copy and comparison pass. State that the copy is
    prepared and schema migration has **not** run. On failure after creation,
    report that the destination may be partial and leave it for inspection. Never
    remove either volume automatically, even on interruption. A retry requires
    another new destination or explicit operator handling of the failed one.

The operational rule is a quiescent source and exclusive operator control of the
destination name. Docker volume creation is not an atomic create-if-absent lock.
The script's running-container checks
are useful safeguards, not proof that no unmanaged writer can exist. No daemon
locking or orchestration framework is introduced.

### 3. Prose transition instructions

Add a concise README development subsection, with a link to a detailed reusable
runbook at `docs/opencode-v2-transition.md`. The README identifies this
repository's chosen names, rebuild/reopen commands, version/persistence checks,
and rollback; the runbook contains the complete one-time prose and script usage.

The runbook must cover this order:

1. **Locate the correct daemon and source.** Run from the host, not from the
   devcontainer's nested Docker-in-Docker daemon. Inspect the current
   devcontainer's mount at `/root/.local/share/opencode` to obtain the real named
   volume. Record the current workspace path, session inventory, and representative
   session IDs before stopping. Account for sessions across all projects if the
   source is shared. Never assume another repository uses this repository's names.
2. **Prepare a local helper image.** Existing v1 or v2 devcontainer images are
   suitable. Show how to find the current local devcontainer image. Do not require
   registry publication of v2 or add another image recipe. Obtain a local copy of
   the standalone script before stopping the container.
3. **Quiesce all users of the source.** Close OpenCode and stop every container
   writing the source, including devcontainers for other repositories sharing it.
   Preserve the workspace checkout. Keep writers stopped through copying and
   validation; do not treat a live file copy as a SQLite-consistent backup.
4. **Run the script.** For this repository, pass source
   `devcontainer-opencode-data`, destination `devcontainer-opencode2-data`, and
   the selected local helper image. Document what success and partial failure mean.
5. **Switch selection and mount together.** Rebuild/reopen this repository with
   VS Code **Dev Containers: Rebuild and Reopen in Container** (or **Rebuild
   Container** if already attached). Keep the workspace path stable for project
   association. Other Dockerfile-based consumers explicitly select their own v2
   recipe/image and destination mount according to their existing workflow;
   changing them is not part of this implementation.
6. **Start pinned v2 and wait for migration.** Check `opencode --version`,
   `opencode debug paths`, and `opencode api experimental.migration.v1.status`.
   Completion alone is insufficient: inspect logs for skipped/malformed rows and
   migration errors. Do not overwrite the copy with v1 data after v2 has started.
7. **Verify continuity and authentication.** Compare all session IDs, including
   archived and child sessions, using read-only inventories or fully paginated
   API results; do not mistake the default top-level/project-limited session list
   for a full inventory. Inspect representative transcripts and attachments.
   Confirm imported accounts with `opencode auth list`, then test an actual
   provider interaction. Do not print/export secrets for verification. Reconnect
   only if provider access fails; do not describe reauthentication as inevitable.
8. **Recreate and verify persistence.** Rebuild/recreate with the same v2 volume
   and confirm migrated and newly created v2 sessions remain available.

If source history is not SQLite-backed in the form verified here, or unexpected
custom database overrides are discovered, stop and investigate before claiming
support; do not silently migrate another location. This script copies named
volumes only. Bind mounts and external credential stores are outside its contract.

Shared sources are copied once per intended shared destination. Downstream
repositories choosing to share that destination use the same migrated volume;
those requiring independent histories choose separate destination names. Do not
repeatedly copy a shared source onto an existing destination or suggest that v1
and v2 histories continue synchronizing after cutover.

### 4. Rollback

Document both container selection and data selection. For this repository:

```text
Dockerfile: ../Dockerfile.OpenCode
Context:    ..
Mount:      devcontainer-opencode-data → /root/.local/share/opencode
```

Stop v2 users, restore these two configuration fields, and rebuild/reopen. Keep
both volumes. Never mount migrated v2 data into v1 as a rollback method. Verify
the restored v1 version and known pre-cutover sessions. Downstream consumers
restore their own prior recipe/image selection and original source mount.

Rollback restores pre-cutover v1 history. V2 sessions created after cutover stay
in the v2 volume; there is no automatic reverse migration or history merge.
Likewise, subsequent v1 activity is absent from the v2 copy. OAuth token refresh
or revocation can affect credentials in the retained snapshot even when its
bytes are unchanged; rollback may require signing in again.

### 5. Repository integration compatibility

Verify actual command registration in the resulting devcontainer and investigate
the observed empty registry before concluding compatibility. Inspect model
override availability after provider login. Do not execute the full update
command merely as a smoke test: its prompt intentionally changes version pins.
Confirm discovery/selection and template behavior without triggering upgrades;
report authenticated execution as pending if it cannot be established safely.

Retain `sst-dev.opencode`. Verify terminal launch and selected-file insertion
through the extension in VS Code. Source inspection supports compatibility but
does not substitute for an interactive result. Do not install Node.js or refresh
locks based on a v1 dependency lock alone. Any necessary command compatibility
adjustment must be supported by observed v2 behavior and remain narrowly scoped.
If a solution requires recipe/pin changes or general plugin work, report a
concrete blocker and return for a decision.

## Focused regression coverage

Use the existing Bats integration runner and named Python test-helper convention.
Register new scenarios through the existing OpenCode Bats suite rather than
changing image workflows or creating another framework.

Cover meaningful preparation-script behavior in isolated fixtures:

- Required arguments/help, invalid/equal names, missing source, existing
  destination, running source/destination consumers, missing helper/tools.
- Argument boundaries and execution from another working directory, including a
  script path with spaces. No reliance on repository files or Dockerfile pins.
- Source read-only/destination read-write mounts, disabled copy-up, immutable
  local helper ID, and no pull, OpenCode invocation, container stopping, or deletion.
- Copy failure, comparison mismatch, and Docker failures propagate nonzero and
  retain the source and any created destination. Success is reported only after
  verification; diagnostics do not disclose data contents.
- A focused config contract checks v2 Dockerfile/context and isolated data mount,
  with existing feature/options, extension choices, and lock resolution retained.

Mocks establish orchestration and failure handling; actual disposable-volume
checks establish copying, preservation, and migration behavior. Do not add tests
that simply mirror every line or a broad migration-compatibility test matrix.

## Implementation verification

After written-spec approval and implementation:

### Static and repository checks

- Run POSIX shell syntax checks and ShellCheck for the new script; run it with
  available `sh` implementations to catch host-shell assumptions.
- Run the focused and complete existing Bats suites through the supported runner,
  including its Python/Ruff checks. Run applicable pre-commit hooks and
  `git diff --check`. Do not invoke the Make pre-commit target that autoupdates
  hook dependencies.
- Use Dev Containers CLI `read-configuration` with feature resolution against the
  actual workspace/config. Check the selected Dockerfile, context, mounts,
  feature resolution, and editor customizations. Record CLI version and ensure
  resolution has not rewritten the feature lock.

### Actual devcontainer build/start and persistence

- Use Dev Containers CLI `up` against `.devcontainer/devcontainer.json` on the
  available native daemon; allow adequate build time (at least 20 minutes).
  A standalone image build is insufficient.
- Seed a uniquely named disposable v1 source with known sessions/history and
  synthetic saved credentials; run the actual preparation script before startup.
  On the available isolated daemon, if this repository's configured v2 volume is
  absent and unused, create that destination through the script and exercise the
  checked-in configuration directly, recording ownership of the test resource.
  Never replace an existing volume to obtain this result. If isolation instead
  requires an override, use a temporary copy with only the destination name
  adjusted, retain the feature lock, and resolve relative paths against the
  original workspace. Validate the checked-in config directly and distinguish
  runtime evidence for the overridden mount from the exact configuration.
- In the resulting container, compare `opencode --version` to the existing pin;
  check startup/API health, migration completion and logs, session-ID/history
  preservation, and imported synthetic credential presence without exposing it.
- Confirm Docker-in-Docker server health and actual execution of a disposable
  nested container, not merely Docker CLI availability or host-socket access.
- Recreate the devcontainer using the same v2 test volume and confirm history
  persists. Compare source file hashes before/after while mounted read-only and
  stopped; demonstrate v1 can still open the original fixture afterward.
- Delete only explicitly created disposable test resources after evidence is
  collected. Never create a fake real-name v1 volume and imply it is user data.

### Interactive dogfooding and actual data

Human steps remain explicit when unavailable to the agent:

- Run the host-side script against the actual source and new destination, then
  rebuild/reopen at the same workspace path.
- Use the OpenCode extension command/shortcut to launch v2, inspect migrated
  conversations, insert a selected-file reference, and verify command discovery.
- Confirm account access and submit a small read-only prompt. Check the update
  command's selected model is available without running version upgrades.
- Recreate and recheck persistence. Check the retained original source separately
  if rollback verification is needed, without opening it with v2.

Report static validation, devcontainer build/start/runtime, standalone migration
evidence, actual-data migration, and interactive dogfooding separately. Do not
infer VS Code reopening, OAuth access, or real-user-history completeness from
synthetic API checks. Provide exact human commands where checks remain pending.

## Deliverables and acceptance criteria

Expected implementation paths:

- `.devcontainer/devcontainer.json`
- `scripts/prepare-opencode2-data.sh`
- `README.md`
- `docs/opencode-v2-transition.md`
- Focused tests in `tests/test-opencode-support.bats` and small named helpers as
  needed; a command file only if a demonstrated narrow compatibility fix is needed.

Acceptance:

- Actual devcontainer resolution selects the existing pinned v2 recipe and
  preserves Docker-in-Docker and unrelated customization/lock choices.
- The standalone POSIX script is reusable across repositories, refuses unsafe
  reuse/live copies, prepares and verifies a complete copy, and never migrates,
  mutates, or deletes the source.
- Both prose and script explain host-daemon selection, explicit volume/image
  arguments, quiescence, failure handling, and migration occurring at v2 startup.
- Disposable real-volume checks demonstrate continuity, recreation persistence,
  and untouched v1 data. Real-user-data and interactive limitations are explicit.
- README/runbook give usable rebuild, verification, and two-part rollback steps,
  including upstream transformation limits and no reverse synchronization.
- Repository command/editor integration is verified to the extent available or
  a concrete blocker/pending human step is recorded.

## Self-review

Self-reviewed the full document against the user's initial constraints, approved
copy-then-migrate direction, and request for reusable prose plus a portable script.
The review checked:

- The script has explicit volume/image inputs, no checkout dependency, and no
  hard-coded consumer-repository assumptions.
- Host versus nested Docker-daemon selection, shared-volume users, and preserving
  the workspace path are explicit.
- Source-existence and destination-nonexistence checks precede mounts; source
  mounts are read-only, image copy-up is disabled, and the destination must still
  be empty before copying. Remaining concurrency limits are stated accurately.
- The script prepares/verifies the copy; pinned OpenCode performs schema
  migration later. Failure cannot be summarized as migration success and does
  not trigger automatic deletion or source mutation.
- A full quiescent copy includes SQLite sidecars and authentication; upstream
  transformations, account renewal limits, and session inventory scope are
  explicit rather than promising lossless migration.
- Rollback restores both image/recipe and original data, with no reverse-sync
  claim. Global configuration persistence is excluded.
- Actual configuration validation and devcontainer runtime verification remain
  distinct from image/probe evidence and human dogfooding. Test-volume ownership
  is explicit, and existing data cannot be replaced to obtain a test result.
- Recipe/pin/workflow changes and broad plugin work remain outside scope.

The review tightened helper network isolation, destination race handling, and
exact-config versus overridden-config runtime reporting. No consequential design
questions remain before the user's written-spec review. The user subsequently
approved this written spec on 2026-10-15 and requested an implementation plan.
Implementation awaits plan review; no commit has been requested.
