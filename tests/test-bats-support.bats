#!/usr/bin/env bats

load 'test_helper/common'
load '/usr/local/share/bats-support/load'
load '/usr/local/share/bats-assert/load'

@test "make upgrade-bats target is available" {
    run make -s -n -C "$REPO_ROOT" upgrade-bats
    assert_success
}

@test "upgrade check for bats succeeds" {
    run bash "$REPO_ROOT/scripts/update-versions.sh" --tool bats --check-only
    assert_success
}

@test "Dockerfile pins BATS_VERSION" {
    run grep -Fq -- "ARG BATS_VERSION=" "$REPO_ROOT/Dockerfile"
    assert_success
}

@test "Dockerfile installs bats via asdf" {
    run grep -Fq -- "RUN asdf plugin add bats https://github.com/timgluz/asdf-bats.git" "$REPO_ROOT/Dockerfile"
    assert_success
}

@test "Dockerfile includes bats in asdf-tool-versions generation" {
    run grep -Fq -- "\"bats \$BATS_VERSION\" \\" "$REPO_ROOT/Dockerfile"
    assert_success
}

@test "README lists bats as asdf-managed" {
    run grep -Fq -- '| bats | asdf |' "$REPO_ROOT/README.md"
    assert_success
}