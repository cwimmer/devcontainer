# OpenCode test Python extraction

**Date:** 2026-10-15
**Status:** Approved by the user on 2026-10-15
**Repository:** `cwimmer/devcontainer`

## Intent

Make the OpenCode integration tests easier to read, maintain, and debug before
part three's dogfooding work. Keep Bats as the integration runner and preserve
the intended build, upgrade, verification, publication, and cleanup coverage.

The two conventions are:

1. Trivial fixtures expressed as heredocs are reasonable.
2. Substantial Python belongs in checked-in `.py` files.

Apply these by purpose and complexity. Repeated parsing, branching, and
assertions belong in named helpers regardless of their individual length.

## Repository findings

Inspected the OpenCode Bats suite, all its helpers, the other suite entry points,
Make targets, image workflow, pre-commit configuration, Dockerfile dependencies,
README development guidance, previous rollout designs, and recent commits.
Relevant commits are `2347869`, `81d6ed3`, and `8286968`.

There is no root or test-tree `AGENTS.md`. The nested Superpowers repository has
its own contributor instructions; it is not the target of this maintenance.
The repository-resident Superpowers brainstorming skill was consulted.
The wiki-context skill is unavailable; repository documentation was inspected
directly.

`test-opencode-support.bats` combines updater checks, workflow checks, real Make
execution against a Docker stub, and verifier checks. Both Make base targets and
CI explicitly include this Bats file. `image-build.bash` repeats JSONL decoding
and comparisons. `image-docker.py` is already standalone and rejects unknown
commands. The curl fixture also rejects unknown URLs.

The workflow tests independently reconstruct YAML blocks by indentation and
compare text fragments. The existing pre-commit hooks cover YAML, shell, and
Actions, but not Python. Python and pip are explicitly installed in the base
image; PyYAML and Ruff are not declared test dependencies.

## Approaches considered

| Approach | Benefits | Costs |
| --- | --- | --- |
| **Two focused Python helpers plus PyYAML (recommended)** | Shared log decoding; semantic workflow checks; readable Bats; small, familiar dependency | Requires explicit test dependency setup in local and CI runners |
| Extract existing text-based workflow checks unchanged | Smallest immediate movement; standard-library-only helpers | Retains duplicated or fragile parsing and rejects harmless YAML formatting changes |
| Move scenarios into Python unittest or pytest | Natural Python fixtures and assertions | Splits integration orchestration across runners and adds more machinery than this task needs |

The recommendation is the smallest maintainable semantic approach: use a
standard YAML loader and a few workflow-specific functions. Do not implement a
YAML parser or a general Actions-expression evaluator.

## Proposed design

### 1. Keep integration intent in Bats

Keep the existing `tests/test-opencode-support.bats` registration and scenarios.
Shell retains temporary setup, environment overrides, Make/script execution,
loops over architectures and failures, and straightforward assertions.

Retain useful literal JSON and shell fixture heredocs. Replace Python-backed
empty-log checking with a Bash assertion that the log exists and is empty, with
a short diagnostic and log contents on failure.

Use thin, descriptively named Bash wrappers for Python checks, for example:

```bash
assert_image_builds "$expected_builds"
assert_v2_builds_precede_verification
assert_build_failure_stops_verification "$failure"
```

These names illustrate the intended interface; final names are implementation
details. Do not introduce a generic assertion language or pass executable Python
through arguments, `-c`, or generated strings.

### 2. Shared command-log helper

Add `tests/test_helper/image_assertions.py` with a small command-line interface
and cohesive functions for:

- Reading the stub's JSONL argument arrays once per helper invocation.
- Comparing complete calls, normalized build records, and verifier calls.
- Checking base runtime/build prerequisites before v2 builds and verification.
- Checking which later operations are forbidden after each controlled failure.
- Checking builder fallback and cleanup attempts.

Retain explicit expected build sequences in Bats so Dockerfile, tag, platform,
load, and pull expectations remain visible. Pass the log pathname, scenario
selector, and expected JSON as separately quoted arguments. File inputs remain
available where a fixture is clearer than an argument. Never split shell
command strings to reconstruct arguments.

Malformed JSONL diagnostics include pathname and line number. Comparison and
ordering failures identify the expectation and show actual commands or relevant
indices. Missing or malformed options fail clearly rather than producing an
unexplained `IndexError` or `StopIteration`. Assertion failures return nonzero
and remain effective under Python optimization.

Keep `image-docker.py` as a separate stub and explicitly adapt its suite-command
recognition to the new invocation through `tests/run-bats.sh`. Match the runner
command in the Docker command's argument array, including the explicit shell
invocation if used by Make; do not look only for a `bats` token or use a broad
substring match. Preserve the existing direct-Bats form where still needed.
For the recognized suite invocation, log the original arguments and return
`IMAGE_BATS_STATUS` (default zero), without running the runner, installing
dependencies, or executing Bats recursively. Unknown commands still fail.

Apply Python checks to the stub and limit other changes to small readability
or lint-driven adjustments. It never delegates to real Docker. Preserve isolated
temporary repositories, spaced paths, explicit argument arrays, and controlled
response files.

### 3. Semantic workflow helper

Add `tests/test_helper/workflow_assertions.py`. Load the workflow once per
invocation with pinned, test-only PyYAML and a small local subclass of
`yaml.SafeLoader`. Copy its implicit-resolver tables before modifying them;
replace only Boolean resolution with a resolver for unquoted `true` and `false`
(case-insensitive). Leave other safe constructors unchanged and never mutate
PyYAML's global loader configuration. This retains safe loading while avoiding
YAML 1.1's interpretation of an unquoted `on` key as Boolean true. Quoted and
unquoted `on` must both produce the same string key and trigger checks. Do not
repair Boolean keys after loading or implement a general YAML compatibility
layer. Validate the expected mapping/list shapes and identify the build job and
relevant steps by v2 IDs and existing base/v1 identities.

Use named checks for these existing contracts:

- Push and pull-request triggers include main; manual dispatch remains present.
- Base and v1 retain their image identities, Dockerfile selection where
  explicit, both platforms, and main-only publication expression.
- Native v2 build precedes verification, which precedes v2 publication.
- V2 native build uses the intended action, context, file, sole tag, amd64
  platform, pull/load settings, and timeout, without publication.
- Verification runs the shared script against the v2 image with its timeout.
- V2 publication uses the intended action, context, file, sole tag, both
  platforms, pull setting, and main-only publication expression.
- Relevant steps and their enclosing job retain normal failure gating.

Compare loaded mappings rather than substrings. For supported Boolean action
inputs (`load`, `pull`, and a literal `push`), use one explicit normalizer:
accept actual booleans and strings spelling `true` or `false` after trimming
and case normalization; reject numbers, null, other strings, and expressions.
The publication `push` expression is checked separately against the existing
main-only contract. Use the same explicit Boolean handling for
`continue-on-error`, whose expression values remain forbidden. Never use Python
truthiness or `value or default`: quoted `"false"` and unquoted `false` must both
remain false. Distinguish missing inputs from explicit false values; apply
documented defaults only where the contract permits omission, such as omitted
native `push` or omitted `continue-on-error` meaning false. Required pull/load
settings must still be present.

Normalize the documented comma/newline-separated tag and platform values.
Accept equivalent YAML indentation, key order, quoting, scalar layout, and
comments subject to the command-boundary rules below.

#### Supported verifier command forms

Validate the decoded `run` scalar as exactly one simple shell invocation with
these three arguments, in order:

```text
sh scripts/verify-opencode2.sh ghcr.io/cwimmer/devcontainer:opencode2
```

Support plain or quoted YAML scalars, folded scalars that decode to one command,
and literal scalars containing either a single command line or explicit shell
backslash-newline continuations. Shell quoting of individual arguments and
ordinary horizontal whitespace are acceptable. Leading/trailing blank lines
and a final newline are acceptable. A representative valid literal form is:

```yaml
run: |
  sh scripts/verify-opencode2.sh \
    ghcr.io/cwimmer/devcontainer:opencode2
```

Use a narrow, quote-aware lexical check for this simple-command subset: preserve
unescaped newline boundaries, recognize backslash-newline continuation outside
single quotes, and reject command separators/operators, substitutions,
redirections, and extra commands. After establishing that there is exactly one
nonblank logical command, use standard-library shell lexing to compare its
argument vector to the three expected tokens. Do not execute the scalar or
flatten it with whitespace splitting. Multiline quoted arguments and other
shell-program forms are outside the supported subset and fail clearly. This
is a focused command check, not a general shell parser or expression evaluator.

In particular, reject this valid YAML because it invokes two shell commands and
does not pass the image argument to the verifier:

```yaml
run: |
  sh scripts/verify-opencode2.sh
  ghcr.io/cwimmer/devcontainer:opencode2
```

Diagnostics distinguish an unsupported/multiple-command form from an incorrect
argument vector and identify the verification step's `run` field.

Reject enabled or expression-valued `continue-on-error` at relevant scopes.
For relevant step/job conditions, accept the implicit default success gate and
an explicit equivalent `success()` gate; reject bypassing or unknown custom
conditions with a useful diagnostic. Do not attempt arbitrary expression
evaluation. Preserve the main-only push expression as an explicit contract.

Use workflow paths in errors, for example
`jobs.build.steps[publish_opencode2].with.platforms`, with expected and actual
values. Missing PyYAML reports the documented dependency setup command.

### 4. Correct and consolidate assertions

Explain these changes in the implementation report:

- Replace `v2[0].index('--platform') < v2[1].index('--platform')`: it compares
  positions inside separate argument arrays, not execution order. The exact
  build sequence already establishes multi-platform-before-native ordering;
  retain explicit build-before-verification and base-runtime-before-v2 checks.
- Remove the repeated arm64 reparsing blocks: the exact per-target build matrix
  already checks those platforms for both `arm64` and `aarch64`.
- Collapse the architecture test's three identical `assert_success` branches.
- Remove the duplicate no-v1 assertion within the native scenario and repeated
  field/count assertions subsumed by exact structured comparisons.
- Replace blanket textual rejection of `continue-on-error` with checking its
  effective setting, so an explicit false value remains valid.

Updater scenario coverage stays intact. Preserve image selection, all three
host architecture spellings, dynamic pin/version verification, immutable local
image execution, failure propagation, stale-image prevention, publication gates,
builder fallback, and best-effort cleanup.

### 5. Dependencies and execution integration

Add `tests/requirements.txt` with exact pins for PyYAML and Ruff, selected and
verified at implementation time. These are test dependencies, not image tools.

Add a small `tests/run-bats.sh` runner that:

1. Creates a temporary dependency directory and cleans it up on exit.
2. Uses the image's explicit Python/pip installation to install the pinned
   requirements into that directory with `pip --target`.
3. Exposes those packages only for this test invocation.
4. Runs Ruff lint and format checks on the affected test Python code.
5. Invokes Bats with the caller's original arguments and propagates failures.

Dependency provisioning is an explicit setup phase that can access the package
index; mocked test execution performs no network or daemon access. Do not rely
on incidental global packages or disable externally-managed-Python protections.
The runner preserves argument boundaries and supports paths containing spaces.

Update only the suite invocation in `make test`, `make test_native`, and the CI
Bats step to call this runner with their existing Bats file lists. Derived
targets continue to obtain suite coverage through their existing prerequisites.
Retain their public entry points and build commands. Direct Bats invocation is
also possible with the declared dependencies explicitly provisioned; document
the supported runner as the reproducible command.

Update the copied Make-test fixture and Docker stub together: mocked Make
execution must recognize the runner command without executing it. Test both a
successful simulated suite and nonzero `IMAGE_BATS_STATUS`. A simulated suite
failure must fail base targets and stop derived targets before any derived build
or verification. Keep dependency provisioning exclusive to actual runner
execution, outside these mocked command simulations.

Add pinned Ruff lint and format hooks to `.pre-commit-config.yaml`, scoped to
the affected test Python tree and matching the requirements version. Use Ruff's
default lint rules and formatter without introducing broad Python policy.
CI executes the same checks through the runner; pre-commit provisions its own
isolated hook environment.

### 6. Focused helper regression evidence

Add a small stdlib unittest module under `tests/` for the extracted logic,
invoked by a Bats case in the existing registered file. No new test framework.
Fixtures use temporary files or small checked-in data where useful.

Exercise meaningful failures rather than mirroring every implementation branch:

- A wrong build tag/platform, forbidden post-failure operation, and reordered
  verification fail with descriptive diagnostics.
- Malformed JSONL reports its source line; spaced paths and argument boundaries
  survive the CLI.
- Wrong publication condition, missing verification, bypassed failure gate,
  and wrong native build settings fail with semantic field diagnostics.
- Equivalent workflow fixtures cover quoted and unquoted `on` keys, indentation,
  key order, comments, and supported scalar layouts. Exercise unquoted booleans
  and quoted `"true"`/`"false"` action inputs, including native `push: false`
  and `continue-on-error: false` in both forms. Verify false remains false;
  enabled failure bypasses and invalid Boolean values still fail.
- Positive verifier fixtures cover a one-line scalar, the current folded form,
  a single-command literal scalar, argument quoting, and a literal scalar with
  explicit backslash-newline continuation. Negative fixtures cover the script
  and image on separate literal lines, a missing or wrong image argument,
  an extra command separated by newline or semicolon, and an operator or
  substitution. Check useful `run`-field diagnostics.
- Mocked Make targets accept the new runner invocation and retain their expected
  build/verification sequence with default suite success. Nonzero
  `IMAGE_BATS_STATUS` fails both base entry points and all four derived entry
  points, with no derived build or verification after the suite failure.
  Recognition tests prove that the runner is simulated even when its file is
  unavailable in the temporary repository: no dependency installation or
  recursive Bats execution is needed for the mock to succeed.

Keep regression cases deterministic and ensure they run through both local and
CI Bats entry points.

### 7. Contributor guidance

Extend `README.md`'s existing Development / Testing section with the two accepted
conventions, their purpose/complexity interpretation, helper locations, explicit
dependency setup through the runner, and focused/full-suite commands. Avoid a
new contributor document for this small maintenance step.

## Verification after approval and implementation

1. Run the focused OpenCode Bats suite through the supported runner, including
   the helper regressions and mocked Make/verifier scenarios. Include runner
   recognition and suite-failure propagation, YAML key/Boolean equivalence,
   false-value preservation, and positive/negative verifier command fixtures.
2. Run the existing full Bats file list through that runner in the supported
   base-image environment. The existing unrelated gh/bats discovery smoke tests
   may use the network; distinguish these from the offline mocked tests.
3. Run pinned Ruff lint/format checks, shell syntax checks, applicable
   pre-commit hooks, and `git diff --check`.
4. Verify local and CI suite argument lists still include the OpenCode file and
   its helper regressions. Exercise changed runner integration with an existing
   suitable base image where available. Rebuild only if needed to establish
   that integration; extraction alone does not require derived-image rebuilds.
5. Report actual commands and outcomes, coverage corrections, and unavailable
   checks separately. Static workflow validation is not remote CI execution.

At design time, Python 3.12.3, pip-backed image tooling, a Bats shim, pre-commit,
and Docker commands are present. Their presence does not establish successful
suite execution or daemon availability. No verification results are claimed yet.

## Scope boundaries and approval

Changes are limited to tests/helpers, test dependency and lint configuration,
the Make/CI test invocation, README testing guidance, and this design document.
Dockerfiles, installed tool versions, upgrade behavior, tags, build recipes,
publication behavior, `.devcontainer/`, and dogfooding are outside this change.
Preserve unrelated working-tree changes, including the modified Superpowers
submodule and untracked metadata files.

The helper names and small internal function decomposition are left to the
implementer. The user approved the revised dependency/setup approach and semantic
workflow contracts above on 2026-10-15.

Implementation follows a separately reviewed implementation plan.
