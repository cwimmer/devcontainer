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

assert_occurrences() {
    local file_path="$1"
    local expected_text="$2"
    local expected_count="$3"
    local actual_count

    actual_count=$(grep -Fc -- "$expected_text" "$file_path" || true)

    if [[ "$actual_count" != "$expected_count" ]]; then
        fail "expected '$file_path' to contain '$expected_text' ${expected_count} times, found ${actual_count}"
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

assert_make_target test_opencode
assert_make_target test_native_opencode
assert_make_target upgrade-nodejs
assert_make_target upgrade-opencode

assert_upgrade_check nodejs
assert_upgrade_check opencode

assert_occurrences "$REPO_ROOT/Makefile" "--platform linux/arm64 \\" "2"
assert_contains "$REPO_ROOT/Makefile" "docker run --rm \$(CONTAINER_NAME):\$(OPENCODE_TAG) opencode --version"
assert_contains "$REPO_ROOT/Makefile" "docker rmi \$(CONTAINER_NAME):\$(OPENCODE_TAG)"
assert_contains "$REPO_ROOT/.github/workflows/image-build.yaml" 'ghcr.io/cwimmer/devcontainer:opencode'

printf 'PASS: OpenCode support is wired into make targets and publish workflow.\n'