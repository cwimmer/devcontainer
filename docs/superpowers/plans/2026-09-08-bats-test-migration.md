# BATS Test Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the three ad hoc Bash test scripts in `tests/` with an idiomatic BATS test suite (`bats-core` + `bats-assert` + `bats-support`) that preserves every existing assertion, runnable locally via `make test_native` and in CI.

**Architecture:** Translate each `tests/test-*-support.sh` to a parallel `tests/test-*-support.bats` file with one `@test` per existing assertion. Install `bats-support` and `bats-assert` into the devcontainer image at `/usr/local/share/bats-{support,assert}` via pinned `ARG` values and `git clone --branch v<version>` lines in `Dockerfile`. Run the BATS suite inside the built image via `docker run`, with `tests/` bind-mounted in. Add a `test` job to the CI workflow that consumes a locally-loaded single-platform build (avoiding the multi-platform `--load` limitation). Extend the existing `shellcheck-py` pre-commit hook to lint `.bats` files.

**Tech Stack:** BATS 1.14.0 (already installed via asdf), `bats-support` 0.3.0, `bats-assert` 2.1.0, Make, Docker buildx, pre-commit, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-09-08-bats-test-migration-design.md`

## Global Constraints

- BATS runner version: `BATS_VERSION=1.14.0` (already in `Dockerfile`).
- `bats-support` version: `BATS_SUPPORT_VERSION=0.3.0` (pinned in `Dockerfile`).
- `bats-assert` version: `BATS_ASSERT_VERSION=2.1.0` (pinned in `Dockerfile`).
- Helper libraries installed at `/usr/local/share/bats-support` and `/usr/local/share/bats-assert` (absolute paths inside the image).
- No new dependency-management mechanism: install via `RUN git clone --branch v<version>` lines in `Dockerfile`, mirroring the `doctl` precedent (pinned in Dockerfile, not in `scripts/update-versions.sh`).
- Test runner location: BATS runs **inside** the built devcontainer image; `make` targets invoke `docker run`.
- Pre-commit coverage: the existing `shellcheck-py` hook must lint `.bats` files (via explicit `files:` regex).
- Commit messages: follow Conventional Commits v1.0.0 (per `.github/copilot-instructions.md`). Avoid the word "comprehensive".
- Shell scripts must be POSIX-compliant where possible and include error handling (per `.github/copilot-instructions.md`).

---

## File Structure

Files to **create**:

- `tests/test_helper/common.bash` — shared `REPO_ROOT` resolver for every `.bats` file.
- `tests/test-bats-support.bats` — 6 `@test` blocks mirroring `test-bats-support.sh`.
- `tests/test-gh-support.bats` — 5 `@test` blocks mirroring `test-gh-support.sh`.
- `tests/test-opencode-support.bats` — 10 `@test` blocks mirroring `test-opencode-support.sh`.

Files to **modify**:

- `Dockerfile` — add two `ARG`s and two `RUN git clone` lines for `bats-support` and `bats-assert`.
- `Makefile` — replace `./tests/test-*-support.sh` invocations in `test:` and `test_native:` with one `docker run ... bats tests/*.bats`.
- `.pre-commit-config.yaml` — extend `shellcheck-py` hook with `files: \.(bash|sh|bats)$` and `args: [-x]`.
- `.github/workflows/image-build.yaml` — add a single-platform `load: true` build step in the `build` job; add a `test` job that runs BATS against the loaded image.
- `README.md` — add a `## Testing` subsection.
- `docs/superpowers/specs/2026-04-25-bats-devcontainer-design.md` — annotate that the original smoke test has been migrated.

Files to **delete** (after Task 10):

- `tests/test-bats-support.sh`
- `tests/test-gh-support.sh`
- `tests/test-opencode-support.sh`

---

### Task 1: Install bats-support and bats-assert in the devcontainer image

**Files:**
- Modify: `Dockerfile:3-16` (version `ARG` block)
- Modify: `Dockerfile:74-96` (between asdf install block and asdf-tool-versions generation)

**Interfaces:**
- Produces: a built image where `/usr/local/share/bats-support/load.bash` and `/usr/local/share/bats-assert/load.bash` exist and are sourced by `load` directives in `.bats` files (verified in Task 3).

- [ ] **Step 1: Add the helper-library `ARG` values to `Dockerfile`**

In the existing version `ARG` block in `Dockerfile` (lines 3–16), add two new lines immediately after the existing `ARG BATS_VERSION=1.14.0`:

```dockerfile
ARG BATS_ASSERT_VERSION=2.1.0
ARG BATS_SUPPORT_VERSION=0.3.0
```

Final block should look like:

```dockerfile
ARG ASDF_VERSION=v0.20.0
ARG BATS_VERSION=1.14.0
ARG BATS_ASSERT_VERSION=2.1.0
ARG BATS_SUPPORT_VERSION=0.3.0
ARG DOCTL_VERSION=1.168.0
ARG GH_VERSION=2.100.0
ARG GOLANG_VERSION=1.27.1
ARG HELM_VERSION=4.2.4
ARG KIND_VERSION=0.33.0
ARG KUBECTX_VERSION=0.11.0
ARG KUBECTL_VERSION=1.37.0
ARG TERRAFORM_DOCS_VERSION=0.24.0
ARG TERRAFORM_VERSION=1.16.1
ARG TFLINT_VERSION=0.64.0
ARG TRIVY_VERSION=0.74.0
```

- [ ] **Step 2: Add the helper-library `git clone` lines to `Dockerfile`**

Insert this block immediately **after** the existing `RUN asdf install kubectx $KUBECTX_VERSION` line (line 81 in the current Dockerfile) and **before** the `RUN printf '%s\n'` block that writes `/usr/local/share/asdf-tool-versions`:

```dockerfile
# BATS helper libraries (loaded from /usr/local/share/bats-{support,assert} by .bats tests)
RUN git clone --depth 1 --branch v$BATS_SUPPORT_VERSION \
        https://github.com/bats-core/bats-support.git /usr/local/share/bats-support
RUN git clone --depth 1 --branch v$BATS_ASSERT_VERSION \
        https://github.com/bats-core/bats-assert.git /usr/local/share/bats-assert
```

- [ ] **Step 3: Build the image locally and verify the helper libs are present**

Run:

```bash
docker buildx build --load --platform linux/amd64 --tag ghcr.io/cwimmer/devcontainer:latest .
```

Expected: build succeeds.

Then verify the helper libraries are in the image:

```bash
docker run --rm ghcr.io/cwimmer/devcontainer:latest ls -1 /usr/local/share/bats-support/load.bash /usr/local/share/bats-assert/load.bash
```

Expected output (paths printed, no errors):

```
/usr/local/share/bats-support/load.bash
/usr/local/share/bats-assert/load.bash
```

- [ ] **Step 4: Commit**

```bash
git add Dockerfile
git commit -m "feat(devcontainer): ship bats-support and bats-assert"
```

---

### Task 2: Create the shared `REPO_ROOT` helper

**Files:**
- Create: `tests/test_helper/common.bash`

**Interfaces:**
- Produces: `REPO_ROOT` environment variable pointing at the repository root, exported so child processes see it.

- [ ] **Step 1: Create the helper file**

Create `tests/test_helper/common.bash` with the following content:

```bash
# Resolve REPO_ROOT once. BATS_TEST_DIRNAME is the directory of the .bats file
# (i.e. tests/), so its parent is the repository root.
REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
export REPO_ROOT
```

- [ ] **Step 2: Verify the file is created and contains the expected content**

Run:

```bash
cat tests/test_helper/common.bash
```

Expected: the file content above is printed.

- [ ] **Step 3: Commit**

```bash
git add tests/test_helper/common.bash
git commit -m "test: add shared REPO_ROOT helper for bats tests"
```

---

### Task 3: Migrate test-bats-support.sh to BATS

**Files:**
- Create: `tests/test-bats-support.bats`
- Reference (read-only, for translation): `tests/test-bats-support.sh`

**Interfaces:**
- Consumes: `$REPO_ROOT` from `tests/test_helper/common.bash` (Task 2), bats-support and bats-assert loaded by absolute path from `/usr/local/share/...` (Task 1).

- [ ] **Step 1: Create `tests/test-bats-support.bats`**

Create `tests/test-bats-support.bats` with the following content:

```bash
#!/usr/bin/env bats

load 'test_helper/common'
load '/usr/local/share/bats-support/load'
load '/usr/local/share/bats-assert/load'

@test "make upgrade-bats target is available" {
    run make -s -n -C "$REPO_ROOT" upgrade-bats
    assert_success
}

@test "upgrade check for bats succeeds" {
    run bash "$REPO_ROOT/scripts/update-versions.sh" --tool bats --check-only
    assert_success
}

@test "Dockerfile pins BATS_VERSION" {
    run grep -Fq -- "ARG BATS_VERSION=" "$REPO_ROOT/Dockerfile"
    assert_success
}

@test "Dockerfile installs bats via asdf" {
    run grep -Fq -- "RUN asdf plugin add bats https://github.com/timgluz/asdf-bats.git" "$REPO_ROOT/Dockerfile"
    assert_success
}

@test "Dockerfile includes bats in asdf-tool-versions generation" {
    run grep -Fq -- '"bats $BATS_VERSION" \\' "$REPO_ROOT/Dockerfile"
    assert_success
}

@test "README lists bats as asdf-managed" {
    run grep -Fq -- '| bats | asdf |' "$REPO_ROOT/README.md"
    assert_success
}
```

- [ ] **Step 2: Run the new bats file inside the built image and verify it passes**

Run:

```bash
docker run --rm -e ASDF_BATS_VERSION=1.14.0 -v "$(pwd):/repo" -w /repo/tests ghcr.io/cwimmer/devcontainer:latest bats test-bats-support.bats
```

Expected: 6 tests, all pass. Output includes `1..6` plan line and `ok N` for each test.

- [ ] **Step 3: Verify a failing assertion produces a useful diagnostic**

Temporarily break the test by inserting an obvious failure. Run:

```bash
sed -i 's|"ARG BATS_VERSION="|"ARG BATS_VERSION=THIS_DOES_NOT_EXIST"|' tests/test-bats-support.bats
docker run --rm -e ASDF_BATS_VERSION=1.14.0 -v "$(pwd):/repo" -w /repo/tests ghcr.io/cwimmer/devcontainer:latest bats test-bats-support.bats
```

Expected: at least one test fails with a message indicating the missing substring, e.g. `grep ... No such file or directory` or a non-zero status from the `run` invocation. The failing `@test` name must be visible in the output.

Then revert:

```bash
git checkout -- tests/test-bats-support.bats
```

- [ ] **Step 4: Commit**

```bash
git add tests/test-bats-support.bats
git commit -m "test: migrate bats-support smoke test to bats"
```

---

### Task 4: Migrate test-gh-support.sh to BATS

**Files:**
- Create: `tests/test-gh-support.bats`
- Reference (read-only, for translation): `tests/test-gh-support.sh`

- [ ] **Step 1: Create `tests/test-gh-support.bats`**

Create `tests/test-gh-support.bats` with the following content:

```bash
#!/usr/bin/env bats

load 'test_helper/common'
load '/usr/local/share/bats-support/load'
load '/usr/local/share/bats-assert/load'

@test "make upgrade-gh target is available" {
    run make -s -n -C "$REPO_ROOT" upgrade-gh
    assert_success
}

@test "upgrade check for gh succeeds" {
    run bash "$REPO_ROOT/scripts/update-versions.sh" --tool gh --check-only
    assert_success
}

@test "Dockerfile installs gh via apt" {
    run grep -Fq -- "https://cli.github.com/packages/githubcli-archive-keyring.gpg" "$REPO_ROOT/Dockerfile"
    assert_success
}

@test "Dockerfile installs pinned gh version" {
    run grep -Fq -- 'apt-get install -y gh=$GH_VERSION' "$REPO_ROOT/Dockerfile"
    assert_success
}

@test "README lists gh as apt-managed" {
    run grep -Fq -- '| gh | apt |' "$REPO_ROOT/README.md"
    assert_success
}
```

- [ ] **Step 2: Run the new bats file and verify it passes**

Run:

```bash
docker run --rm -e ASDF_BATS_VERSION=1.14.0 -v "$(pwd):/repo" -w /repo/tests ghcr.io/cwimmer/devcontainer:latest bats test-gh-support.bats
```

Expected: 5 tests, all pass.

- [ ] **Step 3: Commit**

```bash
git add tests/test-gh-support.bats
git commit -m "test: migrate gh-support smoke test to bats"
```

---

### Task 5: Migrate test-opencode-support.sh to BATS

**Files:**
- Create: `tests/test-opencode-support.bats`
- Reference (read-only, for translation): `tests/test-opencode-support.sh`

- [ ] **Step 1: Create `tests/test-opencode-support.bats`**

Create `tests/test-opencode-support.bats` with the following content:

```bash
#!/usr/bin/env bats

load 'test_helper/common'
load '/usr/local/share/bats-support/load'
load '/usr/local/share/bats-assert/load'

@test "make test_opencode target is available" {
    run make -s -n -C "$REPO_ROOT" test_opencode
    assert_success
}

@test "make test_native_opencode target is available" {
    run make -s -n -C "$REPO_ROOT" test_native_opencode
    assert_success
}

@test "make upgrade-nodejs target is available" {
    run make -s -n -C "$REPO_ROOT" upgrade-nodejs
    assert_success
}

@test "make upgrade-opencode target is available" {
    run make -s -n -C "$REPO_ROOT" upgrade-opencode
    assert_success
}

@test "upgrade check for nodejs succeeds" {
    run bash "$REPO_ROOT/scripts/update-versions.sh" --tool nodejs --check-only
    assert_success
}

@test "upgrade check for opencode succeeds" {
    run bash "$REPO_ROOT/scripts/update-versions.sh" --tool opencode --check-only
    assert_success
}

@test "Makefile targets linux/arm64 platform twice" {
    run grep -Fc -- "--platform linux/arm64 \\" "$REPO_ROOT/Makefile"
    assert_output "2"
}

@test "Makefile runs opencode --version in container" {
    run grep -Fq -- 'docker run --rm $(CONTAINER_NAME):$(OPENCODE_TAG) opencode --version' "$REPO_ROOT/Makefile"
    assert_success
}

@test "clean target removes OpenCode image" {
    run grep -Fq -- 'docker rmi $(CONTAINER_NAME):$(OPENCODE_TAG)' "$REPO_ROOT/Makefile"
    assert_success
}

@test "image-build workflow tags the opencode image" {
    run grep -Fq -- 'ghcr.io/cwimmer/devcontainer:opencode' "$REPO_ROOT/.github/workflows/image-build.yaml"
    assert_success
}
```

- [ ] **Step 2: Run the new bats file and verify it passes**

Run:

```bash
docker run --rm -e ASDF_BATS_VERSION=1.14.0 -v "$(pwd):/repo" -w /repo/tests ghcr.io/cwimmer/devcontainer:latest bats test-opencode-support.bats
```

Expected: 10 tests, all pass.

- [ ] **Step 3: Verify the count assertion behaves correctly**

Temporarily change `assert_output "2"` to `assert_output "99"` and confirm the test fails with a useful diff:

```bash
sed -i 's|assert_output "2"|assert_output "99"|' tests/test-opencode-support.bats
docker run --rm -e ASDF_BATS_VERSION=1.14.0 -v "$(pwd):/repo" -w /repo/tests ghcr.io/cwimmer/devcontainer:latest bats test-opencode-support.bats
```

Expected: the count test fails with output showing actual vs expected values.

Then revert:

```bash
git checkout -- tests/test-opencode-support.bats
```

- [ ] **Step 4: Commit**

```bash
git add tests/test-opencode-support.bats
git commit -m "test: migrate opencode-support smoke test to bats"
```

---

### Task 6: Update the Makefile to run the BATS suite

**Files:**
- Modify: `Makefile:7-19` (`test:` target)
- Modify: `Makefile:44-51` (`test_native:` target)

- [ ] **Step 1: Update the `test:` target**

In `Makefile`, replace this block (lines 17–18):

```makefile
	./tests/test-bats-support.sh
	./tests/test-gh-support.sh
```

with:

```makefile
	docker run --rm -e ASDF_BATS_VERSION=$$(grep '^ARG BATS_VERSION=' Dockerfile | cut -d= -f2) \
		-v $(CURDIR):/repo -w /repo/tests \
		$(CONTAINER_NAME):$(TAG) \
		bats test-bats-support.bats test-gh-support.bats test-opencode-support.bats
```

The double-`$$` is required because Make passes the shell a literal
`$` for command substitution; the inner grep then extracts the
pinned `BATS_VERSION` from the `Dockerfile` so the env var matches
the value baked into the image.

- [ ] **Step 2: Update the `test_native:` target**

In `Makefile`, replace this block (lines 50–51):

```makefile
	./tests/test-bats-support.sh
	./tests/test-gh-support.sh
```

with the same `docker run ... bats ...` invocation as in Step 1.

- [ ] **Step 3: Verify `make -n test_native` shows the new command**

Run:

```bash
make -n test_native
```

Expected: the dry-run output contains `docker run --rm -e ASDF_BATS_VERSION=... -v $(CURDIR):/repo -w /repo/tests ... bats test-bats-support.bats test-gh-support.bats test-opencode-support.bats` and **does not** contain `./tests/test-bats-support.sh` or `./tests/test-gh-support.sh`.

- [ ] **Step 4: Verify the Makefile change lints clean**

Run:

```bash
make -n test_native >/dev/null && echo OK
```

Expected: `OK` is printed with no errors.

- [ ] **Step 5: Commit**

```bash
git add Makefile
git commit -m "build: run bats suite via docker in make test targets"
```

---

### Task 7: Extend pre-commit to lint `.bats` files

**Files:**
- Modify: `.pre-commit-config.yaml:10-13`

- [ ] **Step 1: Add `files:` and `args:` to the shellcheck hook**

In `.pre-commit-config.yaml`, change the `shellcheck-py` block from:

```yaml
  - repo: https://github.com/shellcheck-py/shellcheck-py
    rev: v0.11.0.1
    hooks:
      - id: shellcheck
```

to:

```yaml
  - repo: https://github.com/shellcheck-py/shellcheck-py
    rev: v0.11.0.1
    hooks:
      - id: shellcheck
        files: \.(bash|sh|bats)$
        args: [-x]
```

- [ ] **Step 2: Verify pre-commit picks up the new `.bats` files**

Run:

```bash
pre-commit run shellcheck --files tests/test-bats-support.bats tests/test-gh-support.bats tests/test-opencode-support.bats tests/test_helper/common.bash
```

Expected: shellcheck runs against the listed files. If shellcheck raises warnings (e.g. SC2317 for `load` directives), add targeted `# shellcheck disable=SCxxxx` directives inline with a justifying comment for each.

Note: if `pre-commit` is not installed locally, install it (`pipx install pre-commit` — the devcontainer already ships `pre-commit` via pipx, so this should already be available). Verify with `pre-commit --version`.

- [ ] **Step 3: Verify pre-commit still lints existing scripts**

Run:

```bash
pre-commit run shellcheck --files scripts/update-versions.sh scripts/.bashrc
```

Expected: shellcheck runs and exits successfully.

- [ ] **Step 4: Commit**

```bash
git add .pre-commit-config.yaml
git commit -m "build(pre-commit): lint bats files via shellcheck"
```

---

### Task 8: Add the CI `test` job

**Files:**
- Modify: `.github/workflows/image-build.yaml:36-53`

- [ ] **Step 1: Add a single-platform "build for local testing" step to the `build` job**

In `.github/workflows/image-build.yaml`, immediately **before** the existing `Build and push base multi-architecture image` step (line 36), insert a new step:

```yaml
      - name: Build base image for local testing
        uses: docker/build-push-action@v7
        with:
          context: .
          load: true
          tags: ghcr.io/cwimmer/devcontainer:latest
          platforms: linux/amd64
```

The existing multi-arch build step follows unchanged.

- [ ] **Step 2: Add the `test` job after the `build` job**

Append this job at the end of the `jobs:` block (after the existing `build:` job):

```yaml
  test:
    runs-on: ubuntu-latest
    needs: build
    steps:
      - name: Checkout repository
        uses: actions/checkout@v6

      - name: Run BATS suite inside the built image
        run: |
          docker run --rm \
            -e ASDF_BATS_VERSION=1.14.0 \
            -v ${{ github.workspace }}:/repo \
            -w /repo/tests \
            ghcr.io/cwimmer/devcontainer:latest \
            bats test-bats-support.bats test-gh-support.bats test-opencode-support.bats
```

- [ ] **Step 3: Validate the workflow YAML locally**

Run:

```bash
yamllint --strict .github/workflows/image-build.yaml
```

Expected: exit 0, no output.

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/image-build.yaml
git commit -m "ci: run bats suite in workflow test job"
```

---

### Task 9: Add a Testing subsection to the README

**Files:**
- Modify: `README.md:91-100` (the `### Building` section)

- [ ] **Step 1: Append a Testing subsection**

In `README.md`, immediately after the existing `### Building` subsection (ending at line 100 with the last `make test_native_opencode` line), add:

```markdown
### Testing

The BATS test suite lives in `tests/test-*.bats` and asserts that the
devcontainer's tooling, upgrade workflow, and OpenCode wiring stay
consistent. Run `make test` for the multi-platform build or
`make test_native` for the faster native build; both invoke the suite
inside the freshly built devcontainer image.
```

- [ ] **Step 2: Verify the rendered markdown**

Open `README.md` and confirm:
- the new subsection sits **outside** the fenced shell block that ends at line 99;
- no blank line or wrapping change makes any code fence invalid;
- the tool table at the top still renders as a two-column table.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: add testing subsection to readme"
```

---

### Task 10: Annotate the prior BATS spec note

**Files:**
- Modify: `docs/superpowers/specs/2026-04-25-bats-devcontainer-design.md`

- [ ] **Step 1: Add the migration note to the existing spec**

In `docs/superpowers/specs/2026-04-25-bats-devcontainer-design.md`, append the following paragraph at the end of the document (after the "Expected Outcome" section):

```markdown
## Follow-up: BATS test framework migration (2026-09-08)

The smoke test introduced in this design (`tests/test-bats-support.sh`)
was migrated to BATS as part of
`docs/superpowers/specs/2026-09-08-bats-test-migration-design.md`.
The bash assertion helpers were replaced with `bats-assert`; the test
itself is now `tests/test-bats-support.bats` and is run by `make
test_native` (and CI) inside the devcontainer image.
```

- [ ] **Step 2: Commit**

```bash
git add docs/superpowers/specs/2026-04-25-bats-devcontainer-design.md
git commit -m "docs(specs): note bats test migration in prior bats spec"
```

---

### Task 11: Delete the old bash test scripts

**Files:**
- Delete: `tests/test-bats-support.sh`
- Delete: `tests/test-gh-support.sh`
- Delete: `tests/test-opencode-support.sh`

- [ ] **Step 1: Delete the three files**

Run:

```bash
rm tests/test-bats-support.sh tests/test-gh-support.sh tests/test-opencode-support.sh
```

Expected: no output, files are removed.

- [ ] **Step 2: Verify `git status` lists the deletions**

Run:

```bash
git status --short tests/
```

Expected output (3 lines, all prefixed with `D `):

```
D tests/test-bats-support.sh
D tests/test-gh-support.sh
D tests/test-opencode-support.sh
```

- [ ] **Step 3: Verify no other Makefile or CI reference still points at the `.sh` files**

Run:

```bash
grep -RIn --include="*.sh" --include="Makefile*" --include="*.yaml" --include="*.yml" -e 'test-bats-support\.sh' -e 'test-gh-support\.sh' -e 'test-opencode-support\.sh' . || echo "no references found"
```

Expected: `no references found` is printed.

- [ ] **Step 4: Commit**

```bash
git add tests/test-bats-support.sh tests/test-gh-support.sh tests/test-opencode-support.sh
git commit -m "test: remove superseded bash test scripts"
```

---

### Task 12: Final end-to-end verification

**Files:**
- Verify-only: every file changed in Tasks 1–11.

- [ ] **Step 1: Re-run the full bats suite inside the built image**

Run:

```bash
HOST_ARCH="$(uname -m | sed 's/aarch64/arm64/;s/x86_64/amd64/')"
docker buildx build --load --platform "linux/${HOST_ARCH}" --tag ghcr.io/cwimmer/devcontainer:latest .
docker run --rm -e ASDF_BATS_VERSION=1.14.0 -v "$(pwd):/repo" -w /repo/tests ghcr.io/cwimmer/devcontainer:latest bats test-bats-support.bats test-gh-support.bats test-opencode-support.bats
```

Expected: 21 `@test` blocks total (6 + 5 + 10), all pass.

- [ ] **Step 2: Run `make test_native`**

Run:

```bash
make test_native
```

Expected: docker build succeeds; `cat /usr/local/share/asdf-tool-versions` and `bats --version` and `gh --version` succeed; the BATS suite passes inside the built image.

- [ ] **Step 3: Run pre-commit against all touched files**

Run:

```bash
pre-commit run --all-files
```

Expected: yamllint, shellcheck (now covering `.bats` files), and actionlint all pass.

- [ ] **Step 4: Cause a representative assertion to fail and confirm a useful diagnostic**

Run:

```bash
sed -i 's|ARG BATS_VERSION=1.14.0|ARG BATS_VERSION=999.0.0|' Dockerfile
HOST_ARCH="$(uname -m | sed 's/aarch64/arm64/;s/x86_64/amd64/')"
docker buildx build --load --platform "linux/${HOST_ARCH}" --tag ghcr.io/cwimmer/devcontainer:latest . >/dev/null 2>&1 || true
docker run --rm -e ASDF_BATS_VERSION=1.14.0 -v "$(pwd):/repo" -w /repo/tests ghcr.io/cwimmer/devcontainer:latest bats test-bats-support.bats 2>&1 | head -30
```

Expected: at least one test fails; the failing `@test` name is visible; the diagnostic references the missing substring.

Then revert:

```bash
git checkout -- Dockerfile
HOST_ARCH="$(uname -m | sed 's/aarch64/arm64/;s/x86_64/amd64/')"
docker buildx build --load --platform "linux/${HOST_ARCH}" --tag ghcr.io/cwimmer/devcontainer:latest .
```

- [ ] **Step 5: Inspect `git status --short` for unintended changes**

Run:

```bash
git status --short
```

Expected: only the changes from Tasks 1–11 are present (no untracked files, no unrelated modifications).

- [ ] **Step 6: Capture the final diff summary**

Run:

```bash
git diff --stat $(git rev-list --max-parents=0 HEAD)..HEAD
```

Expected: the diff includes `Dockerfile`, `Makefile`, `.pre-commit-config.yaml`, `.github/workflows/image-build.yaml`, `README.md`, `tests/test_helper/common.bash`, three new `.bats` files, three deleted `.sh` files, and the two spec files.

- [ ] **Step 7: Final commit (only if Step 5 surfaced an intentional follow-up change)**

If Step 5 required keeping an auto-updated pre-commit hook revision, run:

```bash
git add .pre-commit-config.yaml
git commit -m "chore: refresh pre-commit hook versions"
```

Otherwise, skip this step.
