# Additional asdf Tools Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Install helm, kind, kubectx, and kubens via asdf in the devcontainer.

**Architecture:** Add 3 new asdf plugins (helm, kind, kubectx) following the existing pattern in Dockerfile, update-versions.sh, Makefile, and README. The kubectx plugin provides both kubectx and kubens binaries.

**Tech Stack:** Docker, asdf, bash, Make

---

### Task 1: Add version ARGs and asdf installs to Dockerfile

**Files:**
- Modify: `Dockerfile:3-10` (ARG block)
- Modify: `Dockerfile:49-56` (asdf install block)
- Modify: `Dockerfile:58-66` (tool-versions printf block)

- [ ] **Step 1: Add 3 new ARG lines to Dockerfile**

Add `HELM_VERSION`, `KIND_VERSION`, and `KUBECTX_VERSION` to the ARG
block after `DOCTL_VERSION`, keeping alphabetical order:

```dockerfile
ARG ASDF_VERSION=v0.18.1
ARG DOCTL_VERSION=1.154.0
ARG GOLANG_VERSION=1.26.1
ARG HELM_VERSION=4.1.3
ARG KIND_VERSION=0.31.0
ARG KUBECTX_VERSION=0.11.0
ARG KUBECTL_VERSION=1.35.3
ARG TERRAFORM_DOCS_VERSION=0.21.0
ARG TERRAFORM_VERSION=1.14.8
ARG TFLINT_VERSION=0.61.0
ARG TRIVY_VERSION=0.69.3
```

- [ ] **Step 2: Add asdf plugin add + install lines**

Add after the existing `asdf install golang` line (line 56) and
before the tool-versions printf block:

```dockerfile
RUN asdf plugin add helm
RUN asdf install helm $HELM_VERSION
RUN asdf plugin add kind
RUN asdf install kind $KIND_VERSION
RUN asdf plugin add kubectx https://github.com/virtualstaticvoid/asdf-kubectx.git
RUN asdf install kubectx $KUBECTX_VERSION
```

- [ ] **Step 3: Update the tool-versions printf block**

Replace the existing printf block with one that includes the new
tools (alphabetical order):

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

- [ ] **Step 4: Commit**

```bash
git add Dockerfile
git commit -m "feat: add helm, kind, and kubectx asdf plugins to Dockerfile"
```

---

### Task 2: Add version-fetch functions to update-versions.sh

**Files:**
- Modify: `scripts/update-versions.sh:18-27` (TOOL_ARG_NAMES)
- Modify: `scripts/update-versions.sh` (add 3 new functions)
- Modify: `scripts/update-versions.sh` (case statement)
- Modify: `scripts/update-versions.sh` (show_help SUPPORTED TOOLS)

- [ ] **Step 1: Add entries to TOOL_ARG_NAMES**

Add to the associative array (after `["doctl"]` and before the
closing paren):

```bash
declare -A TOOL_ARG_NAMES=(
    ["terraform"]="TERRAFORM_VERSION"
    ["golang"]="GOLANG_VERSION"
    ["helm"]="HELM_VERSION"
    ["kind"]="KIND_VERSION"
    ["kubectx"]="KUBECTX_VERSION"
    ["kubectl"]="KUBECTL_VERSION"
    ["tflint"]="TFLINT_VERSION"
    ["trivy"]="TRIVY_VERSION"
    ["terraform-docs"]="TERRAFORM_DOCS_VERSION"
    ["doctl"]="DOCTL_VERSION"
    ["asdf"]="ASDF_VERSION"
)
```

- [ ] **Step 2: Add get_latest_helm_version function**

Add before the `get_latest_asdf_version` function:

```bash
# Function to get the latest helm version
get_latest_helm_version() {
    local latest_version
    latest_version=$(curl -s "https://api.github.com/repos/helm/helm/releases/latest" | \
                     jq -r '.tag_name' | \
                     sed 's|^v||')

    if [[ -z "$latest_version" || "$latest_version" == "null" ]]; then
        print_error "Failed to fetch the latest helm version"
        return 1
    fi

    echo "$latest_version"
}
```

- [ ] **Step 3: Add get_latest_kind_version function**

Add after the helm function:

```bash
# Function to get the latest kind version
get_latest_kind_version() {
    local latest_version
    latest_version=$(curl -s "https://api.github.com/repos/kubernetes-sigs/kind/releases/latest" | \
                     jq -r '.tag_name' | \
                     sed 's|^v||')

    if [[ -z "$latest_version" || "$latest_version" == "null" ]]; then
        print_error "Failed to fetch the latest kind version"
        return 1
    fi

    echo "$latest_version"
}
```

- [ ] **Step 4: Add get_latest_kubectx_version function**

Add after the kind function:

```bash
# Function to get the latest kubectx version
get_latest_kubectx_version() {
    local latest_version
    latest_version=$(curl -s "https://api.github.com/repos/ahmetb/kubectx/releases/latest" | \
                     jq -r '.tag_name' | \
                     sed 's|^v||')

    if [[ -z "$latest_version" || "$latest_version" == "null" ]]; then
        print_error "Failed to fetch the latest kubectx version"
        return 1
    fi

    echo "$latest_version"
}
```

- [ ] **Step 5: Add entries to get_latest_version case statement**

Add 3 new cases before the `doctl)` case:

```bash
        helm)
            get_latest_helm_version
            ;;
        kind)
            get_latest_kind_version
            ;;
        kubectx)
            get_latest_kubectx_version
            ;;
```

- [ ] **Step 6: Update show_help SUPPORTED TOOLS list**

Add to the SUPPORTED TOOLS section in show_help:

```
    helm            - Kubernetes package manager
    kind            - Kubernetes in Docker
    kubectx         - Kubernetes context and namespace switcher
```

- [ ] **Step 7: Commit**

```bash
git add scripts/update-versions.sh
git commit -m "feat: add helm, kind, kubectx to version update script"
```

---

### Task 3: Add Makefile upgrade targets

**Files:**
- Modify: `Makefile`

- [ ] **Step 1: Add 3 new upgrade targets**

Add after the existing `upgrade-doctl` target and before
`upgrade-asdf`:

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

- [ ] **Step 2: Commit**

```bash
git add Makefile
git commit -m "feat: add Makefile upgrade targets for helm, kind, kubectx"
```

---

### Task 4: Update README.md tool table

**Files:**
- Modify: `README.md:7-19` (tool table)

- [ ] **Step 1: Add new tools to the table**

Update the "Installed tools" table to include the new tools:

```markdown
## Installed tools

| Tool | Manager |
|------|---------|
| terraform | asdf |
| golang | asdf |
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

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: add helm, kind, kubectx, kubens to installed tools table"
```

---

### Task 5: Build and verify

- [ ] **Step 1: Run make test_native to build the container**

```bash
make test_native
```

Expected: Build succeeds. Output includes all 9 asdf tools in the
tool-versions file, including helm, kind, and kubectx.

- [ ] **Step 2: Verify upgrade script works for new tools**

```bash
bash scripts/update-versions.sh --tool helm --check-only
bash scripts/update-versions.sh --tool kind --check-only
bash scripts/update-versions.sh --tool kubectx --check-only
```

Expected: Each reports the current version and confirms it is up to
date (or shows available update).

- [ ] **Step 3: Commit any fixes if needed**

If any changes were needed, commit them with an appropriate message.
