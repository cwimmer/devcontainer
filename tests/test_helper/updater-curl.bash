#!/bin/bash
set -euo pipefail
url="${!#}"
case "$url" in
    https://api.github.com/repos/hashicorp/terraform/releases/latest) key=terraform ;;
    https://api.github.com/repos/terraform-linters/tflint/releases/latest) key=tflint ;;
    https://api.github.com/repos/aquasecurity/trivy/releases/latest) key=trivy ;;
    https://api.github.com/repos/terraform-docs/terraform-docs/releases/latest) key=terraform-docs ;;
    https://api.github.com/repos/digitalocean/doctl/releases/latest) key=doctl ;;
    https://api.github.com/repos/cli/cli/releases/latest) key=gh ;;
    https://api.github.com/repos/bats-core/bats-core/releases/latest) key=bats ;;
    https://api.github.com/repos/helm/helm/releases/latest) key=helm ;;
    https://api.github.com/repos/kubernetes-sigs/kind/releases/latest) key=kind ;;
    https://api.github.com/repos/ahmetb/kubectx/releases/latest) key=kubectx ;;
    https://api.github.com/repos/asdf-vm/asdf/releases/latest) key=asdf ;;
    https://go.dev/VERSION?m=text) key=golang ;;
    https://dl.k8s.io/release/stable.txt) key=kubectl ;;
    https://registry.npmjs.org/opencode-ai) key=opencode ;;
    https://registry.npmjs.org/@opencode/cli) key=opencode2 ;;
    https://nodejs.org/dist/index.json) key=nodejs ;;
    *) printf 'Unexpected curl URL: %s\n' "$url" >&2; exit 97 ;;
esac
printf '%s\n' "$url" >> "$UPDATER_REQUESTS"
if [[ -f "$UPDATER_RESPONSES/$key.fail" ]]; then
    printf 'Controlled HTTP/transport failure: %s\n' "$url" >&2
    exit 22
fi
cat "$UPDATER_RESPONSES/$key"
