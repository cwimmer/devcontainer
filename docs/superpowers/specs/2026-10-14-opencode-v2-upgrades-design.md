# OpenCode V2 Dockerfile and Independent Major-Version Upgrades

**Date:** 2026-10-14
**Status:** Approved
**Repository:** `cwimmer/devcontainer`

## Goal

Complete part one of the OpenCode v2 rollout: provide a usable, explicitly
versioned v2 Dockerfile and maintain the base tools, OpenCode v1, and OpenCode
v2 through `make upgrade`, without crossing OpenCode major versions.

## Repository context

- `Dockerfile` provides the base tool image without OpenCode.
- `Dockerfile.OpenCode` inherits from `ghcr.io/cwimmer/devcontainer:latest`,
  installs Node.js through `NODE_MAJOR=26`, and pins OpenCode `1.19.0`.
- `make upgrade` invokes `scripts/update-versions.sh --all`.
- The updater maps tools to Dockerfiles and ARG names, supports explicit
  versions, check-only operation, backups, and aggregate failure reporting.
- OpenCode discovery currently uses GitHub's unrestricted latest-release
  endpoint. This does not provide independent v1/v2 selection.
- `tests/test-opencode-support.bats` is already registered in the Makefile
  and CI BATS invocations. Its existing updater checks use live responses.
- The README and both update-command prompts currently describe two
  Dockerfiles and base/v1 build verification.
- Recent commits preserve per-tool version updates and native-platform image
  loading. This change follows those conventions.

The repository-local Superpowers brainstorming instructions were consulted.
The wiki-context skill was unavailable; repository documentation was inspected
directly.

## Upstream evidence

Verified on 2026-10-14:

- [V1 documentation](https://opencode.ai/docs/) identifies `opencode-ai` as
  the official npm package and `https://opencode.ai/install` as its installer.
- [V2 documentation](https://opencode.ai/v2/docs/) identifies `@opencode/cli`
  and `https://opencode.ai/v2/install` as supported installation methods.
- The [v2 installer](https://opencode.ai/v2/install) accepts `--version` and
  `--no-modify-path`, downloads a native binary from npm, and installs it in
  `$HOME/.opencode/bin`. This method does not require Node.js.
- V2 stable version `2.0.29` is present in both the
  [official update service](https://opencode.ai/update/api/latest/cli/npm)
  and the [official npm package metadata](https://registry.npmjs.org/@opencode/cli/latest).
- Version `2.0.29` has Linux glibc ARM64 and x64 native packages. The installer
  selects the architecture and handles the x64 baseline variant.
- The npm catalogs contain stable v1 `1.19.0` and stable v2 `2.0.29`.
  GitHub's latest release currently reports v1 `1.19.0`.

Architecture availability is upstream evidence, not proof of local builds on
both architectures.

## Approaches considered

1. **Official standalone v2 installer; independent npm catalogs for discovery
   (chosen).** Reuses the existing installation pattern, avoids a v2 Node.js
   dependency, and permits one small discovery helper with major filtering.
2. **Standalone v2 installer; GitHub releases for v1 and npm for v2.** Retains
   v1's discovery source but requires separate response parsing and paginated
   GitHub release handling.
3. **Pinned npm installation for v2.** Officially supported, but duplicates
   Node.js installation and requires maintaining Node versions in both variants
   without a demonstrated need.

## Detailed design

### 1. V2 image definition

Add `Dockerfile.OpenCode2` inheriting directly from
`ghcr.io/cwimmer/devcontainer:latest`.

- Pin `ARG OPENCODE_VERSION=2.0.29`.
- Download the official v2 installer to a temporary file with HTTP-error
  detection, then execute it with the explicit pin and `--no-modify-path`.
  A failed download must fail the build before execution.
- Remove the temporary installer after installation.
- Follow v1's symlink convention, exposing the installed binary as
  `/usr/local/bin/opencode`.
- Invoke `opencode --version` and assert that its reported version matches
  `OPENCODE_VERSION`. Following the upstream installer's version parsing,
  extract the final whitespace-delimited token and remove an optional leading
  `v` before comparing it with the pin. A failed command fails the build.

The new Dockerfile introduces only one versioned dependency: OpenCode itself.
It contains no Node.js installation or `NODE_MAJOR`. The existing Node upgrade
operation therefore continues targeting `Dockerfile.OpenCode` only.

### 2. Discovery and targeting

Extend the updater's existing tool and Dockerfile mappings:

| Tool | Catalog | Required major | Dockerfile | ARG |
| ---- | ------- | -------------- | ---------- | --- |
| `opencode` | `https://registry.npmjs.org/opencode-ai` | 1 | `Dockerfile.OpenCode` | `OPENCODE_VERSION` |
| `opencode2` | `https://registry.npmjs.org/@opencode/cli` | 2 | `Dockerfile.OpenCode2` | `OPENCODE_VERSION` |

Use one small OpenCode discovery helper parameterized by package and major.
Fetch npm package metadata with `curl -fsSL`; the abbreviated npm metadata
Accept header may be used to limit response size.

Require a JSON object with a `versions` object. Select its version keys that
match the required major and canonical `major.minor.patch` syntax. Each numeric
component is either zero or a positive integer without leading zeros. Exclude
prerelease and build suffixes. Sort by numeric component tuples and select the
highest version, independently of response ordering or npm dist-tags.

HTTP/transport failure, malformed JSON, incorrect response shape, or an empty
eligible set must return nonzero with an actionable tool-specific diagnostic.
No fallback to unrestricted `latest` is used.

### 3. Validation and mutation contract

Validate every OpenCode target version after discovery or explicit-version
selection, before equality comparison, check-only reporting, backup creation,
or file mutation.

- `opencode` accepts only canonical stable `1.x.y` versions.
- `opencode2` accepts only canonical stable `2.x.y` versions.
- Reject wrong majors, leading `v`, incomplete versions, leading zeros,
  whitespace, prereleases, build suffixes, and other malformed input.
- Explicit versions retain the existing override semantics: validate syntax
  and major without adding a remote release-existence check.
- Reject a missing or empty `--version` argument with a clear error rather
  than silently treating it as automatic discovery.

Preserve the existing operational behavior:

- Update only the selected Dockerfile's `ARG OPENCODE_VERSION=...` line;
  unrelated bytes remain unchanged.
- Create `<Dockerfile>.backup` before a changed update unless `--no-backup`
  is supplied. Retain the existing backup replacement behavior.
- An unchanged version creates no backup.
- Check-only mode does not modify Dockerfiles or create, replace, or remove
  backups, including when validation or discovery fails.
- Failed OpenCode discovery or validation does not modify its affected
  Dockerfile or backup as part of that tool's operation. Under `--all`, a
  separate successful Node.js update may still modify the v1 Dockerfile.
- `--all` retains per-tool processing and aggregate failures: other tools may
  update successfully even when one fails; the command ultimately exits
  nonzero and identifies failed tools. It is not a cross-file transaction.
- Ensure discovery diagnostics remain visible on stderr when version values
  are captured through command substitution.

Keep existing tool upgrades and flags intact. Extend required-file checks for
`--all` to include all three Dockerfiles; a single-tool operation requires
only its mapped file. No general updater redesign is needed.

### 4. Makefile interface

- Keep `make upgrade` invoking `scripts/update-versions.sh --all`; update its
  description to name all three Dockerfiles.
- Keep `make upgrade-opencode` and `--tool opencode` targeting v1.
- Add `.PHONY: upgrade-opencode2` and `make upgrade-opencode2`, invoking
  `scripts/update-versions.sh --tool opencode2`.
- Extend script help and examples to explain v1/v2 targeting and stable-major
  selection.

### 5. Documentation and update prompts

Update `README.md`, `.opencode/commands/update-devcontainer.md`, and
`.github/prompts/update-devcontainer.prompt.md` to:

- Identify the base, v1, and v2 Dockerfiles and independent upgrade commands.
- Include all three Dockerfiles in change detection and diff review.
- Report v1 and v2 version updates separately.
- Document the direct local v2 build and version assertion described below.
- Preserve base/v1 verification commands, while explicitly describing what
  they verify. Existing Makefile build targets do not build v2.
- Include direct v2 verification in the update flow when versions change and
  report it separately. A skipped or failed v2 build cannot be summarized as
  verified merely because the existing image checks passed.
- Allow sufficient time for image builds; use at least a 20-minute timeout
  when executing the existing native build targets.

### 6. Behavioral tests

Extend `tests/test-opencode-support.bats` using the existing BATS conventions.
Use isolated temporary repository copies and a PATH-injected `curl` stub with
controlled responses; never run mutating updater tests against the checkout.
Replace the existing live OpenCode/Node updater checks with controlled checks.
The stub must reject unexpected requests so tests cannot silently use the
network. No production endpoint-override API is needed.

Cover:

- Independent v1/v2 discovery with mixed majors, unsorted versions, numeric
  ordering traps, and prerelease/build-suffix exclusion.
- Correct single-tool file targeting and preservation of unrelated content.
- `--all` processing both OpenCode variants, existing base tools, and Node.js
  in v1, using controlled responses for every requested endpoint.
- Valid explicit versions, unchanged versions, and invalid/wrong-major
  explicit versions, including validation in check-only mode.
- Missing/empty explicit-version arguments.
- Transport/HTTP failure, invalid JSON, wrong response structure, and no
  eligible stable version for each OpenCode major.
- Backup contents, `--no-backup`, and byte-for-byte preservation of Dockerfiles
  and existing backups during check-only and failed single-tool OpenCode
  operations.
- Aggregate failure reporting while other `--all` operations succeed.
- Availability and v1/v2 routing of the upgrade Makefile targets.

Keep these tests in the already-registered suite so no workflow or build-target
registration changes are required. Small fixture/helper files under `tests/`
are allowed if they make the controlled responses clearer.

## Implementation verification

After written-spec approval and implementation:

1. Run focused OpenCode BATS tests and Bash syntax checks.
2. Run applicable pre-commit checks and the existing base/v1 checks, using
   `make test_native` and `make test_native_opencode` for native verification.
3. Directly build and run the v2 image without adding a Makefile build target:

   ```sh
   docker build -f Dockerfile.OpenCode2 -t devcontainer-opencode2-local .
   docker run --rm --pull=never devcontainer-opencode2-local opencode --version
   ```

4. Compare the reported runtime version with the Dockerfile pin and record
   the platform and command results. The available Docker host is ARM64.
5. Review `git diff --check`, changed files, and final diffs.

Report focused updater results, existing base/v1 image results, and actual v2
build/runtime results separately. Record environmental blockers as unverified
checks. A native ARM64 success does not establish an amd64 build result.
The v2 Dockerfile consumes the existing base image tag; these checks do not
claim that every derived build used a freshly built local base.

## Scope guardrails

Implementation changes are limited to the new v2 Dockerfile, updater, upgrade
Makefile entries/messages, focused tests and fixtures, README, and two update
prompts. The base Dockerfile and v1 recipe need no version or installation
changes for this feature.

Deferred to later rollout parts:

- V2 Makefile build/test targets and GitHub Actions image-build integration.
- `.devcontainer/` changes, configuration or volume migration, and dogfooding.
- Image publication, registry tags or aliases, v1 retirement, and base-image
  redesign.

## Acceptance criteria

- A direct local v2 build succeeds, and its container reports the pinned 2.x
  version.
- Automatic and explicit OpenCode updates cannot cross majors or write an
  invalid version.
- `make upgrade` maintains all existing tools and both OpenCode variants.
- Focused controlled-response tests demonstrate targeting, discovery,
  validation, backup/check-only behavior, failure reporting, and unrelated
  content preservation.
- Applicable checks pass, with accurate separation of v2 runtime evidence
  from existing base/v1 coverage.
- Documentation and both update prompts describe all three Dockerfiles and
  the verification actually available in part one.
