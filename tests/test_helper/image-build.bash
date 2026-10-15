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
    unset IMAGE_FAIL IMAGE_ID IMAGE_VERSION_OUTPUT IMAGE_VERSION_STATUS
}

assert_image_calls() {
    python3 - "$IMAGE_LOG" "$1" <<'PY'
import json
import pathlib
import sys

actual = [json.loads(line) for line in pathlib.Path(sys.argv[1]).read_text().splitlines()]
expected = json.loads(sys.argv[2])
if actual != expected:
    raise SystemExit(f"image calls differ\nexpected: {expected!r}\nactual:   {actual!r}")
PY
}

assert_no_image_calls() {
    python3 - "$IMAGE_LOG" <<'PY'
import pathlib
import sys

if pathlib.Path(sys.argv[1]).read_text():
    raise SystemExit(f"expected no image calls, got: {pathlib.Path(sys.argv[1]).read_text()}")
PY
}

assert_image_builds() {
    python3 - "$IMAGE_LOG" "$1" <<'PY'
import json
import pathlib
import sys

calls = [json.loads(line) for line in pathlib.Path(sys.argv[1]).read_text().splitlines()]
actual = []
for args in calls:
    if args[:2] != ["buildx", "build"]:
        continue
    dockerfile = args[args.index("-f") + 1] if "-f" in args else "Dockerfile"
    actual.append([
        dockerfile,
        args[args.index("--tag") + 1],
        args[args.index("--platform") + 1] if "--platform" in args else "",
        "--load" in args,
        "--pull" in args,
    ])
expected = json.loads(sys.argv[2])
if actual != expected:
    raise SystemExit(f"image builds differ\nexpected: {expected!r}\nactual:   {actual!r}")
PY
}

assert_image_commands() {
    python3 - "$IMAGE_LOG" "$1" <<'PY'
import json
import pathlib
import sys

calls = [json.loads(line) for line in pathlib.Path(sys.argv[1]).read_text().splitlines()]
actual = [args for args in calls if args[0] == "image" or (args[0] == "run" and "--pull=never" in args)]
expected = json.loads(sys.argv[2])
if actual != expected:
    raise SystemExit(f"image inspection/runtime calls differ\nexpected: {expected!r}\nactual:   {actual!r}")
PY
}
