# Resolve REPO_ROOT once. BATS_TEST_DIRNAME is the directory of the .bats file
# (i.e. tests/), so its parent is the repository root.
REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
export REPO_ROOT