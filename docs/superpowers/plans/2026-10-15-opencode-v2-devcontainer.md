# OpenCode V2 Devcontainer Transition Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reopen this repository in its pinned v2 devcontainer with a reusable, verified copy-then-migrate path for existing v1 data and an intact rollback source.

**Architecture:** A standalone host-side POSIX shell script prepares a new named volume from a stopped v1 source; OpenCode performs schema migration only when v2 subsequently starts. The existing devcontainer changes only its Dockerfile selection and data mount. README plus a reusable runbook explain cutover, continuity checks, and two-part rollback.

**Tech Stack:** POSIX sh, Docker CLI, existing Linux helper-image cp/diff, Dev Containers CLI, Bats/bats-support/bats-assert, Python stdlib test helpers, existing Ruff/pre-commit tooling.

**Spec:** `docs/superpowers/specs/2026-10-15-opencode-v2-devcontainer-design.md` (approved 2026-10-15). Read both documents before execution.

## Global Constraints

- Select the existing `../Dockerfile.OpenCode2`, retaining build context `..`.
- Mount `devcontainer-opencode2-data` at `/root/.local/share/opencode` in this repository; retain the original `devcontainer-opencode-data` for rollback.
- Preserve Docker-in-Docker, unrelated editor customizations, and existing feature lock resolutions.
- Do not change image recipes, pins, upgrade selection, image workflows, registry tags, other repositories, or v1 availability.
- No configuration-volume addition, configuration-directory migration, general plugin migration, dependency refresh, or automatic lifecycle migration hook.
- Script interface: `sh /path/to/prepare-opencode2-data.sh SOURCE_VOLUME DESTINATION_VOLUME HELPER_IMAGE` with all arguments explicit and no checkout dependency.
- Host requirements: POSIX shell and Docker CLI. Container helper requirements: `/bin/sh`, `cp -a`, recursive `diff` including `--no-dereference`.
- All helper runs use `--pull=never`, a resolved local immutable image ID, root user, explicit `/bin/sh` entrypoint, and `--network=none`.
- Never migrate, overwrite, or delete the original volume. Never merge into or automatically delete an existing/partial destination.
- Preserve unrelated submodule/metadata changes and reviewed test fixes; recheck status before editing.
- No commits, pushes, or publication unless separately requested; skill commit suggestions are not authorization.
- Keep Bats orchestration and substantial Python in named files; no new production/test dependencies or generalized Docker framework.

## Review Focus

1. Hidden entries, dangling symlinks, and SQLite WAL/SHM must copy intact, without leaking contents in mismatch diagnostics (Tasks 1, 4).
2. Docker outages or permission failures must not be mistaken for an absent destination and followed by volume creation (Task 1).
3. A destination created/populated concurrently must not receive an overlay copy; all source writers, including other repositories, must remain stopped (Tasks 1, 3).
4. A source containing archived/child sessions must not pass continuity verification using only a default top-level/project-limited listing (Task 4).
5. A premature v2 reopen must fail subsequent preparation rather than overwrite new data; rollback must select the original volume as well as v1 (Tasks 1–3).

## File map

| Path | Responsibility |
| --- | --- |
| New `scripts/prepare-opencode2-data.sh` | Standalone copy/preflight/comparison CLI, never OpenCode schema migration |
| New `tests/test_helper/data-copy.bash` | Small isolated Bats fixture setup and assertion wrappers |
| New `tests/test_helper/data-copy-docker.py` | Strict finite Docker stub with JSONL argv logging and failure injection |
| New `tests/test_helper/data_copy_assertions.py` | Named semantic preparation-call and devcontainer-config checks |
| Modify `tests/test-opencode-support.bats` | Register preparation scenarios and config contract in existing suite |
| Modify `.devcontainer/devcontainer.json` | Two-field v2 selection/data-mount change |
| Modify `README.md` | Concise repository rebuild, persistence, verification, and rollback guidance |
| New `docs/opencode-v2-transition.md` | Reusable operational prose and script examples for many repositories |
| Conditional `.opencode/commands/update-devcontainer.md` | Only a demonstrated narrow v2 compatibility correction |

Keep runtime investigation fixtures/evidence under `/tmp/opencode`, using named
files rather than generated Python strings. Do not commit temporary probes or a
container-management framework. Preserve `.devcontainer/devcontainer-lock.json`.

### Task 1: Implement and test the portable data-copy preparation command

**Files:** Create the script and three data-copy test helpers from the file map;
modify `tests/test-opencode-support.bats` to load/register them.

**Interfaces:**
- Production CLI: `prepare-opencode2-data.sh SOURCE_VOLUME DESTINATION_VOLUME HELPER_IMAGE`; `--help` exits 0, malformed usage exits 2, operational failures exit nonzero, successful verified preparation exits 0.
- `setup_data_copy` creates an isolated `DATA_COPY_REPO`, `DATA_COPY_LOG`, `DATA_COPY_STATE`, and PATH-injected Docker stub; copy only the script into a directory with spaces, with no Dockerfiles or checkout metadata.
- Stub entry point `main(argv: list[str]) -> int` reads `DATA_COPY_SCENARIO`, persists finite fixture state in `DATA_COPY_STATE`, records each argv array to `DATA_COPY_LOG`, rejects unknown calls, and never invokes real Docker.
- Assertion CLI: `python3 data_copy_assertions.py calls LOG SCENARIO`; errors return nonzero with expected/actual diagnostics and remain active under `python3 -O`.
- Internal `check_copy_calls(calls: list[list[str]], scenario: str) -> None` raises `ValueError` for invalid log shape or `AssertionError` for semantic contract failures. Bats wrapper `assert_data_copy_calls SCENARIO` invokes it.

- [ ] **Step 1: Add failing Bats scenarios and minimal strict fixtures.** Use test names beginning `data preparation`. Include these assertion contracts:

  | Scenario | Assertions |
  | --- | --- |
  | help/arity/empty/equal/invalid names | Help succeeds without Docker; usage errors fail before Docker; names follow Docker's `[a-zA-Z0-9][a-zA-Z0-9_.-]+` volume-name form |
  | missing source/existing destination | No destination creation, mounts, or copy; refuse empty and populated destinations equally |
  | daemon/list/inspect/consumer/image/preflight failure | Nonzero; no copy; infrastructure errors cannot become an absent-destination result |
  | running source/destination | Nonzero; container names in diagnostic; no stop/remove commands |
  | success | Source inspection before mount; absent destination before creation; local image ID used; tool preflight before create; consumers rechecked; source read-only, no copy-up; archive copy followed by quiet recursive symlink-aware comparison; success says migration has not run |
  | destination populated at mount time | Nonzero; copy not executed; retain destination |
  | copy/comparison/create failure or interruption | Nonzero; no success message, no deletion; warn about partial state once creation may have occurred |
  | standalone/quoted image | Execute copied script from another directory with spaces in script path; image argument remains one argv element; no repository file reads |

  Use source `other-repo-v1`, destination `other-repo-v2`, helper `local-helper:fixture`, and fake ID `sha256:` followed by 64 `a` characters. No actual image fetch occurs. Keep scenario assertions in Bats and named helpers rather than embedding a second shell program in Python.

- [ ] **Step 2: Run red.** `bash tests/run-bats.sh --filter 'data preparation' tests/test-opencode-support.bats`; expect missing-script/behavior failures, not fixture import errors. Provision Bats using existing asdf defaults if needed, without overwriting a user's existing tool-version file.
- [ ] **Step 3: Implement argument validation and fail-closed Docker preflight.** POSIX `#!/bin/sh` and `set -eu`; quote all inputs; accept only `--help` or exactly three nonempty operands. Check daemon/context, inspect source, and distinguish destination absence from CLI failure by a successful volume listing with exact-name comparison. Recheck immediately before creation. Do not parse human-facing error strings to decide absence. Require a valid immutable image ID and preflight actual tool capabilities using a temporary directory inside a no-network helper, before creating a volume.
- [ ] **Step 4: Implement preparation and verification.** Create the new volume, recheck consumers, and run a root no-network helper with explicit read-only `/source` and read-write `/destination` volume mounts and `volume-nocopy`. Inside the helper, require destination emptiness including dot entries, use `cp -a /source/. /destination/`, then `diff -qr --no-dereference /source /destination` with output suppressed. Set a failure-reporting trap once destination creation is attempted; handle HUP/INT/TERM with nonzero exit. Report partial destination on error without deleting resources. Never invoke OpenCode, build/pull images, stop containers, or print file contents.
- [ ] **Step 5: Run focused tests green and shell checks.** Repeat Step 2; run `sh -n scripts/prepare-opencode2-data.sh`, `shellcheck scripts/prepare-opencode2-data.sh`, and the same focused fixture invocations with available alternate POSIX shells (at least dash when available). Expect all pass and identical argument semantics. Validate the fixture helper with existing Ruff checks. Fix only relevant failures.

### Task 2: Switch this repository's devcontainer with a focused contract

**Files:** Modify `.devcontainer/devcontainer.json`, extend
`tests/test_helper/data_copy_assertions.py` and `tests/test-opencode-support.bats`.

**Interfaces:**
- Add `check_devcontainer(root: Path) -> None` and CLI `python3 data_copy_assertions.py config REPO_ROOT`.
- Consumes Task 1's helper file only for colocated transition assertions; the production script remains independent.
- Produces the approved v2 build configuration and a single v2 data mount; no extra lifecycle actions.

- [ ] **Step 1: Add a failing Bats test named `repository devcontainer selects v2 and isolated persistence`.** Parse JSON through the named helper. Assert `build.dockerfile == '../Dockerfile.OpenCode2'`, `build.context == '..'`, and mount string `source=devcontainer-opencode2-data,target=/root/.local/share/opencode,type=volume`. Assert no original-volume or config-directory mount and no migration lifecycle hook. Check Docker-in-Docker options and existing four extensions against the inspected values. Check the lock retains feature `2.17.0` and digest from the spec. Run the test through the supported runner with `--filter 'repository devcontainer'`; expect failure on v1 selection.
- [ ] **Step 2: Change only the Dockerfile and data-volume fields.** Keep all unrelated JSON bytes and the feature lock unchanged. Rerun Step 1; expect pass. Use `git diff -- .devcontainer` to confirm the two intended field changes and unchanged lock.
- [ ] **Step 3: Resolve the actual configuration.** Use an available Dev Containers CLI or provision it only in a temporary tooling directory after plan approval; record its exact version. Run `devcontainer read-configuration --workspace-folder "$PWD" --config .devcontainer/devcontainer.json --include-features-configuration --include-merged-configuration` (using the CLI's supported equivalent flags if necessary). Confirm the merged selection, context, mount, feature lock/digest, Docker privilege/startup requirements, and extensions. Record failures as blockers rather than replacing this with JSON parsing alone. Confirm lock bytes are unchanged.

### Task 3: Write the reusable prose transition and concise README path

**Files:** Create `docs/opencode-v2-transition.md`; modify README's Development
section. No tests that merely assert documentation wording.

**Interfaces:** Consumes Task 1's exact three-operand CLI and Task 2's actual
selection/mount. Produces host-side instructions and explicit human verification
steps without requiring this repository's checkout in a downstream consumer.

- [ ] **Step 1: Write preparation and cutover instructions.** Include commands for `docker context show`, inspecting the current container's `.Mounts`/`.Config.Image`, listing running consumers of the discovered source, recording workspace path/session IDs, and obtaining a standalone script copy before stopping containers. Show parameterized `SOURCE_VOLUME`, `DESTINATION_VOLUME`, and `HELPER_IMAGE`, followed by this repository's concrete names. Explain local helper preflight/no pull, complete stopped copy including SQLite sidecars, shared sources across projects, Docker's non-atomic destination creation, partial-destination handling, and premature-reopen recovery using another new name. Host daemon, not nested DinD, is required. Never prescribe automatic removal, in-place retries, or a broad stop-all-containers command.
- [ ] **Step 2: Write migration and continuity instructions.** Start v2 only after successful preparation; document `opencode --version`, `opencode debug paths`, `opencode api experimental.migration.v1.status`, migration logs, `opencode auth list`, representative transcripts, account interaction, and recreation. Provide exact read-only inventory commands validated in Task 4 for **all** v1 `session` and v2 `session_v2` IDs, or fully paginated APIs. An explicitly described helper image can supply SQLite tooling; do not add a host Python requirement to the copy script. Inventory queries run after servers are stopped and show IDs/counts only, never credential values. Clearly disclose the pinned migrator's permission/revert resets, interrupted tools, malformed-row skips, attachment limits, and provider-dependent token refresh.
- [ ] **Step 3: Write rollback and downstream-repository guidance.** Restore v1 recipe/image **and** original mount, retain both volumes, preserve workspace path, and verify known v1 history. Explain cutover snapshots/no reverse merge and possible OAuth reauthentication on rollback. For this repository show `../Dockerfile.OpenCode`, context `..`, and `devcontainer-opencode-data`; use discovered values elsewhere. Document that image/config changes elsewhere are manual and outside this rollout.
- [ ] **Step 4: Add concise README guidance.** Link the runbook; foreground copy-before-first-v2-reopen, exact current mount, VS Code rebuild/reopen command, pin verification, persistent data, and two-part rollback. Keep existing build/upgrade documentation intact. Check links and commands against Tasks 1–2, run `git diff --check`, and validate commands during Task 4. Do not add global-config instructions.

### Task 4: Exercise the script and actual devcontainer; resolve integration evidence

**Files:** Temporary named fixtures/evidence under `/tmp/opencode`; conditional
minimal command fix plus its focused regression in existing test/helper paths;
update the runbook only to correct validated operational commands.

**Interfaces:** Consumes production preparation CLI, checked-in devcontainer
configuration, existing Dockerfile pin, and runbook commands. Produces recorded
evidence with explicit platform, CLI/image IDs, test-resource ownership, commands,
and pending human steps. It does not change recipes/pins to make a check pass.

- [ ] **Step 1: Establish the runtime boundary and resource ownership.** Record Docker daemon/context/platform and current volumes/containers; never assume this nested daemon owns the user's actual volume. Name synthetic v1 sources uniquely. If configured `devcontainer-opencode2-data` already exists, preserve it and use the spec's isolated override route; otherwise record its creation as a disposable test destination. Record existing lock hash. Keep logs free of real secrets.
- [ ] **Step 2: Seed and stop a v1 fixture.** Use existing pinned v1 image; make a genuine session/user message with `noReply` through its API, then stop it. Use a named temporary fixture file for synthetic assistant/completed-tool data, archived and child sessions, and a synthetic `auth.json` key. Add hidden files, WAL/SHM sidecars as present, a dangling symlink, modes/timestamps, and a subdirectory. Record source file hashes/link targets and an all-session-ID inventory after quiescence. Use no real provider requests.
- [ ] **Step 3: Run the actual preparation script and verify its real-file contract.** Require successful copy/comparison; independently compare contents/link targets and selected modes/ownership/timestamps. Rerun against the existing destination and test a running source consumer; both must fail without altering data. Exercise dangling symlinks in the real copy; use the controlled comparison failure from Task 1 to assert that mismatch diagnostics contain no sentinel file contents. Keep real Docker fixtures outside default mocked Bats execution.
- [ ] **Step 4: Build/start with Dev Containers CLI.** Run `devcontainer up --workspace-folder "$PWD" --config .devcontainer/devcontainer.json`, with a timeout of at least 1,200,000 ms. Use the exact config if its mount is a newly owned test volume; otherwise retain relative path resolution and feature lock in the isolated copy and label results accurately. Save structured returned container ID. Inspect actual mounts, feature metadata, privilege/startup options, and workspace directory in the running container; compare pin via `ARG OPENCODE_VERSION` from the existing Dockerfile and normalized `opencode --version`.
- [ ] **Step 5: Verify v2 startup, migration, and nested Docker.** In that container start OpenCode's service/API, poll migration until `completed` or concrete error, inspect warnings, and check known user/assistant/tool history and credential **presence only**. Run `docker info` inside it and execute a disposable nested container (for example `docker run --rm hello-world`, recording pull/network failures separately). Confirm this is its nested daemon, not the host socket. No model execution is needed for synthetic checks.
- [ ] **Step 6: Verify all-session continuity and recreation.** Stop OpenCode before read-only DB inventory. Compare all source `session` IDs to destination `session_v2` IDs with missing/extra output and counts, explicitly including archived/child fixtures. Do not compare message counts as if migration were one-to-one. Create a new no-model v2 session through its API, remove only the owned outer test container, run `up` again with the same volume, and confirm old/new sessions persist. Recheck source hashes **before** reopening it with v1, then use v1 on that original fixture to verify rollback readability. Validate inventory/runbook commands with these fixtures.
- [ ] **Step 7: Investigate command discovery in the actual repository location.** Check `opencode api command.list` and location selection/config sources; investigate service readiness, logs, and pinned command parser behavior. Confirm `update-devcontainer` registration, description/template, and model override without executing its version-changing prompt. If evidence warrants a small command-file correction, add a focused failing regression using the existing test dependencies, apply only that correction, and rerun affected tests. Treat recipe/pin/plugin migration requirements as concrete blockers needing a decision.
- [ ] **Step 8: Record pending interactive checks and clean owned resources.** Provide exact VS Code **Rebuild and Reopen in Container**, **Open opencode**, file-reference shortcut, `/connect` only if needed, model-availability, and read-only-prompt steps. Mark real user-volume copy, OAuth refresh, GUI launch, and actual-history validation pending when inaccessible. Retain concise command/platform/results evidence for the final response, then remove only logged disposable containers/volumes/temp configuration. Never delete an unfamiliar volume or image to clean up.

### Task 5: Run applicable checks and hand off verification results

**Files:** Implementation paths above; no new framework or pipeline files.

**Interfaces:** Consumes Tasks 1–4's artifacts/results; produces a reviewed diff
and accurate completion/blocker report. No commit operation is included.

- [ ] **Step 1: Run final relevant shell/Python checks.** `sh -n scripts/prepare-opencode2-data.sh` and `pre-commit run --files scripts/prepare-opencode2-data.sh tests/test-opencode-support.bats tests/test_helper/data-copy.bash tests/test_helper/data-copy-docker.py tests/test_helper/data_copy_assertions.py`. Include any conditional edited command file. Expect applicable hooks pass; do not run `make pre-commit` or autoupdate dependencies.
- [ ] **Step 2: Run the complete registered suite.** `bash tests/run-bats.sh tests/test-bats-support.bats tests/test-gh-support.bats tests/test-opencode-support.bats tests/test-file-support.bats`. Expect all existing and new scenarios plus Python/Ruff checks pass. Distinguish existing live dependency/network checks from new offline mocked scenarios. Broaden testing only for new failures or unresolved concerns; standalone image rebuilds are not a substitute for Task 4.
- [ ] **Step 3: Review preservation and final diff.** Run `git diff --check`, `git status --short`, and focused diffs including untracked implementation files. Confirm all Dockerfiles/pins, Makefile, image workflows, package locks, feature lock, and unrelated submodule/metadata changes are preserved. Inspect newly added files directly; `git diff --check` alone does not check untracked contents.
- [ ] **Step 4: Report results separately.** Summarize static/configuration checks; actual devcontainer build/start/version and DinD; script/migration/persistence/original-volume fixture checks; command/editor compatibility; real-data migration and interactive dogfooding. Include concrete blockers and exact human steps. Do not describe fixture success as migrated user data or infer CI/publication evidence. No commit/push unless separately requested.

## Plan self-review

Completed against the approved spec using the writing-plans checklist:

- **Spec coverage:** Task 1 owns the complete portable-script contract and failure tests; Task 2 owns exact devcontainer selection and static resolution; Task 3 owns prose/rebuild/rollback/shared-consumer instructions; Task 4 owns actual container/migration/DinD/persistence/integration evidence; Task 5 owns applicable checks and bounded reporting. No uncovered deliverable was found.
- **Step scan:** Steps specify file/interface, behavior, command or measurable result. Unknown upstream command discovery is explicitly a runtime investigation with a bounded correction/blocker path, not a speculative plugin migration. Documentation commands are validated against disposable fixtures before handoff.
- **Interface consistency:** The three production operands and data-volume names match throughout. Bats setup, state/log names, assertion CLI, and config-check signatures agree across tasks; helper files remain within existing Ruff discovery.
- **Review Focus:** All five cases are assigned to concrete mock tests or real fixtures. Added fail-closed destination discovery, populated-destination refusal, and archived/child-session inventories; no default session listing can stand in for complete continuity.
- **Proportion/scope:** Five cohesive tasks reuse the existing suite and tooling. No implementation bodies, new dependencies, image recipes, automatic migration hooks, or unrelated framework changes are prescribed. Temporary runtime fixtures are not production deliverables.
- **Evidence/preservation:** Source hashes are checked before v1 rollback-readability testing can legitimately write to the fixture. Exact versus overridden config results, synthetic versus real data, and interactive versus API evidence remain separate. No commit is included without separate authorization.

Plan awaits user review and execution-method selection. Implementation has not started.
