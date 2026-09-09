#!/usr/bin/env bats

load 'test_helper/common'
load '/usr/local/share/bats-support/load'
load '/usr/local/share/bats-assert/load'

@test "make test_opencode target is available" {
    run make -s -n -C "$REPO_ROOT" test_opencode
    assert_success
}

@test "make test_native_opencode target is available" {
    run make -s -n -C "$REPO_ROOT" test_native_opencode
    assert_success
}

@test "make upgrade-nodejs target is available" {
    run make -s -n -C "$REPO_ROOT" upgrade-nodejs
    assert_success
}

@test "make upgrade-opencode target is available" {
    run make -s -n -C "$REPO_ROOT" upgrade-opencode
    assert_success
}

@test "upgrade check for nodejs succeeds" {
    run bash "$REPO_ROOT/scripts/update-versions.sh" --tool nodejs --check-only
    assert_success
}

@test "upgrade check for opencode succeeds" {
    run bash "$REPO_ROOT/scripts/update-versions.sh" --tool opencode --check-only
    assert_success
}

@test "Makefile targets linux/arm64 platform twice" {
    run grep -Fc -- "--platform linux/arm64 \\" "$REPO_ROOT/Makefile"
    assert_output "2"
}

@test "Makefile runs opencode --version in container" {
    run grep -Fq -- "docker run --rm \$(CONTAINER_NAME):\$(OPENCODE_TAG) opencode --version" "$REPO_ROOT/Makefile"
    assert_success
}

@test "clean target removes OpenCode image" {
    run grep -Fq -- "docker rmi \$(CONTAINER_NAME):\$(OPENCODE_TAG)" "$REPO_ROOT/Makefile"
    assert_success
}

@test "image-build workflow tags the opencode image" {
    run grep -Fq -- 'ghcr.io/cwimmer/devcontainer:opencode' "$REPO_ROOT/.github/workflows/image-build.yaml"
    assert_success
}
