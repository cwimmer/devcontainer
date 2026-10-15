# OpenCode V2 Build and Publication Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and verify OpenCode v2 through local Make targets and publish
both supported architectures as `ghcr.io/cwimmer/devcontainer:opencode2` through
the existing workflow.

**Architecture:** Preserve the published base source and existing base/v1
targets. Add two v2 targets and one POSIX runtime verifier shared with CI, then
append native verification and conditional multi-platform publication steps.
Use isolated execution tests with a Docker stub rather than a daemon.

**Tech Stack:** GNU Make, Docker Buildx, POSIX shell, Bash/BATS,
bats-support/bats-assert, Python 3 standard library for test-only argument logs,
GitHub Actions, ShellCheck, yamllint, actionlint.

**Spec:** `docs/superpowers/specs/2026-10-15-opencode-v2-build-publication-design.md`
(approved by the user on 2026-10-15).

## Global Constraints

- Treat part one's installation, pins, assertion, and independent upgrades as correct.
- Preserve `latest` as base, `opencode` as v1, and add only `opencode2` for v2.
- V2 consumes the published `ghcr.io/cwimmer/devcontainer:latest`; use `--pull`
  locally and `pull: true` in the new workflow builds.
- Base prerequisites independently verify the local base; derived v2 does not
  claim to consume that freshly built image.
- `test_opencode2` builds `linux/amd64,linux/arm64`, then loads the native variant.
- `test_native_opencode2` builds/loads only the native v2 variant.
- Read the expected version from `Dockerfile.OpenCode2`, never a duplicated pin.
- Runtime checks use a locally inspected image ID and `--pull=never`.
- Build, image lookup, runtime-command, and comparison failures must fail verification.
- Preserve base/v1 target meanings, prerequisite conventions, and best-effort cleanup.
- Preserve `push: ${{ github.ref == 'refs/heads/main' }}`; PRs must not publish.
- No `.devcontainer/`, installer, version, updater, alias, or broad pipeline changes.
- Allow at least 20 minutes per native command and at least 60 minutes per
  multi-platform invocation; increase allowances when necessary.
- Do not commit, push, or trigger publication without explicit authorization.
- Preserve unrelated working-tree changes, including the modified `superpowers`
  submodule and untracked `.DS_Store` files.

## Review Focus

These implied conditions get explicit tests in their owning tasks:

1. A version command prints the expected version but exits nonzero: fail (Task 1).
2. Caller working directory and repository path contain spaces: locate the pin
   and preserve the image argument unchanged (Task 1).
3. Build fails while an old valid local tag exists: never inspect/run it (Task 2).
4. Builder inspection fails: try creation; failed creation stops the build (Task 2).
5. A publication step gains `always()` or `continue-on-error`: reject bypass of
   the smoke-test gate (Task 3).

## File Map

| File | Responsibility |
| ---- | -------------- |
| `scripts/verify-opencode2.sh` (new) | Pin extraction, local image identity, metadata/version smoke checks |
| `Makefile` | V2 native/multi-platform targets and cleanup |
| `.github/workflows/image-build.yaml` | Native v2 verification before conditional publication |
| `tests/test-opencode-support.bats` | Registered behavioral verifier/Make/workflow tests; existing updater tests retained |
| `tests/test_helper/image-build.bash` (new) | Temporary image-test repository and argument-log assertions |
| `tests/test_helper/image-docker.py` (new) | Test-only Docker stub with JSON-lines argv log and controlled outcomes |
| `README.md` | Three image variants, six targets, base source and coverage |
| `.github/prompts/update-devcontainer.prompt.md` | Updated Copilot verification flow |
| `.opencode/commands/update-devcontainer.md` | Updated OpenCode verification flow |

## Execution Setup

- [ ] Read the approved spec and this plan; inspect `git status --short` and
  applicable repository instructions. Record the existing unrelated changes.
- [ ] Check tools with `ASDF_BATS_VERSION=1.14.0 bats --version`, `python3 --version`,
  `docker version`, and `docker buildx version`. Check BATS support/assert
  libraries at `/usr/local/share/bats-{support,assert}/load.bash`.
  Record missing tools or daemon access as blockers, not successes.
- [ ] If host BATS is unavailable, run tests in an available base container with
  the repository mounted and `ASDF_BATS_VERSION=1.14.0`. Controlled image tests
  must still use their stub and must not require a Docker socket in that container.

---

### Task 1: Shared pin-aware runtime verifier

**Files:** Create `scripts/verify-opencode2.sh`,
`tests/test_helper/image-build.bash`, and `tests/test_helper/image-docker.py`;
modify `tests/test-opencode-support.bats`.

**Interfaces:**
- Produces: `sh scripts/verify-opencode2.sh IMAGE_REFERENCE`, exit 0 only after
  successful metadata/version checks against the Dockerfile pin; diagnostics on failure.
- Test helper: `setup_image_build` creates `IMAGE_REPO` (including a space in its
  path), `IMAGE_LOG`, and a PATH-injected executable named `docker`; copies the
  active Dockerfiles, Makefile, and verifier when present. Call it only in image
  tests, leaving existing updater setup and tests intact.
- Stub: log each argv array as one JSON line; `IMAGE_VERSION_OUTPUT` and
  `IMAGE_VERSION_STATUS` control version output/exit; `IMAGE_FAIL` selects a
  failed operation; `IMAGE_ID` defaults to a valid `sha256:` ID. Seed its default
  successful output from the temporary Dockerfile pin, not a version constant.
- Helper: `assert_image_calls EXPECTED_JSON` compares ordered argv arrays;
  `assert_no_image_calls` checks an empty log. Tests may inspect filtered log
  arrays with Python 3 for focused assertions rather than global command counts.

- [ ] Create the test fixture helpers with the interfaces above and load
  `test_helper/image-build` from the registered BATS file. Initially support
  only inspect and verifier runtime calls; fail unknown stub commands. Ensure
  fixture creation succeeds even while the production verifier is absent.
- [ ] Write tests named `v2 verifier reads the Dockerfile pin and uses a local ID`
  and `v2 verifier works outside the repository with spaced paths`. Execute the
  real script via `sh` with the stub. Assert the exact runtime calls below after
  successful `docker image inspect --format '{{.Id}}' IMAGE_REFERENCE`:

  ```python
  assert runtime_calls == [
      ["run", "--rm", "--pull=never", image_id,
       "cat", "/usr/local/share/asdf-tool-versions"],
      ["run", "--rm", "--pull=never", image_id, "opencode", "--version"],
  ]
  ```

  Cover raw pin output and `OpenCode v<PIN>`; change the temporary pin and
  independently configure output so a hidden hardcoded expectation fails.
- [ ] Write `v2 verifier rejects invalid pins and runtime failures`: missing
  Dockerfile, absent/empty/duplicate pin, missing image, empty ID, metadata
  failure, version failure (including correct stdout with nonzero exit), empty
  output, and mismatch all return nonzero. Mismatch output includes expected
  and actual values. Missing/extra script arguments fail with usage guidance.
- [ ] Run `ASDF_BATS_VERSION=1.14.0 bats tests/test-opencode-support.bats --filter 'v2 verifier'`.
  Expected: new tests fail because the verifier does not exist; fixture failures
  must be corrected before treating this as the intended red result.
- [ ] Implement the verifier using `set -eu`, quoted paths, script-relative pin
  lookup, checked capture of inspect/version commands, and Dockerfile-equivalent
  `${actual##* }` then `${actual#v}` normalization. Reject ambiguous/empty pin
  extraction before running Docker. Use the command interface asserted above.
- [ ] Rerun the focused command; expect all verifier tests to pass. Run
  `sh -n scripts/verify-opencode2.sh` and ShellCheck on changed shell/test files;
  expect zero errors.

### Task 2: V2 Make targets and cleanup

**Files:** Modify `Makefile`, `tests/test-opencode-support.bats`, and the image
test helpers from Task 1.

**Interfaces:**
- Consumes: Task 1's verifier and fixture/log helpers.
- Produces: `make test_opencode2`, `make test_native_opencode2`, and v2 cleanup.
- Extend stub dispatch for existing builder/base/v1 recipes and new v2 recipes;
  reject unknown commands. `IMAGE_FAIL` distinguishes `builder-inspect`,
  `builder-create`, `base-build`, `v2-multi-build`, and `v2-native-build`.
  Selecting `builder-create` also makes the initial builder lookup fail so the
  creation path is exercised; bootstrap inspection is a separate operation.
  Simulated Docker `run ... bats ...` returns a controlled result; never recurse
  into the actual suite from the stub.

- [ ] Replace the global `NATIVE_PLATFORM` count assertion with tests named
  `image targets select their Dockerfiles tags and native platforms`. Execute
  all six targets with `HOST_ARCH=x86_64`, `arm64`, and `aarch64` overrides.
  Assert base/v1 retain existing behavior and v2 selects `Dockerfile.OpenCode2`
  and `ghcr.io/cwimmer/devcontainer:opencode2`; inspect ordered per-image calls.
- [ ] Add `v2 multi target builds both platforms before loading native`:
  assert v2 builds are `(linux/amd64,linux/arm64, load=false)` followed by
  `(native, load=true)`, both with `--pull`; metadata/version verification follows.
  Add `v2 native target builds only native`: exactly one v2 build with `--load`,
  `--pull`, and explicit native platform. Assert corresponding base build/check
  calls precede v2 and no v1 calls occur in these v2 targets.
- [ ] Add `v2 Make targets propagate failures instead of checking stale images`:
  seed a successful old image ID/output, inject each base/v2 build failure, and
  assert nonzero Make status with no later v2 inspection/runtime calls. Test
  verifier missing-image/version/mismatch failures through Make as well.
- [ ] Add `builder fallback preserves failure propagation`: failed inspection
  attempts creation; successful creation permits progress; failed creation
  prevents builds. Add `clean attempts all three images despite removal failure`:
  execute real `make clean`, fail an early removal, and assert builder removal
  plus all three tag removals are attempted under existing best-effort semantics.
- [ ] Run `ASDF_BATS_VERSION=1.14.0 bats tests/test-opencode-support.bats --filter 'image targets|v2 multi|v2 native|v2 Make|builder fallback|clean attempts'`.
  Expected: v2 and cleanup tests fail before Make changes.
- [ ] Add the two variables and phony targets with the exact prerequisites from
  the spec. Add the two-build multi recipe and one-build native recipe, followed
  by `sh scripts/verify-opencode2.sh $(CONTAINER_NAME):$(OPENCODE2_TAG)` with the
  image argument quoted. Add only the v2 removal to `clean`.
- [ ] Rerun Task 2's focused tests, then the full OpenCode BATS file. Expected:
  all tests pass, including existing independent-upgrade tests. Review Make diff
  to confirm existing base/v1 recipe bodies and prerequisite lists are preserved.

### Task 3: CI verification gate and publication

**Files:** Modify `.github/workflows/image-build.yaml` and
`tests/test-opencode-support.bats`; extend `tests/test_helper/image-build.bash`
only if needed for scoped workflow-field assertions.

**Interfaces:**
- Consumes: `sh scripts/verify-opencode2.sh IMAGE_REFERENCE` from Task 1.
- Produces: native v2 build/load, shared smoke test, then both-architecture v2
  build with the existing main-only push predicate.
- Give the new steps IDs `build_opencode2_native`, `verify_opencode2`, and
  `publish_opencode2` so tests address steps rather than incidental prose.

- [ ] Add `workflow verifies v2 before conditional multiarch publication`.
  Scope assertions to each new step block (using standard-library text handling
  for the existing simple workflow shape; actionlint validates YAML semantics).
  Assert ordered IDs, native action `docker/build-push-action@v7`, file/context,
  single v2 tag, `load: true`, `pull: true`, `linux/amd64`, and no enabled push.
  Assert smoke command invokes the actual shared verifier and native/smoke
  timeouts are 30/20 minutes. Assert publish file, sole v2 tag, both architectures,
  `pull: true`, and exact `push: ${{ github.ref == 'refs/heads/main' }}`.
- [ ] Add `workflow preserves base v1 and failure gates`: original base/v1
  tags, platform lists, and push predicates remain; no new `continue-on-error`
  or `if: always()` bypasses the v2 gate; existing triggers remain. Do not merely
  search the entire file for the tag or predicate.
- [ ] Run `ASDF_BATS_VERSION=1.14.0 bats tests/test-opencode-support.bats --filter 'workflow'`.
  Expected: new tests fail because v2 steps are absent.
- [ ] Append the three steps after the existing v1 publication step using the
  exact fields above, native timeout 30, and smoke timeout 20. Keep the job's
  existing overall timeout allowance and action versions. Do not call Make in
  CI, since that would repeat existing base prerequisites unnecessarily.
- [ ] Rerun workflow tests; run `actionlint .github/workflows/image-build.yaml`
  and `yamllint --strict .github/workflows/image-build.yaml`. Expected: tests
  pass and both linters exit zero. Record these as static validation only.

### Task 4: Documentation and end-to-end verification

**Files:** Modify `README.md`, `.github/prompts/update-devcontainer.prompt.md`,
and `.opencode/commands/update-devcontainer.md`.

**Interfaces:** Consumes all targets and CI behavior from Tasks 1–3; produces
accurate user/update instructions and a separately categorized results report.

- [ ] Update README's image table to the three fixed tag mappings; list all six
  Make commands with native versus multi-platform coverage. Replace the direct
  v2 build/comparison block with the new targets. Explain published-base
  resolution, independent local base verification, and native-only runtime scope.
- [ ] Update both prompts: preserve upgrade/diff/no-change logic; run
  `make test_native`, `make test_native_opencode`, and
  `make test_native_opencode2` with at least 20 minutes each; remove direct v2
  build snippets and obsolete notes. Require per-image results and separate
  local, workflow/CI, and publication evidence. Keep configured destination
  wording distinct from observed publication success.
- [ ] Review all three documents against the spec; ensure no remaining claim
  that v2 lacks a Make target or that a local base prerequisite supplies its base.
  No mirrored documentation tests are needed for these prose changes.
- [ ] Run `ASDF_BATS_VERSION=1.14.0 bats tests/test-*.bats`. Expected: all existing
  and new tests pass; disclose any network-dependent existing-test blockers.
- [ ] Run `pre-commit run --files scripts/verify-opencode2.sh tests/test-opencode-support.bats tests/test_helper/image-build.bash tests/test_helper/image-docker.py .github/workflows/image-build.yaml`.
  Expected: applicable hooks pass. Invoke pre-commit directly, avoiding the Make
  target that installs hooks and updates hook revisions.
- [ ] Run `make test_native` with at least 1,200,000 ms timeout and record base
  results. Run `make test_native_opencode` with the same allowance and record v1
  results. Diagnose failures without changing part-one versions or scope.
- [ ] Run `make test_native_opencode2` with at least 1,200,000 ms timeout; record
  actual host architecture, inspected local image, pin, and runtime result.
- [ ] Run `make test_opencode2` with at least 3,600,000 ms timeout; record both
  architecture build outcomes and the separate native runtime outcome. If an
  infrastructure/tool/network failure blocks either command, mark it unverified
  and include its failing output; stub tests do not replace build evidence.
- [ ] Review `git diff --check`, `git status --short`, and the complete intended
  diff. Confirm no Dockerfile, updater, `.devcontainer/`, dependency revision,
  unrelated file, or tag-alias changes slipped in.
- [ ] Report local tests/builds/runtime and static workflow checks separately.
  Report remote CI execution and registry publication as unverified unless
  independently observed; publication evidence requires a successful main run
  plus a manifest showing both architectures. Do not trigger a workflow or push
  to obtain evidence without authorization.

## Self-Review and Handoff

Completed planning self-review:

- **Spec coverage:** Task 1 covers pin/runtime identity and failures; Task 2
  covers target/platform/prerequisite/cleanup behavior; Task 3 covers CI gating
  and tag policy; Task 4 covers docs, time budgets, actual builds, and evidence.
- **Step scan:** Each task has concrete files/interfaces, named assertions,
  red/green verification, and a bounded deliverable. No production bodies or
  speculative framework are prescribed.
- **Interface consistency:** Make and CI both invoke the same `sh` script with
  one image reference; fixture/log names and step IDs are consistent throughout.
- **Review Focus:** All five listed conditions have explicit tests in their
  owning tasks. Existing updater behavior remains covered by the same suite.
- **Proportion:** Four tasks keep the plan close to the spec's size. Small
  fixture helpers support execution tests without introducing production APIs.

No blocking gaps remain. Implementation awaits plan review and selection of an
execution method. No commits or implementation are authorized by this plan alone.
