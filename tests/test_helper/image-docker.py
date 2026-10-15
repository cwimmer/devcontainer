#!/usr/bin/env python3
"""Docker stub for the v2 verifier and Make integration tests."""

import json
import os
import pathlib
import re
import sys


args = sys.argv[1:]
with pathlib.Path(os.environ["IMAGE_LOG"]).open("a", encoding="utf-8") as log:
    log.write(json.dumps(args) + "\n")


def fail(message: str) -> None:
    print(message, file=sys.stderr)
    raise SystemExit(1)


failure = os.environ.get("IMAGE_FAIL", "")

if args == ["buildx", "inspect", "builder"]:
    if failure in {"builder-inspect", "builder-create"}:
        fail("stubbed builder inspection failure")
    raise SystemExit(0)

if args == ["buildx", "create", "--name", "builder"]:
    if failure == "builder-create":
        fail("stubbed builder creation failure")
    raise SystemExit(0)

if args == ["buildx", "use", "builder"] or args == ["buildx", "inspect", "--bootstrap"]:
    raise SystemExit(0)

if len(args) >= 3 and args[:2] == ["buildx", "build"]:
    if "-f" in args:
        dockerfile = args[args.index("-f") + 1]
    else:
        dockerfile = "Dockerfile"
    tag = args[args.index("--tag") + 1] if "--tag" in args else ""
    platform = args[args.index("--platform") + 1] if "--platform" in args else ""
    if dockerfile == "Dockerfile.OpenCode2":
        operation = "v2-multi-build" if platform == "linux/amd64,linux/arm64" else "v2-native-build"
    elif dockerfile == "Dockerfile.OpenCode":
        operation = "v1-build"
    elif dockerfile == "Dockerfile":
        operation = "base-build"
    else:
        fail(f"unknown build Dockerfile: {dockerfile!r}")
    if failure == operation or (operation == "base-build" and failure == "base-build"):
        fail(f"stubbed {operation} failure")
    raise SystemExit(0)

if args[:3] == ["image", "inspect", "--format"]:
    if failure in {"inspect", "missing-image"}:
        fail("stubbed missing local image" if failure == "missing-image" else "stubbed image inspect failure")
    print(os.environ.get("IMAGE_ID", "sha256:" + "a" * 64))
    raise SystemExit(0)

if len(args) >= 5 and args[:3] == ["run", "--rm", "--pull=never"]:
    command = args[4:]
    if command == ["cat", "/usr/local/share/asdf-tool-versions"]:
        if failure == "metadata":
            fail("stubbed metadata failure")
        raise SystemExit(0)
    if command == ["opencode", "--version"]:
        if failure == "version":
            if "IMAGE_VERSION_OUTPUT" in os.environ:
                print(os.environ["IMAGE_VERSION_OUTPUT"])
            fail("stubbed version failure")
        if "IMAGE_VERSION_OUTPUT" in os.environ:
            output = os.environ["IMAGE_VERSION_OUTPUT"]
        else:
            dockerfile = pathlib.Path(os.environ["IMAGE_REPO"]) / "Dockerfile.OpenCode2"
            contents = dockerfile.read_text(encoding="utf-8")
            pins = re.findall(r"^ARG OPENCODE_VERSION=(.*)$", contents, re.MULTILINE)
            output = f"OpenCode v{pins[0]}" if len(pins) == 1 else ""
        if output:
            print(output)
        raise SystemExit(int(os.environ.get("IMAGE_VERSION_STATUS", "0")))

if args[:2] == ["run", "--rm"]:
    # The Makefile's base/v1 smoke-test commands are simulated locally; never
    # invoke BATS recursively from this stub.
    if "bats" in args:
        raise SystemExit(int(os.environ.get("IMAGE_BATS_STATUS", "0")))
    if len(args) >= 5 and args[3:] == ["cat", "/usr/local/share/asdf-tool-versions"]:
        raise SystemExit(0)
    if len(args) >= 6 and args[3:5] == ["sh", "-lc"]:
        raise SystemExit(0)
    if len(args) >= 5 and args[3:] == ["gh", "--version"]:
        raise SystemExit(0)
    if len(args) >= 5 and args[3:] == ["opencode", "--version"]:
        raise SystemExit(0)
    fail(f"unknown stub Docker run command: {args!r}")

if args[:1] == ["rmi"]:
    if failure == "remove" and args[-1].endswith(":latest"):
        fail("stubbed image removal failure")
    raise SystemExit(0)

if args == ["buildx", "rm", "builder"]:
    if failure == "remove-builder":
        fail("stubbed builder removal failure")
    raise SystemExit(0)

fail(f"unknown stub Docker command: {args!r}")
