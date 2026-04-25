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

assert_make_target upgrade-bats

assert_contains "$REPO_ROOT/Dockerfile" "ARG BATS_VERSION="
assert_contains "$REPO_ROOT/Dockerfile" "RUN asdf plugin add bats https://github.com/timgluz/asdf-bats.git"
assert_contains "$REPO_ROOT/Dockerfile" "RUN asdf install bats \$BATS_VERSION"
assert_contains "$REPO_ROOT/Dockerfile" "\"bats \$BATS_VERSION\" \\"
assert_contains "$REPO_ROOT/README.md" "| bats | asdf |"

printf 'PASS: Bats support is wired into the devcontainer build, upgrade workflow, and documentation.\n'
