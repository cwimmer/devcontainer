# Design: Additional asdf Tools (helm, kind, kubectx)

**Date:** 2026-04-03
**Status:** Approved

## Problem

The devcontainer needs helm, kind, kubectx, and kubens available for
Kubernetes development workflows. These tools are not currently
installed.

## Solution

Add 3 new asdf-managed plugins — helm, kind, and kubectx — following
the exact pattern used by the 6 existing asdf tools. The kubectx
plugin (virtualstaticvoid/asdf-kubectx) installs both `kubectx` and
`kubens` binaries.

`jq` is already installed via apt and requires no changes.

## Scope

### In scope

- 3 new `ARG` lines in the Dockerfile (helm, kind, kubectx)
- `asdf plugin add` + `asdf install` for each
- Updated `/usr/local/share/asdf-tool-versions` generation
- 3 new version-fetch functions in `update-versions.sh`
- 3 new `upgrade-*` Makefile targets
- Updated README.md tool table

### Out of scope

- Changes to apt-installed tools (jq stays as-is)
- Changes to doctl, pre-commit, or commitizen
- New scripts or architectural changes

## Design

### 1. Dockerfile

Add version ARGs alongside existing ones:

```dockerfile
ARG HELM_VERSION=<latest>
ARG KIND_VERSION=<latest>
ARG KUBECTX_VERSION=<latest>
```

Add plugin installs after the existing asdf install block, before the
tool-versions file generation:

```dockerfile
RUN asdf plugin add helm
RUN asdf install helm $HELM_VERSION
RUN asdf plugin add kind
RUN asdf install kind $KIND_VERSION
RUN asdf plugin add kubectx https://github.com/virtualstaticvoid/asdf-kubectx.git
RUN asdf install kubectx $KUBECTX_VERSION
```

Update the `printf` block that generates
`/usr/local/share/asdf-tool-versions` to include the 3 new tools:

```dockerfile
RUN printf '%s\n' \
    "golang $GOLANG_VERSION" \
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

### 2. update-versions.sh

Add to the `TOOL_ARG_NAMES` associative array:

```bash
["helm"]="HELM_VERSION"
["kind"]="KIND_VERSION"
["kubectx"]="KUBECTX_VERSION"
```

Add 3 version-fetch functions using the GitHub releases API, same
pattern as existing tools:

| Tool | GitHub repo | Tag prefix |
|------|-------------|------------|
| helm | helm/helm | v |
| kind | kubernetes-sigs/kind | v |
| kubectx | ahmetb/kubectx | v |

Add 3 entries to the `get_latest_version()` case statement.

### 3. Makefile

Add 3 per-tool upgrade targets:

```makefile
.PHONY: upgrade-helm
upgrade-helm:
	@echo "Updating helm version in Dockerfile..."
	@bash scripts/update-versions.sh --tool helm

.PHONY: upgrade-kind
upgrade-kind:
	@echo "Updating kind version in Dockerfile..."
	@bash scripts/update-versions.sh --tool kind

.PHONY: upgrade-kubectx
upgrade-kubectx:
	@echo "Updating kubectx version in Dockerfile..."
	@bash scripts/update-versions.sh --tool kubectx
```

The existing `make upgrade` target runs `--all`, which iterates all
keys in `TOOL_ARG_NAMES` and will pick up the new tools automatically.

### 4. README.md

Add to the "Installed tools" table:

| Tool | Manager |
|------|---------|
| helm | asdf |
| kind | asdf |
| kubectx | asdf |
| kubens | asdf (via kubectx) |

## Testing

- `make test` builds the container multi-platform and prints the
  tool-versions file, which must include the 3 new tools.
- `make upgrade` must successfully fetch and update versions for all
  tools including the new ones.
