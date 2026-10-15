# OpenCode Test Python Extraction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract substantial embedded Python into maintainable test helpers while preserving Bats orchestration and intended coverage.

**Architecture:** Two focused Python helpers own command-log assertions and semantic workflow checks. Bats remains the integration runner; a small shell entry point provisions pinned test dependencies and runs Python checks before Bats. The Docker stub simulates that entry point during mocked Make tests.

**Tech Stack:** Bash, Bats with existing bats-support/bats-assert, Python 3.12 in the supported base environment, stdlib unittest, PyYAML, Ruff, pre-commit.

**Spec:** `docs/superpowers/specs/2026-10-15-opencode-test-python-refactor-design.md` (revised design approved 2026-10-15).

## Global Constraints

- Trivial fixtures expressed as heredocs are reasonable.
- Substantial Python belongs in checked-in `.py` files.
- Keep Bats as the integration runner; shell retains setup, commands, and simple assertions.
- Apply extraction by purpose and complexity, not line count; consolidate repeated parsing and assertions.
- No Python `-c`, generated Python source, general YAML parser, or general expression interpreter.
- Mocked tests never access the real Docker daemon or network, install dependencies, or invoke Bats recursively.
- Preserve `IMAGE_BATS_STATUS`, argument boundaries, spaced paths, and deterministic isolated fixtures.
- Preserve all existing Make entry points, image/build/upgrade/publication behavior, and updater scenarios.
- No Dockerfile, installed tool version, `.devcontainer/`, or dogfooding changes.
- Preserve the modified `superpowers` submodule and unrelated untracked metadata files.
- No commits, pushes, or publication unless separately requested; the skill's suggested commit steps are not authorized here.

## Review Focus

1. Empty/malformed JSONL records and missing option operands must produce useful file/line or command diagnostics, not Python tracebacks (Task 1).
2. YAML loader customization must not change global SafeLoader behavior; false strings, nulls, and numbers must not become true/default values (Task 2).
3. A continued shell line inside single quotes, an unterminated quote, or an extra shell operation must not masquerade as the expected invocation (Task 2).
4. Dependency, lint, or Bats failure must stop the runner, preserve a nonzero status, and remove temporary dependencies (Task 3).
5. Suite invocation recognition must inspect Docker's command vector, not mistake an option value for a command; all six mocked Make entry points must propagate suite failure (Task 3).

## File map

| File | Responsibility |
| --- | --- |
| New `tests/test_helper/image_assertions.py` | Shared JSONL loading, normalized comparisons, scenario-specific ordering/failure checks and CLI |
| New `tests/test_helper/workflow_assertions.py` | Local safe loader, Boolean normalization, narrow verifier command validation, workflow contracts and CLI |
| New `tests/test_opencode_helpers.py` | Focused stdlib unittest regressions for helpers, runner and stub boundaries |
| New `tests/requirements.txt` | Exact PyYAML and Ruff test pins |
| New `tests/run-bats.sh` | Temporary dependencies, Python checks, Bats argument/status forwarding and cleanup |
| Modify `tests/test_helper/image-build.bash` | Thin descriptive wrappers, empty-log Bash check, fixture environment reset |
| Modify `tests/test_helper/image-docker.py` | Runner-command simulation and Python formatting |
| Modify `tests/test-opencode-support.bats` | Replace embedded Python calls; retain scenarios; register regressions and suite-failure cases |
| Modify `Makefile` and `.github/workflows/image-build.yaml` | Only suite-command wiring and necessary mount quoting |
| Modify `.pre-commit-config.yaml` | Scoped, version-matched Ruff hooks |
| Modify `README.md` | Testing conventions and reproducible invocation |

No separate test package or fixture framework is needed. Regression tests can add
`tests/test_helper` to their import path explicitly using their own file location.
Small fixture data can live in the unittest module; do not generate Python code.

### Task 1: Extract command-log assertions and simplify Bats

**Files:** Create `tests/test_helper/image_assertions.py` and `tests/test_opencode_helpers.py`; modify `tests/test_helper/image-build.bash` and `tests/test-opencode-support.bats` (current Python blocks around lines 644–847).

**Interfaces:**
- `load_calls(path: Path) -> list[list[str]]` validates JSONL argument arrays.
- `build_records(calls: list[list[str]]) -> list[list[object]]` returns ordered `[dockerfile, tag, platform, load, pull]` records with existing defaults.
- `check_calls(calls, expected, selection: str) -> None` compares `all`, `builds`, or `verifier` projections; raises `AssertionError` on mismatch.
- `check_scenario(calls, scenario: str, detail: str | None = None) -> None` implements the finite scenarios below, with named internal functions.
- CLI: `python3 image_assertions.py LOG {calls|builds|verifier} EXPECTED_JSON`, or `python3 image_assertions.py LOG SCENARIO [DETAIL]`; errors go to stderr, exit nonzero. No optimization-sensitive bare `assert` in executable checks.
- Bash wrappers retain `assert_image_calls`, `assert_image_builds`, `assert_image_commands`, `assert_no_image_calls`; add descriptive wrappers for scenario names.

- [ ] **Step 1: Add `ImageAssertionsTests` regression cases and run them red.** Write tests for exact comparisons with wrong tags/platforms, spaced arguments preserved in CLI, malformed JSON at line 2, a non-array/empty/non-string record, and missing `--tag`/`--platform` operands. Include wrong ordering and forbidden post-failure commands. Run `python3 tests/test_opencode_helpers.py ImageAssertionsTests -v`; expect failure because the helper is absent.
- [ ] **Step 2: Implement the shared helper and CLI.** Decode once per invocation, validate nonempty string arrays, report path/line for bad records, and show expected/actual comparisons. Explicit option lookup must diagnose missing operands. Implement finite scenario selectors: `v2-order`, `build-failure DETAIL`, `runtime-failure DETAIL`, `builder-fallback DETAIL`, `cleanup`; reserve `suite-failure` for Task 3.
- [ ] **Step 3: Preserve each scenario's contract.** `v2-order` requires base runtime checks before the first v2 build, all v2 builds before inspect/runtime verification, and no v1 calls. `build-failure` forbids verification, forbids v2 builds after base failure, and forbids native load after v2 multi failure. `runtime-failure` requires inspect, forbids runtime after missing-image, otherwise requires a version attempt. Builder scenarios require create and either subsequent v2 build or no builds/inspect. Cleanup requires builder removal and all three image-removal attempts.
- [ ] **Step 4: Run `python3 tests/test_opencode_helpers.py ImageAssertionsTests -v`.** Expect all cases to pass, including CLI failures with informative stderr. Also invoke a failing helper via `python3 -O tests/test_helper/image_assertions.py ...` from a regression subprocess to prove assertions remain active.
- [ ] **Step 5: Replace Python heredocs in image Bash helpers and Make/verifier Bats cases with quoted helper calls.** Keep literal expected build records in Bats. Implement `assert_no_image_calls` with file existence and `test ! -s`, printing the log on failure. Remove redundant arm64 reparsing, identical success branches, duplicate no-v1 assertion, and the flag-index ordering comparison. Exact build order and real build-before-verification checks remain.
- [ ] **Step 6: Register a Bats case named `OpenCode Python helper regressions pass`** invoking `python3 "$REPO_ROOT/tests/test_opencode_helpers.py" -v`; assert success. Workflow/runner classes are added in later tasks to this same module, so registration needs no further file-list changes.
- [ ] **Step 7: Run focused Bats before introducing PyYAML:** `bats tests/test-opencode-support.bats`. Expect all existing updater, workflow, Make, and verifier cases plus helper regressions to pass in the supported environment. Record unavailable Bats activation/helper-library prerequisites rather than silently skipping cases.

### Task 2: Replace workflow text parsing with semantic contracts

**Files:** Create `tests/test_helper/workflow_assertions.py`, `tests/requirements.txt`; extend `tests/test_opencode_helpers.py`; modify the two workflow Python blocks in `tests/test-opencode-support.bats` (currently around lines 439–544).

**Interfaces:**
- `load_workflow(path: Path) -> dict` uses a private SafeLoader subclass with copied resolver tables and only true/false Boolean resolution.
- `normalize_boolean(value: object, field: str) -> bool` accepts bool or trimmed, case-insensitive true/false strings; rejects everything else.
- `verifier_argv(command: str, field: str) -> list[str]` validates the supported simple-command subset before lexing arguments.
- `check_v2_workflow(workflow: dict) -> None` and `check_existing_lanes(workflow: dict) -> None` implement the two Bats checks.
- CLI: `python3 workflow_assertions.py PATH {v2|existing}`; contextual errors on stderr and nonzero status.
- Test pins: start with `PyYAML==6.0.3` and `ruff==0.14.0`; verify availability/support before adopting. If either cannot be provisioned in the supported environment, select an available exact release and keep all references synchronized; report the choice.

- [ ] **Step 1: Declare and provision the test pins for this task.** Add only those two requirements. Use `python3 -m pip install --target /tmp/opencode/opencode-refactor-deps -r tests/requirements.txt` after verifying `/tmp/opencode` exists. Set `PYTHONPATH=/tmp/opencode/opencode-refactor-deps` for interim Python/Bats commands. This is explicit setup, not mocked test execution; do not rely on host PyYAML or Ruff.
- [ ] **Step 2: Add `WorkflowAssertionsTests` and run red.** Read the actual workflow as the baseline; make isolated copies for controlled mutations. Require current contracts to pass and wrong tags/platforms, missing/reordered verification, wrong push expression, enabled/expression-valued failure bypass, and unsupported conditions to fail with field paths. Run `PYTHONPATH=/tmp/opencode/opencode-refactor-deps python3 tests/test_opencode_helpers.py WorkflowAssertionsTests -v`; expect the missing-helper failure.
- [ ] **Step 3: Add YAML equivalence cases.** Test quoted and unquoted `on`, key reordering/comments/indentation changes, scalar and multiline tag/platform values, actual booleans and quoted mixed-case/trimmed Boolean strings. Explicitly require native `push: false` and `continue-on-error: false` (quoted and unquoted) to pass; true must fail where false is required. Reject null, `0`, `1`, arbitrary strings, and expressions for literal Boolean inputs. Check missing required load/pull separately from optional false defaults. Verify ordinary `yaml.safe_load('on: false')` behaves exactly as before importing/using the local loader, proving no global resolver mutation.
- [ ] **Step 4: Add verifier command cases.** Positive fixtures: plain, quoted, current folded `>-`, one-line literal `|`, shell-quoted arguments, leading/trailing blank lines, and literal backslash-newline continuation. Negative fixtures: script/image on separate literal lines, semicolon/newline extra commands, `&&`, pipes, redirections, `$()`/backticks, wrong/missing/extra image arguments, unterminated quotes, and continuation inside single quotes. Assert `jobs.build.steps[verify_opencode2].run` diagnostics and distinguish command-form from argument-vector failure.
- [ ] **Step 5: Implement the narrow lexical check.** Track single/double quote and escape state; permit backslash-newline joining only outside single quotes, reject remaining newlines inside quoted arguments, and reject shell operators/substitutions/redirections outside literal quoting. Retain unescaped newline boundaries until exactly one nonblank logical command is established. Use `shlex.split(..., posix=True)` only after that check and require exactly `['sh', 'scripts/verify-opencode2.sh', 'ghcr.io/cwimmer/devcontainer:opencode2']`. Unsupported syntax fails; never execute it. No shell AST library or new dependency.
- [ ] **Step 6: Implement workflow checks.** Validate shapes and unique relevant IDs; compare native action `docker/build-push-action@v7`, context `.`, file `Dockerfile.OpenCode2`, sole v2 tag, `linux/amd64`, pull/load true, push absent/false, timeout 30; verifier timeout 20; publication both platforms, pull true and exact main-only push expression. Preserve base/v1 tags, platforms and publication expression plus main push/PR/manual triggers. Normalize comma/newline lists and reject extras. Check relevant job/steps for false/absent continue-on-error and absent or explicit `success()` conditions (with or without `${{ ... }}` wrapping). Raise contextual errors for unsupported conditions; do not evaluate them.
- [ ] **Step 7: Replace the two workflow heredocs with CLI calls** using `run python3 "$REPO_ROOT/tests/test_helper/workflow_assertions.py" "$REPO_ROOT/.github/workflows/image-build.yaml" v2` (and `existing`), then `assert_success`. Keep Bats descriptions of the contracts.
- [ ] **Step 8: Run all Python helper regressions and focused Bats** with the explicitly provisioned `PYTHONPATH`. Expect equivalent formats to pass and every deliberately incorrect fixture to fail with useful diagnostics. Missing PyYAML in an unprovisioned interpreter must report setup through `tests/run-bats.sh`, not an opaque import traceback.

### Task 3: Integrate reproducible test execution, lint, and Docker simulation

**Files:** Create `tests/run-bats.sh`; modify `tests/requirements.txt` if verified pins changed, `.pre-commit-config.yaml`, `Makefile`, `.github/workflows/image-build.yaml`, `tests/test_helper/image-docker.py`, `tests/test_helper/image-build.bash`, `tests/test_helper/image_assertions.py`, `tests/test_opencode_helpers.py`, and `tests/test-opencode-support.bats`.

**Interfaces:**
- `bash tests/run-bats.sh [BATS_ARGUMENT ...]`: preserve caller working directory and Bats argv; locate repository paths relative to the script; lint paths are absolute. Provision with existing Python/pip; no venv package requirement or global install.
- Make/CI command from `/repo/tests`: `bash /repo/tests/run-bats.sh test-bats-support.bats test-gh-support.bats test-opencode-support.bats test-file-support.bats`.
- Docker stub recognizes the container command vector `['bash', '/repo/tests/run-bats.sh', ...]` and returns `int(IMAGE_BATS_STATUS or default '0')` using an absent-only environment default; no execution. Supported direct `bats` form may remain, also matched at the command position.
- Add `suite-failure` to `check_scenario`: require one suite invocation and no subsequent derived build or image inspect/runtime verification.

- [ ] **Step 1: Add `RunnerTests` that exercise the real shell runner with PATH-injected shell stubs for `python3` and `bats`.** Shell fixtures may use trivial heredocs or literal text files; substantive test logic stays in Python. The Python-command stub records pip/Ruff calls and can fail each stage; the Bats stub records argv and returns a controlled status. Set a temporary `TMPDIR`, start from a spaced working directory, invoke the real runner by a spaced absolute path, and pass a Bats argument containing spaces. Require ordered install → lint → format → Bats, original arguments/cwd, and temporary-directory cleanup on success and on pip/lint/format/Bats failure. Expect red before runner creation. These tests must never invoke real pip or Bats.
- [ ] **Step 2: Implement the runner with `set -euo pipefail`, `mktemp -d`, and an EXIT cleanup trap.** Run `python3 -m pip install --target "$deps" -r "$repo/tests/requirements.txt"`; expose dependencies in invocation-local `PYTHONPATH` with the temporary path first. Run `python3 -m ruff check "$repo/tests/test_helper" "$repo/tests/test_opencode_helpers.py"` and `python3 -m ruff format --check` on the same paths, then `bats "$@"`. Do not `exec bats`, so cleanup occurs. Verify nonzero status preservation and trap behavior with RunnerTests.
- [ ] **Step 3: Add Bats suite-failure cases for all six Make targets.** For `test`, `test_native`, `test_opencode`, `test_native_opencode`, `test_opencode2`, and `test_native_opencode2`, run with `IMAGE_BATS_STATUS=17`, assert Make fails, and check `suite-failure`. Use the existing default-success build matrix as success evidence. Assert the recorded suite arguments include the complete unchanged file list. The temporary image repo deliberately has no runner file, proving Docker simulation rather than recursive execution.
- [ ] **Step 4: Wire Make and CI to the exact runner command and adapt the Docker stub in the same change.** Only replace suite invocation tokens, preserve environment/file lists and existing build steps. Quote the Make suite mount as `-v "$(CURDIR):/repo"` so copied repositories with spaces produce one argument. In the stub, inspect Docker options `--rm`, `--pull=never`, `-e`, `-v`, `-w` with their operands to locate the image and command; accept only the known suite vector for the base image. Reject unknown forms rather than dispatching on any token named `bats` or runner pathname. Add `IMAGE_BATS_STATUS` to fixture setup's unset list.
- [ ] **Step 5: Add boundary regression tests for the stub.** Directly invoke it with recorded Docker argv and a log tempfile: valid runner returns 0 or injected 17 without a runner file; a runner pathname in an environment/mount operand does not count as a command; an unknown command exits nonzero. Keep existing metadata/version/build stub behavior intact.
- [ ] **Step 6: Implement `suite-failure` checking and run the focused suite through the new runner.** First format affected Python with the provisioned pinned Ruff and fix default lint findings so the runner's initial checks pass. `bash tests/run-bats.sh tests/test-opencode-support.bats` must pass, including RunnerTests and failure injection. Confirm no derived Dockerfile builds or verifier commands occur after a simulated suite failure.
- [ ] **Step 7: Add Ruff pre-commit hooks.** Use `https://github.com/astral-sh/ruff-pre-commit` with the verified matching release tag, hook IDs `ruff-check` and `ruff-format`, scoped with `^tests/(test_helper/.*\.py|test_opencode_helpers\.py)$`. Keep default lint rules; format the affected files using the pinned formatter. Fix legitimate lint findings without restructuring the Docker stub unnecessarily. The runner always checks; pre-commit can format locally.
- [ ] **Step 8: Run Python and shell integration checks.** The runner's focused suite must pass both Ruff checks. Run `bash -n tests/run-bats.sh tests/test_helper/image-build.bash`; Bats files are checked with Bats/ShellCheck rather than Bash's parser. Confirm CI still runs all four files and helper regressions remain registered through the OpenCode Bats file.

### Task 4: Document conventions and verify supported entry points

**Files:** Modify `README.md` Development / Testing; review all changed files and the approved spec. No implementation expansion.

**Interfaces:** Supported root commands are `bash tests/run-bats.sh tests/test-opencode-support.bats` and `bash tests/run-bats.sh tests/test-bats-support.bats tests/test-gh-support.bats tests/test-opencode-support.bats tests/test-file-support.bats`. Existing six Make commands remain entry points.

- [ ] **Step 1: Update README testing guidance.** State both accepted heredoc/Python conventions and their purpose/complexity interpretation, the helper locations, pinned test-only dependencies, setup network access vs offline mocks, runner cleanup/lint behavior, and focused/full commands. Explain that direct Bats requires explicitly provisioned requirements; do not add another bootstrap system.
- [ ] **Step 2: Run the focused supported command.** Expect all OpenCode and Python helper tests to pass with Python lint/format checks. Record command, counts, and outcomes. Run `git diff --check`.
- [ ] **Step 3: Run the full supported command in the base environment.** Expect all four Bats files to pass. Existing gh/bats updater smoke checks may access the network; record those separately from mocked checks and report any actual failures or unavailable prerequisites.
- [ ] **Step 4: Run applicable repository hooks without updating them.** Run `pre-commit run --all-files`, not `make pre-commit` (which calls autoupdate). If new files are untracked, also run `pre-commit run --files` with the explicit new Python/shell paths so they are checked. Report unrelated existing failures distinctly; do not fix outside scope. Run `git diff --check` after any formatting changes.
- [ ] **Step 5: Verify real runner integration with an existing suitable base image.** Check daemon/image availability with `docker image inspect ghcr.io/cwimmer/devcontainer:latest`; if present, run the CI-equivalent `docker run --rm --pull=never -e ASDF_BATS_VERSION="$(grep '^ARG BATS_VERSION=' Dockerfile | cut -d= -f2)" -v "$PWD:/repo" -w /repo/tests ghcr.io/cwimmer/devcontainer:latest bash /repo/tests/run-bats.sh test-bats-support.bats test-gh-support.bats test-opencode-support.bats test-file-support.bats`. If no suitable image exists and a rebuild is necessary to verify integration, use only the existing base native target with adequate build time; no derived rebuild is justified by extraction. If Docker/build access is unavailable, report that check unavailable rather than claiming success.
- [ ] **Step 6: Review the diff against the coverage inventory.** Updater cases unchanged; all three architecture spellings and six target selections retained; dynamic versions/local IDs, fail-fast builds/runtime, builder fallback, main-only publication and cleanup retained. Confirm every substantial Python heredoc was extracted and trivial fixture heredocs remain where useful. Explain the corrected flag-index assertion and removed redundant parsing; do not equate fewer assertions with reduced scenario coverage.
- [ ] **Step 7: Report actual verification and blockers separately.** Include test counts, deliberately incorrect fixture outcomes, lint results, dependency pins, real container integration result, and any unavailable checks. Static workflow checks do not establish remote CI or publication. Leave production behavior and part-three migration untouched.

## Self-review and handoff

This plan maps spec sections 1–2 and assertion corrections to Task 1, semantic
YAML and verifier command forms to Task 2, dependencies/lint/runner simulation to
Task 3, and contributor guidance/verification to Task 4. The five Review Focus
items each have owning regression steps. Shared CLI names and runner command
forms are defined once above and consumed consistently by later tasks.

The tasks depend on shared helper interfaces, so native execution with one final
independent review is the recommended minimal approach. Wait for plan review and
the user's execution-method choice before implementation. This plan does not
authorize commits, pushes, or publication.

## Final review fix — workflow trigger branches

- Changed the existing-lane trigger contract to require `main` among the branch
  values while preserving branch-list shape validation.
- Regression coverage rejects branch lists without `main` for both `push` and
  `pull_request`, accepts `main` alongside `release` for both, and rejects a
  scalar branch value.
- Verification passed: focused `WorkflowAssertionsTests` (11 tests), all Python
  helper tests (26 tests), focused OpenCode Bats suite (36 tests), Ruff lint and
  format checks, and `git diff --check`.
- Bats was run as
  `ASDF_BATS_VERSION=1.14.0 PYTHONPATH=/tmp/opencode/opencode-refactor-deps bats tests/test-opencode-support.bats`;
  the first attempt without `ASDF_BATS_VERSION` was blocked by the unselected
  asdf shim, then the installed Bats 1.14.0 passed.
