#!/usr/bin/env bats

load 'test_helper/common'
load '/usr/local/share/bats-support/load'
load '/usr/local/share/bats-assert/load'

@test "make upgrade-gh target is available" {
    run make -s -n -C "$REPO_ROOT" upgrade-gh
    assert_success
}

@test "upgrade check for gh succeeds" {
    run bash "$REPO_ROOT/scripts/update-versions.sh" --tool gh --check-only
    assert_success
}

@test "Dockerfile installs gh via apt" {
    run grep -Fq -- "https://cli.github.com/packages/githubcli-archive-keyring.gpg" "$REPO_ROOT/Dockerfile"
    assert_success
}

@test "Dockerfile installs pinned gh version" {
    run grep -Fq -- "apt-get install -y gh=\$GH_VERSION" "$REPO_ROOT/Dockerfile"
    assert_success
}

@test "README lists gh as apt-managed" {
    run grep -Fq -- '| gh | apt |' "$REPO_ROOT/README.md"
    assert_success
}
