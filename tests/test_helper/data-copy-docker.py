#!/usr/bin/env python3
"""Finite Docker CLI fixture for the standalone data-preparation command."""

from __future__ import annotations

import json
import os
import signal
import subprocess
import sys
import tempfile
from pathlib import Path

IMAGE_ID = "sha256:" + "a" * 64


def main(argv: list[str]) -> int:
    scenario = os.environ.get("DATA_COPY_SCENARIO", "success")
    log = Path(os.environ["DATA_COPY_LOG"])
    state_path = Path(os.environ["DATA_COPY_STATE"])
    state = json.loads(state_path.read_text(encoding="utf-8"))
    state["docker_context_env"] = os.environ.get("DOCKER_CONTEXT", "")
    state["docker_host_env"] = os.environ.get("DOCKER_HOST", "")
    context = state.get("docker_context") or "fixture-context"
    endpoint = state.get("context_endpoint") or "unix:///fixture/docker.sock"
    if state["docker_context_env"]:
        state["effective_endpoint"] = endpoint
        state["endpoint_source"] = "DOCKER_CONTEXT"
    elif state["docker_host_env"]:
        state["effective_endpoint"] = state["docker_host_env"]
        state["endpoint_source"] = "DOCKER_HOST"
    else:
        state["effective_endpoint"] = endpoint
        state["endpoint_source"] = "selected context"
    state_path.write_text(json.dumps(state), encoding="utf-8")
    with log.open("a", encoding="utf-8") as stream:
        stream.write(json.dumps(argv) + "\n")

    if argv == ["context", "show"]:
        if scenario == "context-failure":
            return fail("context unavailable")
        context = os.environ.get("DOCKER_CONTEXT") or "fixture-context"
        state["docker_context"] = context
        state_path.write_text(json.dumps(state), encoding="utf-8")
        print(context)
        return 0
    if argv[:2] == ["context", "inspect"] and len(argv) == 5:
        if scenario == "context-endpoint-failure":
            return fail("context endpoint unavailable")
        if argv[2] != "--format" or argv[3] != '{{ (index .Endpoints "docker").Host }}':
            return fail(f"unexpected context inspect arguments: {argv!r}")
        context = argv[4]
        expected_context = os.environ.get("DOCKER_CONTEXT") or "fixture-context"
        if context != expected_context:
            return fail(f"unexpected context name: {context}")
        endpoint = (
            "unix:///override/context.sock"
            if os.environ.get("DOCKER_CONTEXT")
            else "unix:///fixture/docker.sock"
        )
        state["context_endpoint"] = endpoint
        state["effective_endpoint"] = (
            endpoint
            if os.environ.get("DOCKER_CONTEXT")
            else os.environ.get("DOCKER_HOST") or endpoint
        )
        state["endpoint_source"] = (
            "DOCKER_CONTEXT"
            if os.environ.get("DOCKER_CONTEXT")
            else "DOCKER_HOST"
            if os.environ.get("DOCKER_HOST")
            else "selected context"
        )
        state_path.write_text(json.dumps(state), encoding="utf-8")
        print(endpoint)
        return 0
    if argv == ["info", "--format", "{{.Name}}"]:
        if scenario == "daemon-failure":
            return fail("daemon unavailable")
        print("fixture-daemon")
        return 0
    if argv == ["--version"]:
        return 0
    if argv == ["volume", "ls", "--format", "{{.Name}}"]:
        if scenario == "list-failure":
            return fail("volume listing unavailable")
        if (
            scenario in {"existing-destination", "existing-destination-empty"}
            or state["created"]
        ):
            print("other-repo-v2")
        print("other-repo-v1")
        return 0
    if argv[:2] == ["volume", "inspect"] and len(argv) == 3:
        if scenario == "missing-source" and argv[2] == "other-repo-v1":
            return fail("source does not exist")
        if scenario == "source-inspect-failure" and argv[2] == "other-repo-v1":
            return fail("source inspection failed")
        return 0
    if argv[:2] == ["ps", "--filter"] and len(argv) == 5:
        if scenario == "consumer-failure":
            return fail("consumer query failed")
        volume = argv[2].split("=", 1)[1]
        if scenario == "running-source" and volume == "other-repo-v1":
            print("fixture-writer")
        elif scenario == "running-destination" and volume == "other-repo-v2":
            print("fixture-writer")
        elif (
            scenario == "consumer-race"
            and volume == "other-repo-v2"
            and state["created"]
        ):
            print("fixture-writer")
        return 0
    if argv[:3] == ["image", "inspect", "--format"]:
        if scenario == "image-failure":
            return fail("image not present locally")
        print(IMAGE_ID)
        return 0
    if argv[:2] == ["volume", "create"] and len(argv) == 3:
        if scenario == "create-failure":
            state["created"] = True
            state_path.write_text(json.dumps(state), encoding="utf-8")
            return fail("volume create failed after request")
        state["created"] = True
        state_path.write_text(json.dumps(state), encoding="utf-8")
        return 0
    if argv and argv[0] == "run":
        command = "\0".join(argv)
        if "DATA_COPY_PREFLIGHT" in command:
            if scenario == "preflight-failure":
                return fail("required helper tools unavailable")
            return 0
        if "DATA_COPY_TRANSFER" in command:
            if scenario == "destination-race":
                state.update(simulate_populated_destination(argv))
                state_path.write_text(json.dumps(state), encoding="utf-8")
                if state["empty_guard_rejected_populated_destination"]:
                    print("destination must be empty", file=sys.stderr)
                    return 1
                return fail("helper did not reject populated destination")
            if scenario == "copy-failure":
                return fail("copy failed")
            if scenario == "compare-failure":
                return fail("comparison failed")
            if scenario == "interrupt":
                os.kill(os.getppid(), signal.SIGTERM)
                return 0
            state["copy_executed"] = True
            state_path.write_text(json.dumps(state), encoding="utf-8")
            return 0
    return fail(f"unknown Docker call: {argv!r}")


def simulate_populated_destination(argv: list[str]) -> dict[str, bool]:
    """Run the helper shell against temporary fake mounts, without Docker."""
    try:
        helper_script = argv[argv.index("-c") + 1]
    except (ValueError, IndexError) as error:
        raise ValueError(f"transfer helper has no shell program: {argv!r}") from error

    with tempfile.TemporaryDirectory(prefix="data-copy-simulated-mounts-") as temporary:
        root = Path(temporary)
        source = root / "source"
        destination = root / "destination"
        fake_bin = root / "bin"
        source.mkdir()
        destination.mkdir()
        fake_bin.mkdir()
        (source / "source fixture").write_text("source", encoding="utf-8")
        (destination / "concurrent writer sentinel").write_text(
            "must be retained", encoding="utf-8"
        )

        copy_marker = root / "cp was reached"
        cp_stub = fake_bin / "cp"
        cp_stub.write_text(
            '#!/bin/sh\nprintf reached > "$COPY_MARKER"\nexit 0\n',
            encoding="utf-8",
        )
        cp_stub.chmod(0o755)

        simulated_script = helper_script.replace("/source", str(source)).replace(
            "/destination", str(destination)
        )
        result = subprocess.run(
            ["/bin/sh", "-c", simulated_script, "DATA_COPY_TRANSFER"],
            capture_output=True,
            text=True,
            check=False,
            env={
                **os.environ,
                "PATH": str(fake_bin) + os.pathsep + os.environ.get("PATH", ""),
                "COPY_MARKER": str(copy_marker),
            },
        )
        return {
            "destination_populated_at_mount": True,
            "empty_guard_rejected_populated_destination": (
                result.returncode != 0 and "destination must be empty" in result.stderr
            ),
            "copy_executed": copy_marker.exists(),
        }


def fail(message: str) -> int:
    print(message, file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
