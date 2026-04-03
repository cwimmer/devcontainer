# asdf Default Tool Versions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Generate an asdf `.tool-versions`-compatible file at container build time and document its usage in a README.

**Architecture:** A single `RUN printf` step in the Dockerfile writes tool names and versions from existing `ARG` values to `/usr/local/share/asdf-tool-versions`. A new root `README.md` documents two ways for consumers to adopt the file.

**Tech Stack:** Dockerfile, Markdown, Make, Bash

**Spec:** `docs/2026-04-03-asdf-default-tool-versions-design.md`

---

### Task 1: Add tool-versions generation to Dockerfile

**Files:**
- Modify: `Dockerfile:55-58` (insert before the build-timestamp block)

- [ ] **Step 1: Add the RUN step to the Dockerfile**

Insert this block after the `RUN asdf install golang $GOLANG_VERSION` line and before the build-timestamp comment block:

```dockerfile
# Write default asdf tool versions for optional use by consumers.
# See README.md for usage instructions.
RUN printf '%s\n' \
    "golang $GOLANG_VERSION" \
    "kubectl $KUBECTL_VERSION" \
    "terraform $TERRAFORM_VERSION" \
    "terraform-docs $TERRAFORM_DOCS_VERSION" \
    "tflint $TFLINT_VERSION" \
    "trivy $TRIVY_VERSION" \
    > /usr/local/share/asdf-tool-versions
```

- [ ] **Step 2: Build the image to verify the Dockerfile is valid**

Run: `make test_native`
Expected: Build completes successfully.

- [ ] **Step 3: Verify the generated file contents**

Run: `docker run --rm ghcr.io/cwimmer/devcontainer:latest cat /usr/local/share/asdf-tool-versions`

Expected output (versions will match current Dockerfile ARGs):
```
golang 1.26.1
kubectl 1.35.3
terraform 1.14.8
terraform-docs 0.21.0
tflint 0.61.0
trivy 0.69.3
```

- [ ] **Step 4: Commit**

```bash
git add Dockerfile
git commit -m "feat: generate asdf tool-versions file at build time"
```

---

### Task 2: Create root README.md

**Files:**
- Create: `README.md`

- [ ] **Step 1: Create the README**

Create `README.md` at the repo root with this content:

```markdown
# devcontainer

A Docker container used as the base for development containers.
Includes common CLI tools managed by [asdf](https://asdf-vm.com/).

## Installed tools

| Tool | Manager |
|------|---------|
| terraform | asdf |
| golang | asdf |
| kubectl | asdf |
| terraform-docs | asdf |
| tflint | asdf |
| trivy | asdf |
| doctl | binary |
| pre-commit | pipx |
| commitizen | pipx |

## Using default tool versions

The container ships a `.tool-versions`-compatible file at
`/usr/local/share/asdf-tool-versions` containing the default versions
of all asdf-managed tools.

You can adopt these defaults in your project using either method:

### Option 1: Symlink

```sh
ln -s /usr/local/share/asdf-tool-versions .tool-versions
```

This makes your project use the container's default versions. The
symlink target updates automatically when the container is rebuilt.

### Option 2: Environment variable

Add to your shell profile or `.envrc`:

```sh
export ASDF_TOOL_VERSIONS_FILENAME=/usr/local/share/asdf-tool-versions
```

This tells asdf to use the container's file globally without creating
a `.tool-versions` in your project directory.

### Overriding individual tools

If you need a different version of one tool, create your own
`.tool-versions` file in your project instead of symlinking. You can
copy the defaults as a starting point:

```sh
cp /usr/local/share/asdf-tool-versions .tool-versions
```

Then edit the version for the tool you want to change.

## Development

### Building

```sh
make test          # multi-platform build (amd64 + arm64)
make test_native   # native platform only (faster)
```

### Upgrading tool versions

```sh
make upgrade       # update all tools to latest versions
```
```

- [ ] **Step 2: Verify the README renders correctly**

Skim the file for broken Markdown. Confirm all code blocks are closed
and the table renders properly.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: add README with tool-versions usage instructions"
```

---

### Task 3: Run full test suite

- [ ] **Step 1: Run `make test`**

Run: `make test`
Expected: Multi-platform build completes successfully. This validates
that the Dockerfile change works on both amd64 and arm64.

- [ ] **Step 2: Verify file contents one more time**

Run: `docker run --rm ghcr.io/cwimmer/devcontainer:latest cat /usr/local/share/asdf-tool-versions`
Expected: All 6 tools listed with correct versions matching Dockerfile ARGs.
