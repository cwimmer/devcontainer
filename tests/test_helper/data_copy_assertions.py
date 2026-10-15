#!/usr/bin/env python3
"""Semantic checks for data-copy Docker-call fixtures."""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

SOURCE = "other-repo-v1"
DESTINATION = "other-repo-v2"
IMAGE = "local-helper:fixture"
IMAGE_ID = "sha256:" + "a" * 64
DOCKER_FEATURE = "ghcr.io/devcontainers/features/docker-in-docker:2"
DOCKER_FEATURE_DIGEST = (
    "sha256:25b9f05705ffba7dbe503230ac76081419306f8c8bc88e0ce78c4ecd99a0c78c"
)
OPENCODE_DATA_MOUNT = (
    "source=devcontainer-opencode2-data,target=/root/.local/share/opencode,type=volume"
)
OPENCODE_CONFIG_TARGET = "/root/.config/opencode"
VSCODE_EXTENSIONS = [
    "ms-vscode.makefile-tools",
    "redhat.vscode-yaml",
    "DavidAnson.vscode-markdownlint",
    "sst-dev.opencode",
]


def load_calls(path: Path) -> list[list[str]]:
    calls: list[list[str]] = []
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        try:
            value = json.loads(line)
        except json.JSONDecodeError as error:
            raise ValueError(f"{path}: line {number}: invalid JSON: {error}") from error
        if not isinstance(value, list) or any(
            not isinstance(item, str) for item in value
        ):
            raise ValueError(
                f"{path}: line {number}: expected an array of strings, got {value!r}"
            )
        calls.append(value)
    return calls


def check_copy_calls(calls: list[list[str]], scenario: str) -> None:
    if any(
        not isinstance(call, list) or any(not isinstance(arg, str) for arg in call)
        for call in calls
    ):
        raise ValueError("calls must be arrays of strings")
    if scenario not in {
        "help",
        "usage",
        "missing-source",
        "existing-destination",
        "existing-destination-empty",
        "daemon-failure",
        "context-failure",
        "context-endpoint-failure",
        "list-failure",
        "source-inspect-failure",
        "consumer-failure",
        "image-failure",
        "preflight-failure",
        "running-source",
        "running-destination",
        "consumer-race",
        "create-failure",
        "copy-failure",
        "compare-failure",
        "destination-race",
        "interrupt",
        "success",
        "success-quoted-image",
    }:
        raise ValueError(f"unknown scenario {scenario!r}")
    forbidden = ("stop", "rm", "rmi", "pull", "build")
    for call in calls:
        if call and call[0] in forbidden:
            raise AssertionError(f"forbidden Docker operation: {call!r}")
    if scenario == "help":
        require(not calls, "help must not call Docker", calls)
        return
    if scenario == "usage":
        require(not calls, "usage errors must not call Docker", calls)
        return

    def calls_with(prefix: list[str]) -> list[int]:
        return [
            index for index, call in enumerate(calls) if call[: len(prefix)] == prefix
        ]

    if scenario == "missing-source":
        require(
            not calls_with(["volume", "create"]),
            "missing source created destination",
            calls,
        )
        require(not calls_with(["run"]), "missing source mounted or copied", calls)
        return
    if scenario.startswith("existing-destination"):
        require(
            not calls_with(["volume", "create"]),
            "existing destination was created",
            calls,
        )
        require(not calls_with(["run"]), "existing destination was mounted", calls)
        return
    failures = {
        "daemon-failure": ["info", "--format", "{{.Name}}"],
        "context-failure": ["context", "show"],
        "context-endpoint-failure": ["context", "inspect"],
        "list-failure": ["volume", "ls"],
        "source-inspect-failure": ["volume", "inspect", SOURCE],
        "consumer-failure": ["ps"],
        "image-failure": ["image", "inspect"],
        "preflight-failure": ["run"],
    }
    if scenario in failures:
        require(
            calls_with(failures[scenario]),
            f"expected failing stage {failures[scenario]!r}",
            calls,
        )
        require(
            not any("DATA_COPY_TRANSFER" in "\0".join(call) for call in calls),
            "failure reached copy",
            calls,
        )
        require(
            not calls_with(["volume", "create"]),
            "preflight failure created destination",
            calls,
        )
        return
    if scenario in {"running-source", "running-destination"}:
        expected = SOURCE if scenario == "running-source" else DESTINATION
        require(
            any(
                call[:2] == ["ps", "--filter"] and f"volume={expected}" in call
                for call in calls
            ),
            f"consumer check missing for {expected}",
            calls,
        )
        require(
            not calls_with(["volume", "create"]),
            "running consumer allowed destination creation",
            calls,
        )
        return
    if scenario == "consumer-race":
        create = calls_with(["volume", "create", DESTINATION])
        destination_checks = [
            index
            for index, call in enumerate(calls)
            if call[:2] == ["ps", "--filter"] and f"volume={DESTINATION}" in call
        ]
        require(
            create and destination_checks[-1] > create[0],
            "destination consumers were not rechecked after create",
            calls,
        )
        require(
            not any("DATA_COPY_TRANSFER" in "\0".join(call) for call in calls),
            "copy continued after a new consumer appeared",
            calls,
        )
        return
    if scenario == "destination-race":
        transfer_calls = [
            call for call in calls if "DATA_COPY_TRANSFER" in "\0".join(call)
        ]
        require(
            len(transfer_calls) == 1,
            "expected exactly one mount-time helper call",
            calls,
        )
        transfer_command = "\0".join(transfer_calls[0])
        guard_index = transfer_command.index("for path in /destination/*")
        copy_index = transfer_command.index("cp -a /source/. /destination/")
        require(
            guard_index < copy_index,
            "destination emptiness guard must run before copy",
            calls,
        )
        require(
            not calls_with(["volume", "rm"]),
            "mount-time destination race deleted a volume",
            calls,
        )
        state_path = os.environ.get("DATA_COPY_STATE")
        require(
            state_path is not None,
            "DATA_COPY_STATE is required for race assertions",
            calls,
        )
        state = json.loads(Path(state_path).read_text(encoding="utf-8"))
        require(
            state["destination_populated_at_mount"],
            "fixture did not populate destination at mount time",
            state,
        )
        require(
            state["empty_guard_rejected_populated_destination"],
            "helper did not reject the populated destination",
            state,
        )
        require(
            not state["copy_executed"], "copy ran on a populated destination", state
        )
        return
    if scenario in {
        "create-failure",
        "copy-failure",
        "compare-failure",
        "interrupt",
    }:
        if scenario == "create-failure":
            require(
                calls_with(["volume", "create"]),
                "destination creation was not attempted",
                calls,
            )
            create_index = calls_with(["volume", "create"])[0]
            require(
                not any(
                    call[:2] == ["ps", "--filter"] for call in calls[create_index + 1 :]
                ),
                "create failure unexpectedly continued to consumer checks",
                calls,
            )
        else:
            require(
                calls_with(["volume", "create"]),
                "destination was not created before failure",
                calls,
            )
        if scenario in {
            "copy-failure",
            "compare-failure",
            "interrupt",
        }:
            require(
                any("DATA_COPY_TRANSFER" in "\0".join(call) for call in calls),
                "transfer stage missing",
                calls,
            )
        require(not calls_with(["volume", "rm"]), "failure deleted destination", calls)
        return
    if scenario not in {"success", "success-quoted-image"}:
        raise ValueError(f"unknown scenario {scenario!r}")

    source_inspect = calls_with(["volume", "inspect", SOURCE])
    source_mounts = [
        i
        for i, call in enumerate(calls)
        if call[:1] == ["run"]
        and any(f"src={SOURCE},dst=/source" in argument for argument in call)
    ]
    listing = calls_with(["volume", "ls"])
    create = calls_with(["volume", "create", DESTINATION])
    preflight = [
        i for i, call in enumerate(calls) if "DATA_COPY_PREFLIGHT" in "\0".join(call)
    ]
    transfer = [
        i for i, call in enumerate(calls) if "DATA_COPY_TRANSFER" in "\0".join(call)
    ]
    require(
        source_inspect and listing, "source and volume-list checks are required", calls
    )
    endpoint_calls = [
        (index, call)
        for index, call in enumerate(calls)
        if call[:2] == ["context", "inspect"]
    ]
    state_path = os.environ.get("DATA_COPY_STATE")
    require(
        state_path is not None,
        "DATA_COPY_STATE is required for endpoint assertions",
        calls,
    )
    state = json.loads(Path(state_path).read_text(encoding="utf-8"))
    context_override = state["docker_context_env"]
    require(
        len(endpoint_calls) == 1
        and endpoint_calls[0][1]
        == [
            "context",
            "inspect",
            "--format",
            '{{ (index .Endpoints "docker").Host }}',
            context_override or "fixture-context",
        ],
        "the selected context endpoint must be inspected by context name",
        calls,
    )
    require(
        source_inspect[0] < source_mounts[0] if source_mounts else False,
        "source must be inspected before any helper mount",
        calls,
    )
    require(
        endpoint_calls[0][0] < calls_with(["info", "--format"])[0],
        "endpoint must be resolved before daemon verification",
        calls,
    )
    require(
        len(listing) >= 2 and listing[-1] < create[0],
        "destination absence must be checked and rechecked around creation",
        calls,
    )
    require(
        create and preflight and preflight[0] < create[0],
        "helper capabilities must be preflighted before creation",
        calls,
    )
    require(
        transfer and create[0] < transfer[0],
        "copy must follow destination creation",
        calls,
    )
    require(
        any(
            call[:3] == ["image", "inspect", "--format"]
            and call[-1]
            == (
                "local-helper:fixture with spaces"
                if scenario == "success-quoted-image"
                else IMAGE
            )
            for call in calls
        ),
        "image must be resolved from the supplied image reference",
        calls,
    )
    require(
        all(IMAGE_ID in call for call in calls if call[:1] == ["run"]),
        "helper runs must use immutable local image ID",
        calls,
    )
    require(
        all(
            "--pull=never" in call and "--network=none" in call
            for call in calls
            if call[:1] == ["run"]
        ),
        "helper runs must disable pulls and networking",
        calls,
    )
    require(
        any(
            "--read-only" in call or "readonly" in "\0".join(call)
            for call in calls
            if call[:1] == ["run"]
        ),
        "source must be read-only",
        calls,
    )
    require(
        any(
            any(
                f"src={SOURCE},dst=/source,readonly,volume-nocopy" in argument
                for argument in call
            )
            for call in calls
            if call[:1] == ["run"]
        ),
        "source mount must be read-only with copy-up disabled",
        calls,
    )
    require(
        any(
            "volume-nocopy" in "\0".join(call) for call in calls if call[:1] == ["run"]
        ),
        "volume copy-up must be disabled",
        calls,
    )
    require(
        any(
            "--entrypoint" in call
            and call[call.index("--entrypoint") + 1] == "/bin/sh"
            and call[call.index("--user") + 1] == "0:0"
            for call in calls
            if call[:1] == ["run"]
        ),
        "helper must use explicit shell entrypoint and root user",
        calls,
    )
    require(
        len([call for call in calls if call[:2] == ["ps", "--filter"]]) >= 4,
        "source and destination consumers must be checked before and after create",
        calls,
    )
    require(
        any("cp -a /source/. /destination/" in "\0".join(call) for call in calls),
        "archive copy command missing",
        calls,
    )
    transfer_command = "\0".join(calls[transfer[0]])
    require(
        transfer_command.index("for path in /destination/*")
        < transfer_command.index("cp -a /source/. /destination/"),
        "destination emptiness guard must run before copy",
        calls,
    )
    require(
        transfer_command.index("cp -a /source/. /destination/")
        < transfer_command.index("diff -qr --no-dereference /source /destination"),
        "copy must precede verification",
        calls,
    )
    require(
        any(
            "diff -qr --no-dereference /source /destination" in "\0".join(call)
            for call in calls
        ),
        "quiet recursive symlink-aware comparison missing",
        calls,
    )
    require(not calls_with(["volume", "rm"]), "success deleted a volume", calls)
    expected_context_endpoint = (
        "unix:///override/context.sock"
        if context_override
        else "unix:///fixture/docker.sock"
    )
    if context_override:
        expected_endpoint = expected_context_endpoint
        expected_source = "DOCKER_CONTEXT"
    elif state["docker_host_env"]:
        expected_endpoint = state["docker_host_env"]
        expected_source = "DOCKER_HOST"
    else:
        expected_endpoint = expected_context_endpoint
        expected_source = "selected context"
    require(
        state["context_endpoint"] == expected_context_endpoint,
        "fixture context endpoint was not captured",
        state,
    )
    require(
        state["effective_endpoint"] == expected_endpoint,
        "effective endpoint precedence was incorrect",
        state,
    )
    require(
        state["endpoint_source"] == expected_source,
        "effective endpoint source was incorrect",
        state,
    )


def check_devcontainer(root: Path) -> None:
    """Check this repository's approved v2 devcontainer and locked feature."""
    config_path = root / ".devcontainer" / "devcontainer.json"
    lock_path = root / ".devcontainer" / "devcontainer-lock.json"
    config = load_json(config_path)
    lock = load_json(lock_path)

    build = require_mapping(config.get("build"), "build")
    require_equal(
        build.get("dockerfile"), "../Dockerfile.OpenCode2", "build.dockerfile"
    )
    require_equal(build.get("context"), "..", "build.context")

    mounts = config.get("mounts")
    if not isinstance(mounts, list) or any(
        not isinstance(item, str) for item in mounts
    ):
        raise ValueError("mounts: expected a list of strings")
    require_equal(mounts, [OPENCODE_DATA_MOUNT], "mounts")
    if any(
        "devcontainer-opencode-data" in mount or OPENCODE_CONFIG_TARGET in mount
        for mount in mounts
    ):
        raise AssertionError("mounts: original data/configuration mount is forbidden")

    lifecycle_fields = {
        "initializeCommand",
        "onCreateCommand",
        "updateContentCommand",
        "postCreateCommand",
        "postStartCommand",
        "postAttachCommand",
    }
    configured_lifecycle = sorted(lifecycle_fields.intersection(config))
    if configured_lifecycle:
        raise AssertionError(
            f"lifecycle commands must be absent; found {configured_lifecycle!r}"
        )

    features = require_mapping(config.get("features"), "features")
    docker = require_mapping(features.get(DOCKER_FEATURE), f"features.{DOCKER_FEATURE}")
    require_equal(docker.get("version"), "latest", f"features.{DOCKER_FEATURE}.version")
    require_equal(docker.get("moby"), False, f"features.{DOCKER_FEATURE}.moby")
    require_equal(
        docker.get("enableNonRootDocker"),
        "true",
        f"features.{DOCKER_FEATURE}.enableNonRootDocker",
    )

    customizations = require_mapping(config.get("customizations"), "customizations")
    vscode = require_mapping(customizations.get("vscode"), "customizations.vscode")
    require_equal(vscode.get("extensions"), VSCODE_EXTENSIONS, "VS Code extensions")

    locked_features = require_mapping(lock.get("features"), "lock.features")
    locked_docker = require_mapping(
        locked_features.get(DOCKER_FEATURE), f"lock.features.{DOCKER_FEATURE}"
    )
    require_equal(locked_docker.get("version"), "2.17.0", "locked feature version")
    require_equal(
        locked_docker.get("resolved"),
        f"ghcr.io/devcontainers/features/docker-in-docker@{DOCKER_FEATURE_DIGEST}",
        "locked feature resolution",
    )
    require_equal(
        locked_docker.get("integrity"),
        DOCKER_FEATURE_DIGEST,
        "locked feature integrity",
    )


def load_json(path: Path) -> dict:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ValueError(f"{path}: cannot load JSON: {error}") from error
    return require_mapping(value, str(path))


def require_mapping(value: object, field: str) -> dict:
    if not isinstance(value, dict):
        raise ValueError(f"{field}: expected an object")
    return value


def require_equal(actual: object, expected: object, field: str) -> None:
    if actual != expected:
        raise AssertionError(f"{field}: expected {expected!r}, got {actual!r}")


def require(condition: bool, message: str, actual: object) -> None:
    if not condition:
        raise AssertionError(f"{message}; actual calls: {actual!r}")


def main(argv: list[str]) -> int:
    if len(argv) == 2 and argv[0] == "config":
        try:
            check_devcontainer(Path(argv[1]))
        except (OSError, ValueError, AssertionError) as error:
            print(f"devcontainer assertion failed: {error}", file=sys.stderr)
            return 1
        return 0
    if len(argv) != 3 or argv[0] != "calls":
        print(
            "usage: data_copy_assertions.py calls LOG SCENARIO | config REPO_ROOT",
            file=sys.stderr,
        )
        return 2
    try:
        calls = load_calls(Path(argv[1]))
        check_copy_calls(calls, argv[2])
    except (OSError, ValueError, AssertionError) as error:
        print(f"data-copy assertion failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
