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

assert_upgrade_check() {
    local tool="$1"

    if ! bash "$REPO_ROOT/scripts/update-versions.sh" --tool "$tool" --check-only >/dev/null; then
        fail "expected upgrade check for '$tool' to succeed"
    fi
}

assert_contains() {
    local file_path="$1"
    local expected_text="$2"

    if ! grep -Fq "$expected_text" "$file_path"; then
        fail "expected '$file_path' to contain: $expected_text"
    fi
}

assert_make_target upgrade-gh
assert_upgrade_check gh

assert_contains "$REPO_ROOT/Dockerfile" "ARG GH_VERSION="
assert_contains "$REPO_ROOT/Dockerfile" "https://cli.github.com/packages/githubcli-archive-keyring.gpg"
assert_contains "$REPO_ROOT/Dockerfile" "apt-get install -y gh=\$GH_VERSION"
assert_contains "$REPO_ROOT/README.md" "| gh | apt |"

printf 'PASS: GitHub CLI support is wired into the devcontainer build, upgrade workflow, and documentation.\n'
