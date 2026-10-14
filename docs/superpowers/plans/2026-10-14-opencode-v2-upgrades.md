# OpenCode V2 and Independent Upgrades Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a pinned v2 Dockerfile and independently maintain stable OpenCode
1.x and 2.x through the existing upgrade workflow.

**Architecture:** Install v2 using its official standalone installer on the
existing base image. Extend the current Bash updater mappings with `opencode2`
and share a major-filtered npm-catalog discovery function. Exercise the CLI in
isolated temporary repositories with controlled HTTP responses.

**Tech Stack:** Docker, Bash associative arrays, curl, jq, GNU sed, Make, BATS,
bats-support/bats-assert, pre-commit.

**Spec:** `docs/superpowers/specs/2026-10-14-opencode-v2-upgrades-design.md`
(written spec approved by the user on 2026-10-14).

## Global Constraints

- Pin `ARG OPENCODE_VERSION=2.0.29` in `Dockerfile.OpenCode2`.
- Inherit directly from `ghcr.io/cwimmer/devcontainer:latest`.
- `opencode` accepts only canonical stable `1.x.y` versions.
- `opencode2` accepts only canonical stable `2.x.y` versions.
- Reject wrong majors, leading `v`, incomplete versions, leading zeros,
  whitespace, prereleases, build suffixes, and other malformed input.
- Validate before comparison, check-only reporting, backups, or mutation.
- No Node.js installation or `NODE_MAJOR` in v2; Node upgrades remain in v1.
- Preserve explicit overrides, check-only, backups, `--no-backup`, unrelated
  content, existing tool upgrades, and aggregate `--all` failure reporting.
- Updater behavioral tests use controlled responses and temporary repositories.
- No v2 Makefile build/test targets or GitHub Actions image integration.
- No `.devcontainer/`, configuration/volume migration, dogfooding, publication,
  registry-tag changes, v1 retirement, or base-image redesign.
- Record v2 runtime evidence separately from existing base/v1 checks.
- Do not commit unless the user explicitly requests commits. If requested,
  inspect status, diff, and recent history first and stage only intended files.

## File map

| File | Responsibility |
| ---- | -------------- |
| `Dockerfile.OpenCode2` (new) | Standalone pinned v2 installation and build-time version assertion |
| `scripts/update-versions.sh` | v1/v2 mappings, discovery, validation, required-file checks, help |
| `Makefile` | New upgrade-only entry and three-Dockerfile upgrade message |
| `tests/test-opencode-support.bats` | Existing wiring tests plus controlled updater behavior |
| `tests/test_helper/updater.bash` (new) | Temporary repo, response fixtures, state comparisons |
| `tests/test_helper/updater-curl.bash` (new) | Network-free curl stub |
| `README.md` | Variant/upgrade usage and verification boundaries |
| `.opencode/commands/update-devcontainer.md` | OpenCode update flow for all three files |
| `.github/prompts/update-devcontainer.prompt.md` | Copilot update flow for all three files |

Keep production changes in the existing updater; no new production modules or
endpoint-override interface. Do not modify historical specs, base/v1 recipes,
workflow files, or unrelated untracked files (including `.DS_Store` files).

## Execution setup

- [ ] Read the spec and this plan, then inspect `git status --short`.
- [ ] Verify the native test tools and Docker daemon:

  ```sh
  ASDF_BATS_VERSION=1.14.0 bats --version
  test -f /usr/local/share/bats-support/load.bash
  test -f /usr/local/share/bats-assert/load.bash
  docker version
  ```

  Expected: BATS 1.14.0, helper libraries present, available Docker daemon.
  If local BATS cannot run, use the existing base container with the repository
  mounted at `/repo`, working directory `/repo/tests`, and
  `ASDF_BATS_VERSION=1.14.0` to run the same test file.

---

### Task 1: Pinned standalone v2 image

**Files:** Create `Dockerfile.OpenCode2`.

**Interfaces:** Consumes the existing base tag and official v2 installer;
produces `/usr/local/bin/opencode` reporting the Dockerfile's explicit pin.

- [ ] Create the Dockerfile using this installation sequence:

  ```dockerfile
  FROM ghcr.io/cwimmer/devcontainer:latest

  ARG OPENCODE_VERSION=2.0.29

  RUN curl -fsSL https://opencode.ai/v2/install -o /tmp/opencode-install \
      && bash /tmp/opencode-install --version "${OPENCODE_VERSION}" --no-modify-path \
      && rm /tmp/opencode-install \
      && ln -sf "$HOME/.opencode/bin/opencode" /usr/local/bin/opencode \
      && installed_version="$(opencode --version)" \
      && installed_version="${installed_version##* }" \
      && test "${installed_version#v}" = "${OPENCODE_VERSION}"
  ```

  Preserve command failure with `&&`. Do not introduce Node.js or a shell
  pipeline whose last command can hide an installer download failure.

- [ ] Build the actual image (allow at least 20 minutes):

  ```sh
  docker build -f Dockerfile.OpenCode2 -t devcontainer-opencode2-local .
  ```

  Expected: successful native build, including the version assertion.

- [ ] Run and compare the version without allowing an implicit pull:

  ```sh
  expected=$(sed -n 's/^ARG OPENCODE_VERSION=//p' Dockerfile.OpenCode2)
  actual=$(docker run --rm --pull=never devcontainer-opencode2-local opencode --version) &&
    actual=${actual##* } && test "${actual#v}" = "$expected"
  ```

  Expected: exit 0 for `2.0.29`. Record Docker's server platform. Fix any actual
  installer/runtime problem before considering the image verified.

### Task 2: Independently discover and validate OpenCode versions

**Files:** Modify `scripts/update-versions.sh` and
`tests/test-opencode-support.bats`; create
`tests/test_helper/updater.bash` and `tests/test_helper/updater-curl.bash`.

**Interfaces:**
- Existing CLI: `bash scripts/update-versions.sh --tool TOOL [--version VER]
  [--check-only] [--no-backup]`.
- Add `get_latest_opencode_version(package, major)`: stdout contains only the
  canonical version on success; failures return nonzero with stderr diagnostics.
- Add `validate_opencode_version(tool, version)`: success for matching stable
  major, nonzero plus stderr diagnostic otherwise; other tools remain unaffected.
- Test helpers: `setup_updater`, `snapshot_updater`, `assert_updater_unchanged`.
  Export `UPDATER_REPO`, `UPDATER_RESPONSES`, and `UPDATER_REQUESTS`.

- [ ] Add isolated fixture setup. Load `test_helper/updater` from the existing
  BATS file and call `setup_updater` in `setup()`. Implement the helper core:

  ```bash
  setup_updater() {
      export UPDATER_REPO="$BATS_TEST_TMPDIR/repo"
      export UPDATER_RESPONSES="$BATS_TEST_TMPDIR/responses"
      export UPDATER_REQUESTS="$BATS_TEST_TMPDIR/requests"
      mkdir -p "$UPDATER_REPO/scripts" "$UPDATER_RESPONSES" "$BATS_TEST_TMPDIR/bin"
      cp "$REPO_ROOT/scripts/update-versions.sh" "$UPDATER_REPO/scripts/"
      cp "$REPO_ROOT"/Dockerfile{,.OpenCode,.OpenCode2} "$UPDATER_REPO/"
      cp "$REPO_ROOT/tests/test_helper/updater-curl.bash" "$BATS_TEST_TMPDIR/bin/curl"
      chmod +x "$BATS_TEST_TMPDIR/bin/curl"
      export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
      : > "$UPDATER_REQUESTS"
      printf '%s\n' '{"versions":{"1.9.9":{},"2.99.0":{},"1.20.10":{},"1.20.9":{},"1.99.0-beta":{},"1.99.0+build":{}}}' > "$UPDATER_RESPONSES/opencode"
      printf '%s\n' '{"versions":{"2.9.9":{},"3.0.0":{},"1.99.0":{},"2.0.30":{},"2.10.0":{},"2.99.0-rc.1":{}}}' > "$UPDATER_RESPONSES/opencode2"
      printf '%s\n' '[{"version":"v28.0.0"}]' > "$UPDATER_RESPONSES/nodejs"
  }

  snapshot_updater() {
      mkdir -p "$BATS_TEST_TMPDIR/before"
      cp "$UPDATER_REPO"/Dockerfile* "$BATS_TEST_TMPDIR/before/"
  }

  assert_updater_unchanged() {
      local file
      for file in Dockerfile Dockerfile.OpenCode Dockerfile.OpenCode2; do
          cmp "$BATS_TEST_TMPDIR/before/$file" "$UPDATER_REPO/$file" || return 1
          if [[ -f "$BATS_TEST_TMPDIR/before/$file.backup" ]]; then
              cmp "$BATS_TEST_TMPDIR/before/$file.backup" "$UPDATER_REPO/$file.backup" || return 1
          else
              test ! -e "$UPDATER_REPO/$file.backup" || return 1
          fi
      done
  }
  ```

- [ ] Implement the curl stub with no delegation to real curl:

  ```bash
  #!/bin/bash
  set -euo pipefail
  url="${!#}"
  case "$url" in
      https://registry.npmjs.org/opencode-ai) key=opencode ;;
      https://registry.npmjs.org/@opencode/cli) key=opencode2 ;;
      https://nodejs.org/dist/index.json) key=nodejs ;;
      *) printf 'Unexpected curl URL: %s\n' "$url" >&2; exit 97 ;;
  esac
  printf '%s\n' "$url" >> "$UPDATER_REQUESTS"
  if [[ -f "$UPDATER_RESPONSES/$key.fail" ]]; then
      printf 'Controlled HTTP/transport failure: %s\n' "$url" >&2
      exit 22
  fi
  cat "$UPDATER_RESPONSES/$key"
  ```

- [ ] Replace the live Node/OpenCode check-only tests with controlled tests.
  Add this independent discovery test and explicit validation loop:

  ```bash
  @test "OpenCode discovery independently selects stable numeric majors" {
      run bash "$UPDATER_REPO/scripts/update-versions.sh" --tool opencode --no-backup
      assert_success
      assert_output --partial "1.20.10"
      run bash "$UPDATER_REPO/scripts/update-versions.sh" --tool opencode2 --no-backup
      assert_success
      assert_output --partial "2.10.0"
      grep -Fx 'ARG OPENCODE_VERSION=1.20.10' "$UPDATER_REPO/Dockerfile.OpenCode"
      grep -Fx 'ARG OPENCODE_VERSION=2.10.0' "$UPDATER_REPO/Dockerfile.OpenCode2"
  }

  @test "OpenCode rejects invalid and wrong-major explicit versions without writes" {
      snapshot_updater
      local tool version
      for tool in opencode opencode2; do
          for version in 0.9.0 3.0.0 v2.0.29 2.0 02.0.0 2.01.0 2.0.01 ' 2.0.29' '2.0.29 ' 2.0.29-rc.1 2.0.29+build; do
              run bash "$UPDATER_REPO/scripts/update-versions.sh" --tool "$tool" --version "$version"
              assert_failure
              assert_output --partial "$tool"
              assert_updater_unchanged
          done
      done
      run bash "$UPDATER_REPO/scripts/update-versions.sh" --tool opencode --version 2.0.29 --check-only
      assert_failure
      run bash "$UPDATER_REPO/scripts/update-versions.sh" --tool opencode2 --version 1.19.0 --check-only
      assert_failure
      assert_updater_unchanged
      test ! -s "$UPDATER_REQUESTS"
  }
  ```

- [ ] Run the new tests before production changes:

  ```sh
  ASDF_BATS_VERSION=1.14.0 bats tests/test-opencode-support.bats
  ```

  Expected red: v1 cannot discover a version through the rejected GitHub
  latest request, and `opencode2` is unknown. The existing script can also
  expose missing failure propagation here. Do not count unrelated missing-tool
  errors as the expected red.

- [ ] Add `OPENCODE2_DOCKERFILE_PATH`, `opencode2` ARG/file mappings, and case
  dispatch (`opencode-ai`, 1) / (`@opencode/cli`, 2). Replace the old discovery
  function with guarded fetch, shape validation, numeric selection:

  ```bash
  get_latest_opencode_version() {
      local package="$1" major="$2" metadata latest_version
      if ! metadata=$(curl -fsSL -H 'Accept: application/vnd.npm.install-v1+json' \
          "https://registry.npmjs.org/$package"); then
          print_error "Failed to fetch OpenCode $major.x metadata ($package)" >&2
          return 1
      fi
      if ! latest_version=$(jq -er --arg major "$major" '
          if type != "object" then error("expected package object")
          elif (.versions | type) != "object" then error("expected versions object")
          else [.versions | keys[] |
              select(test("^" + $major + "\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)$"))]
              | sort_by(split(".") | map(tonumber)) | last // empty
          end' <<< "$metadata"); then
          print_error "Invalid metadata or no eligible stable OpenCode $major.x release ($package)" >&2
          return 1
      fi
      if [[ -z "$latest_version" ]]; then
          print_error "No eligible stable OpenCode $major.x release ($package)" >&2
          return 1
      fi
      printf '%s\n' "$latest_version"
  }
  ```

  Ensure empty/malformed responses fail even when called inside the existing
  `if ! process_tool ...` context, where Bash errexit cannot be relied upon.

- [ ] Implement `validate_opencode_version` with a `case` mapping to majors
  and Bash ERE `^${major}\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$`.
  Return 0 immediately for other tools. On rejection, print
  `Invalid $tool version: '$version'; expected stable $major.x.y` to stderr
  and return 1. Call it before the existing equality/check-only branches:

  ```bash
  validate_opencode_version() {
      local tool="$1" version="$2" major pattern
      case "$tool" in
          opencode) major=1 ;;
          opencode2) major=2 ;;
          *) return 0 ;;
      esac
      pattern="^${major}\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)$"
      if [[ ! "$version" =~ $pattern ]]; then
          print_error "Invalid $tool version: '$version'; expected stable $major.x.y" >&2
          return 1
      fi
  }

  # Inside process_tool, after selecting target_version:
  validate_opencode_version "$tool" "$target_version" || return 1
  ```

  Guard `-v|--version` with `[[ $# -ge 2 && -n "${2:-}" ]]`; otherwise
  report `--version requires a version argument` and exit 1.

- [ ] Run the focused suite again. Expected: discovery, validation, and
  controlled Node check pass; existing wiring assertions still pass.

### Task 3: Prove failure, check-only, backup, and targeting contracts

**Files:** Modify `tests/test-opencode-support.bats`; adjust updater only if a
new behavioral test exposes a violation in the changed flow.

**Interfaces:** Uses Task 2 helpers and CLI; produces regression coverage for
every per-tool mutation and failure requirement.

- [ ] Add a failure matrix for both tools and both normal/check-only modes.
  Before each run, restore the default fixture or replace it with one of:
  an empty body, `not-json`, `null`, `[]`, `{"versions":[]}`, `{}`, or
  `{"versions":{"0.0.0":{},"3.0.0":{},"2.0.0-beta":{}}}`.
  The last fixture has no eligible stable version for either major.

  ```bash
  printf '%s\n' 'not-json' > "$UPDATER_RESPONSES/$tool"
  run bash "$UPDATER_REPO/scripts/update-versions.sh" --tool "$tool" "${flags[@]}"
  assert_failure
  assert_output --partial "OpenCode"
  assert_updater_unchanged
  ```

  Repeat the assertions with a `$tool.fail` sentinel to exercise fetch failure.
  Seed all three `.backup` files with distinct sentinel text before taking the
  snapshot. Use arrays `flags=()` / `flags=(--check-only)` to avoid empty args.

- [ ] Add explicit successful-update tests for each variant using `1.21.0` /
  `2.1.0`. Compare each backup to its original snapshot, the other two files
  to their originals, and the changed file to a complete expected file:

  ```bash
  sed "s/^ARG OPENCODE_VERSION=.*/ARG OPENCODE_VERSION=$version/" \
      "$BATS_TEST_TMPDIR/before/$file" > "$BATS_TEST_TMPDIR/expected"
  cmp "$BATS_TEST_TMPDIR/expected" "$UPDATER_REPO/$file"
  cmp "$BATS_TEST_TMPDIR/before/$file" "$UPDATER_REPO/$file.backup"
  test ! -s "$UPDATER_REQUESTS"
  ```

  Select `file=Dockerfile.OpenCode` for v1 and `file=Dockerfile.OpenCode2` for
  v2. Use separate BATS tests or reset the copied repo between loop iterations.

- [ ] Add unchanged-version and `--no-backup` tests for both variants.
  Read the current pin from the temporary file, pass it explicitly, assert no
  backup is created. For a changed `--no-backup` operation with preexisting
  backup sentinels, assert the sentinel backup remains byte-identical.

- [ ] Add check-only tests with and without existing backups; use automatic
  discovery and valid explicit versions. Every run must succeed, report the
  target, and satisfy `assert_updater_unchanged`.

- [ ] Add missing/empty explicit argument tests:

  ```bash
  run bash "$UPDATER_REPO/scripts/update-versions.sh" --tool opencode2 --version
  assert_failure
  assert_output --partial "--version requires a version argument"
  run bash "$UPDATER_REPO/scripts/update-versions.sh" --tool opencode --version ""
  assert_failure
  assert_output --partial "--version requires a version argument"
  ```

- [ ] Run the focused suite; fix only failures in the scoped OpenCode paths.
  Expected: all new failure tests exit nonzero visibly and preserve snapshots.

### Task 4: Integrate `--all` and upgrade Makefile interfaces

**Files:** Modify updater, Makefile, BATS file, and curl stub/helper.

**Interfaces:** Adds `make upgrade-opencode2`; preserves `make upgrade`,
`make upgrade-opencode`, and all other upgrade targets.

- [ ] Extend the stub's exact URL cases for every existing tool. Map these
  GitHub repo paths under `https://api.github.com/repos/REPO/releases/latest`:
  `hashicorp/terraform`, `terraform-linters/tflint`, `aquasecurity/trivy`,
  `terraform-docs/terraform-docs`, `digitalocean/doctl`, `cli/cli`,
  `bats-core/bats-core`, `helm/helm`, `kubernetes-sigs/kind`,
  `ahmetb/kubectx`, and `asdf-vm/asdf`. Set keys to their updater tool names.
  Also map `https://go.dev/VERSION?m=text` to `golang` and
  `https://dl.k8s.io/release/stable.txt` to `kubectl`.
  Keep the catch-all rejection intact.

- [ ] Seed base-tool responses in `setup_updater`:

  ```bash
  local tool
  for tool in terraform tflint trivy terraform-docs doctl gh bats helm kind kubectx asdf; do
      printf '%s\n' '{"tag_name":"v9.9.9"}' > "$UPDATER_RESPONSES/$tool"
  done
  printf 'go9.9.9\n' > "$UPDATER_RESPONSES/golang"
  printf 'v9.9.9\n' > "$UPDATER_RESPONSES/kubectl"
  ```

  Synthetic versions are test inputs only; never copy them into the checkout.

- [ ] Add a failing `--all --no-backup` test: assert every base ARG becomes
  `9.9.9` (`ASDF_VERSION` remains `v9.9.9`), Node becomes `28` in v1, and the
  OpenCode pins become `1.20.10` / `2.10.0`. Build a complete expected copy
  of each file with only those ARG substitutions and compare with `cmp`.
  Enumerate ARGs explicitly:

  ```bash
  base_args=(TERRAFORM_VERSION GOLANG_VERSION KUBECTL_VERSION TFLINT_VERSION
      TRIVY_VERSION TERRAFORM_DOCS_VERSION DOCTL_VERSION GH_VERSION BATS_VERSION
      HELM_VERSION KIND_VERSION KUBECTX_VERSION)
  ```

- [ ] Add `--all --check-only` snapshot assertions with existing backup
  sentinels, then a failure-aggregation test with only `opencode2.fail` set.
  Expected: nonzero summary identifies `opencode2`, base/v1 updates succeed,
  and v2 plus its backup remain unchanged. Do not depend on associative-array
  processing order or assume shared v1 backups are transaction snapshots.

- [ ] Add required-file tests: remove temporary `Dockerfile.OpenCode2`;
  `--all --check-only` must fail naming the missing file before HTTP requests;
  `--tool opencode --check-only` must still succeed. Remove the v1 Dockerfile
  in a separate test and prove v2-only checking still works.

- [ ] Add Make routing checks with `make -s -n -C "$REPO_ROOT"`:

  ```bash
  run make -s -n -C "$REPO_ROOT" upgrade-opencode2
  assert_success
  assert_output --partial 'scripts/update-versions.sh --tool opencode2'
  run make -s -n -C "$REPO_ROOT" upgrade-opencode
  assert_success
  assert_output --partial 'scripts/update-versions.sh --tool opencode'
  refute_output --partial '--tool opencode2'
  run make -s -n -C "$REPO_ROOT" upgrade
  assert_success
  assert_output --partial 'scripts/update-versions.sh --all'
  ```

- [ ] Run the focused suite and observe failure from the missing Make target
  and absent `--all` required-file check. Then implement the minimal changes:

```makefile
.PHONY: upgrade-opencode2
upgrade-opencode2:
	@echo "Updating OpenCode v2 version in Dockerfile.OpenCode2..."
	@bash scripts/update-versions.sh --tool opencode2
```

  Name all three Dockerfiles in the `upgrade` message. Add the v2 existence
  guard alongside existing `--all` guards. Update updater header/help/tool
  examples and clarify the existing v1 target message. Keep Node targeting v1.

- [ ] Run focused tests again; expected all pass with no live network needed
  for any updater test in this file. Confirm the help lists both major lanes.

### Task 5: Document the three-file upgrade and verification flow

**Files:** Modify README and both update-command prompts.

**Interfaces:** Documentation mirrors the CLI and direct Docker commands from
Tasks 1–4; existing base/v1 build targets retain their meanings.

- [ ] Add a README variant table naming the base, v1 (Node plus OpenCode),
  and v2 (standalone OpenCode) recipes. Describe v2 as locally buildable at
  this stage and retain the existing published v1 image description.

- [ ] Expand upgrade examples:

  ```sh
  make upgrade                  # base tools plus stable OpenCode 1.x and 2.x
  make upgrade-opencode         # v1 only
  make upgrade-opencode2        # v2 only
  bash scripts/update-versions.sh --all --check-only
  bash scripts/update-versions.sh --tool opencode2 --version 2.0.29
  ```

  Explain canonical stable explicit versions, no cross-major upgrades, and
  Node's continued v1-only targeting. Document the direct Docker build/run
  commands and version comparison from Task 1. State that existing Makefile
  build targets cover base/v1 and do not establish v2 runtime verification.

- [ ] Update both prompts with the same operational sequence:
  1. Run `make upgrade` and report failures with output.
  2. Inspect status and `git diff -- Dockerfile Dockerfile.OpenCode Dockerfile.OpenCode2`.
  3. Stop with “no changes” only if all three are unchanged and upgrade succeeded.
  4. Report tool changes, identifying `opencode` (v1) and `opencode2` (v2).
  5. Run `make test_native`, then `make test_native_opencode`, allowing at least
     20 minutes for each command.
  6. Directly build/run v2 and compare its reported version with the pin using
     Task 1's commands; allow at least 20 minutes for the build.
  7. Report base, v1, and v2 results separately; include failing output and
     identify unrun checks without treating other successes as v2 evidence.

- [ ] Review the three documentation diffs against actual commands and scope.
  No prose-locking tests are needed for these reversible documentation edits.

### Task 6: Final verification and acceptance evidence

**Files:** Review all implementation files; no additional feature scope.

**Interfaces:** Consumes completed tasks and produces an accurate verification
summary and final diff.

- [ ] Run syntax and focused regression checks:

  ```sh
  bash -n scripts/update-versions.sh tests/test_helper/updater.bash tests/test_helper/updater-curl.bash
  ASDF_BATS_VERSION=1.14.0 bats tests/test-opencode-support.bats
  ```

  Expected: all pass. Do not invoke `bash -n` directly on BATS `@test` syntax.

- [ ] Run configured checks directly, avoiding `make pre-commit` because it
  installs hooks and updates dependencies:

  ```sh
  pre-commit run --files scripts/update-versions.sh tests/test-opencode-support.bats tests/test_helper/updater.bash tests/test_helper/updater-curl.bash
  ```

  Expected: applicable hooks pass; unrelated hook types may skip these files.

- [ ] Run existing base/v1 verification with at least a 20-minute timeout per
  invocation:

  ```sh
  make test_native
  make test_native_opencode
  ```

  The second target depends on the first; Make may rerun it. Retain existing
  behavior. Existing GH/BATS tests may use the network; distinguish those
  from the controlled OpenCode updater tests. Record any blocker accurately.

- [ ] If the v2 recipe changed after Task 1, rebuild and rerun Task 1's direct
  acceptance commands. Otherwise retain the successful Task 1 evidence;
  repeat only if a later change introduces an unresolved build concern.

- [ ] Inspect final changes:

  ```sh
  git diff --check
  git status --short
  git diff --stat
  git diff -- scripts/update-versions.sh Makefile tests/test-opencode-support.bats README.md .opencode/commands/update-devcontainer.md .github/prompts/update-devcontainer.prompt.md
  ```

  Also read the newly added Dockerfile/helpers, which may remain untracked
  and therefore absent from `git diff`. Confirm base/v1 recipes, CI, and
  `.devcontainer/` have no feature edits. Do not delete unfamiliar files.

- [ ] Summarize results under updater checks, base/v1 image checks, and native
  v2 build/runtime. Include the pin and tested platform. Do not claim amd64
  runtime verification or fresh-local-base provenance without evidence.

## Self-review coverage map

| Approved spec requirement | Plan coverage |
| ------------------------- | ------------- |
| Official pinned v2 recipe; no Node dependency | Task 1 |
| Independent stable-major catalog discovery | Task 2 |
| Explicit validation before writes/comparison | Tasks 2–3 |
| Failure diagnostics and malformed/empty responses | Tasks 2–3 |
| Backups, no-backup, unchanged versions, check-only | Task 3 |
| Exact targeting and unrelated-byte preservation | Tasks 2–4 |
| Existing tools, Node, `--all`, required files, aggregation | Task 4 |
| Backward-compatible v1 and new v2 upgrade commands | Task 4 |
| README and both prompts; accurate verification claims | Task 5 |
| Real native v2 runtime plus applicable checks | Tasks 1 and 6 |
| Rollout scope and no accidental publishing/migration | Global constraints and Task 6 |

## Execution handoff

Choose either subagent-driven development with per-task reviews, or inline
execution using executing-plans with checkpoints. Begin implementation only
after the user selects an execution approach. No commits are authorized by
this plan.
