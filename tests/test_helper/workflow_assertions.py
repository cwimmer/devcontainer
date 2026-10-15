#!/usr/bin/env python3
"""Semantic contracts for the image-build GitHub Actions workflow."""

from __future__ import annotations

import re
import shlex
import sys
from pathlib import Path

try:
    import yaml
except (
    ImportError
) as error:  # pragma: no cover - exercised in an unprovisioned environment
    raise SystemExit(
        "workflow assertions require PyYAML; provision test dependencies with "
        "python3 -m pip install --target /tmp/opencode/opencode-refactor-deps -r tests/requirements.txt"
    ) from error


EXPECTED_V2_TAG = "ghcr.io/cwimmer/devcontainer:opencode2"
EXPECTED_V1_TAG = "ghcr.io/cwimmer/devcontainer:opencode"
EXPECTED_BASE_TAG = "ghcr.io/cwimmer/devcontainer:latest"
EXPECTED_PUSH = "${{ github.ref == 'refs/heads/main' }}"
VERIFY_FIELD = "jobs.build.steps[verify_opencode2].run"
VERIFY_ARGV = ["sh", "scripts/verify-opencode2.sh", EXPECTED_V2_TAG]


class _WorkflowLoader(yaml.SafeLoader):
    """Safe YAML loader that recognizes only YAML 1.2 true/false booleans."""


_WorkflowLoader.yaml_implicit_resolvers = {
    key: list(resolvers)
    for key, resolvers in yaml.SafeLoader.yaml_implicit_resolvers.items()
}
for _key, _resolvers in tuple(_WorkflowLoader.yaml_implicit_resolvers.items()):
    _WorkflowLoader.yaml_implicit_resolvers[_key] = [
        (_tag, _regexp)
        for _tag, _regexp in _resolvers
        if _tag != "tag:yaml.org,2002:bool"
    ]
_WorkflowLoader.add_implicit_resolver(
    "tag:yaml.org,2002:bool",
    re.compile(r"^(?:true|false)$", re.IGNORECASE),
    list("tTfF"),
)


def load_workflow(path: Path) -> dict:
    """Load workflow YAML without changing PyYAML's global YAML 1.1 behavior."""
    try:
        with path.open(encoding="utf-8") as source:
            workflow = yaml.load(source, Loader=_WorkflowLoader)
    except (OSError, yaml.YAMLError) as error:
        raise ValueError(f"{path}: cannot load workflow YAML: {error}") from error
    if not isinstance(workflow, dict):
        raise ValueError(f"{path}: workflow root must be a mapping")
    return workflow


def normalize_boolean(value: object, field: str) -> bool:
    """Normalize actual booleans and explicit true/false strings only."""
    if isinstance(value, bool):
        return value
    if isinstance(value, str):
        normalized = value.strip().casefold()
        if normalized == "true":
            return True
        if normalized == "false":
            return False
    raise ValueError(f"{field}: expected literal boolean true or false, got {value!r}")


def verifier_argv(command: str, field: str) -> list[str]:
    """Validate the narrow verifier command form, then lex and compare argv."""
    if not isinstance(command, str):
        raise ValueError(f"{field}: command form must be a string")

    logical_parts: list[str] = []
    current: list[str] = []
    quote: str | None = None
    escaped = False
    index = 0
    while index < len(command):
        character = command[index]
        if character == "\n":
            if escaped and quote != "'":
                current.pop()  # remove the joining backslash
                escaped = False
                index += 1
                continue
            if quote is not None:
                raise ValueError(
                    f"{field}: command form has a newline inside a quoted argument"
                )
            logical_parts.append("".join(current))
            current = []
            escaped = False
            index += 1
            continue

        if quote is None:
            if escaped:
                current.append(character)
                escaped = False
            elif character in "'\"":
                quote = character
                current.append(character)
            elif character in ";|&<>`":
                raise ValueError(
                    f"{field}: command form contains unsupported shell operator {character!r}"
                )
            elif character == "$":
                raise ValueError(
                    f"{field}: command form contains unsupported shell substitution"
                )
            elif character == "\\":
                current.append(character)
                escaped = True
            else:
                current.append(character)
                escaped = False
        elif quote == "'":
            current.append(character)
            if character == "'":
                quote = None
        else:
            if character == "$" or character == "`":
                raise ValueError(
                    f"{field}: command form contains unsupported shell substitution"
                )
            current.append(character)
            if escaped:
                escaped = False
            elif character == "\\":
                escaped = True
            elif character == '"':
                quote = None
        index += 1

    if quote is not None:
        raise ValueError(f"{field}: command form has an unterminated quote")
    logical_parts.append("".join(current))
    nonblank = [part.strip() for part in logical_parts if part.strip()]
    if len(nonblank) != 1:
        raise ValueError(
            f"{field}: command form must contain exactly one nonblank logical command"
        )
    try:
        arguments = shlex.split(nonblank[0], posix=True)
    except ValueError as error:
        raise ValueError(f"{field}: command form cannot be lexed: {error}") from error
    if arguments != VERIFY_ARGV:
        raise ValueError(
            f"{field}: command argument vector mismatch; expected {VERIFY_ARGV!r}, got {arguments!r}"
        )
    return arguments


def _mapping(value: object, field: str) -> dict:
    if not isinstance(value, dict):
        raise ValueError(f"{field}: expected a mapping")
    return value


def _sequence(value: object, field: str) -> list:
    if not isinstance(value, list):
        raise ValueError(f"{field}: expected a list")
    return value


def _split_values(value: object, field: str) -> list[str]:
    if not isinstance(value, str):
        raise ValueError(f"{field}: expected a string list")
    values = [item.strip() for item in re.split(r"[,\n]", value) if item.strip()]
    if not values:
        raise ValueError(f"{field}: expected at least one value")
    return values


def _field(mapping: dict, key: str, field: str) -> object:
    if key not in mapping:
        raise ValueError(f"{field}.{key}: required field is missing")
    return mapping[key]


def _steps(workflow: dict) -> tuple[dict, list, dict[str, dict]]:
    jobs = _mapping(_field(workflow, "jobs", "workflow"), "jobs")
    build = _mapping(_field(jobs, "build", "jobs"), "jobs.build")
    steps = _sequence(_field(build, "steps", "jobs.build"), "jobs.build.steps")
    by_id: dict[str, dict] = {}
    for index, raw_step in enumerate(steps):
        step = _mapping(raw_step, f"jobs.build.steps[{index}]")
        step_id = step.get("id")
        if step_id in {
            "build_opencode2_native",
            "verify_opencode2",
            "publish_opencode2",
        }:
            if step_id in by_id:
                raise ValueError(
                    f"jobs.build.steps[{step_id}].id: duplicate relevant step id"
                )
            by_id[step_id] = step
    return build, steps, by_id


def _check_failure_gates(build: dict, selected: list[tuple[str, dict]]) -> None:
    for field, step in selected:
        if "continue-on-error" in step and normalize_boolean(
            step["continue-on-error"], f"{field}.continue-on-error"
        ):
            raise ValueError(f"{field}.continue-on-error: must be absent or false")
        if "if" in step:
            _check_condition(step["if"], f"{field}.if")
    if "continue-on-error" in build and normalize_boolean(
        build["continue-on-error"], "jobs.build.continue-on-error"
    ):
        raise ValueError("jobs.build.continue-on-error: must be absent or false")
    if "if" in build:
        _check_condition(build["if"], "jobs.build.if")


def _check_condition(value: object, field: str) -> None:
    if not isinstance(value, str):
        raise ValueError(
            f"{field}: unsupported condition; expected success() or no condition"
        )
    condition = value.strip()
    if condition.startswith("${{") and condition.endswith("}}"):
        condition = condition[3:-2].strip()
    if condition != "success()":
        raise ValueError(
            f"{field}: unsupported condition {value!r}; only success() is supported"
        )


def _check_action(step: dict, field: str) -> dict:
    if step.get("uses") != "docker/build-push-action@v7":
        raise ValueError(f"{field}.uses: expected docker/build-push-action@v7")
    return _mapping(_field(step, "with", field), f"{field}.with")


def _check_build_fields(
    step: dict,
    field: str,
    *,
    dockerfile: str,
    tags: list[str],
    platforms: list[str],
    push: bool | str | None,
    pull: bool | None,
    load: bool | None,
) -> None:
    values = _check_action(step, field)
    if values.get("context") != ".":
        raise ValueError(
            f"{field}.with.context: expected '.', got {values.get('context')!r}"
        )
    if dockerfile == "Dockerfile":
        if values.get("file", "Dockerfile") != "Dockerfile":
            raise ValueError(
                f"{field}.with.file: expected Dockerfile or omitted default, got {values.get('file')!r}"
            )
    elif values.get("file") != dockerfile:
        raise ValueError(
            f"{field}.with.file: expected {dockerfile!r}, got {values.get('file')!r}"
        )
    actual_tags = _split_values(
        _field(values, "tags", f"{field}.with"), f"{field}.with.tags"
    )
    if actual_tags != tags:
        raise ValueError(f"{field}.with.tags: expected {tags!r}, got {actual_tags!r}")
    actual_platforms = _split_values(
        _field(values, "platforms", f"{field}.with"), f"{field}.with.platforms"
    )
    if actual_platforms != platforms:
        raise ValueError(
            f"{field}.with.platforms: expected {platforms!r}, got {actual_platforms!r}"
        )
    for key, expected in (("push", push), ("pull", pull), ("load", load)):
        if expected is None:
            continue
        if key not in values:
            if expected is False:
                continue
            raise ValueError(f"{field}.with.{key}: required field is missing")
        if isinstance(expected, str):
            if values[key] != expected:
                raise ValueError(
                    f"{field}.with.{key}: expected exact expression {expected!r}"
                )
            continue
        actual = normalize_boolean(values[key], f"{field}.with.{key}")
        if actual != expected:
            raise ValueError(f"{field}.with.{key}: expected {expected}, got {actual}")


def check_v2_workflow(workflow: dict) -> None:
    """Check native build, verification, and conditional publication contracts."""
    build, steps, by_id = _steps(workflow)
    required = ("build_opencode2_native", "verify_opencode2", "publish_opencode2")
    missing = [step_id for step_id in required if step_id not in by_id]
    if missing:
        raise ValueError(f"jobs.build.steps: missing required v2 step IDs {missing!r}")
    positions = [
        next(index for index, step in enumerate(steps) if step.get("id") == step_id)
        for step_id in required
    ]
    if positions != sorted(positions):
        raise ValueError(
            "jobs.build.steps: v2 build, verify, and publication IDs must be in order"
        )

    native = by_id["build_opencode2_native"]
    native_field = "jobs.build.steps[build_opencode2_native]"
    _check_build_fields(
        native,
        native_field,
        dockerfile="Dockerfile.OpenCode2",
        tags=[EXPECTED_V2_TAG],
        platforms=["linux/amd64"],
        push=False,
        pull=True,
        load=True,
    )
    if native.get("timeout-minutes") != 30:
        raise ValueError(f"{native_field}.timeout-minutes: expected 30")

    verify = by_id["verify_opencode2"]
    verify_field = "jobs.build.steps[verify_opencode2]"
    verifier_argv(_field(verify, "run", verify_field), VERIFY_FIELD)
    if verify.get("timeout-minutes") != 20:
        raise ValueError(f"{verify_field}.timeout-minutes: expected 20")

    publish = by_id["publish_opencode2"]
    publish_field = "jobs.build.steps[publish_opencode2]"
    _check_build_fields(
        publish,
        publish_field,
        dockerfile="Dockerfile.OpenCode2",
        tags=[EXPECTED_V2_TAG],
        platforms=["linux/amd64", "linux/arm64"],
        push=EXPECTED_PUSH,
        pull=True,
        load=None,
    )
    _check_failure_gates(
        build,
        [(f"jobs.build.steps[{step_id}]", by_id[step_id]) for step_id in required],
    )


def _named_build_steps(steps: list, lane: str) -> dict[str, dict]:
    selected: dict[str, dict] = {}
    for index, raw_step in enumerate(steps):
        step = _mapping(raw_step, f"jobs.build.steps[{index}]")
        if step.get("uses") != "docker/build-push-action@v7":
            continue
        name = step.get("name")
        if name in selected:
            raise ValueError(f"jobs.build.steps[{name}]: duplicate build lane")
        selected[name] = step
    for name in lane:
        if name not in selected:
            raise ValueError(
                f"jobs.build.steps[{name}]: required build lane is missing"
            )
    return selected


def check_existing_lanes(workflow: dict) -> None:
    """Ensure base/v1 publication semantics and workflow triggers are retained."""
    build, steps, _ = _steps(workflow)
    lanes = _named_build_steps(
        steps,
        (
            "Build and push base multi-architecture image",
            "Build and push OpenCode multi-architecture image",
        ),
    )
    base_name = "Build and push base multi-architecture image"
    v1_name = "Build and push OpenCode multi-architecture image"
    _check_build_fields(
        lanes[base_name],
        f"jobs.build.steps[{base_name}]",
        dockerfile="Dockerfile",
        tags=[EXPECTED_BASE_TAG],
        platforms=["linux/amd64", "linux/arm64"],
        push=EXPECTED_PUSH,
        pull=None,
        load=None,
    )
    _check_build_fields(
        lanes[v1_name],
        f"jobs.build.steps[{v1_name}]",
        dockerfile="Dockerfile.OpenCode",
        tags=[EXPECTED_V1_TAG],
        platforms=["linux/amd64", "linux/arm64"],
        push=EXPECTED_PUSH,
        pull=None,
        load=None,
    )
    triggers = _mapping(_field(workflow, "on", "workflow"), "on")
    for trigger in ("push", "pull_request", "workflow_dispatch"):
        if trigger not in triggers:
            raise ValueError(f"on.{trigger}: required workflow trigger is missing")
    for trigger in ("push", "pull_request"):
        config = _mapping(triggers[trigger], f"on.{trigger}")
        branches = _sequence(
            _field(config, "branches", f"on.{trigger}"), f"on.{trigger}.branches"
        )
        if "main" not in branches:
            raise ValueError(
                f"on.{trigger}.branches: expected 'main' to be included, got {branches!r}"
            )

    selected_gates = [
        (f"jobs.build.steps[{step.get('id', step.get('name', index))}]", step)
        for index, step in enumerate(steps)
        if step.get("id")
        in {"build_opencode2_native", "verify_opencode2", "publish_opencode2"}
        or step.get("name") in {base_name, v1_name}
    ]
    _check_failure_gates(build, selected_gates)


def main(arguments: list[str]) -> int:
    if len(arguments) != 2 or arguments[1] not in {"v2", "existing"}:
        raise ValueError("usage: workflow_assertions.py PATH {v2|existing}")
    workflow = load_workflow(Path(arguments[0]))
    (check_v2_workflow if arguments[1] == "v2" else check_existing_lanes)(workflow)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv[1:]))
    except (AssertionError, ValueError) as error:
        print(error, file=sys.stderr)
        raise SystemExit(1) from None
