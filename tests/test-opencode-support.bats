#!/usr/bin/env bats

load 'test_helper/common'
load 'test_helper/updater'
load 'test_helper/image-build'
load 'test_helper/data-copy.bash'
load '/usr/local/share/bats-support/load'
load '/usr/local/share/bats-assert/load'

setup() {
    setup_updater
    setup_data_copy
}

@test "data preparation help and malformed arguments are handled before Docker" {
    run "$DATA_COPY_SCRIPT" --help
    assert_success
    assert_output --partial 'POSIX shell'
    assert_output --partial 'Docker CLI'
    assert_output --partial 'cp -a'
    assert_output --partial 'mkdir, ln, rm, mktemp'
    assert_output --partial 'writable /tmp'
    assert_output --partial 'other-repo-v1 other-repo-v2 local-helper:fixture'
    assert_output --partial 'Migration has not run'
    assert_output --partial 'all other writers'
    assert_output --partial 'cannot atomically combine'
    assert_output --partial 'DOCKER_CONTEXT'
    assert_output --partial 'DOCKER_HOST (overrides the selected context endpoint)'
    assert_data_copy_calls help

    for args in none one two extra empty-source empty-destination empty-image equal invalid-source invalid-destination; do
        : > "$DATA_COPY_LOG"
        case "$args" in
            none) run "$DATA_COPY_SCRIPT" ;;
            one) run "$DATA_COPY_SCRIPT" other-repo-v1 ;;
            two) run "$DATA_COPY_SCRIPT" other-repo-v1 other-repo-v2 ;;
            extra) run "$DATA_COPY_SCRIPT" other-repo-v1 other-repo-v2 local-helper:fixture extra ;;
            empty-source) run "$DATA_COPY_SCRIPT" '' other-repo-v2 local-helper:fixture ;;
            empty-destination) run "$DATA_COPY_SCRIPT" other-repo-v1 '' local-helper:fixture ;;
            empty-image) run "$DATA_COPY_SCRIPT" other-repo-v1 other-repo-v2 '' ;;
            equal) run "$DATA_COPY_SCRIPT" other-repo-v1 other-repo-v1 local-helper:fixture ;;
            invalid-source) run "$DATA_COPY_SCRIPT" '_invalid' other-repo-v2 local-helper:fixture ;;
            invalid-destination) run "$DATA_COPY_SCRIPT" other-repo-v1 'x' local-helper:fixture ;;
        esac
        assert_failure
        assert_equal 2 "$status"
        assert_data_copy_calls usage
    done
}

@test "data preparation refuses missing source and every existing destination" {
    local scenario
    for scenario in missing-source existing-destination existing-destination-empty; do
        reset_data_copy_fixture
        DATA_COPY_SCENARIO="$scenario" run "$DATA_COPY_SCRIPT" other-repo-v1 other-repo-v2 local-helper:fixture
        assert_failure
        assert_data_copy_calls "$scenario"
    done
}

@test "data preparation fails closed on Docker, inspect, image, and helper preflight errors" {
    local scenario
    for scenario in daemon-failure context-failure context-endpoint-failure list-failure source-inspect-failure consumer-failure image-failure preflight-failure; do
        reset_data_copy_fixture
        DATA_COPY_SCENARIO="$scenario" run "$DATA_COPY_SCRIPT" other-repo-v1 other-repo-v2 local-helper:fixture
        assert_failure
        assert_data_copy_calls "$scenario"
        refute_output --partial 'Creating destination'
    done
}

@test "data preparation names running consumers and never stops or removes them" {
    local scenario
    for scenario in running-source running-destination; do
        reset_data_copy_fixture
        DATA_COPY_SCENARIO="$scenario" run "$DATA_COPY_SCRIPT" other-repo-v1 other-repo-v2 local-helper:fixture
        assert_failure
        assert_output --partial 'fixture-writer'
        assert_output --partial 'stop'
        assert_data_copy_calls "$scenario"
    done
}

@test "data preparation copies with immutable image and quiet verification" {
    run "$DATA_COPY_SCRIPT" other-repo-v1 other-repo-v2 'local-helper:fixture'
    assert_success
    assert_output --partial 'Docker context: fixture-context'
    assert_output --partial 'other-repo-v1'
    assert_output --partial 'other-repo-v2'
    assert_output --partial 'DOCKER_CONTEXT'
    assert_output --partial 'DOCKER_HOST'
    assert_output --partial 'fixture-daemon'
    assert_output --partial 'Selected context endpoint: unix:///fixture/docker.sock'
    assert_output --partial 'Effective Docker endpoint: unix:///fixture/docker.sock (selected Docker context endpoint)'
    assert_output --partial 'migration has not run'
    assert_data_copy_calls success
}

@test "data preparation shows Docker endpoint override precedence" {
    reset_data_copy_fixture
    run env DOCKER_HOST=tcp://docker-host.invalid:2375 "$DATA_COPY_SCRIPT" other-repo-v1 other-repo-v2 local-helper:fixture
    assert_success
    assert_output --partial 'Selected context endpoint: unix:///fixture/docker.sock'
    assert_output --partial 'Effective Docker endpoint: tcp://docker-host.invalid:2375 (DOCKER_HOST (overrides selected context endpoint))'
    assert_data_copy_calls success

    reset_data_copy_fixture
    run env DOCKER_HOST=tcp://lower-precedence.invalid:2375 DOCKER_CONTEXT=fixture-override "$DATA_COPY_SCRIPT" other-repo-v1 other-repo-v2 local-helper:fixture
    assert_success
    assert_output --partial 'Docker context: fixture-override'
    assert_output --partial 'Selected context endpoint: unix:///override/context.sock'
    assert_output --partial 'Effective Docker endpoint: unix:///override/context.sock (DOCKER_CONTEXT (overrides DOCKER_HOST))'
    assert_data_copy_calls success
}

@test "data preparation rejects a destination populated at mount time" {
    DATA_COPY_SCENARIO=destination-race run "$DATA_COPY_SCRIPT" other-repo-v1 other-repo-v2 local-helper:fixture
    assert_failure
    assert_output --partial 'empty'
    assert_data_copy_calls destination-race
}

@test "data preparation rechecks consumers after destination creation" {
    DATA_COPY_SCENARIO=consumer-race run "$DATA_COPY_SCRIPT" other-repo-v1 other-repo-v2 local-helper:fixture
    assert_failure
    assert_output --partial 'fixture-writer'
    assert_data_copy_calls consumer-race
}

@test "data preparation retains and reports a possibly partial destination after failure" {
    local scenario
    for scenario in create-failure copy-failure compare-failure interrupt; do
        reset_data_copy_fixture
        DATA_COPY_SCENARIO="$scenario" run "$DATA_COPY_SCRIPT" other-repo-v1 other-repo-v2 local-helper:fixture
        assert_failure
        assert_output --partial 'partial'
        refute_output --partial 'Preparation complete'
        test "$(printf '%s\n' "$output" | grep -c 'may be partial')" -eq 1
        assert_data_copy_calls "$scenario"
    done
}

@test "data preparation is standalone with spaced script path and quoted image argument" {
    cd "$BATS_TEST_TMPDIR"
    run "$DATA_COPY_SCRIPT" other-repo-v1 other-repo-v2 'local-helper:fixture with spaces'
    assert_success
    assert_data_copy_calls success-quoted-image
    test "$(find "$DATA_COPY_REPO" -type f | wc -l)" -eq 1
}

@test "data preparation has matching sh and dash argument behavior" {
    local shell
    for shell in sh dash; do
        command -v "$shell" >/dev/null 2>&1 || continue
        reset_data_copy_fixture
    DATA_COPY_SCENARIO=success run "$shell" "$DATA_COPY_SCRIPT" other-repo-v1 other-repo-v2 local-helper:fixture
        assert_success
        assert_data_copy_calls success

        reset_data_copy_fixture
        run "$shell" "$DATA_COPY_SCRIPT" other-repo-v1
        assert_failure
        assert_equal 2 "$status"
        assert_data_copy_calls usage
    done
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

@test "OpenCode Python helper regressions pass" {
    run python3 "$REPO_ROOT/tests/test_opencode_helpers.py" -v
    assert_success
}

@test "workflow verifies v2 before conditional multiarch publication" {
    run python3 "$REPO_ROOT/tests/test_helper/workflow_assertions.py" "$REPO_ROOT/.github/workflows/image-build.yaml" v2
    assert_success
}

@test "workflow preserves base v1 and failure gates" {
    run python3 "$REPO_ROOT/tests/test_helper/workflow_assertions.py" "$REPO_ROOT/.github/workflows/image-build.yaml" existing
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
        assert_runtime_failure_stops_at_expected_stage "$failure"
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
            assert_success
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
        done
    done
}

@test "all Make test targets stop after a failed BATS suite" {
    setup_image_build
    local target
    for target in test test_native test_opencode test_native_opencode test_opencode2 test_native_opencode2; do
        : > "$IMAGE_LOG"
        run env IMAGE_BATS_STATUS=17 make -s -C "$IMAGE_REPO" "$target"
        assert_failure
        assert_suite_failure_stops_followup_builds
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
    assert_v2_builds_precede_verification
}

@test "v2 native target builds only native" {
    setup_image_build
    local native=linux/amd64
    [[ "$(uname -m)" == arm64 || "$(uname -m)" == aarch64 ]] && native=linux/arm64
    run make -s -C "$IMAGE_REPO" test_native_opencode2
    assert_success
    assert_image_builds "[[\"Dockerfile\",\"ghcr.io/cwimmer/devcontainer:latest\",\"\",true,false],[\"Dockerfile.OpenCode2\",\"ghcr.io/cwimmer/devcontainer:opencode2\",\"$native\",true,true]]"
    assert_image_commands '[["image","inspect","--format","{{.Id}}","ghcr.io/cwimmer/devcontainer:opencode2"],["run","--rm","--pull=never","sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","cat","/usr/local/share/asdf-tool-versions"],["run","--rm","--pull=never","sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","opencode","--version"]]'
    assert_v2_builds_precede_verification
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
            case "$failure" in
                base-build) assert_build_failure_stops_verification base-build ;;
                v2-native-build) assert_build_failure_stops_verification v2-native-build ;;
            esac
        done
        if [[ "$target" == test_opencode2 ]]; then
            : > "$IMAGE_LOG"
            run env IMAGE_FAIL=v2-multi-build IMAGE_ID=sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb \
                IMAGE_VERSION_OUTPUT=2.10.0 make -s -C "$IMAGE_REPO" "$target"
            assert_failure
            assert_build_failure_stops_verification v2-multi-build
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
        assert_runtime_failure_stops_at_expected_stage "$failure"
    done
}

@test "builder fallback preserves failure propagation" {
    setup_image_build
    run env IMAGE_FAIL=builder-inspect make -s -C "$IMAGE_REPO" test_native_opencode2
    assert_success
    assert_builder_fallback_behavior builder-inspect

    : > "$IMAGE_LOG"
    run env IMAGE_FAIL=builder-create make -s -C "$IMAGE_REPO" test_native_opencode2
    assert_failure
    assert_builder_fallback_behavior builder-create
}

@test "clean attempts all three images despite removal failure" {
    setup_image_build
    run env IMAGE_FAIL=remove make -s -k -C "$IMAGE_REPO" clean
    assert_success
    assert_cleanup_attempts_all_removals
}
