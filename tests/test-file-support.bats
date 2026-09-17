#!/usr/bin/env bats

load 'test_helper/common'
load '/usr/local/share/bats-support/load'
load '/usr/local/share/bats-assert/load'

@test "README lists file as apt-managed" {
    run grep -Fq -- '| file | apt |' "$REPO_ROOT/README.md"
    assert_success
}

@test "file --version succeeds" {
    run file --version
    assert_success
}

@test "file identifies /etc/passwd as text" {
    run file /etc/passwd
    assert_success
    assert_output --partial "text"
}

@test "file identifies /usr/bin/ls as ELF" {
    run file /usr/bin/ls
    assert_success
    assert_output --partial "ELF"
}