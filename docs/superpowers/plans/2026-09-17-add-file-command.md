# Add `file` Command Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the `file` command-line program to the base devcontainer image so it's available to the development user after a fresh build.

**Architecture:** Append `file` to the existing `apt-get install` block in the base `Dockerfile` (Ubuntu 24.04 already ships it; no version pin, no `update-versions.sh` entry). Lock the install with a BATS regression file matching the project's per-tool convention. Restructure the CI workflow so PRs validate the image built from their own revision instead of pulling the previously-published `latest` tag.

**Tech Stack:** Ubuntu 24.04 `apt`, BATS 1.14.0, `bats-assert` 2.1.0, `bats-support` 0.3.0, Make, Docker buildx, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-09-17-add-file-command-design.md`

## Global Constraints

- Base image: `public.ecr.aws/ubuntu/ubuntu:24.04_stable` (unchanged).
- Package manager: `apt` (Ubuntu base image); package name is exactly `file`.
- No version pin for `file`; no `ARG FILE_VERSION`; no `upgrade-file` Makefile target; no `scripts/update-versions.sh` entry. (The repo has no precedent for pinning unpinned system packages.)
- BATS helper libraries are already installed at `/usr/local/share/bats-support` and `/usr/local/share/bats-assert` (no work needed).
- CI workflow: BATS step uses `--pull=never` and runs immediately after the local single-platform build, before either publishing step. The standalone `test:` job is removed.
- Local verification uses `docker buildx inspect default` (must show `Driver: docker`) and `--builder default` for both base and OpenCode builds, with `--platform linux/amd64` throughout. The Makefile's `test_native_opencode` target is unchanged and is not used by verification.
- Commit messages: follow Conventional Commits v1.0.0 (per `.github/copilot-instructions.md`). Avoid the word "comprehensive".
- Shell scripts must be POSIX-compliant where possible and include error handling (per `.github/copilot-instructions.md`).

---

## File Structure

Files to **create**:

- `tests/test-file-support.bats` — 4 `@test` blocks (1 README grep + 3 functional smoke tests).

Files to **modify**:

- `Dockerfile` — append `file` to the existing `apt-get install` block.
- `README.md` — add `| file | apt |` row to the "Installed tools" table.
- `Makefile` — append `test-file-support.bats` to the `bats` invocation in both `test:` and `test_native:` targets.
- `.github/workflows/image-build.yaml` — move BATS test step into `build` job between local build and publishing steps, add `--pull=never`, delete the standalone `test:` job.

Files **not** touched: `Dockerfile.OpenCode`, `.devcontainer/devcontainer.json`, `scripts/update-versions.sh`, `.pre-commit-config.yaml`, `tests/test-bats-support.bats`, `tests/test-gh-support.bats`, `tests/test-opencode-support.bats`.

---

### Task 1: Add `file` to the base `Dockerfile`

**Files:**
- Modify: `Dockerfile:19-35` (apt-get install block)

**Interfaces:**
- Produces: a built `ghcr.io/cwimmer/devcontainer:latest` image where `/usr/bin/file` is present and exits zero on `--version`. (Consumed by Task 3's BATS file and Task 4's `make test_native`.)

- [ ] **Step 1: Edit the apt-get install block to append `file`**

Open `Dockerfile` and locate the existing block (lines 19-35):

```dockerfile
RUN apt-get update && apt-get install -y \
    unzip \
    curl \
    git \
    make \
    python3-pip \
    pipx \
    jq \
    wget \
    direnv \
    golang-go \
    httpie \
    iproute2 \
    iputils-ping \
    socat \
    dnsutils \
    ripgrep
```

Append a single line `    file \` after `    ripgrep \`. The final block must read:

```dockerfile
RUN apt-get update && apt-get install -y \
    unzip \
    curl \
    git \
    make \
    python3-pip \
    pipx \
    jq \
    wget \
    direnv \
    golang-go \
    httpie \
    iproute2 \
    iputils-ping \
    socat \
    dnsutils \
    ripgrep \
    file
```

Save the file. Do not add `ARG FILE_VERSION`, do not change any other line.

- [ ] **Step 2: Verify the `default` builder uses the `docker` driver**

Run:

```bash
docker buildx inspect default
```

Expected: the YAML output contains a line `Driver: docker`. If it shows `Driver: docker-container`, `Driver: remote`, or any other value, stop and report — proceeding would build into a separate image store and the local verification path in Task 4 would not work.

- [ ] **Step 3: Build the base image locally**

Run:

```bash
docker buildx build --builder default --load \
  --platform linux/amd64 \
  --tag ghcr.io/cwimmer/devcontainer:latest \
  .
```

Expected: buildkit progress to stderr, exit 0. The `docker` CLI prints the loaded tag (`Loaded image: ghcr.io/cwimmer/devcontainer:latest`) when `--load` succeeds.

- [ ] **Step 4: Smoke-test `file` inside the freshly-built image**

Run:

```bash
set -e
set -o pipefail

docker run --rm --pull=never \
  ghcr.io/cwimmer/devcontainer:latest file --version
docker run --rm --pull=never \
  ghcr.io/cwimmer/devcontainer:latest file /etc/passwd | grep -q text
docker run --rm --pull=never \
  ghcr.io/cwimmer/devcontainer:latest file /usr/bin/ls | grep -q ELF
```

Expected:

- `file --version` prints a one-line banner such as `file-5.45` to stdout and exits 0.
- The two `grep -q` pipelines exit 0 silently. A non-matching `file` output propagates `grep`'s exit 1 via `pipefail` and aborts the shell.

If any pipeline exits nonzero, stop and report the failure before committing.

- [ ] **Step 5: Commit**

```bash
git add Dockerfile
git commit -m "feat: install file in base devcontainer image"
```

---

### Task 2: Add `| file | apt |` row to `README.md`

**Files:**
- Modify: `README.md:6-25` (Installed tools table)

**Interfaces:**
- Produces: a README row that the regression test (Task 3) and any future reader can grep for.

- [ ] **Step 1: Edit the Installed tools table**

Open `README.md` and locate the table around lines 6-25. The current end of the table is:

```markdown
| doctl | binary |
| gh | apt |
| pre-commit | pipx |
| commitizen | pipx |
```

Insert one new row `| file | apt |` immediately after the `| gh | apt |` row, so the apt-managed group stays together:

```markdown
| doctl | binary |
| gh | apt |
| file | apt |
| pre-commit | pipx |
| commitizen | pipx |
```

Save the file. Do not change any other line.

- [ ] **Step 2: Verify the row with grep**

Run:

```bash
grep -F '| file | apt |' README.md
```

Expected: one matching line, exit 0. If zero matches, the row was inserted incorrectly; stop and fix before committing.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: list file in installed tools table"
```

---

### Task 3: Create `tests/test-file-support.bats`

**Files:**
- Create: `tests/test-file-support.bats`

**Interfaces:**
- Produces: a BATS file loadable by the existing suite and runnable via `bats test-file-support.bats`. The four `@test` blocks are read by the Makefile's `test_native` target (Task 4) and the CI workflow (Task 5).

- [ ] **Step 1: Write the test file**

Create `tests/test-file-support.bats` with the following content (exact bytes — the existing `tests/test-gh-support.bats` is the model):

```bash
#!/usr/bin/env bats

load 'test_helper/common'
load '/usr/local/share/bats-support/load'
load '/usr/local/share/bats-assert/load'

@test "README lists file as apt-managed" {
    run grep -Fq -- '| file | apt |' "$REPO_ROOT/README.md"
    assert_success
}

@test "file --version succeeds" {
    run file --version
    assert_success
}

@test "file identifies /etc/passwd as text" {
    run file /etc/passwd
    assert_success
    assert_output --partial "text"
}

@test "file identifies /usr/bin/ls as ELF" {
    run file /usr/bin/ls
    assert_success
    assert_output --partial "ELF"
}
```

Save the file. The shebang and the three `load` lines must match the convention used by `tests/test-bats-support.bats:1-5` and `tests/test-gh-support.bats:1-5` exactly.

- [ ] **Step 2: Run the new file standalone inside the built image**

Run:

```bash
docker run --rm --pull=never \
  -e ASDF_BATS_VERSION=1.14.0 \
  -v "$(pwd):/repo" \
  -w /repo/tests \
  ghcr.io/cwimmer/devcontainer:latest \
  bats test-file-support.bats
```

Expected: 4 tests pass, exit 0. If any test fails:

- README row failure → re-check Task 2.
- `file --version` failure → re-check Task 1 (the `file` package was not installed; rebuild).
- Text / ELF failure → re-check Task 1 (`file` is installed but the runtime behavior is unexpected; investigate the image's `/usr/bin/file` binary).

- [ ] **Step 3: Confirm a missing `file` package would fail the new tests**

This is the negative-control step. Run:

```bash
docker run --rm --pull=never \
  -e ASDF_BATS_VERSION=1.14.0 \
  -v "$(pwd):/repo" \
  -w /repo/tests \
  public.ecr.aws/ubuntu/ubuntu:24.04_stable \
  bash -c 'apt-get update >/dev/null && apt-get install -y bats >/dev/null && bats /repo/tests/test-file-support.bats'
```

Expected: the three functional tests fail with non-zero exits, and the README grep test also fails (because the test image doesn't have the repo's `README.md`). Exit nonzero overall. This confirms the tests actually exercise `file` and don't accidentally pass on any image.

If all four tests pass against the unmodified Ubuntu image, the assertions are too weak; stop and tighten them before committing.

- [ ] **Step 4: Commit**

```bash
git add tests/test-file-support.bats
git commit -m "test: add bats regression file for file command"
```

---

### Task 4: Register the BATS file in `Makefile`

**Files:**
- Modify: `Makefile:20` (the `test:` target's `bats` invocation)
- Modify: `Makefile:55` (the `test_native:` target's `bats` invocation)

**Interfaces:**
- Produces: a `make test` / `make test_native` run that executes the new BATS file alongside the existing three.

- [ ] **Step 1: Edit `Makefile:20`**

Open `Makefile` and find line 20. The current line reads (with surrounding context):

```makefile
		$(CONTAINER_NAME):$(TAG) \
		bats test-bats-support.bats test-gh-support.bats test-opencode-support.bats
```

Replace that final `bats ...` line with:

```makefile
		$(CONTAINER_NAME):$(TAG) \
		bats test-bats-support.bats test-gh-support.bats test-opencode-support.bats \
		     test-file-support.bats
```

Preserve the leading tab indentation on the line you modify.

- [ ] **Step 2: Edit `Makefile:55` identically**

Apply the same edit at line 55 (the `test_native:` target). The pattern to replace is identical to Step 1.

- [ ] **Step 3: Run `make test_native`**

Run:

```bash
make test_native
```

Expected: image builds (or is reused from Task 1's local build), `bats --version` and `gh --version` checks pass, the BATS suite runs four files (25 `@test` blocks total: 6 + 5 + 10 + 4) and exits 0.

If the suite fails, read the failing `@test` name and resolve against Tasks 1-3.

- [ ] **Step 4: Commit**

```bash
git add Makefile
git commit -m "build: register test-file-support.bats in test_native targets"
```

---

### Task 5: Restructure `.github/workflows/image-build.yaml`

**Files:**
- Modify: `.github/workflows/image-build.yaml` (the `build:` job's step list; the standalone `test:` job is deleted)

**Interfaces:**
- Produces: a workflow where PRs run the BATS suite against the image built from their own revision (same runner, locally-loaded image, `--pull=never`), instead of pulling the previously-published `latest` tag on a separate runner.

- [ ] **Step 1: Reorder the `build:` job steps**

Open `.github/workflows/image-build.yaml`. Locate the `build:` job (lines 17-61 in the current file). The current order is:

1. Checkout repository
2. Set up QEMU
3. Set up Docker Buildx
4. Login to Docker registry
5. **Build base image for local testing** (`load: true`, `platforms: linux/amd64`)
6. **Build and push base multi-architecture image**
7. **Build and push OpenCode multi-architecture image**

Insert one new step between step 5 and step 6 (immediately after "Build base image for local testing" and before "Build and push base multi-architecture image"):

```yaml
      - name: Run BATS suite against locally-built image
        run: |
          docker run --rm --pull=never \
            -e ASDF_BATS_VERSION=1.14.0 \
            -v ${{ github.workspace }}:/repo \
            -w /repo/tests \
            ghcr.io/cwimmer/devcontainer:latest \
            bats \
              test-bats-support.bats \
              test-gh-support.bats \
              test-opencode-support.bats \
              test-file-support.bats
```

Preserve the existing step names, `uses:` lines, and indentation. The new step uses `--pull=never` so a missing local image hard-fails rather than silently pulling from the registry.

- [ ] **Step 2: Delete the standalone `test:` job**

Remove the entire `test:` job at the end of the file (currently lines 63-80, beginning with `  test:` and ending with the matching indentation). The new in-job BATS step from Step 1 replaces it.

- [ ] **Step 3: Verify YAML syntax**

Run:

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/image-build.yaml'))"
```

Expected: exit 0, no output. If `yaml.YAMLError` is raised, re-open the file and fix the indentation / quoting reported in the error.

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/image-build.yaml
git commit -m "ci: run bats suite in build job against pr-built image"
```

---

### Task 6: Local OpenCode-layer verification (post-implementation)

**Files:** None (verification only).

**Interfaces:** None (consumes the locally-built images from Tasks 1 and 4).

- [ ] **Step 1: Build OpenCode on the local base**

Run:

```bash
docker buildx build --builder default --load \
  --platform linux/amd64 \
  --tag ghcr.io/cwimmer/devcontainer:opencode \
  -f Dockerfile.OpenCode \
  .
```

Expected: exit 0; the load summary lists `ghcr.io/cwimmer/devcontainer:opencode`.

- [ ] **Step 2: Smoke-test `file` inside the OpenCode image**

Run:

```bash
set -e
set -o pipefail

docker run --rm --pull=never --user root \
  ghcr.io/cwimmer/devcontainer:opencode file --version
docker run --rm --pull=never --user root \
  ghcr.io/cwimmer/devcontainer:opencode file /etc/passwd | grep -q text
docker run --rm --pull=never --user root \
  ghcr.io/cwimmer/devcontainer:opencode file /usr/bin/ls | grep -q ELF
```

Expected:

- `file --version` prints `file-X.YY` to stdout.
- The two `grep -q` pipelines exit 0 silently.

A nonzero exit on any line indicates either the OpenCode build did not consume the local base (silently pulled a different `latest` from the registry) or `file` is missing from the base. Re-run Task 1's Step 3 and this task's Step 1, then re-run Step 2; if the failure persists, the Makefile's `builder` Buildx instance is leaking in and needs investigation.

- [ ] **Step 3: Report unperformed verification**

The following checks **cannot** be performed from this environment and must be reported as such in the implementation report:

- The full local verification sequence requires a Docker daemon, which is not running here.
- The modified `image-build.yaml` workflow can only be validated by opening a PR against `main`.
- A live VS Code "Rebuild Container" against `.devcontainer/devcontainer.json` requires a host with the Dev Containers extension and a running daemon; the `docker-in-docker` feature is not exercised by this change.

No commit is produced by Task 6; it produces a verification report instead.