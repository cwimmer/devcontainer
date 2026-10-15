#!/usr/bin/env bash

set -euo pipefail

repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
deps="$(mktemp -d)"
trap 'rm -rf -- "$deps"' EXIT

python3 -m pip install --target "$deps" -r "$repo/tests/requirements.txt"
export PYTHONPATH="$deps${PYTHONPATH:+:$PYTHONPATH}"
python3 -m ruff check \
    "$repo/tests/test_helper" \
    "$repo/tests/test_opencode_helpers.py"
python3 -m ruff format --check \
    "$repo/tests/test_helper" \
    "$repo/tests/test_opencode_helpers.py"
bats "$@"
