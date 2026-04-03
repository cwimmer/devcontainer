# Design: asdf Default Tool Versions File

**Date:** 2026-04-03
**Status:** Approved

## Problem

Users of this devcontainer who want to pin their project to the same
tool versions shipped in the container have no easy way to discover or
adopt those versions. They must manually inspect the Dockerfile ARGs
and maintain their own `.tool-versions` file.

## Solution

Generate a `.tool-versions`-compatible file at build time and place it
at a well-known path inside the container. Document usage in a new
root README.md.

## Scope

Only the 6 asdf-managed tools are included: golang, kubectl,
terraform, terraform-docs, tflint, trivy.

### In scope

- One new `RUN` step in the Dockerfile
- One new README.md at the repo root

### Out of scope

- Changes to non-asdf tools (e.g. doctl)
- Changes to `update-versions.sh` or version upgrade workflow
- New scripts or Makefile targets

## Design

### 1. Dockerfile change

A single `RUN` step added after all asdf installs and before the
build-timestamp block:

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

The file is generated from the existing Dockerfile `ARG` values, so it
is always in sync with the installed versions. No additional scripts or
build steps are needed.

**Output path:** `/usr/local/share/asdf-tool-versions`

### 2. README.md (new file at repo root)

Contains:

- Brief description of what the devcontainer provides
- Section "Using default tool versions" with two usage options:
  - **Symlink:** `ln -s /usr/local/share/asdf-tool-versions .tool-versions`
  - **Environment variable:** `export ASDF_TOOL_VERSIONS_FILENAME=/usr/local/share/asdf-tool-versions`
- Note that consumers can override individual tools by creating their
  own `.tool-versions` in their project

### 3. Testing

`make test` already builds the image and validates the Dockerfile.
The generated file can be verified with:

```sh
docker run --rm <image> cat /usr/local/share/asdf-tool-versions
```

Add this test to the `test_native` and `test` targets.

## Maintenance

When a new asdf-managed tool is added to the Dockerfile, one line must
be added to the `printf` block. This is the same maintenance burden as
the existing `asdf plugin add` / `asdf install` pair.

`make upgrade` continues to work unchanged — it updates Dockerfile
ARGs, and the next build produces the correct file.
