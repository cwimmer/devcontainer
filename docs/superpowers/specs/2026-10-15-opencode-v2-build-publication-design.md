# OpenCode V2 Local Verification and Image Publication

**Date:** 2026-10-15
**Status:** Approved by the user on 2026-10-15
**Repository:** `cwimmer/devcontainer`

## Goal

Complete part two of the OpenCode v2 rollout: integrate local build/runtime
verification and publish the multi-platform v2 image through the existing image
workflow. Preserve the base and OpenCode v1 image identities and behavior.

Part one is assumed correct. Its `Dockerfile.OpenCode2`, explicitly pinned
installation, build-time version assertion, and independent upgrade selection
are inputs to this work, not subjects for redesign.

## Repository context

The design is based on inspection of repository instructions, all three active
Dockerfiles, `Makefile`, `.github/workflows/image-build.yaml`, the BATS suite and
helpers, `README.md`, both update-command prompts, the part-one design and plan,
and recent commits. Relevant commits include:

- `81d6ed3`: v2 Dockerfile and independent upgrades.
- `8286968`: host-native platform selection for local image loads.
- `fd97042`: CI BATS execution against the locally built base image.

The existing v1 targets depend on the corresponding base verification target.
The multi-platform targets build both supported platforms, then load the native
variant separately. CI builds and tests a native base before its multi-platform
publication step and publishes only when `github.ref == 'refs/heads/main'`.

The repository-resident Superpowers brainstorming skill was consulted.
The wiki-context skill was unavailable; repository documentation was inspected
directly. A design-only builder review of the proposed approach found no
important missing decisions before this written spec was prepared.

## Approaches considered

1. **Existing target conventions plus a shared runtime verifier (recommended).**
   Additive Make and workflow changes, with one implementation of pin extraction,
   image identity resolution, and runtime checking. Retains the published base.
2. **Inline verification in each target and CI.** Avoids a helper script but
   duplicates version parsing and failure handling across three call sites.
3. **Feed freshly built base images into derived builds.** Verifies the complete
   checkout together but requires additional Buildx image/context plumbing for
   local and CI multi-platform builds. This exceeds the needs of this rollout.

## Detailed design

### 1. Image identities and base source

| Dockerfile | Image tag |
| ---------- | --------- |
| `Dockerfile` | `ghcr.io/cwimmer/devcontainer:latest` |
| `Dockerfile.OpenCode` | `ghcr.io/cwimmer/devcontainer:opencode` |
| `Dockerfile.OpenCode2` | `ghcr.io/cwimmer/devcontainer:opencode2` |

V2 inherits from the published `ghcr.io/cwimmer/devcontainer:latest`, as its
existing Dockerfile specifies. Use `--pull` for the new local v2 builds and
`pull: true` for the new workflow builds to make registry base resolution
explicit. Do not change `Dockerfile.OpenCode2` or add base-context overrides,
base-selection arguments, aliases, or another tagging scheme.

The base Make prerequisites independently build and verify the checkout's base
image. A Buildx builder does not implicitly consume that newly loaded Docker
daemon image for a derived build. Therefore, v2 verification does not claim to
test a v2 image derived from the freshly built local base.

On main, the existing base publication step precedes the v2 steps. On pull
requests, v2 builds consume the existing published base. Registry tag resolution
does not establish an immutable relationship to a particular base workflow run;
this design makes no such provenance claim.

### 2. Make interface

Add `OPENCODE2_TAG:=opencode2` and
`OPENCODE2_DOCKERFILE:=Dockerfile.OpenCode2`, following existing naming patterns.

Add the following phony targets:

| Target | Prerequisites | V2 build sequence |
| ------ | ------------- | ----------------- |
| `test_opencode2` | `$(OPENCODE2_DOCKERFILE) builder test` | Build `linux/amd64,linux/arm64`, then build/load `$(NATIVE_PLATFORM)` |
| `test_native_opencode2` | `$(OPENCODE2_DOCKERFILE) builder test_native` | Build/load only `$(NATIVE_PLATFORM)` |

Both targets select the v2 Dockerfile and tag explicitly and request the
published base with `--pull`. Only the native build uses `--load`. After the
build sequence succeeds, invoke the shared verifier against the v2 tag.

Each build is a normal failure-propagating Make recipe command. A failed
multi-platform build prevents the native build and verification; a failed
native build prevents verification, even if an older v2 image is already local.

Preserve existing base/v1 targets and their meanings. Extend `clean` with removal
of the local v2 tag, retaining the existing best-effort cleanup convention.

### 3. Shared runtime verifier

Add `scripts/verify-opencode2.sh`, a small POSIX shell script shared by Make and
CI. Its single required argument is the locally built image reference.

The verifier must:

1. Locate `Dockerfile.OpenCode2` relative to its own repository location, so its
   behavior does not depend on the caller's working directory.
2. Read the expected version from the Dockerfile's `ARG OPENCODE_VERSION` line
   on every invocation. Reject missing, empty, or multiple pin definitions.
   Do not duplicate the current version in the script, Makefile, or workflow.
3. Resolve the supplied image reference to a nonempty local immutable image ID
   with `docker image inspect`. A failed lookup or missing image fails the check.
4. Run `cat /usr/local/share/asdf-tool-versions` against that image ID, following
   the existing v1 metadata smoke-check convention.
5. Run `opencode --version` against the same ID and capture its output only when
   the command succeeds.
6. Normalize the output exactly as the part-one Dockerfile does: select the
   final space-delimited token and remove an optional leading `v`. Require the
   resulting version to equal the Dockerfile pin.
7. Report success or an actionable failure, including expected and actual
   versions on a mismatch, and return nonzero on any failed check.

Every runtime invocation uses `--rm --pull=never` and the resolved image ID.
Registry fallback cannot substitute another image for runtime verification.
Use strict shell error handling and explicitly preserve failures in captured
commands; parsing must not hide an unsuccessful version command.

### 4. GitHub Actions integration

Append three steps after the existing v1 build/publication step in
`.github/workflows/image-build.yaml`:

1. **Build native v2 for local testing.** Use the existing build-push action
   version with `context: .`, `file: Dockerfile.OpenCode2`, `load: true`,
   `pull: true`, `platforms: linux/amd64`, and the v2 tag. Do not publish here.
2. **Smoke-test the loaded v2 image.** Invoke the shared verifier against the v2
   tag. Use normal step failure behavior; do not continue to v2 publication
   after a failed build or smoke check.
3. **Build and conditionally publish multi-platform v2.** Use the v2 Dockerfile,
   `pull: true`, `platforms: linux/amd64,linux/arm64`, and only the v2 tag.
   Preserve the existing `push: ${{ github.ref == 'refs/heads/main' }}` policy.

The native CI check covers amd64, matching the current Ubuntu runner convention.
The subsequent multi-platform build also executes the existing Dockerfile's
build-time version assertion for both architectures. Do not describe this as
arm64 runtime smoke-test evidence.

Keep existing base/v1 workflow steps, tag meanings, triggers, and publication
policy. Pull-request builds must not publish. No new jobs, matrix, release
system, or caching framework are needed.

Allow 30 minutes for the new native build step and 20 minutes for its smoke-test
step. Retain the workflow's existing overall time allowance for multi-platform
builds rather than introducing a shorter job limit.

### 5. Behavioral regression tests

Extend the already-registered `tests/test-opencode-support.bats`. Add small
helpers under `tests/test_helper/` as needed. Tests execute real Make recipes
and the real verifier in an isolated temporary repository with a PATH-injected
Docker stub. The stub records argument boundaries, rejects unexpected calls,
and controls build, inspect, and runtime outcomes. Tests must not build images
or require access to the host Docker daemon.

Cover:

- V2 Dockerfile/tag selection and preservation of base/v1 selection.
- amd64 and arm64 host selection using the existing Make architecture variables.
- Both-platform build followed by native load for `test_opencode2`.
- Only a native v2 build/load for `test_native_opencode2`.
- Matching base verification prerequisites and propagation of prerequisite
  failure before v2 verification.
- Successful raw and supported prefixed version output.
- Changing only the temporary Dockerfile pin changes the expected version.
- Missing, empty, or ambiguous pin; missing image or empty image ID; failed
  inspect, metadata command, or version command; and a version mismatch.
- A failed multi-platform or native build prevents later runtime verification,
  including when an older local tag is represented in the fixture.
- Runtime execution uses the inspected image ID and `--pull=never`.
- Cleanup attempts removal of the base, v1, and v2 tags.

Replace the brittle global assertion that exactly two commands contain
`--platform $(NATIVE_PLATFORM)` with per-target execution assertions. Preserve
existing updater coverage and base/v1 behavior checks.

Validate workflow step order and actual fields: v2 file/tag/platform selection,
native loading without publication, shared smoke-check invocation, and the
existing main-only publication expression. Keep checks focused and use existing
test tooling; do not introduce a production parsing dependency.

### 6. README and update-command prompts

Update `README.md`, `.github/prompts/update-devcontainer.prompt.md`, and
`.opencode/commands/update-devcontainer.md` to:

- Describe the base, v1, and v2 variants and the intended registry tag for each.
- Document all six native/multi-platform verification targets.
- Replace part one's direct v2 build/version-comparison command block with
  `make test_native_opencode2`; document `make test_opencode2` for both supported
  architectures.
- Explain that the base prerequisite checks the local base separately, while
  derived builds consume the published base.
- Preserve independent upgrade commands and selection semantics.
- Allow at least 20 minutes per native Make invocation.
- Require separate base, v1, and v2 results, including failures and skipped
  checks, and distinguish local evidence from CI and publication evidence.

Describe the configured publication destination without claiming that a
successful registry publication has already occurred.

## Implementation verification and evidence

After written-spec approval and implementation:

1. Run focused behavioral BATS tests and shell syntax checks.
2. Run applicable ShellCheck, yamllint, actionlint, and `git diff --check` checks.
3. Run the existing BATS suite and base/v1 native verification targets.
4. Run `make test_native_opencode2` and `make test_opencode2`. Allow at least
   20 minutes per native command and at least 60 minutes for the multi-platform
   invocation, increasing the allowance if necessary.
5. Record actual commands, platforms, runtime version results, and any blockers.

Report these evidence categories separately:

| Category | Evidence required |
| -------- | ----------------- |
| Local tests/builds/runtime | Actual test and Make results, built platforms, native runtime version comparison |
| Workflow validation | Static/lint results; remote CI execution reported separately if observed |
| Registry publication | Successful remote main-branch workflow and registry manifest evidence for both architectures |

Do not infer CI execution or successful publication from local checks. If remote
execution or publication is not observed, report it as unverified. This spec
does not authorize creating commits, pushing branches, or triggering publication.

## Scope and non-goals

Implementation changes are limited to `Makefile`, the existing image workflow,
the new runtime verifier, focused tests/helpers, README, and both update prompts.

- No `.devcontainer/`, configuration, volume, or dogfooding changes.
- No installation-method, dependency-version, or upgrade-selection changes.
- No v1 retirement, tag aliases, or repointing existing tags.
- No broad pipeline restructuring or fresh-base transport framework.
- Preserve unrelated working-tree changes and historical design documents.

Minor helper naming, diagnostics, and fixture organization are left to the
implementer within these constraints.

## Acceptance criteria

- `make test_native_opencode2` builds/loads the native v2 image and verifies its
  reported version against the Dockerfile pin.
- `make test_opencode2` builds both supported architectures, then loads and
  verifies the native variant.
- Build failure, missing image, failed version command, or mismatch fails the
  target; runtime checks cannot pull a substitute image.
- Base/v1 target meanings and checks are preserved; `clean` includes v2.
- Focused execution tests establish selection, platforms, failures, and cleanup.
- CI smoke-tests native v2 before its multi-platform publication step and
  preserves main-only publication under the sole `opencode2` tag.
- Documentation and prompts describe the three variants, correct targets,
  published-base source, sufficient build budgets, and evidence boundaries.

## Self-review

Reviewed this written spec against the requested rollout boundaries and success
criteria. The review confirmed:

- The published-base source is explicit, including the PR/main distinction and
  the absence of a claim that derived builds consume the local base prerequisite.
- Native and multi-platform builds have distinct load/platform behavior.
- The shared verifier preserves command failures and uses a local image ID with
  registry pulls disabled for runtime checks.
- CI verification gates v2 publication while retaining base/v1 tags and the
  existing main-only publication predicate.
- Tests exercise command behavior, failures, and cleanup instead of relying on
  target existence or global command counts.
- Timeout and reporting requirements are explicit.

An independent builder check of this written document also found nothing
important left unanswered.

No blocking questions remain. The user approved this written document on
2026-10-15; implementation follows a separately reviewed implementation plan.
