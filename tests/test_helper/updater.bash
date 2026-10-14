setup_updater() {
    export UPDATER_REPO="$BATS_TEST_TMPDIR/repo"
    export UPDATER_RESPONSES="$BATS_TEST_TMPDIR/responses"
    export UPDATER_REQUESTS="$BATS_TEST_TMPDIR/requests"
    mkdir -p "$UPDATER_REPO/scripts" "$UPDATER_RESPONSES" "$BATS_TEST_TMPDIR/bin"
    cp "$REPO_ROOT/scripts/update-versions.sh" "$UPDATER_REPO/scripts/"
    cp "$REPO_ROOT"/Dockerfile{,.OpenCode,.OpenCode2} "$UPDATER_REPO/"
    cp "$REPO_ROOT/tests/test_helper/updater-curl.bash" "$BATS_TEST_TMPDIR/bin/curl"
    chmod +x "$BATS_TEST_TMPDIR/bin/curl"
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    : > "$UPDATER_REQUESTS"
    printf '%s\n' '{"versions":{"1.9.9":{},"2.99.0":{},"1.20.10":{},"1.20.9":{},"1.99.0-beta":{},"1.99.0+build":{}}}' > "$UPDATER_RESPONSES/opencode"
    printf '%s\n' '{"versions":{"2.9.9":{},"3.0.0":{},"1.99.0":{},"2.0.30":{},"2.10.0":{},"2.99.0-rc.1":{}}}' > "$UPDATER_RESPONSES/opencode2"
    printf '%s\n' '[{"version":"v28.0.0"}]' > "$UPDATER_RESPONSES/nodejs"
    local tool
    for tool in terraform tflint trivy terraform-docs doctl gh bats helm kind kubectx asdf; do
        printf '%s\n' '{"tag_name":"v9.9.9"}' > "$UPDATER_RESPONSES/$tool"
    done
    printf 'go9.9.9\n' > "$UPDATER_RESPONSES/golang"
    printf 'v9.9.9\n' > "$UPDATER_RESPONSES/kubectl"
}

snapshot_updater() {
    mkdir -p "$BATS_TEST_TMPDIR/before"
    cp "$UPDATER_REPO"/Dockerfile* "$BATS_TEST_TMPDIR/before/"
}

assert_updater_unchanged() {
    local file
    for file in Dockerfile Dockerfile.OpenCode Dockerfile.OpenCode2; do
        cmp "$BATS_TEST_TMPDIR/before/$file" "$UPDATER_REPO/$file" || return 1
        if [[ -f "$BATS_TEST_TMPDIR/before/$file.backup" ]]; then
            cmp "$BATS_TEST_TMPDIR/before/$file.backup" "$UPDATER_REPO/$file.backup" || return 1
        else
            test ! -e "$UPDATER_REPO/$file.backup" || return 1
        fi
    done
}
