setup_image_build() {
    IMAGE_REPO="$BATS_TEST_TMPDIR/image build repo"
    IMAGE_LOG="$BATS_TEST_TMPDIR/image docker calls.jsonl"
    IMAGE_BIN="$BATS_TEST_TMPDIR/image docker bin"
    mkdir -p "$IMAGE_REPO/scripts" "$IMAGE_BIN"

    local file
    for file in Dockerfile Dockerfile.OpenCode Dockerfile.OpenCode2 Makefile; do
        if [[ -f "$REPO_ROOT/$file" ]]; then
            cp "$REPO_ROOT/$file" "$IMAGE_REPO/$file"
        fi
    done
    if [[ -f "$REPO_ROOT/scripts/verify-opencode2.sh" ]]; then
        cp "$REPO_ROOT/scripts/verify-opencode2.sh" "$IMAGE_REPO/scripts/"
    fi
    cp "$REPO_ROOT/tests/test_helper/image-docker.py" "$IMAGE_BIN/image-docker.py"
    cat > "$IMAGE_BIN/docker" <<'EOF'
#!/bin/sh
exec python3 "$IMAGE_BIN/image-docker.py" "$@"
EOF
    chmod +x "$IMAGE_BIN/docker"
    : > "$IMAGE_LOG"

    export IMAGE_REPO IMAGE_LOG IMAGE_BIN
    export PATH="$IMAGE_BIN:$PATH"
    unset IMAGE_FAIL IMAGE_ID IMAGE_VERSION_OUTPUT IMAGE_VERSION_STATUS IMAGE_BATS_STATUS
}

assert_image_calls() {
    python3 "$REPO_ROOT/tests/test_helper/image_assertions.py" "$IMAGE_LOG" calls "$1"
}

assert_no_image_calls() {
    if [[ ! -f "$IMAGE_LOG" ]]; then
        printf 'expected image log to exist: %s\n' "$IMAGE_LOG" >&2
        return 1
    fi
    if test ! -s "$IMAGE_LOG"; then
        return 0
    else
        printf 'expected no image calls in %s; log contents:\n' "$IMAGE_LOG" >&2
        cat "$IMAGE_LOG" >&2
        return 1
    fi
}

assert_image_builds() {
    python3 "$REPO_ROOT/tests/test_helper/image_assertions.py" "$IMAGE_LOG" builds "$1"
}

assert_image_commands() {
    python3 "$REPO_ROOT/tests/test_helper/image_assertions.py" "$IMAGE_LOG" verifier "$1"
}

assert_v2_builds_precede_verification() {
    python3 "$REPO_ROOT/tests/test_helper/image_assertions.py" "$IMAGE_LOG" v2-order
}

assert_build_failure_stops_verification() {
    python3 "$REPO_ROOT/tests/test_helper/image_assertions.py" "$IMAGE_LOG" build-failure "$1"
}

assert_runtime_failure_stops_at_expected_stage() {
    python3 "$REPO_ROOT/tests/test_helper/image_assertions.py" "$IMAGE_LOG" runtime-failure "$1"
}

assert_builder_fallback_behavior() {
    python3 "$REPO_ROOT/tests/test_helper/image_assertions.py" "$IMAGE_LOG" builder-fallback "$1"
}

assert_cleanup_attempts_all_removals() {
    python3 "$REPO_ROOT/tests/test_helper/image_assertions.py" "$IMAGE_LOG" cleanup
}

assert_suite_failure_stops_followup_builds() {
    python3 "$REPO_ROOT/tests/test_helper/image_assertions.py" "$IMAGE_LOG" suite-failure
}
