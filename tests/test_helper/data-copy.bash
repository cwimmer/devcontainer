setup_data_copy() {
    export DATA_COPY_REPO="$BATS_TEST_TMPDIR/data copy repo"
    export DATA_COPY_LOG="$BATS_TEST_TMPDIR/data copy docker.jsonl"
    export DATA_COPY_STATE="$BATS_TEST_TMPDIR/data copy state.json"
    export DATA_COPY_BIN="$BATS_TEST_TMPDIR/data copy bin"
    export DATA_COPY_SCRIPT="$DATA_COPY_REPO/copied script/prepare-opencode2-data.sh"
    unset DOCKER_CONTEXT DOCKER_HOST
    mkdir -p "$DATA_COPY_REPO/copied script" "$DATA_COPY_BIN"
    if [[ -f "$REPO_ROOT/scripts/prepare-opencode2-data.sh" ]]; then
        cp "$REPO_ROOT/scripts/prepare-opencode2-data.sh" "$DATA_COPY_SCRIPT"
        chmod +x "$DATA_COPY_SCRIPT"
    fi
    cp "$REPO_ROOT/tests/test_helper/data-copy-docker.py" "$DATA_COPY_BIN/data-copy-docker.py"
    cat > "$DATA_COPY_BIN/docker" <<'EOF'
#!/bin/sh
exec python3 "$DATA_COPY_BIN/data-copy-docker.py" "$@"
EOF
    chmod +x "$DATA_COPY_BIN/docker"
    printf '%s\n' '{"created": false, "destination_populated_at_mount": false, "empty_guard_checked": false, "copy_executed": false, "docker_context": "", "context_endpoint": "", "effective_endpoint": "", "endpoint_source": ""}' > "$DATA_COPY_STATE"
    : > "$DATA_COPY_LOG"
    export DATA_COPY_SCENARIO=success
    export PATH="$DATA_COPY_BIN:$PATH"
}

reset_data_copy_fixture() {
    printf '%s\n' '{"created": false, "destination_populated_at_mount": false, "empty_guard_checked": false, "copy_executed": false, "docker_context": "", "context_endpoint": "", "effective_endpoint": "", "endpoint_source": ""}' > "$DATA_COPY_STATE"
    : > "$DATA_COPY_LOG"
}

assert_data_copy_calls() {
    python3 "$REPO_ROOT/tests/test_helper/data_copy_assertions.py" calls "$DATA_COPY_LOG" "$1"
}
