# Bats in Devcontainer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `bats` to the base devcontainer image with pinned versioning, upgrade support, lightweight smoke coverage, and README documentation that matches the repository's existing tool-management conventions.

**Architecture:** Extend the base `Dockerfile` with one more asdf-managed tool using a pinned `BATS_VERSION` ARG, then wire that tool through the existing upgrade path in `scripts/update-versions.sh` and `Makefile`. Document the installed tool and the discovered maintenance convention in `README.md`, and add one small shell smoke test to verify the new wiring without expanding the repo's test surface unnecessarily.

**Tech Stack:** Dockerfile, Bash, Make, Markdown, asdf, pre-commit

**Spec:** `docs/superpowers/specs/2026-04-25-bats-devcontainer-design.md`

---

## File Structure

- `Dockerfile`
  Add the pinned Bats version, install Bats via the community asdf plugin, and include it in `/usr/local/share/asdf-tool-versions`.
- `scripts/update-versions.sh`
  Teach the existing upgrade script how to discover and update `BATS_VERSION` in `Dockerfile`.
- `Makefile`
  Add `upgrade-bats` to match the existing per-tool upgrade targets.
- `README.md`
  Add `bats` to the installed tools table and document the maintenance convention for future asdf-managed tools.
- `tests/test-bats-support.sh`
  Add a focused smoke test for the new Makefile target, upgrade check, and documentation/config wiring.

### Task 1: Add Bats to the base Docker image

**Files:**
- Modify: `Dockerfile:3-13` (version ARG block)
- Modify: `Dockerfile:55-76` (asdf install and tool-versions block)

- [ ] **Step 1: Add the pinned Bats version ARG**

Update the ARG block in `Dockerfile` to insert `BATS_VERSION=1.13.0` after `ASDF_VERSION` and before `DOCTL_VERSION`:

```dockerfile
ARG ASDF_VERSION=v0.19.0
ARG BATS_VERSION=1.13.0
ARG DOCTL_VERSION=1.155.0
ARG GOLANG_VERSION=1.26.2
ARG HELM_VERSION=4.1.4
ARG KIND_VERSION=0.31.0
ARG KUBECTX_VERSION=0.11.0
ARG KUBECTL_VERSION=1.36.0
ARG TERRAFORM_DOCS_VERSION=0.22.0
ARG TERRAFORM_VERSION=1.14.9
ARG TFLINT_VERSION=0.62.0
ARG TRIVY_VERSION=0.70.0
```

- [ ] **Step 2: Add the Bats asdf plugin install lines**

Insert these lines in the asdf section after `RUN asdf install golang $GOLANG_VERSION` and before `RUN asdf plugin add helm`:

```dockerfile
RUN asdf plugin add bats https://github.com/timgluz/asdf-bats.git
RUN asdf install bats $BATS_VERSION
```

The surrounding section should read:

```dockerfile
RUN asdf plugin add trivy https://github.com/zufardhiyaulhaq/asdf-trivy.git
RUN asdf install trivy $TRIVY_VERSION
RUN asdf plugin add golang https://github.com/asdf-community/asdf-golang.git
RUN asdf install golang $GOLANG_VERSION
RUN asdf plugin add bats https://github.com/timgluz/asdf-bats.git
RUN asdf install bats $BATS_VERSION
RUN asdf plugin add helm
RUN asdf install helm $HELM_VERSION
RUN asdf plugin add kind
RUN asdf install kind $KIND_VERSION
RUN asdf plugin add kubectx https://github.com/virtualstaticvoid/asdf-kubectx.git
RUN asdf install kubectx $KUBECTX_VERSION
```

- [ ] **Step 3: Add Bats to the generated asdf tool versions file**

Update the `RUN printf '%s\n'` block so it includes `bats` immediately after `golang`:

```dockerfile
RUN printf '%s\n' \
    "golang $GOLANG_VERSION" \
    "bats $BATS_VERSION" \
    "helm $HELM_VERSION" \
    "kind $KIND_VERSION" \
    "kubectx $KUBECTX_VERSION" \
    "kubectl $KUBECTL_VERSION" \
    "terraform $TERRAFORM_VERSION" \
    "terraform-docs $TERRAFORM_DOCS_VERSION" \
    "tflint $TFLINT_VERSION" \
    "trivy $TRIVY_VERSION" \
    > /usr/local/share/asdf-tool-versions
```

- [ ] **Step 4: Build the native image to verify Dockerfile validity**

Run: `make test_native`

Expected:
- Docker build completes successfully
- The output from `cat /usr/local/share/asdf-tool-versions` includes a `bats 1.13.0` line

- [ ] **Step 5: Verify Bats is available in the built image**

Run: `docker run --rm ghcr.io/cwimmer/devcontainer:latest bats --version`

Expected: command succeeds and prints a Bats version string beginning with `Bats`.

- [ ] **Step 6: Commit the Dockerfile change**

```bash
git add Dockerfile
git commit -m "feat: add bats to the base devcontainer image"
```

---

### Task 2: Add Bats to the upgrade workflow

**Files:**
- Modify: `scripts/update-versions.sh:22-52` (tool maps)
- Modify: `scripts/update-versions.sh:172-259` (version fetch functions)
- Modify: `scripts/update-versions.sh:265-304` (tool dispatch)
- Modify: `scripts/update-versions.sh:452-465` (supported tools help)
- Modify: `Makefile:93-126` (per-tool upgrade targets)

- [ ] **Step 1: Extend the tool maps in `scripts/update-versions.sh`**

Update the two associative arrays so they contain `bats` entries that point at the base Dockerfile:

```bash
declare -A TOOL_ARG_NAMES=(
    ["terraform"]="TERRAFORM_VERSION"
    ["golang"]="GOLANG_VERSION"
    ["kubectl"]="KUBECTL_VERSION"
    ["tflint"]="TFLINT_VERSION"
    ["trivy"]="TRIVY_VERSION"
    ["terraform-docs"]="TERRAFORM_DOCS_VERSION"
    ["doctl"]="DOCTL_VERSION"
    ["asdf"]="ASDF_VERSION"
    ["bats"]="BATS_VERSION"
    ["helm"]="HELM_VERSION"
    ["kind"]="KIND_VERSION"
    ["kubectx"]="KUBECTX_VERSION"
    ["nodejs"]="NODE_MAJOR"
    ["opencode"]="OPENCODE_VERSION"
)

declare -A TOOL_DOCKERFILE_PATHS=(
    ["terraform"]="$DOCKERFILE_PATH"
    ["golang"]="$DOCKERFILE_PATH"
    ["kubectl"]="$DOCKERFILE_PATH"
    ["tflint"]="$DOCKERFILE_PATH"
    ["trivy"]="$DOCKERFILE_PATH"
    ["terraform-docs"]="$DOCKERFILE_PATH"
    ["doctl"]="$DOCKERFILE_PATH"
    ["asdf"]="$DOCKERFILE_PATH"
    ["bats"]="$DOCKERFILE_PATH"
    ["helm"]="$DOCKERFILE_PATH"
    ["kind"]="$DOCKERFILE_PATH"
    ["kubectx"]="$DOCKERFILE_PATH"
    ["nodejs"]="$OPENCODE_DOCKERFILE_PATH"
    ["opencode"]="$OPENCODE_DOCKERFILE_PATH"
)
```

- [ ] **Step 2: Add a Bats version fetch function**

Insert this function after `get_latest_doctl_version()` and before `get_latest_helm_version()`:

```bash
# Function to get the latest Bats version
get_latest_bats_version() {
    local latest_version
    latest_version=$(curl -s "https://api.github.com/repos/bats-core/bats-core/releases/latest" | \
                     jq -r '.tag_name' | \
                     sed 's|^v||')

    if [[ -z "$latest_version" || "$latest_version" == "null" ]]; then
        print_error "Failed to fetch the latest Bats version"
        return 1
    fi

    echo "$latest_version"
}
```

- [ ] **Step 3: Add Bats to the tool dispatch and help output**

Update `get_latest_version()` to include:

```bash
        bats)
            get_latest_bats_version
            ;;
```

Place it between the existing `doctl)` and `helm)` cases.

Then update `show_help()` so the supported tools list includes:

```text
    bats            - Bash Automated Testing System
```

Place it between `asdf`/`doctl` and `helm` so it remains easy to scan.

- [ ] **Step 4: Add the Makefile target for Bats upgrades**

Insert this target after `upgrade-doctl` and before `upgrade-helm`:

```makefile
.PHONY: upgrade-bats
upgrade-bats:
	@echo "Updating bats version in Dockerfile..."
	@bash scripts/update-versions.sh --tool bats
```

- [ ] **Step 5: Verify the Bats upgrade check works**

Run: `bash scripts/update-versions.sh --tool bats --check-only`

Expected:
- The script prints the current Bats version from `Dockerfile`
- The script prints the latest Bats version from GitHub releases
- The command exits successfully whether the version is already current or upgradable

- [ ] **Step 6: Verify the Makefile target is available**

Run: `make -s -n upgrade-bats`

Expected: the dry-run output contains `bash scripts/update-versions.sh --tool bats`.

- [ ] **Step 7: Commit the upgrade workflow changes**

```bash
git add scripts/update-versions.sh Makefile
git commit -m "feat: add bats to the devcontainer upgrade workflow"
```

---

### Task 3: Document the tool and maintenance convention

**Files:**
- Modify: `README.md:6-22` (installed tools table)
- Modify: `README.md:94-98` (upgrade section)

- [ ] **Step 1: Add Bats to the installed tools table**

Update the table in `README.md` so it includes `bats` immediately after `golang`:

```markdown
| Tool | Manager |
| ---- | ------- |
| terraform | asdf |
| golang | asdf |
| bats | asdf |
| helm | asdf |
| kind | asdf |
| kubectl | asdf |
| kubectx | asdf |
| kubens | asdf (via kubectx) |
| terraform-docs | asdf |
| tflint | asdf |
| trivy | asdf |
| doctl | binary |
| pre-commit | pipx |
| commitizen | pipx |
```

- [ ] **Step 2: Add the maintenance convention note**

Extend the `### Upgrading tool versions` section in `README.md` to read:

````markdown
### Upgrading tool versions

```sh
make upgrade       # update all tools to latest versions
```

When adding a new asdf-managed tool to this repository, update all of
these together so installs, upgrades, and documentation stay in sync:

- `Dockerfile`
- the `/usr/local/share/asdf-tool-versions` block in `Dockerfile`
- `scripts/update-versions.sh`
- `Makefile`
- `README.md`
````

- [ ] **Step 3: Review the README formatting**

Open `README.md` and verify:
- the tool table still renders as a two-column table
- the new maintenance note is outside the fenced shell block
- no blank line or wrapping change makes the code fence invalid

- [ ] **Step 4: Commit the documentation changes**

```bash
git add README.md
git commit -m "docs: document bats and the asdf tool maintenance pattern"
```

---

### Task 4: Add a minimal smoke test for Bats wiring

**Files:**
- Create: `tests/test-bats-support.sh`

- [ ] **Step 1: Create the smoke test file**

Create `tests/test-bats-support.sh` with this content:

```bash
#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

assert_make_target() {
    local target="$1"

    if ! make -s -n -C "$REPO_ROOT" "$target" >/dev/null; then
        fail "expected make target '$target' to be available"
    fi
}

assert_contains() {
    local file_path="$1"
    local expected_text="$2"

    if ! grep -Fq "$expected_text" "$file_path"; then
        fail "expected '$file_path' to contain: $expected_text"
    fi
}

assert_upgrade_check() {
    local tool="$1"

    if ! bash "$REPO_ROOT/scripts/update-versions.sh" --tool "$tool" --check-only >/dev/null; then
        fail "expected upgrade check for '$tool' to succeed"
    fi
}

assert_make_target upgrade-bats
assert_upgrade_check bats

assert_contains "$REPO_ROOT/Dockerfile" "ARG BATS_VERSION="
assert_contains "$REPO_ROOT/Dockerfile" "RUN asdf plugin add bats https://github.com/timgluz/asdf-bats.git"
assert_contains "$REPO_ROOT/Dockerfile" "\"bats \$BATS_VERSION\" \\" 
assert_contains "$REPO_ROOT/README.md" "| bats | asdf |"

printf 'PASS: Bats support is wired into the devcontainer build, upgrade workflow, and documentation.\n'
```

- [ ] **Step 2: Make the new smoke test executable**

Run: `chmod +x tests/test-bats-support.sh`

Expected: no output and the file mode becomes executable.

- [ ] **Step 3: Run the smoke test directly**

Run: `./tests/test-bats-support.sh`

Expected: the script exits successfully and prints `PASS: Bats support is wired into the devcontainer build, upgrade workflow, and documentation.`

- [ ] **Step 4: Commit the smoke test**

```bash
git add tests/test-bats-support.sh
git commit -m "test: add smoke coverage for bats wiring"
```

---

### Task 5: Run final verification and handle fallout explicitly

**Files:**
- Verify: `Dockerfile`
- Verify: `scripts/update-versions.sh`
- Verify: `Makefile`
- Verify: `README.md`
- Verify: `tests/test-bats-support.sh`
- Possibly modify: `.pre-commit-config.yaml` (only if `make pre-commit` updates hook versions)

- [ ] **Step 1: Re-run the repo-targeted checks**

Run these commands in order:

```bash
bash scripts/update-versions.sh --tool bats --check-only
./tests/test-bats-support.sh
make test_native
docker run --rm ghcr.io/cwimmer/devcontainer:latest bats --version
docker run --rm ghcr.io/cwimmer/devcontainer:latest cat /usr/local/share/asdf-tool-versions
```

Expected:
- all commands succeed
- the built image reports a Bats version
- `/usr/local/share/asdf-tool-versions` contains `bats 1.13.0`

- [ ] **Step 2: Run the requested pre-commit verification**

Run: `make pre-commit`

Expected:
- `pre-commit install` succeeds
- `pre-commit autoupdate` either leaves hooks unchanged or updates `.pre-commit-config.yaml`
- `pre-commit run --all-files` succeeds

- [ ] **Step 3: Inspect whether `make pre-commit` introduced unrelated hook updates**

Run: `git status --short`

Expected:
- if only the intended Bats files are modified, continue
- if `.pre-commit-config.yaml` changed because of `pre-commit autoupdate`, decide explicitly whether to keep that change in this branch as a separate documented outcome or revert it with user approval before committing

- [ ] **Step 4: Commit only if the verification step created an intentional follow-up change**

If `make pre-commit` reformats files or updates hooks and the change is intentionally kept, create one more commit:

```bash
git add .pre-commit-config.yaml
git commit -m "chore: refresh pre-commit hook versions"
```

If there is no follow-up change, skip this step.

- [ ] **Step 5: Capture the final diff for review**

If no follow-up pre-commit commit was created, run:

```bash
git diff --stat HEAD~4..HEAD
```

If the optional pre-commit follow-up commit was created, run:

```bash
git diff --stat HEAD~5..HEAD
```

Expected: summary includes the Dockerfile, update script, Makefile, README, smoke test, and optionally `.pre-commit-config.yaml` if the pre-commit run intentionally updated hooks.
