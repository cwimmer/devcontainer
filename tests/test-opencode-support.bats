#!/usr/bin/env bats

load 'test_helper/common'
load 'test_helper/updater'
load 'test_helper/image-build'
load '/usr/local/share/bats-support/load'
load '/usr/local/share/bats-assert/load'

setup() {
    setup_updater
}

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

@test "Make upgrade targets route to the intended OpenCode lane and all tools" {
    run make -s -n -C "$REPO_ROOT" upgrade-opencode2
    assert_success
    assert_output --partial 'scripts/update-versions.sh --tool opencode2'

    run make -s -n -C "$REPO_ROOT" upgrade-opencode
    assert_success
    assert_output --partial 'scripts/update-versions.sh --tool opencode'
    refute_output --partial '--tool opencode2'

    run make -s -n -C "$REPO_ROOT" upgrade
    assert_success
    assert_output --partial 'scripts/update-versions.sh --all'
}

@test "upgrade check for nodejs succeeds" {
    run bash "$UPDATER_REPO/scripts/update-versions.sh" --tool nodejs --check-only
    assert_success
}

@test "OpenCode discovery independently selects stable numeric majors" {
    run bash "$UPDATER_REPO/scripts/update-versions.sh" --tool opencode --no-backup
    assert_success
    assert_output --partial "1.20.10"
    run bash "$UPDATER_REPO/scripts/update-versions.sh" --tool opencode2 --no-backup
    assert_success
    assert_output --partial "2.10.0"
    grep -Fx 'ARG OPENCODE_VERSION=1.20.10' "$UPDATER_REPO/Dockerfile.OpenCode"
    grep -Fx 'ARG OPENCODE_VERSION=2.10.0' "$UPDATER_REPO/Dockerfile.OpenCode2"
}

@test "OpenCode discovery sorts arbitrarily large numeric components exactly" {
    printf '%s\n' '{"versions":{"1.9007199254740992.999":{},"1.9007199254740993.0":{}}}' \
        > "$UPDATER_RESPONSES/opencode"

    run bash "$UPDATER_REPO/scripts/update-versions.sh" --tool opencode --check-only
    assert_success
    assert_output --partial 'Latest opencode version: 1.9007199254740993.0'
}

@test "OpenCode rejects invalid and wrong-major explicit versions without writes" {
    snapshot_updater
    local tool version
    for tool in opencode opencode2; do
        for version in 0.9.0 3.0.0 v2.0.29 2.0 02.0.0 2.01.0 2.0.01 ' 2.0.29' '2.0.29 ' 2.0.29-rc.1 2.0.29+build; do
            run bash "$UPDATER_REPO/scripts/update-versions.sh" --tool "$tool" --version "$version"
            assert_failure
            assert_output --partial "$tool"
            assert_updater_unchanged
        done
    done
    run bash "$UPDATER_REPO/scripts/update-versions.sh" --tool opencode --version 2.0.29 --check-only
    assert_failure
    run bash "$UPDATER_REPO/scripts/update-versions.sh" --tool opencode2 --version 1.19.0 --check-only
    assert_failure
    assert_updater_unchanged
    test ! -s "$UPDATER_REQUESTS"
}

@test "OpenCode failures preserve all files and backups in normal and check-only modes" {
    local tool response backup_state fixture mode
    local -a flags=()

    for backup_state in absent present; do
        for tool in opencode opencode2; do
            case "$tool" in
                opencode)
                    response="$UPDATER_RESPONSES/opencode"
                    printf '%s\n' '{"versions":{"1.9.9":{},"2.99.0":{},"1.20.10":{},"1.20.9":{},"1.99.0-beta":{},"1.99.0+build":{}}}' > "$BATS_TEST_TMPDIR/default-response"
                    ;;
                opencode2)
                    response="$UPDATER_RESPONSES/opencode2"
                    printf '%s\n' '{"versions":{"2.9.9":{},"3.0.0":{},"1.99.0":{},"2.0.30":{},"2.10.0":{},"2.99.0-rc.1":{}}}' > "$BATS_TEST_TMPDIR/default-response"
                    ;;
            esac

            for mode in normal check-only; do
                if [[ "$mode" == check-only ]]; then
                    flags=(--check-only)
                else
                    flags=()
                fi

                for fixture in empty not-json null array empty-versions object no-stable; do
                    cp "$BATS_TEST_TMPDIR/default-response" "$response"
                    rm -f "$response.fail"
                    case "$fixture" in
                        empty) : > "$response" ;;
                        not-json) printf '%s\n' 'not-json' > "$response" ;;
                        null) printf '%s\n' 'null' > "$response" ;;
                        array) printf '%s\n' '[]' > "$response" ;;
                        empty-versions) printf '%s\n' '{"versions":[]}' > "$response" ;;
                        object) printf '%s\n' '{}' > "$response" ;;
                        no-stable) printf '%s\n' '{"versions":{"0.0.0":{},"3.0.0":{},"2.0.0-beta":{}}}' > "$response" ;;
                    esac

                    rm -f "$UPDATER_REPO"/*.backup
                    if [[ "$backup_state" == present ]]; then
                        printf '%s\n' 'Dockerfile backup sentinel' > "$UPDATER_REPO/Dockerfile.backup"
                        printf '%s\n' 'OpenCode v1 backup sentinel' > "$UPDATER_REPO/Dockerfile.OpenCode.backup"
                        printf '%s\n' 'OpenCode v2 backup sentinel' > "$UPDATER_REPO/Dockerfile.OpenCode2.backup"
                    fi
                    rm -rf "$BATS_TEST_TMPDIR/before"
                    snapshot_updater

                    run bash "$UPDATER_REPO/scripts/update-versions.sh" --tool "$tool" "${flags[@]}"
                    assert_failure
                    assert_output --partial "OpenCode"
                    assert_updater_unchanged
                done

                cp "$BATS_TEST_TMPDIR/default-response" "$response"
                rm -f "$response.fail" "$UPDATER_REPO"/*.backup
                if [[ "$backup_state" == present ]]; then
                    printf '%s\n' 'Dockerfile backup sentinel' > "$UPDATER_REPO/Dockerfile.backup"
                    printf '%s\n' 'OpenCode v1 backup sentinel' > "$UPDATER_REPO/Dockerfile.OpenCode.backup"
                    printf '%s\n' 'OpenCode v2 backup sentinel' > "$UPDATER_REPO/Dockerfile.OpenCode2.backup"
                fi
                touch "$response.fail"
                rm -rf "$BATS_TEST_TMPDIR/before"
                snapshot_updater

                run bash "$UPDATER_REPO/scripts/update-versions.sh" --tool "$tool" "${flags[@]}"
                assert_failure
                assert_output --partial "OpenCode"
                assert_updater_unchanged
            done
        done
    done
}

@test "OpenCode v1 update changes only Dockerfile.OpenCode and records its original" {
    local file=Dockerfile.OpenCode version=1.21.0
    snapshot_updater

    run bash "$UPDATER_REPO/scripts/update-versions.sh" --tool opencode --version "$version"
    assert_success
    assert_output --partial "$version"
    sed "s/^ARG OPENCODE_VERSION=.*/ARG OPENCODE_VERSION=$version/" \
        "$BATS_TEST_TMPDIR/before/$file" > "$BATS_TEST_TMPDIR/expected"
    cmp "$BATS_TEST_TMPDIR/expected" "$UPDATER_REPO/$file"
    cmp "$BATS_TEST_TMPDIR/before/$file" "$UPDATER_REPO/$file.backup"
    cmp "$BATS_TEST_TMPDIR/before/Dockerfile" "$UPDATER_REPO/Dockerfile"
    cmp "$BATS_TEST_TMPDIR/before/Dockerfile.OpenCode2" "$UPDATER_REPO/Dockerfile.OpenCode2"
    test ! -e "$UPDATER_REPO/Dockerfile.backup"
    test ! -e "$UPDATER_REPO/Dockerfile.OpenCode2.backup"
    test ! -s "$UPDATER_REQUESTS"
}

@test "OpenCode v2 update changes only Dockerfile.OpenCode2 and records its original" {
    local file=Dockerfile.OpenCode2 version=2.1.0
    snapshot_updater

    run bash "$UPDATER_REPO/scripts/update-versions.sh" --tool opencode2 --version "$version"
    assert_success
    assert_output --partial "$version"
    sed "s/^ARG OPENCODE_VERSION=.*/ARG OPENCODE_VERSION=$version/" \
        "$BATS_TEST_TMPDIR/before/$file" > "$BATS_TEST_TMPDIR/expected"
    cmp "$BATS_TEST_TMPDIR/expected" "$UPDATER_REPO/$file"
    cmp "$BATS_TEST_TMPDIR/before/$file" "$UPDATER_REPO/$file.backup"
    cmp "$BATS_TEST_TMPDIR/before/Dockerfile" "$UPDATER_REPO/Dockerfile"
    cmp "$BATS_TEST_TMPDIR/before/Dockerfile.OpenCode" "$UPDATER_REPO/Dockerfile.OpenCode"
    test ! -e "$UPDATER_REPO/Dockerfile.backup"
    test ! -e "$UPDATER_REPO/Dockerfile.OpenCode.backup"
    test ! -s "$UPDATER_REQUESTS"
}

@test "OpenCode unchanged and no-backup operations preserve backup state for both variants" {
    local tool file version current
    for tool in opencode opencode2; do
        case "$tool" in
            opencode) file=Dockerfile.OpenCode; version=1.21.0 ;;
            opencode2) file=Dockerfile.OpenCode2; version=2.1.0 ;;
        esac

        current="$(grep '^ARG OPENCODE_VERSION=' "$UPDATER_REPO/$file" | cut -d= -f2)"
        rm -f "$UPDATER_REPO"/*.backup
        rm -rf "$BATS_TEST_TMPDIR/before"
        snapshot_updater
        run bash "$UPDATER_REPO/scripts/update-versions.sh" --tool "$tool" --version "$current"
        assert_success
        assert_output --partial "$current"
        assert_updater_unchanged
        test ! -e "$UPDATER_REPO/Dockerfile.backup"
        test ! -e "$UPDATER_REPO/Dockerfile.OpenCode.backup"
        test ! -e "$UPDATER_REPO/Dockerfile.OpenCode2.backup"

        printf '%s\n' 'Dockerfile backup sentinel' > "$UPDATER_REPO/Dockerfile.backup"
        printf '%s\n' 'OpenCode v1 backup sentinel' > "$UPDATER_REPO/Dockerfile.OpenCode.backup"
        printf '%s\n' 'OpenCode v2 backup sentinel' > "$UPDATER_REPO/Dockerfile.OpenCode2.backup"
        rm -rf "$BATS_TEST_TMPDIR/before"
        snapshot_updater
        run bash "$UPDATER_REPO/scripts/update-versions.sh" --tool "$tool" --version "$version" --no-backup
        assert_success
        assert_output --partial "$version"
        cmp "$BATS_TEST_TMPDIR/before/Dockerfile.backup" "$UPDATER_REPO/Dockerfile.backup"
        cmp "$BATS_TEST_TMPDIR/before/Dockerfile.OpenCode.backup" "$UPDATER_REPO/Dockerfile.OpenCode.backup"
        cmp "$BATS_TEST_TMPDIR/before/Dockerfile.OpenCode2.backup" "$UPDATER_REPO/Dockerfile.OpenCode2.backup"
        grep -Fx "ARG OPENCODE_VERSION=$version" "$UPDATER_REPO/$file"
        for other in Dockerfile Dockerfile.OpenCode Dockerfile.OpenCode2; do
            [[ "$other" == "$file" ]] || cmp "$BATS_TEST_TMPDIR/before/$other" "$UPDATER_REPO/$other"
        done
        test ! -s "$UPDATER_REQUESTS"
    done
}

@test "OpenCode check-only preserves files and backup state for discovery and explicit versions" {
    local tool current backup_state selection version expected_url
    local -a flags=()
    for backup_state in absent present; do
        for tool in opencode opencode2; do
            case "$tool" in
                opencode) current=1.21.0; expected_url=https://registry.npmjs.org/opencode-ai ;;
                opencode2) current=2.1.0; expected_url=https://registry.npmjs.org/@opencode/cli ;;
            esac
            for selection in discovery explicit; do
                if [[ "$selection" == discovery ]]; then
                    flags=()
                    case "$tool" in opencode) version=1.20.10 ;; opencode2) version=2.10.0 ;; esac
                else
                    case "$tool" in opencode) version=1.21.0 ;; opencode2) version=2.1.0 ;; esac
                    flags=(--version "$version")
                fi

                rm -f "$UPDATER_REPO"/*.backup
                if [[ "$backup_state" == present ]]; then
                    printf '%s\n' 'Dockerfile backup sentinel' > "$UPDATER_REPO/Dockerfile.backup"
                    printf '%s\n' 'OpenCode v1 backup sentinel' > "$UPDATER_REPO/Dockerfile.OpenCode.backup"
                    printf '%s\n' 'OpenCode v2 backup sentinel' > "$UPDATER_REPO/Dockerfile.OpenCode2.backup"
                fi
                : > "$UPDATER_REQUESTS"
                rm -rf "$BATS_TEST_TMPDIR/before"
                snapshot_updater

                run bash "$UPDATER_REPO/scripts/update-versions.sh" --tool "$tool" --check-only "${flags[@]}"
                assert_success
                assert_output --partial "$tool"
                assert_output --partial "$version"
                assert_updater_unchanged
                if [[ "$selection" == discovery ]]; then
                    printf '%s\n' "$expected_url" > "$BATS_TEST_TMPDIR/expected-requests"
                    cmp "$BATS_TEST_TMPDIR/expected-requests" "$UPDATER_REQUESTS"
                else
                    test ! -s "$UPDATER_REQUESTS"
                fi
            done
        done
    done
}

@test "--all updates every base tool and both OpenCode variants exactly" {
    local file arg
    local -a base_args=(TERRAFORM_VERSION GOLANG_VERSION KUBECTL_VERSION TFLINT_VERSION
        TRIVY_VERSION TERRAFORM_DOCS_VERSION DOCTL_VERSION GH_VERSION BATS_VERSION
        HELM_VERSION KIND_VERSION KUBECTX_VERSION ASDF_VERSION)
    snapshot_updater

    run bash "$UPDATER_REPO/scripts/update-versions.sh" --all --no-backup
    assert_success
    assert_output --partial 'All updates completed successfully'

    cp "$BATS_TEST_TMPDIR/before/Dockerfile" "$BATS_TEST_TMPDIR/expected-Dockerfile"
    for arg in "${base_args[@]}"; do
        local value=9.9.9
        [[ "$arg" == ASDF_VERSION ]] && value=v9.9.9
        sed -i "s/^ARG ${arg}=.*/ARG ${arg}=${value}/" "$BATS_TEST_TMPDIR/expected-Dockerfile"
    done
    cp "$BATS_TEST_TMPDIR/before/Dockerfile.OpenCode" "$BATS_TEST_TMPDIR/expected-Dockerfile.OpenCode"
    sed -i 's/^ARG NODE_MAJOR=.*/ARG NODE_MAJOR=28/; s/^ARG OPENCODE_VERSION=.*/ARG OPENCODE_VERSION=1.20.10/' \
        "$BATS_TEST_TMPDIR/expected-Dockerfile.OpenCode"
    cp "$BATS_TEST_TMPDIR/before/Dockerfile.OpenCode2" "$BATS_TEST_TMPDIR/expected-Dockerfile.OpenCode2"
    sed -i 's/^ARG OPENCODE_VERSION=.*/ARG OPENCODE_VERSION=2.10.0/' \
        "$BATS_TEST_TMPDIR/expected-Dockerfile.OpenCode2"

    for file in Dockerfile Dockerfile.OpenCode Dockerfile.OpenCode2; do
        cmp "$BATS_TEST_TMPDIR/expected-$file" "$UPDATER_REPO/$file"
    done
}

@test "--all check-only preserves Dockerfiles and existing backup sentinels" {
    local file
    snapshot_updater
    for file in Dockerfile Dockerfile.OpenCode Dockerfile.OpenCode2; do
        printf 'backup sentinel for %s\n' "$file" > "$UPDATER_REPO/$file.backup"
    done
    cp "$UPDATER_REPO"/*.backup "$BATS_TEST_TMPDIR/"

    run bash "$UPDATER_REPO/scripts/update-versions.sh" --all --check-only
    assert_success

    cat > "$BATS_TEST_TMPDIR/expected-requests" <<'EOF'
https://api.github.com/repos/hashicorp/terraform/releases/latest
https://api.github.com/repos/terraform-linters/tflint/releases/latest
https://api.github.com/repos/aquasecurity/trivy/releases/latest
https://api.github.com/repos/terraform-docs/terraform-docs/releases/latest
https://api.github.com/repos/digitalocean/doctl/releases/latest
https://api.github.com/repos/cli/cli/releases/latest
https://api.github.com/repos/bats-core/bats-core/releases/latest
https://api.github.com/repos/helm/helm/releases/latest
https://api.github.com/repos/kubernetes-sigs/kind/releases/latest
https://api.github.com/repos/ahmetb/kubectx/releases/latest
https://api.github.com/repos/asdf-vm/asdf/releases/latest
https://go.dev/VERSION?m=text
https://dl.k8s.io/release/stable.txt
https://nodejs.org/dist/index.json
https://registry.npmjs.org/opencode-ai
https://registry.npmjs.org/@opencode/cli
EOF
    LC_ALL=C sort "$BATS_TEST_TMPDIR/expected-requests" > "$BATS_TEST_TMPDIR/expected-requests.sorted"
    LC_ALL=C sort "$UPDATER_REQUESTS" > "$BATS_TEST_TMPDIR/actual-requests.sorted"
    cmp "$BATS_TEST_TMPDIR/expected-requests.sorted" "$BATS_TEST_TMPDIR/actual-requests.sorted"

    for file in Dockerfile Dockerfile.OpenCode Dockerfile.OpenCode2; do
        cmp "$BATS_TEST_TMPDIR/before/$file" "$UPDATER_REPO/$file"
        cmp "$BATS_TEST_TMPDIR/$file.backup" "$UPDATER_REPO/$file.backup"
    done
}

@test "--all aggregates an OpenCode v2 failure while other lanes update" {
    local arg value
    local -a base_args=(TERRAFORM_VERSION GOLANG_VERSION KUBECTL_VERSION TFLINT_VERSION
        TRIVY_VERSION TERRAFORM_DOCS_VERSION DOCTL_VERSION GH_VERSION BATS_VERSION
        HELM_VERSION KIND_VERSION KUBECTX_VERSION ASDF_VERSION)
    snapshot_updater
    printf '%s\n' 'v2 backup sentinel' > "$UPDATER_REPO/Dockerfile.OpenCode2.backup"
    printf '%s\n' 'v2 backup sentinel' > "$BATS_TEST_TMPDIR/expected-v2-backup"
    touch "$UPDATER_RESPONSES/opencode2.fail"

    run bash "$UPDATER_REPO/scripts/update-versions.sh" --all
    assert_failure
    assert_output --partial 'opencode2'
    for arg in "${base_args[@]}"; do
        value=9.9.9
        [[ "$arg" == ASDF_VERSION ]] && value=v9.9.9
        grep -Fx "ARG ${arg}=${value}" "$UPDATER_REPO/Dockerfile"
    done
    grep -Fx 'ARG NODE_MAJOR=28' "$UPDATER_REPO/Dockerfile.OpenCode"
    grep -Fx 'ARG OPENCODE_VERSION=1.20.10' "$UPDATER_REPO/Dockerfile.OpenCode"
    cmp "$BATS_TEST_TMPDIR/before/Dockerfile.OpenCode2" "$UPDATER_REPO/Dockerfile.OpenCode2"
    cmp "$BATS_TEST_TMPDIR/expected-v2-backup" "$UPDATER_REPO/Dockerfile.OpenCode2.backup"
}

@test "--all checks every required Dockerfile before making requests" {
    local file
    for file in Dockerfile Dockerfile.OpenCode Dockerfile.OpenCode2; do
        cp "$UPDATER_REPO/$file" "$BATS_TEST_TMPDIR/$file"
        rm "$UPDATER_REPO/$file"
        : > "$UPDATER_REQUESTS"
        run bash "$UPDATER_REPO/scripts/update-versions.sh" --all --check-only
        assert_failure
        assert_output --partial "$file"
        test ! -s "$UPDATER_REQUESTS"
        cp "$BATS_TEST_TMPDIR/$file" "$UPDATER_REPO/$file"
    done

    rm "$UPDATER_REPO/Dockerfile.OpenCode2"
    : > "$UPDATER_REQUESTS"
    run bash "$UPDATER_REPO/scripts/update-versions.sh" --tool opencode --check-only
    assert_success
    printf '%s\n' 'https://registry.npmjs.org/opencode-ai' > "$BATS_TEST_TMPDIR/expected-requests"
    cmp "$BATS_TEST_TMPDIR/expected-requests" "$UPDATER_REQUESTS"

    rm "$UPDATER_REPO/Dockerfile.OpenCode"
    cp "$BATS_TEST_TMPDIR/Dockerfile.OpenCode2" "$UPDATER_REPO/"
    : > "$UPDATER_REQUESTS"
    run bash "$UPDATER_REPO/scripts/update-versions.sh" --tool opencode2 --check-only
    assert_success
    printf '%s\n' 'https://registry.npmjs.org/@opencode/cli' > "$BATS_TEST_TMPDIR/expected-requests"
    cmp "$BATS_TEST_TMPDIR/expected-requests" "$UPDATER_REQUESTS"
}

@test "single-tool checks require only the mapped Dockerfile" {
    rm "$UPDATER_REPO/Dockerfile.OpenCode" "$UPDATER_REPO/Dockerfile.OpenCode2"
    run bash "$UPDATER_REPO/scripts/update-versions.sh" --tool terraform --version 1.2.3 --check-only
    assert_success

    cp "$REPO_ROOT/Dockerfile.OpenCode2" "$UPDATER_REPO/"
    rm -f "$UPDATER_REPO/Dockerfile" "$UPDATER_REPO/Dockerfile.OpenCode"
    run bash "$UPDATER_REPO/scripts/update-versions.sh" --tool opencode2 --version 2.1.0 --check-only
    assert_success
}

@test "missing and empty OpenCode version arguments are rejected with a diagnostic" {
    run bash "$UPDATER_REPO/scripts/update-versions.sh" --tool opencode2 --version
    assert_failure
    assert_output --partial "--version requires a version argument"
    run bash "$UPDATER_REPO/scripts/update-versions.sh" --tool opencode --version ""
    assert_failure
    assert_output --partial "--version requires a version argument"
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

@test "workflow verifies v2 before conditional multiarch publication" {
    run python3 - "$REPO_ROOT/.github/workflows/image-build.yaml" <<'PY'
import pathlib
import re
import sys

text = pathlib.Path(sys.argv[1]).read_text()
lines = text.splitlines()
steps = {}
for index, line in enumerate(lines):
    if re.match(r"      - name:", line):
        end = index + 1
        while end < len(lines) and not re.match(r"      - name:", lines[end]):
            end += 1
        block = "\n".join(lines[index:end])
        match = re.search(r"^        id: ([a-z0-9_]+)$", block, re.MULTILINE)
        if match:
            steps[match.group(1)] = block

expected_ids = ["build_opencode2_native", "verify_opencode2", "publish_opencode2"]
positions = [text.index(f"        id: {step_id}") for step_id in expected_ids if step_id in steps]
assert len(positions) == 3 and positions == sorted(positions), "v2 steps must have ordered IDs"

native = steps["build_opencode2_native"]
assert "uses: docker/build-push-action@v7" in native
for field in (
    "context: .",
    "file: Dockerfile.OpenCode2",
    "tags: ghcr.io/cwimmer/devcontainer:opencode2",
    "platforms: linux/amd64",
    "pull: true",
    "load: true",
):
    assert field in native, f"native build missing {field!r}"
assert native.count("ghcr.io/cwimmer/devcontainer:opencode2") == 1, "native build must have only the v2 tag"
assert len(re.findall(r"^\s+tags:", native, re.MULTILINE)) == 1, "native build must have one tags field"
assert "push:" not in native, "native build must not publish"
assert "timeout-minutes: 30" in native

verify = steps["verify_opencode2"]
assert "sh scripts/verify-opencode2.sh" in verify
assert "ghcr.io/cwimmer/devcontainer:opencode2" in verify
assert "timeout-minutes: 20" in verify

publish = steps["publish_opencode2"]
assert "uses: docker/build-push-action@v7" in publish
for field in (
    "context: .",
    "file: Dockerfile.OpenCode2",
    "tags: ghcr.io/cwimmer/devcontainer:opencode2",
    "platforms: linux/amd64,linux/arm64",
    "pull: true",
    "push: ${{ github.ref == 'refs/heads/main' }}",
):
    assert field in publish, f"publication missing {field!r}"
assert publish.count("ghcr.io/cwimmer/devcontainer:opencode2") == 1, "publication must have only the v2 tag"
assert "continue-on-error" not in "\n".join(steps[step_id] for step_id in expected_ids)
assert "if: always()" not in "\n".join(steps[step_id] for step_id in expected_ids)
PY
    assert_success
}

@test "workflow preserves base v1 and failure gates" {
    run python3 - "$REPO_ROOT/.github/workflows/image-build.yaml" <<'PY'
import pathlib
import re
import sys

text = pathlib.Path(sys.argv[1]).read_text()
lines = text.splitlines()
steps = {}
for index, line in enumerate(lines):
    if re.match(r"      - name:", line):
        end = index + 1
        while end < len(lines) and not re.match(r"      - name:", lines[end]):
            end += 1
        block = "\n".join(lines[index:end])
        match = re.search(r"^        uses: docker/build-push-action@v7$", block, re.MULTILINE)
        if match:
            name = re.match(r"      - name: (.+)", lines[index]).group(1)
            steps[name] = block

base = steps["Build and push base multi-architecture image"]
assert "tags: |\n            ghcr.io/cwimmer/devcontainer:latest" in base
assert base.count("ghcr.io/cwimmer/devcontainer:latest") == 1
assert len(re.findall(r"^\s+tags:", base, re.MULTILINE)) == 1
assert "platforms: linux/amd64,linux/arm64" in base
assert "push: ${{ github.ref == 'refs/heads/main' }}" in base
v1 = steps["Build and push OpenCode multi-architecture image"]
assert "file: Dockerfile.OpenCode" in v1
assert "ghcr.io/cwimmer/devcontainer:opencode\n" in v1
assert v1.count("ghcr.io/cwimmer/devcontainer:opencode") == 1
assert len(re.findall(r"^\s+tags:", v1, re.MULTILINE)) == 1
assert "platforms: linux/amd64,linux/arm64" in v1
assert "push: ${{ github.ref == 'refs/heads/main' }}" in v1

trigger_section = text.split("jobs:", 1)[0]
for trigger in ("  push:\n    branches:\n      - main", "  pull_request:\n    branches:\n      - main", "  workflow_dispatch:"):
    assert trigger in trigger_section, f"existing workflow trigger lost: {trigger!r}"

new_steps = text[text.index("        id: build_opencode2_native"):] if "        id: build_opencode2_native" in text else ""
assert "continue-on-error" not in new_steps
assert "if: always()" not in new_steps
PY
    assert_success
}

@test "v2 verifier reads the Dockerfile pin and uses a local ID" {
    setup_image_build
    local image_ref=example/opencode-v2:test
    local image_id=sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
    local pin
    pin="$(sed -n 's/^ARG OPENCODE_VERSION=//p' "$IMAGE_REPO/Dockerfile.OpenCode2")"

    IMAGE_ID="$image_id" IMAGE_VERSION_OUTPUT="$pin" \
        run sh "$IMAGE_REPO/scripts/verify-opencode2.sh" "$image_ref"
    assert_success
    assert_output --partial "$pin"
    assert_image_calls "[[\"image\",\"inspect\",\"--format\",\"{{.Id}}\",\"$image_ref\"],[\"run\",\"--rm\",\"--pull=never\",\"$image_id\",\"cat\",\"/usr/local/share/asdf-tool-versions\"],[\"run\",\"--rm\",\"--pull=never\",\"$image_id\",\"opencode\",\"--version\"]]"

    : > "$IMAGE_LOG"
    sed -i 's/^ARG OPENCODE_VERSION=.*/ARG OPENCODE_VERSION=2.8.14/' "$IMAGE_REPO/Dockerfile.OpenCode2"
    IMAGE_ID="$image_id" IMAGE_VERSION_OUTPUT="OpenCode v2.8.14" \
        run sh "$IMAGE_REPO/scripts/verify-opencode2.sh" "$image_ref"
    assert_success
    assert_output --partial '2.8.14'
    assert_image_calls "[[\"image\",\"inspect\",\"--format\",\"{{.Id}}\",\"$image_ref\"],[\"run\",\"--rm\",\"--pull=never\",\"$image_id\",\"cat\",\"/usr/local/share/asdf-tool-versions\"],[\"run\",\"--rm\",\"--pull=never\",\"$image_id\",\"opencode\",\"--version\"]]"
}

@test "v2 verifier works outside the repository with spaced paths" {
    setup_image_build
    local image_ref=example/opencode-v2:spaced
    local image_id=sha256:fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210
    local pin
    pin="$(sed -n 's/^ARG OPENCODE_VERSION=//p' "$IMAGE_REPO/Dockerfile.OpenCode2")"

    cd "$BATS_TEST_TMPDIR"
    IMAGE_ID="$image_id" IMAGE_VERSION_OUTPUT="v$pin" \
        run sh "$IMAGE_REPO/scripts/verify-opencode2.sh" "$image_ref"
    assert_success
    assert_output --partial "$pin"
    assert_image_calls "[[\"image\",\"inspect\",\"--format\",\"{{.Id}}\",\"$image_ref\"],[\"run\",\"--rm\",\"--pull=never\",\"$image_id\",\"cat\",\"/usr/local/share/asdf-tool-versions\"],[\"run\",\"--rm\",\"--pull=never\",\"$image_id\",\"opencode\",\"--version\"]]"
}

@test "v2 verifier rejects invalid pins and runtime failures" {
    setup_image_build
    local image_ref=example/opencode-v2:failure
    local pin
    pin="$(sed -n 's/^ARG OPENCODE_VERSION=//p' "$IMAGE_REPO/Dockerfile.OpenCode2")"

    rm "$IMAGE_REPO/Dockerfile.OpenCode2"
    run sh "$IMAGE_REPO/scripts/verify-opencode2.sh" "$image_ref"
    assert_failure
    assert_no_image_calls

    cp "$REPO_ROOT/Dockerfile.OpenCode2" "$IMAGE_REPO/Dockerfile.OpenCode2"
    for pin_case in absent empty duplicate; do
        case "$pin_case" in
            absent) sed -i '/^ARG OPENCODE_VERSION=/d' "$IMAGE_REPO/Dockerfile.OpenCode2" ;;
            empty) sed -i 's/^ARG OPENCODE_VERSION=.*/ARG OPENCODE_VERSION=/' "$IMAGE_REPO/Dockerfile.OpenCode2" ;;
            duplicate) printf '\nARG OPENCODE_VERSION=%s\n' "$pin" >> "$IMAGE_REPO/Dockerfile.OpenCode2" ;;
        esac
        : > "$IMAGE_LOG"
        run sh "$IMAGE_REPO/scripts/verify-opencode2.sh" "$image_ref"
        assert_failure
        assert_no_image_calls
        cp "$REPO_ROOT/Dockerfile.OpenCode2" "$IMAGE_REPO/Dockerfile.OpenCode2"
    done

    run sh "$IMAGE_REPO/scripts/verify-opencode2.sh"
    assert_failure
    assert_output --partial 'Usage:'
    run sh "$IMAGE_REPO/scripts/verify-opencode2.sh" "$image_ref" extra
    assert_failure
    assert_output --partial 'Usage:'

    for failure in missing-image metadata version; do
        : > "$IMAGE_LOG"
        if [[ "$failure" == version ]]; then
            IMAGE_FAIL=version IMAGE_VERSION_OUTPUT="$pin" \
                run sh "$IMAGE_REPO/scripts/verify-opencode2.sh" "$image_ref"
        else
            IMAGE_FAIL="$failure" run sh "$IMAGE_REPO/scripts/verify-opencode2.sh" "$image_ref"
        fi
        assert_failure
    done

    : > "$IMAGE_LOG"
    IMAGE_ID='' run sh "$IMAGE_REPO/scripts/verify-opencode2.sh" "$image_ref"
    assert_failure
    assert_output --partial 'image ID'
    : > "$IMAGE_LOG"
    IMAGE_VERSION_OUTPUT="$pin" IMAGE_VERSION_STATUS=9 \
        run sh "$IMAGE_REPO/scripts/verify-opencode2.sh" "$image_ref"
    assert_failure
    : > "$IMAGE_LOG"
    IMAGE_VERSION_OUTPUT='' run sh "$IMAGE_REPO/scripts/verify-opencode2.sh" "$image_ref"
    assert_failure
    : > "$IMAGE_LOG"
    IMAGE_VERSION_OUTPUT=0.0.0 run sh "$IMAGE_REPO/scripts/verify-opencode2.sh" "$image_ref"
    assert_failure
    assert_output --partial "expected $pin"
    assert_output --partial 'actual 0.0.0'
}

@test "image targets select their Dockerfiles tags and native platforms" {
    setup_image_build
    local arch target expected
    for arch in x86_64 arm64 aarch64; do
        if [[ "$arch" == x86_64 ]]; then
            expected=linux/amd64
        else
            expected=linux/arm64
        fi
        for target in test test_native test_opencode test_native_opencode test_opencode2 test_native_opencode2; do
            : > "$IMAGE_LOG"
            run make -s -C "$IMAGE_REPO" "HOST_ARCH=$arch" "$target"
            if [[ "$target" == test_opencode2 || "$target" == test_native_opencode2 ]]; then
                assert_success
            elif [[ "$target" == test_opencode || "$target" == test_native_opencode ]]; then
                assert_success
            else
                assert_success
            fi
            case "$target" in
                test)
                    assert_image_builds "[[\"Dockerfile\",\"ghcr.io/cwimmer/devcontainer:latest\",\"linux/amd64,linux/arm64\",false,false],[\"Dockerfile\",\"ghcr.io/cwimmer/devcontainer:latest\",\"$expected\",true,false]]"
                    ;;
                test_native)
                    assert_image_builds '[["Dockerfile","ghcr.io/cwimmer/devcontainer:latest","",true,false]]'
                    ;;
                test_opencode)
                    assert_image_builds "[[\"Dockerfile\",\"ghcr.io/cwimmer/devcontainer:latest\",\"linux/amd64,linux/arm64\",false,false],[\"Dockerfile\",\"ghcr.io/cwimmer/devcontainer:latest\",\"$expected\",true,false],[\"Dockerfile.OpenCode\",\"ghcr.io/cwimmer/devcontainer:opencode\",\"linux/amd64,linux/arm64\",false,false],[\"Dockerfile.OpenCode\",\"ghcr.io/cwimmer/devcontainer:opencode\",\"$expected\",true,false]]"
                    ;;
                test_native_opencode)
                    assert_image_builds '[["Dockerfile","ghcr.io/cwimmer/devcontainer:latest","",true,false],["Dockerfile.OpenCode","ghcr.io/cwimmer/devcontainer:opencode","",true,false]]'
                    ;;
                test_opencode2)
                    assert_image_builds "[[\"Dockerfile\",\"ghcr.io/cwimmer/devcontainer:latest\",\"linux/amd64,linux/arm64\",false,false],[\"Dockerfile\",\"ghcr.io/cwimmer/devcontainer:latest\",\"$expected\",true,false],[\"Dockerfile.OpenCode2\",\"ghcr.io/cwimmer/devcontainer:opencode2\",\"linux/amd64,linux/arm64\",false,true],[\"Dockerfile.OpenCode2\",\"ghcr.io/cwimmer/devcontainer:opencode2\",\"$expected\",true,true]]"
                    ;;
                test_native_opencode2)
                    assert_image_builds "[[\"Dockerfile\",\"ghcr.io/cwimmer/devcontainer:latest\",\"\",true,false],[\"Dockerfile.OpenCode2\",\"ghcr.io/cwimmer/devcontainer:opencode2\",\"$expected\",true,true]]"
                    ;;
            esac
            if [[ "$arch" != x86_64 ]]; then
                case "$target" in
                    test|test_opencode|test_opencode2)
                        # Multi-platform recipes retain both architectures and load arm64.
                        python3 - "$IMAGE_LOG" "$target" <<'PY'
import json, pathlib, sys
calls=[json.loads(line) for line in pathlib.Path(sys.argv[1]).read_text().splitlines()]
builds=[a for a in calls if a[:2]==["buildx","build"]]
native=[a for a in builds if "--load" in a]
assert native and native[-1][native[-1].index("--platform")+1] == "linux/arm64", (sys.argv[2], builds)
PY
                        ;;
                    *)
                        python3 - "$IMAGE_LOG" <<'PY'
import json, pathlib, sys
calls=[json.loads(line) for line in pathlib.Path(sys.argv[1]).read_text().splitlines()]
builds=[a for a in calls if a[:2]==["buildx","build"]]
v2=[a for a in builds if "Dockerfile.OpenCode2" in a]
if v2:
    assert v2[0][v2[0].index("--platform")+1] == "linux/arm64", v2
PY
                        ;;
                esac
            fi
        done
    done
}

@test "v2 multi target builds both platforms before loading native" {
    setup_image_build
    local native=linux/amd64
    [[ "$(uname -m)" == arm64 || "$(uname -m)" == aarch64 ]] && native=linux/arm64
    run make -s -C "$IMAGE_REPO" test_opencode2
    assert_success
    assert_image_builds "[[\"Dockerfile\",\"ghcr.io/cwimmer/devcontainer:latest\",\"linux/amd64,linux/arm64\",false,false],[\"Dockerfile\",\"ghcr.io/cwimmer/devcontainer:latest\",\"$native\",true,false],[\"Dockerfile.OpenCode2\",\"ghcr.io/cwimmer/devcontainer:opencode2\",\"linux/amd64,linux/arm64\",false,true],[\"Dockerfile.OpenCode2\",\"ghcr.io/cwimmer/devcontainer:opencode2\",\"$native\",true,true]]"
    assert_image_commands '[["image","inspect","--format","{{.Id}}","ghcr.io/cwimmer/devcontainer:opencode2"],["run","--rm","--pull=never","sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","cat","/usr/local/share/asdf-tool-versions"],["run","--rm","--pull=never","sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","opencode","--version"]]'
    python3 - "$IMAGE_LOG" <<'PY'
import json, pathlib, sys
calls=[json.loads(line) for line in pathlib.Path(sys.argv[1]).read_text().splitlines()]
v2=[a for a in calls if a[:2]==["buildx","build"] and "Dockerfile.OpenCode2" in a]
assert len(v2)==2 and v2[0].index("--platform") < v2[1].index("--platform")
assert all("--pull" in a for a in v2)
assert calls.index(v2[-1]) < next(i for i,a in enumerate(calls) if a[:2]==["image","inspect"])
assert not any("Dockerfile.OpenCode" in a for a in calls)
base_checks=[i for i,a in enumerate(calls) if a[:3]==["run","--rm","ghcr.io/cwimmer/devcontainer:latest"]]
assert base_checks and max(base_checks) < calls.index(v2[0]), (base_checks, v2, calls)
PY
}

@test "v2 native target builds only native" {
    setup_image_build
    local native=linux/amd64
    [[ "$(uname -m)" == arm64 || "$(uname -m)" == aarch64 ]] && native=linux/arm64
    run make -s -C "$IMAGE_REPO" test_native_opencode2
    assert_success
    assert_image_builds "[[\"Dockerfile\",\"ghcr.io/cwimmer/devcontainer:latest\",\"\",true,false],[\"Dockerfile.OpenCode2\",\"ghcr.io/cwimmer/devcontainer:opencode2\",\"$native\",true,true]]"
    assert_image_commands '[["image","inspect","--format","{{.Id}}","ghcr.io/cwimmer/devcontainer:opencode2"],["run","--rm","--pull=never","sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","cat","/usr/local/share/asdf-tool-versions"],["run","--rm","--pull=never","sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","opencode","--version"]]'
    python3 - "$IMAGE_LOG" <<'PY'
import json, pathlib, sys
calls=[json.loads(line) for line in pathlib.Path(sys.argv[1]).read_text().splitlines()]
builds=[a for a in calls if a[:2]==["buildx","build"]]
assert not any("Dockerfile.OpenCode" in a for a in calls)
base=[i for i,a in enumerate(calls) if a[:2]==["buildx","build"] and ("-f" not in a or a[a.index("-f")+1]=="Dockerfile")]
v2=next(i for i,a in enumerate(calls) if a[:2]==["buildx","build"] and "Dockerfile.OpenCode2" in a)
base_runtime=max(i for i,a in enumerate(calls) if a[:3]==["run","--rm","ghcr.io/cwimmer/devcontainer:latest"] and "cat" in a)
assert base and base[-1] < base_runtime < v2, (base, base_runtime, v2)
assert len([a for a in builds if "Dockerfile.OpenCode2" in a]) == 1
assert not any("Dockerfile.OpenCode" in a for a in calls)
PY
}

@test "v2 Make targets propagate failures instead of checking stale images" {
    setup_image_build
    local target failure
    for target in test_opencode2 test_native_opencode2; do
        for failure in base-build v2-native-build; do
            : > "$IMAGE_LOG"
            run env IMAGE_FAIL="$failure" IMAGE_ID=sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb \
                IMAGE_VERSION_OUTPUT=2.10.0 make -s -C "$IMAGE_REPO" "$target"
            assert_failure
            python3 - "$IMAGE_LOG" "$failure" <<'PY'
import json, pathlib, sys
calls=[json.loads(line) for line in pathlib.Path(sys.argv[1]).read_text().splitlines()]
assert not any(a[:2]==["image","inspect"] or (a[:2]==["run","--rm"] and "--pull=never" in a) for a in calls), calls
if sys.argv[2] == "base-build":
    assert not any(a[:2]==["buildx","build"] and "Dockerfile.OpenCode2" in a for a in calls), calls
PY
        done
        if [[ "$target" == test_opencode2 ]]; then
            : > "$IMAGE_LOG"
            run env IMAGE_FAIL=v2-multi-build IMAGE_ID=sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb \
                IMAGE_VERSION_OUTPUT=2.10.0 make -s -C "$IMAGE_REPO" "$target"
            assert_failure
            python3 - "$IMAGE_LOG" <<'PY'
import json, pathlib, sys
calls=[json.loads(line) for line in pathlib.Path(sys.argv[1]).read_text().splitlines()]
assert not any(a[:2]==["buildx","build"] and "Dockerfile.OpenCode2" in a and "--load" in a for a in calls), calls
assert not any(a[:2]==["image","inspect"] or (a[:2]==["run","--rm"] and "--pull=never" in a) for a in calls), calls
PY
        fi
    done

    for failure in missing-image version mismatch; do
        : > "$IMAGE_LOG"
        case "$failure" in
            missing-image) run env IMAGE_FAIL=missing-image make -s -C "$IMAGE_REPO" test_native_opencode2 ;;
            version) run env IMAGE_FAIL=version IMAGE_VERSION_OUTPUT=2.10.0 make -s -C "$IMAGE_REPO" test_native_opencode2 ;;
            mismatch) run env IMAGE_VERSION_OUTPUT=0.0.0 make -s -C "$IMAGE_REPO" test_native_opencode2 ;;
        esac
        assert_failure
        python3 - "$IMAGE_LOG" <<'PY'
import json, pathlib, sys
calls=[json.loads(line) for line in pathlib.Path(sys.argv[1]).read_text().splitlines()]
assert any(a[:2]==["image","inspect"] for a in calls), calls
PY
        if [[ "$failure" == missing-image ]]; then
            python3 - "$IMAGE_LOG" <<'PY'
import json, pathlib, sys
calls=[json.loads(line) for line in pathlib.Path(sys.argv[1]).read_text().splitlines()]
assert not any(a[:2]==["run","--rm"] and "--pull=never" in a for a in calls), calls
PY
        else
            python3 - "$IMAGE_LOG" <<'PY'
import json, pathlib, sys
calls=[json.loads(line) for line in pathlib.Path(sys.argv[1]).read_text().splitlines()]
assert any(a[-2:]==["opencode","--version"] for a in calls), calls
PY
        fi
    done
}

@test "builder fallback preserves failure propagation" {
    setup_image_build
    run env IMAGE_FAIL=builder-inspect make -s -C "$IMAGE_REPO" test_native_opencode2
    assert_success
    python3 - "$IMAGE_LOG" <<'PY'
import json, pathlib, sys
calls=[json.loads(line) for line in pathlib.Path(sys.argv[1]).read_text().splitlines()]
assert ["buildx","create","--name","builder"] in calls
assert any(a[:2]==["buildx","build"] and "Dockerfile.OpenCode2" in a for a in calls)
PY

    : > "$IMAGE_LOG"
    run env IMAGE_FAIL=builder-create make -s -C "$IMAGE_REPO" test_native_opencode2
    assert_failure
    python3 - "$IMAGE_LOG" <<'PY'
import json, pathlib, sys
calls=[json.loads(line) for line in pathlib.Path(sys.argv[1]).read_text().splitlines()]
assert ["buildx","create","--name","builder"] in calls
assert not any(a[:2]==["buildx","build"] for a in calls), calls
assert not any(a[:2]==["image","inspect"] for a in calls), calls
PY
}

@test "clean attempts all three images despite removal failure" {
    setup_image_build
    run env IMAGE_FAIL=remove make -s -k -C "$IMAGE_REPO" clean
    assert_success
    python3 - "$IMAGE_LOG" <<'PY'
import json, pathlib, sys
calls=[json.loads(line) for line in pathlib.Path(sys.argv[1]).read_text().splitlines()]
assert ["buildx","rm","builder"] in calls
for tag in ("latest", "opencode", "opencode2"):
    assert ["rmi", f"ghcr.io/cwimmer/devcontainer:{tag}"] in calls, calls
PY
}
