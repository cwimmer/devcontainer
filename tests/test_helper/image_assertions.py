#!/usr/bin/env python3
"""Assertions for argument-array logs emitted by the Docker test stub."""

from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any


def load_calls(path: Path) -> list[list[str]]:
    """Read and validate one JSON-encoded command argument array per line."""
    calls: list[list[str]] = []
    try:
        with path.open(encoding="utf-8") as log:
            for line_number, line in enumerate(log, start=1):
                try:
                    record = json.loads(line)
                except json.JSONDecodeError as error:
                    raise ValueError(
                        f"{path}: line {line_number}: malformed JSON: {error.msg}"
                    ) from error
                if not isinstance(record, list) or not record:
                    raise ValueError(
                        f"{path}: line {line_number}: expected a nonempty JSON array of strings"
                    )
                if any(
                    not isinstance(argument, str) or not argument for argument in record
                ):
                    raise ValueError(
                        f"{path}: line {line_number}: expected a nonempty array of nonempty strings"
                    )
                calls.append(record)
    except OSError as error:
        raise ValueError(f"cannot read command log {path}: {error}") from error
    return calls


def option_value(arguments: list[str], option: str, call_number: int) -> str:
    """Return an option operand, producing a useful error for malformed calls."""
    if option not in arguments:
        raise ValueError(
            f"call {call_number}: expected {option} option in build command: {arguments!r}"
        )
    index = arguments.index(option)
    if index + 1 >= len(arguments) or arguments[index + 1].startswith("--"):
        raise ValueError(
            f"call {call_number}: {option} is missing its operand in build command: {arguments!r}"
        )
    return arguments[index + 1]


def build_records(calls: list[list[str]]) -> list[list[object]]:
    """Project build commands to their Dockerfile/tag/platform/load/pull fields."""
    records: list[list[object]] = []
    for call_number, arguments in enumerate(calls, start=1):
        if arguments[:2] != ["buildx", "build"]:
            continue
        dockerfile = (
            option_value(arguments, "-f", call_number)
            if "-f" in arguments
            else "Dockerfile"
        )
        tag = option_value(arguments, "--tag", call_number)
        platform = (
            option_value(arguments, "--platform", call_number)
            if "--platform" in arguments
            else ""
        )
        records.append(
            [dockerfile, tag, platform, "--load" in arguments, "--pull" in arguments]
        )
    return records


def verifier_calls(calls: list[list[str]]) -> list[list[str]]:
    return [
        arguments
        for arguments in calls
        if arguments[0] == "image"
        or (arguments[0] == "run" and "--pull=never" in arguments)
    ]


def check_calls(calls: list[list[str]], expected: Any, selection: str) -> None:
    """Compare complete calls or a named projection against expected JSON data."""
    if selection == "all":
        actual: Any = calls
    elif selection == "builds":
        actual = build_records(calls)
    elif selection == "verifier":
        actual = verifier_calls(calls)
    else:
        raise ValueError(
            f"unknown call selection {selection!r}; expected all, builds, or verifier"
        )
    if actual != expected:
        raise AssertionError(
            f"image {selection} differ\nexpected: {expected!r}\nactual:   {actual!r}"
        )


def is_v2_build(arguments: list[str]) -> bool:
    return arguments[:2] == ["buildx", "build"] and "Dockerfile.OpenCode2" in arguments


def is_v1_build(arguments: list[str]) -> bool:
    return arguments[:2] == ["buildx", "build"] and "Dockerfile.OpenCode" in arguments


def is_verifier_call(arguments: list[str]) -> bool:
    return arguments[0] == "image" or (
        arguments[0] == "run" and "--pull=never" in arguments
    )


def is_base_runtime_call(arguments: list[str]) -> bool:
    return arguments[:3] == ["run", "--rm", "ghcr.io/cwimmer/devcontainer:latest"]


def is_base_build(arguments: list[str]) -> bool:
    if arguments[:2] != ["buildx", "build"]:
        return False
    dockerfile = option_value(arguments, "-f", 0) if "-f" in arguments else "Dockerfile"
    return dockerfile == "Dockerfile"


def is_v2_native_build(arguments: list[str]) -> bool:
    if not is_v2_build(arguments) or "--load" not in arguments:
        return False
    platform = option_value(arguments, "--platform", 0)
    return "," not in platform


def is_v2_multi_build(arguments: list[str]) -> bool:
    if not is_v2_build(arguments) or "--load" in arguments:
        return False
    return option_value(arguments, "--platform", 0) == "linux/amd64,linux/arm64"


def check_v2_order(calls: list[list[str]]) -> None:
    v2_indices = [index for index, call in enumerate(calls) if is_v2_build(call)]
    verifier_indices = [
        index for index, call in enumerate(calls) if is_verifier_call(call)
    ]
    base_runtime_indices = [
        index for index, call in enumerate(calls) if is_base_runtime_call(call)
    ]
    v1_indices = [index for index, call in enumerate(calls) if is_v1_build(call)]
    if not v2_indices:
        raise AssertionError(
            f"v2-order expected v2 build calls; actual calls: {calls!r}"
        )
    if not base_runtime_indices or max(base_runtime_indices) >= min(v2_indices):
        raise AssertionError(
            f"base runtime checks must occur before the first v2 build; actual calls: {calls!r}"
        )
    if not verifier_indices:
        raise AssertionError(
            f"v2-order requires image inspection/runtime verification; actual calls: {calls!r}"
        )
    if max(v2_indices) >= min(verifier_indices):
        raise AssertionError(
            f"all v2 builds must occur before verification; actual calls: {calls!r}"
        )
    if v1_indices:
        raise AssertionError(
            f"v2-order forbids v1 build calls at indices {v1_indices}; actual calls: {calls!r}"
        )


def check_build_failure(calls: list[list[str]], detail: str | None) -> None:
    allowed = {"base-build", "v2-native-build", "v2-multi-build"}
    if detail not in allowed:
        raise ValueError(f"build-failure requires one of {sorted(allowed)!r} as DETAIL")
    failed_attempt_checks = {
        "base-build": is_base_build,
        "v2-native-build": is_v2_native_build,
        "v2-multi-build": is_v2_multi_build,
    }
    matching_attempts = [call for call in calls if failed_attempt_checks[detail](call)]
    if not matching_attempts:
        expected = {
            "base-build": "a buildx build using the base Dockerfile (implicit or -f Dockerfile)",
            "v2-native-build": "a Dockerfile.OpenCode2 build with a native --platform operand and --load",
            "v2-multi-build": "a Dockerfile.OpenCode2 build with --platform linux/amd64,linux/arm64 and no --load",
        }[detail]
        build_calls = [call for call in calls if call[:2] == ["buildx", "build"]]
        raise AssertionError(
            f"build-failure {detail} requires the failed build attempt ({expected}); actual build calls: {build_calls!r}"
        )
    verification = [index for index, call in enumerate(calls) if is_verifier_call(call)]
    if verification:
        raise AssertionError(
            f"build-failure {detail} forbids verification; calls at indices {verification}: {calls!r}"
        )
    if detail == "base-build":
        base_indices = [
            index for index, call in enumerate(calls) if is_base_build(call)
        ]
        v2_indices = [index for index, call in enumerate(calls) if is_v2_build(call)]
        if v2_indices and min(v2_indices) > min(base_indices):
            raise AssertionError(
                f"v2 builds must not follow base build failure; indices {v2_indices}: {calls!r}"
            )
    if detail == "v2-multi-build":
        failed_attempt_indices = [
            index for index, call in enumerate(calls) if is_v2_multi_build(call)
        ]
        loaded_v2 = [
            index for index, call in enumerate(calls) if is_v2_native_build(call)
        ]
        if loaded_v2 and min(loaded_v2) > min(failed_attempt_indices):
            raise AssertionError(
                f"native v2 load must not follow multi-platform build failure; indices {loaded_v2}: {calls!r}"
            )


def check_runtime_failure(calls: list[list[str]], detail: str | None) -> None:
    allowed = {"missing-image", "metadata", "version", "mismatch"}
    if detail not in allowed:
        raise ValueError(
            f"runtime-failure requires one of {sorted(allowed)!r} as DETAIL"
        )
    inspect_indices = [
        index for index, call in enumerate(calls) if call[:2] == ["image", "inspect"]
    ]
    runtime_indices = [
        index
        for index, call in enumerate(calls)
        if call[:2] == ["run", "--rm"] and "--pull=never" in call
    ]
    version_indices = [
        index
        for index in runtime_indices
        if calls[index][-2:] == ["opencode", "--version"]
    ]
    if not inspect_indices:
        raise AssertionError(
            f"runtime-failure {detail} requires an image inspect call; actual calls: {calls!r}"
        )
    if detail == "missing-image":
        if runtime_indices:
            raise AssertionError(
                f"runtime checks must not follow missing-image failure; actual calls: {calls!r}"
            )
    elif detail == "metadata":
        metadata_indices = [
            index
            for index in runtime_indices
            if calls[index][-2:] == ["cat", "/usr/local/share/asdf-tool-versions"]
        ]
        if not metadata_indices:
            raise AssertionError(
                f"runtime-failure metadata requires a metadata command attempt; actual calls: {calls!r}"
            )
        if version_indices:
            raise AssertionError(
                f"metadata failure forbids an OpenCode version attempt; actual calls: {calls!r}"
            )
    elif not version_indices:
        raise AssertionError(
            f"runtime-failure {detail} requires an OpenCode version attempt; actual calls: {calls!r}"
        )


def check_builder_fallback(calls: list[list[str]], detail: str | None) -> None:
    allowed = {"builder-inspect", "builder-create"}
    if detail not in allowed:
        raise ValueError(
            f"builder-fallback requires one of {sorted(allowed)!r} as DETAIL"
        )
    create = [
        index
        for index, call in enumerate(calls)
        if call == ["buildx", "create", "--name", "builder"]
    ]
    if not create:
        raise AssertionError(
            f"builder fallback requires buildx create; actual calls: {calls!r}"
        )
    later_calls = calls[create[-1] + 1 :]
    later_v2_builds = [call for call in later_calls if is_v2_build(call)]
    if detail == "builder-inspect":
        if not later_v2_builds:
            raise AssertionError(
                f"builder-inspect fallback requires a subsequent v2 build; actual calls: {calls!r}"
            )
    else:
        any_builds = [call for call in calls if call[:2] == ["buildx", "build"]]
        any_inspects = [call for call in calls if call[:2] == ["image", "inspect"]]
        if any_builds or any_inspects:
            raise AssertionError(
                f"builder-create failure must have no builds or image inspection; actual calls: {calls!r}"
            )


def check_cleanup(calls: list[list[str]]) -> None:
    required = [
        ["buildx", "rm", "builder"],
        ["rmi", "ghcr.io/cwimmer/devcontainer:latest"],
        ["rmi", "ghcr.io/cwimmer/devcontainer:opencode"],
        ["rmi", "ghcr.io/cwimmer/devcontainer:opencode2"],
    ]
    missing = [call for call in required if call not in calls]
    if missing:
        raise AssertionError(
            f"cleanup must attempt builder and all three image removals; missing {missing!r}; actual calls: {calls!r}"
        )


def is_suite_call(arguments: list[str]) -> bool:
    if len(arguments) < 4 or arguments[0] != "run":
        return False
    try:
        image_index = arguments.index("ghcr.io/cwimmer/devcontainer:latest", 1)
    except ValueError:
        return False
    return arguments[image_index + 1 : image_index + 3] == [
        "bash",
        "/repo/tests/run-bats.sh",
    ]


def check_suite_failure(calls: list[list[str]]) -> None:
    expected_command = [
        "bash",
        "/repo/tests/run-bats.sh",
        "test-bats-support.bats",
        "test-gh-support.bats",
        "test-opencode-support.bats",
        "test-file-support.bats",
    ]
    suite_indices = [index for index, call in enumerate(calls) if is_suite_call(call)]
    if len(suite_indices) != 1:
        raise AssertionError(
            f"suite-failure requires exactly one suite invocation; actual calls: {calls!r}"
        )
    suite_index = suite_indices[0]
    suite_call = calls[suite_index]
    try:
        image_index = suite_call.index("ghcr.io/cwimmer/devcontainer:latest", 1)
    except ValueError:
        raise AssertionError(
            f"suite-failure requires the base image: {suite_call!r}"
        ) from None
    if suite_call[image_index + 1 :] != expected_command:
        raise AssertionError(
            f"suite-failure requires the complete unchanged BATS file list; actual command: {suite_call[image_index + 1 :]!r}"
        )
    later_builds = [
        call
        for call in calls[suite_index + 1 :]
        if call[:2] == ["buildx", "build"]
        and ("Dockerfile.OpenCode" in call or "Dockerfile.OpenCode2" in call)
    ]
    later_verification = [
        call for call in calls[suite_index + 1 :] if is_verifier_call(call)
    ]
    if later_builds or later_verification:
        raise AssertionError(
            "suite-failure forbids derived builds and image inspection/runtime verification after the suite; "
            f"builds: {later_builds!r}; verification: {later_verification!r}"
        )


def check_scenario(
    calls: list[list[str]], scenario: str, detail: str | None = None
) -> None:
    checks = {
        "v2-order": lambda: check_v2_order(calls),
        "build-failure": lambda: check_build_failure(calls, detail),
        "runtime-failure": lambda: check_runtime_failure(calls, detail),
        "builder-fallback": lambda: check_builder_fallback(calls, detail),
        "cleanup": lambda: check_cleanup(calls),
        "suite-failure": lambda: check_suite_failure(calls),
    }
    check = checks.get(scenario)
    if check is None:
        raise ValueError(
            f"unknown scenario {scenario!r}; expected one of {sorted(checks)!r}"
        )
    check()


def main(arguments: list[str]) -> int:
    if len(arguments) not in {2, 3}:
        raise ValueError(
            "usage: image_assertions.py LOG {calls|builds|verifier} EXPECTED_JSON | LOG SCENARIO [DETAIL]"
        )
    calls = load_calls(Path(arguments[0]))
    selection_or_scenario = arguments[1]
    if selection_or_scenario in {"calls", "builds", "verifier"}:
        if len(arguments) != 3:
            raise ValueError(
                f"{selection_or_scenario} selection expects one EXPECTED_JSON argument"
            )
        try:
            expected = json.loads(arguments[2])
        except json.JSONDecodeError as error:
            raise ValueError(f"invalid expected JSON: {error.msg}") from error
        check_calls(
            calls,
            expected,
            "all" if selection_or_scenario == "calls" else selection_or_scenario,
        )
    else:
        if len(arguments) == 3 and not arguments[2]:
            raise ValueError("scenario DETAIL must not be empty")
        check_scenario(
            calls, selection_or_scenario, arguments[2] if len(arguments) == 3 else None
        )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv[1:]))
    except (AssertionError, ValueError) as error:
        print(error, file=sys.stderr)
        raise SystemExit(1) from None
