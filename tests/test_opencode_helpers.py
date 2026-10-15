#!/usr/bin/env python3
"""Regression tests for the standalone test helpers."""

from __future__ import annotations

import copy
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent / "test_helper"))
from workflow_assertions import (  # noqa: E402
    check_existing_lanes,
    check_v2_workflow,
    load_workflow,
    verifier_argv,
)

ROOT = Path(__file__).resolve().parent
IMAGE_ASSERTIONS = ROOT / "test_helper" / "image_assertions.py"
IMAGE_DOCKER = ROOT / "test_helper" / "image-docker.py"


class ImageAssertionsTests(unittest.TestCase):
    def write_calls(self, directory: Path, calls: list[list[str]]) -> Path:
        path = directory / "docker calls.jsonl"
        path.write_text(
            "".join(json.dumps(call) + "\n" for call in calls), encoding="utf-8"
        )
        return path

    def invoke(
        self, path: Path, *arguments: str, optimized: bool = False
    ) -> subprocess.CompletedProcess[str]:
        command = [sys.executable]
        if optimized:
            command.append("-O")
        command.extend([str(IMAGE_ASSERTIONS), str(path), *arguments])
        return subprocess.run(command, capture_output=True, text=True, check=False)

    def test_exact_build_comparison_rejects_wrong_tag_and_platform(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            path = self.write_calls(
                Path(temporary),
                [
                    [
                        "buildx",
                        "build",
                        "-f",
                        "Dockerfile.OpenCode2",
                        "--tag",
                        "image:wrong",
                        "--platform",
                        "linux/arm64",
                    ]
                ],
            )
            expected = json.dumps(
                [
                    [
                        "Dockerfile.OpenCode2",
                        "image:expected",
                        "linux/amd64",
                        False,
                        False,
                    ]
                ]
            )
            result = self.invoke(path, "builds", expected)

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("expected", result.stderr)
        self.assertIn("actual", result.stderr)


class RunnerTests(unittest.TestCase):
    runner_path = ROOT / "run-bats.sh"

    def make_stub(self, directory: Path, name: str, source: str) -> Path:
        path = directory / name
        path.write_text(source, encoding="utf-8")
        path.chmod(0o755)
        return path

    def read_events(self, path: Path) -> list[list[str]]:
        fields = path.read_bytes().decode().split("\0")
        events: list[list[str]] = []
        event: list[str] = []
        for field in fields:
            if field == "__END__":
                events.append(event)
                event = []
            elif field:
                event.append(field)
        return events

    def test_runner_orders_provision_lint_format_and_bats_and_cleans_tempfiles(
        self,
    ) -> None:
        self.assert_runner_lifecycle()

    def test_runner_stops_at_each_failure_and_preserves_status_and_cleanup(
        self,
    ) -> None:
        for stage in ("pip", "lint", "format", "bats"):
            with self.subTest(stage=stage):
                self.assert_runner_lifecycle(failure=stage)

    def assert_runner_lifecycle(self, failure: str | None = None) -> None:
        with tempfile.TemporaryDirectory(prefix="runner fixture ") as temporary:
            root = Path(temporary)
            bin_dir = root / "stub bin"
            bin_dir.mkdir()
            workdir = root / "caller working directory"
            workdir.mkdir()
            tempdir = root / "temporary files"
            tempdir.mkdir()
            runner_root = root / "repository path with spaces"
            runner_root.symlink_to(ROOT.parent, target_is_directory=True)
            runner_path = runner_root / "tests" / "run-bats.sh"
            log = root / "runner events"
            python_stub = """#!/bin/sh
printf 'python3\\0%s\\0%s\\0%s\\0' "$PWD" "$TMPDIR" "$PYTHONPATH" >> "$RUNNER_LOG"
printf '%s\\0' "$@" >> "$RUNNER_LOG"
printf '__END__\\0' >> "$RUNNER_LOG"
stage=lint
if [ "$2" = pip ]; then stage=pip; elif [ "$3" = format ]; then stage=format; fi
if [ "${RUNNER_FAIL:-}" = "$stage" ]; then
    case "$stage" in pip) exit 31 ;; lint) exit 32 ;; format) exit 33 ;; esac
fi
            """
            bats_stub = """#!/bin/sh
printf 'bats\\0%s\\0%s\\0%s\\0' "$PWD" "$TMPDIR" "$PYTHONPATH" >> "$RUNNER_LOG"
printf '%s\\0' "$@" >> "$RUNNER_LOG"
printf '__END__\\0' >> "$RUNNER_LOG"
if [ "${RUNNER_FAIL:-}" = bats ]; then exit 34; fi
"""
            self.make_stub(bin_dir, "python3", python_stub)
            self.make_stub(bin_dir, "bats", bats_stub)
            inherited_pythonpath = str(root / "existing Python path")
            environment = {
                **__import__("os").environ,
                "PATH": str(bin_dir) + os.pathsep + os.environ["PATH"],
                "TMPDIR": str(tempdir),
                "RUNNER_LOG": str(log),
                "RUNNER_FAIL": failure or "",
                "PYTHONPATH": inherited_pythonpath,
            }
            bats_arguments = ["test suite.bats", "--filter", "case name with spaces"]
            result = subprocess.run(
                ["bash", str(runner_path), *bats_arguments],
                cwd=workdir,
                env=environment,
                capture_output=True,
                text=True,
                check=False,
            )

            status_by_stage = {"pip": 31, "lint": 32, "format": 33, "bats": 34}
            expected_status = status_by_stage.get(failure, 0)
            self.assertEqual(result.returncode, expected_status, result.stderr)
            expected_stages = ["pip", "lint", "format", "bats"]
            if failure:
                expected_stages = expected_stages[: expected_stages.index(failure) + 1]
            events = self.read_events(log) if log.exists() else []
            self.assertEqual(
                [event[0] for event in events],
                ["python3"] * (len(expected_stages) - ("bats" in expected_stages))
                + (["bats"] if "bats" in expected_stages else []),
            )
            self.assertEqual(list(tempdir.iterdir()), [])

            deps_path = None
            for event, stage in zip(events, expected_stages, strict=False):
                self.assertEqual(event[1], str(workdir))
                self.assertEqual(event[2], str(tempdir))
                if stage == "pip":
                    self.assertEqual(event[3], inherited_pythonpath)
                else:
                    self.assertTrue(
                        event[3].startswith(str(tempdir) + os.path.sep), repr(event)
                    )
                    self.assertTrue(
                        event[3].endswith(inherited_pythonpath), repr(event)
                    )
                command = event[4:]
                if stage == "pip":
                    deps_path = command[4]
                    self.assertEqual(
                        command,
                        [
                            "-m",
                            "pip",
                            "install",
                            "--target",
                            command[4],
                            "-r",
                            str(runner_root / "tests" / "requirements.txt"),
                        ],
                    )
                    self.assertTrue(deps_path.startswith(str(tempdir) + os.path.sep))
                elif stage in {"lint", "format"}:
                    self.assertIsNotNone(deps_path)
                    self.assertEqual(
                        event[3], f"{deps_path}{os.pathsep}{inherited_pythonpath}"
                    )
                    self.assertEqual(
                        command,
                        [
                            "-m",
                            "ruff",
                            "check" if stage == "lint" else "format",
                            *(["--check"] if stage == "format" else []),
                            str(runner_root / "tests" / "test_helper"),
                            str(runner_root / "tests" / "test_opencode_helpers.py"),
                        ],
                    )
                else:
                    self.assertEqual(
                        event[3], f"{deps_path}{os.pathsep}{inherited_pythonpath}"
                    )
                    self.assertEqual(event[4:], bats_arguments)


class WorkflowAssertionsTests(unittest.TestCase):
    workflow_path = ROOT.parent / ".github" / "workflows" / "image-build.yaml"

    def setUp(self) -> None:
        self.workflow = load_workflow(self.workflow_path)

    def invoke(self, path: Path, contract: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [
                sys.executable,
                str(ROOT / "test_helper" / "workflow_assertions.py"),
                str(path),
                contract,
            ],
            capture_output=True,
            text=True,
            check=False,
        )

    def test_current_workflow_satisfies_both_contracts(self) -> None:
        check_v2_workflow(self.workflow)
        check_existing_lanes(self.workflow)

    def test_existing_lane_contract_rejects_legacy_behavior_mutations(self) -> None:
        base_name = "Build and push base multi-architecture image"
        v1_name = "Build and push OpenCode multi-architecture image"
        mutations = (
            (
                "base tag",
                lambda workflow: self.named_step(workflow, base_name)["with"].update(
                    tags="ghcr.io/cwimmer/devcontainer:wrong"
                ),
                "base multi-architecture image.*with\\.tags",
            ),
            (
                "v1 tag",
                lambda workflow: self.named_step(workflow, v1_name)["with"].update(
                    tags="ghcr.io/cwimmer/devcontainer:wrong"
                ),
                "OpenCode multi-architecture image.*with\\.tags",
            ),
            (
                "base platforms",
                lambda workflow: self.named_step(workflow, base_name)["with"].update(
                    platforms="linux/amd64"
                ),
                "base multi-architecture image.*with\\.platforms",
            ),
            (
                "v1 platforms",
                lambda workflow: self.named_step(workflow, v1_name)["with"].update(
                    platforms="linux/amd64"
                ),
                "OpenCode multi-architecture image.*with\\.platforms",
            ),
            (
                "base publication expression",
                lambda workflow: self.named_step(workflow, base_name)["with"].update(
                    push="${{ github.ref == 'refs/heads/release' }}"
                ),
                "base multi-architecture image.*with\\.push",
            ),
            (
                "v1 publication expression",
                lambda workflow: self.named_step(workflow, v1_name)["with"].update(
                    push="${{ github.ref == 'refs/heads/release' }}"
                ),
                "OpenCode multi-architecture image.*with\\.push",
            ),
            (
                "push trigger branches",
                lambda workflow: workflow["on"]["push"].update(branches=["release"]),
                "on\\.push\\.branches",
            ),
            (
                "pull request trigger branches",
                lambda workflow: workflow["on"]["pull_request"].update(
                    branches=["release"]
                ),
                "on\\.pull_request\\.branches",
            ),
            (
                "manual trigger",
                lambda workflow: workflow["on"].pop("workflow_dispatch"),
                "on\\.workflow_dispatch",
            ),
        )
        for label, mutate, expected_field in mutations:
            with self.subTest(contract=label):
                workflow = copy.deepcopy(self.workflow)
                mutate(workflow)
                self.assert_contract_error(workflow, "existing", expected_field)

    def test_existing_lane_contract_accepts_main_with_additional_branches(self) -> None:
        workflow = copy.deepcopy(self.workflow)
        for trigger in ("push", "pull_request"):
            workflow["on"][trigger]["branches"] = ["main", "release"]

        check_existing_lanes(workflow)

    def test_existing_lane_contract_retains_branch_list_type_validation(self) -> None:
        for trigger in ("push", "pull_request"):
            with self.subTest(trigger=trigger):
                workflow = copy.deepcopy(self.workflow)
                workflow["on"][trigger]["branches"] = "main"
                self.assert_contract_error(
                    workflow, "existing", rf"on\.{trigger}\.branches: expected a list"
                )

    def named_step(self, workflow: dict, name: str) -> dict:
        return next(
            step
            for step in workflow["jobs"]["build"]["steps"]
            if step.get("name") == name
        )

    def test_wrong_tags_platforms_order_and_push_are_rejected_with_paths(self) -> None:
        mutations = (
            (
                "build_opencode2_native",
                "tags",
                "ghcr.io/cwimmer/devcontainer:wrong",
                "tags",
            ),
            ("build_opencode2_native", "platforms", "linux/arm64", "platforms"),
            (
                "publish_opencode2",
                "push",
                "${{ github.ref == 'refs/heads/release' }}",
                "push",
            ),
        )
        for step_id, field, value, expected in mutations:
            with self.subTest(step=step_id, field=field):
                workflow = copy.deepcopy(self.workflow)
                step = self.step_by_id(workflow, step_id)
                step["with"][field] = value
                self.assert_contract_error(workflow, "v2", expected)

        workflow = copy.deepcopy(self.workflow)
        verify = self.step_by_id(workflow, "verify_opencode2")
        workflow["jobs"]["build"]["steps"].remove(verify)
        self.assert_contract_error(workflow, "v2", "verify_opencode2")

        workflow = copy.deepcopy(self.workflow)
        steps = workflow["jobs"]["build"]["steps"]
        native_index = steps.index(self.step_by_id(workflow, "build_opencode2_native"))
        verify_index = steps.index(self.step_by_id(workflow, "verify_opencode2"))
        steps[native_index], steps[verify_index] = (
            steps[verify_index],
            steps[native_index],
        )
        self.assert_contract_error(workflow, "v2", "order")

    def test_failure_bypasses_and_unsupported_conditions_are_rejected(self) -> None:
        for value in (True, "${{ github.event_name == 'push' }}"):
            workflow = copy.deepcopy(self.workflow)
            self.step_by_id(workflow, "verify_opencode2")["continue-on-error"] = value
            self.assert_contract_error(workflow, "v2", "continue-on-error")

        for value in (
            "always()",
            "${{ failure() }}",
            "github.ref == 'refs/heads/main'",
        ):
            workflow = copy.deepcopy(self.workflow)
            self.step_by_id(workflow, "verify_opencode2")["if"] = value
            self.assert_contract_error(workflow, "v2", "if")

        workflow = copy.deepcopy(self.workflow)
        workflow["jobs"]["build"]["if"] = "always()"
        self.assert_contract_error(workflow, "v2", "jobs.build.if")

    def test_yaml_formatting_and_scalar_forms_are_semantically_equivalent(self) -> None:
        original = self.workflow_path.read_text(encoding="utf-8")
        variants = (
            original.replace("'on':", "on:", 1),
            "# reordered and reformatted\n"
            + __import__("yaml").safe_dump(self.workflow, sort_keys=True),
            original.replace(
                "tags: ghcr.io/cwimmer/devcontainer:opencode2",
                "tags: |\n            ghcr.io/cwimmer/devcontainer:opencode2",
                1,
            ),
            original.replace(
                "platforms: linux/amd64,linux/arm64",
                "platforms: >-\n            linux/amd64,\n            linux/arm64",
                1,
            ),
        )
        for source in variants:
            with (
                self.subTest(source=source[:70]),
                tempfile.TemporaryDirectory() as temporary,
            ):
                path = Path(temporary) / "workflow.yaml"
                path.write_text(source, encoding="utf-8")
                workflow = load_workflow(path)
                check_v2_workflow(workflow)
                check_existing_lanes(workflow)

    def test_yaml_boolean_resolution_is_local_and_false_defaults_are_literal(
        self,
    ) -> None:
        import yaml

        before = yaml.safe_load("on: false")
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "workflow.yaml"
            path.write_text("on: false\n", encoding="utf-8")
            self.assertIs(load_workflow(path)["on"], False)
        self.assertEqual(yaml.safe_load("on: false"), before)

        for value in (False, " false ", "FaLsE"):
            with self.subTest(value=value):
                workflow = copy.deepcopy(self.workflow)
                self.step_by_id(workflow, "build_opencode2_native")["with"]["push"] = (
                    value
                )
                check_v2_workflow(workflow)
        for value in (False, " false ", "FaLsE"):
            workflow = copy.deepcopy(self.workflow)
            self.step_by_id(workflow, "publish_opencode2")["with"]["push"] = value
            self.assert_contract_error(workflow, "v2", "push")
        for value in (True, "true", None, 0, 1, "no", "${{ false }}"):
            with self.subTest(value=value):
                workflow = copy.deepcopy(self.workflow)
                self.step_by_id(workflow, "build_opencode2_native")["with"]["push"] = (
                    value
                )
                self.assert_contract_error(workflow, "v2", "push")

        for value in (False, " false ", "FALSE"):
            workflow = copy.deepcopy(self.workflow)
            self.step_by_id(workflow, "verify_opencode2")["continue-on-error"] = value
            check_v2_workflow(workflow)

        for false_scalar in ("false", "' false '", '"FaLsE"'):
            workflow = copy.deepcopy(self.workflow)
            native = self.step_by_id(workflow, "build_opencode2_native")
            native["with"]["push"] = yaml.safe_load(f"value: {false_scalar}")["value"]
            self.step_by_id(workflow, "verify_opencode2")["continue-on-error"] = (
                yaml.safe_load(f"value: {false_scalar}")["value"]
            )
            source = yaml.safe_dump(workflow, sort_keys=False)
            with (
                self.subTest(false_scalar=false_scalar),
                tempfile.TemporaryDirectory() as temporary,
            ):
                path = Path(temporary) / "workflow.yaml"
                path.write_text(source, encoding="utf-8")
                check_v2_workflow(load_workflow(path))

    def test_missing_required_and_optional_boolean_fields_differ(self) -> None:
        workflow = copy.deepcopy(self.workflow)
        del self.step_by_id(workflow, "build_opencode2_native")["with"]["load"]
        self.assert_contract_error(workflow, "v2", "load")

        workflow = copy.deepcopy(self.workflow)
        del self.step_by_id(workflow, "build_opencode2_native")["with"]["pull"]
        self.assert_contract_error(workflow, "v2", "pull")

        workflow = copy.deepcopy(self.workflow)
        workflow["jobs"]["build"]["steps"].append(
            {
                "id": "verify_opencode2",
                "run": "sh scripts/verify-opencode2.sh ghcr.io/cwimmer/devcontainer:opencode2",
            }
        )
        with self.assertRaisesRegex(ValueError, "verify_opencode2.*duplicate"):
            check_v2_workflow(workflow)

        workflow = copy.deepcopy(self.workflow)
        self.step_by_id(workflow, "build_opencode2_native")["with"].pop("push", None)
        check_v2_workflow(workflow)

        workflow = copy.deepcopy(self.workflow)
        self.step_by_id(workflow, "build_opencode2_native")["with"]["push"] = " false "
        check_v2_workflow(workflow)

        workflow = copy.deepcopy(self.workflow)
        self.step_by_id(workflow, "build_opencode2_native")["with"]["push"] = True
        self.assert_contract_error(workflow, "v2", "push")

        for value in (None, 0, 1, "no", "${{ false }}"):
            workflow = copy.deepcopy(self.workflow)
            self.step_by_id(workflow, "build_opencode2_native")["with"]["push"] = value
            self.assert_contract_error(workflow, "v2", "push")

        workflow = copy.deepcopy(self.workflow)
        self.step_by_id(workflow, "verify_opencode2")["continue-on-error"] = True
        self.assert_contract_error(workflow, "v2", "continue-on-error")

        workflow = copy.deepcopy(self.workflow)
        self.step_by_id(workflow, "verify_opencode2").pop("continue-on-error", None)
        check_v2_workflow(workflow)

    def test_verifier_command_subset_and_exact_argv(self) -> None:
        import yaml

        expected = [
            "sh",
            "scripts/verify-opencode2.sh",
            "ghcr.io/cwimmer/devcontainer:opencode2",
        ]
        positive = (
            "sh scripts/verify-opencode2.sh ghcr.io/cwimmer/devcontainer:opencode2",
            "sh 'scripts/verify-opencode2.sh' \"ghcr.io/cwimmer/devcontainer:opencode2\"",
            "sh scripts/verify-opencode2.sh \\\n                ghcr.io/cwimmer/devcontainer:opencode2",
            "\n\nsh scripts/verify-opencode2.sh ghcr.io/cwimmer/devcontainer:opencode2\n\n",
            "sh scripts/verify-opencode2.sh\\\n    ghcr.io/cwimmer/devcontainer:opencode2",
            "sh scripts/verify-opencode2.sh \\\n                ghcr.io/cwimmer/devcontainer:opencode2",
            yaml.safe_load(
                "run: >-\n  sh scripts/verify-opencode2.sh\n  ghcr.io/cwimmer/devcontainer:opencode2"
            )["run"],
            yaml.safe_load(
                "run: |\n  sh scripts/verify-opencode2.sh ghcr.io/cwimmer/devcontainer:opencode2"
            )["run"],
        )
        for command in positive:
            with self.subTest(command=command):
                self.assertEqual(
                    verifier_argv(command, "jobs.build.steps[verify_opencode2].run"),
                    expected,
                )

        negative_command_forms = (
            "sh scripts/verify-opencode2.sh\nghcr.io/cwimmer/devcontainer:opencode2",
            "sh scripts/verify-opencode2.sh ghcr.io/cwimmer/devcontainer:opencode2; true",
            "sh scripts/verify-opencode2.sh ghcr.io/cwimmer/devcontainer:opencode2\ntrue",
            "sh scripts/verify-opencode2.sh ghcr.io/cwimmer/devcontainer:opencode2 && true",
            "sh scripts/verify-opencode2.sh ghcr.io/cwimmer/devcontainer:opencode2 | cat",
            "sh scripts/verify-opencode2.sh ghcr.io/cwimmer/devcontainer:opencode2 > /tmp/out",
            "sh scripts/verify-opencode2.sh $(echo image)",
            "sh scripts/verify-opencode2.sh `echo image`",
            "sh 'unterminated",
            "sh 'scripts/verify-opencode2.sh \\\n                ghcr.io/cwimmer/devcontainer:opencode2'",
        )
        for command in negative_command_forms:
            with self.subTest(command=command):
                with self.assertRaisesRegex(
                    ValueError, "jobs.build.steps\\[verify_opencode2\\].run.*command"
                ):
                    verifier_argv(command, "jobs.build.steps[verify_opencode2].run")

        for command in (
            "bash scripts/verify-opencode2.sh ghcr.io/cwimmer/devcontainer:opencode2",
            "sh scripts/other.sh ghcr.io/cwimmer/devcontainer:opencode2",
            "sh scripts/verify-opencode2.sh ghcr.io/cwimmer/devcontainer:wrong",
            "sh scripts/verify-opencode2.sh",
            "sh scripts/verify-opencode2.sh ghcr.io/cwimmer/devcontainer:opencode2 extra",
        ):
            with self.subTest(command=command):
                with self.assertRaisesRegex(ValueError, "argument vector"):
                    verifier_argv(command, "jobs.build.steps[verify_opencode2].run")

    def test_cli_reports_contextual_errors_and_preserves_spaced_paths(self) -> None:
        with tempfile.TemporaryDirectory(prefix="workflow assertions ") as temporary:
            path = Path(temporary) / "image workflow.yaml"
            workflow = copy.deepcopy(self.workflow)
            self.step_by_id(workflow, "verify_opencode2")["timeout-minutes"] = 19
            import yaml

            path.write_text(yaml.safe_dump(workflow, sort_keys=False), encoding="utf-8")
            result = self.invoke(path, "v2")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("verify_opencode2", result.stderr)
        self.assertIn("timeout-minutes", result.stderr)

    def step_by_id(self, workflow: dict, step_id: str) -> dict:
        return next(
            step
            for step in workflow["jobs"]["build"]["steps"]
            if step.get("id") == step_id
        )

    def assert_contract_error(
        self, workflow: dict, contract: str, expected: str
    ) -> None:
        check = check_v2_workflow if contract == "v2" else check_existing_lanes
        with self.assertRaisesRegex(ValueError, expected):
            check(workflow)


class ImageAssertionsAdditionalTests(unittest.TestCase):
    def write_calls(self, directory: Path, calls: list[list[str]]) -> Path:
        path = directory / "docker calls.jsonl"
        path.write_text(
            "".join(json.dumps(call) + "\n" for call in calls), encoding="utf-8"
        )
        return path

    def invoke(
        self, path: Path, *arguments: str, optimized: bool = False
    ) -> subprocess.CompletedProcess[str]:
        command = [sys.executable]
        if optimized:
            command.append("-O")
        command.extend([str(IMAGE_ASSERTIONS), str(path), *arguments])
        return subprocess.run(command, capture_output=True, text=True, check=False)

    def invoke_docker_stub(
        self, directory: Path, *arguments: str, status: str | None = None
    ) -> subprocess.CompletedProcess[str]:
        log = directory / "docker argv.jsonl"
        environment = {**os.environ, "IMAGE_LOG": str(log)}
        environment.pop("IMAGE_BATS_STATUS", None)
        if status is not None:
            environment["IMAGE_BATS_STATUS"] = status
        result = subprocess.run(
            [sys.executable, str(IMAGE_DOCKER), *arguments],
            capture_output=True,
            text=True,
            env=environment,
            check=False,
        )
        records = [
            json.loads(line) for line in log.read_text(encoding="utf-8").splitlines()
        ]
        self.assertEqual(records[-1], list(arguments))
        return result

    def test_docker_stub_simulates_only_the_exact_runner_command_vector(self) -> None:
        valid = [
            "run",
            "--rm",
            "-e",
            "ASDF_BATS_VERSION=1.14.0",
            "-v",
            "/copied repo:/repo",
            "-w",
            "/repo/tests",
            "ghcr.io/cwimmer/devcontainer:latest",
            "bash",
            "/repo/tests/run-bats.sh",
            "test-bats-support.bats",
            "test-gh-support.bats",
            "test-opencode-support.bats",
            "test-file-support.bats",
        ]
        with tempfile.TemporaryDirectory(prefix="docker stub ") as temporary:
            directory = Path(temporary)
            for injected_status, expected in ((None, 0), ("17", 17)):
                with self.subTest(status=injected_status):
                    result = self.invoke_docker_stub(
                        directory, *valid, status=injected_status
                    )
                    self.assertEqual(result.returncode, expected, result.stderr)

            for decoy in (
                [
                    "run",
                    "--rm",
                    "-e",
                    "TEST=/repo/tests/run-bats.sh",
                    "ghcr.io/cwimmer/devcontainer:latest",
                    "not-a-command",
                ],
                [
                    "run",
                    "--rm",
                    "-v",
                    "/repo/tests/run-bats.sh:/data",
                    "ghcr.io/cwimmer/devcontainer:latest",
                    "not-a-command",
                ],
            ):
                result = self.invoke_docker_stub(directory, *decoy)
                self.assertNotEqual(result.returncode, 0)

            unknown = valid[:9] + ["bash", "/repo/tests/run-bats.sh", "unknown.bats"]
            result = self.invoke_docker_stub(directory, *unknown)
            self.assertNotEqual(result.returncode, 0)

    def test_suite_failure_requires_one_exact_suite_and_no_later_verification(
        self,
    ) -> None:
        suite = [
            "run",
            "--rm",
            "-e",
            "ASDF_BATS_VERSION=1.14.0",
            "-v",
            "/repo:/repo",
            "-w",
            "/repo/tests",
            "ghcr.io/cwimmer/devcontainer:latest",
            "bash",
            "/repo/tests/run-bats.sh",
            "test-bats-support.bats",
            "test-gh-support.bats",
            "test-opencode-support.bats",
            "test-file-support.bats",
        ]
        with tempfile.TemporaryDirectory() as temporary:
            path = self.write_calls(Path(temporary), [suite])
            result = self.invoke(path, "suite-failure")
            self.assertEqual(result.returncode, 0, result.stderr)

            for later_call in (
                [
                    "buildx",
                    "build",
                    "-f",
                    "Dockerfile.OpenCode2",
                    "--tag",
                    "repo:opencode2",
                ],
                ["image", "inspect", "--format", "{{.Id}}", "repo:latest"],
            ):
                invalid = self.write_calls(Path(temporary), [suite, later_call])
                result = self.invoke(invalid, "suite-failure")
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("forbids", result.stderr)

            invalid = self.write_calls(Path(temporary), [suite[:-1]])
            result = self.invoke(invalid, "suite-failure")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("complete unchanged BATS file list", result.stderr)

    def test_cli_preserves_spaced_path_and_argument_boundaries(self) -> None:
        with tempfile.TemporaryDirectory(prefix="image assertions ") as temporary:
            path = self.write_calls(
                Path(temporary),
                [
                    [
                        "image",
                        "inspect",
                        "--format",
                        "{{.Id}}",
                        "repo/image:tag with space",
                    ]
                ],
            )
            expected = json.dumps(
                [
                    [
                        "image",
                        "inspect",
                        "--format",
                        "{{.Id}}",
                        "repo/image:tag with space",
                    ]
                ]
            )
            result = self.invoke(path, "calls", expected)

        self.assertEqual(result.returncode, 0, result.stderr)

    def test_malformed_json_reports_source_line(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "bad log.jsonl"
            path.write_text('["ok"]\nnot-json\n', encoding="utf-8")
            result = self.invoke(path, "calls", "[]")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn(str(path), result.stderr)
        self.assertIn("line 2", result.stderr)

    def test_invalid_jsonl_records_are_rejected(self) -> None:
        invalid_records = ("{}", "[]", '[""]', '["docker", 1]')
        for record in invalid_records:
            with (
                self.subTest(record=record),
                tempfile.TemporaryDirectory() as temporary,
            ):
                path = Path(temporary) / "invalid.jsonl"
                path.write_text(record + "\n", encoding="utf-8")
                result = self.invoke(path, "calls", "[]")
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("line 1", result.stderr)

    def test_missing_build_option_operands_are_diagnosed(self) -> None:
        for option in ("--tag", "--platform"):
            with (
                self.subTest(option=option),
                tempfile.TemporaryDirectory() as temporary,
            ):
                path = self.write_calls(Path(temporary), [["buildx", "build", option]])
                result = self.invoke(path, "builds", "[]")
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(option, result.stderr)

    def test_v2_order_scenario_rejects_verification_before_build(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            path = self.write_calls(
                Path(temporary),
                [
                    [
                        "run",
                        "--rm",
                        "repo:latest",
                        "cat",
                        "/usr/local/share/asdf-tool-versions",
                    ],
                    ["image", "inspect", "--format", "{{.Id}}", "repo:opencode2"],
                    [
                        "buildx",
                        "build",
                        "-f",
                        "Dockerfile.OpenCode2",
                        "--tag",
                        "repo:opencode2",
                        "--platform",
                        "linux/amd64",
                        "--load",
                    ],
                ],
            )
            result = self.invoke(path, "v2-order")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("before", result.stderr)

    def test_build_failure_scenario_rejects_forbidden_post_failure_commands(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            path = self.write_calls(
                Path(temporary),
                [
                    ["buildx", "build", "--tag", "repo:latest"],
                    [
                        "buildx",
                        "build",
                        "-f",
                        "Dockerfile.OpenCode2",
                        "--tag",
                        "repo:opencode2",
                        "--platform",
                        "linux/amd64",
                        "--load",
                    ],
                    ["image", "inspect", "--format", "{{.Id}}", "repo:opencode2"],
                ],
            )
            result = self.invoke(path, "build-failure", "base-build")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("verification", result.stderr)

    def test_build_failure_requires_each_failed_build_attempt(self) -> None:
        expected_attempts = {
            "base-build": (
                "a buildx build using the base Dockerfile (implicit or -f Dockerfile)",
                ["buildx", "build", "--tag", "repo:latest"],
            ),
            "v2-native-build": (
                "a Dockerfile.OpenCode2 build with a native --platform operand and --load",
                [
                    "buildx",
                    "build",
                    "-f",
                    "Dockerfile.OpenCode2",
                    "--platform",
                    "linux/amd64",
                    "--load",
                ],
            ),
            "v2-multi-build": (
                "a Dockerfile.OpenCode2 build with --platform linux/amd64,linux/arm64 and no --load",
                [
                    "buildx",
                    "build",
                    "-f",
                    "Dockerfile.OpenCode2",
                    "--platform",
                    "linux/amd64,linux/arm64",
                ],
            ),
        }
        for detail, (description, expected_attempt) in expected_attempts.items():
            cases = (
                ("empty", []),
                (
                    "missing attempt",
                    [
                        [
                            "buildx",
                            "build",
                            "-f",
                            "Dockerfile.Other",
                            "--tag",
                            "repo:unrelated",
                        ]
                    ],
                ),
            )
            for label, calls in cases:
                with (
                    self.subTest(detail=detail, log=label),
                    tempfile.TemporaryDirectory() as temporary,
                ):
                    path = self.write_calls(Path(temporary), calls)
                    result = self.invoke(path, "build-failure", detail)

                self.assertNotEqual(result.returncode, 0)
                self.assertIn(detail, result.stderr)
                self.assertIn("failed build attempt", result.stderr)
                self.assertIn(description, result.stderr)
                if label == "missing attempt":
                    self.assertIn("Dockerfile.Other", result.stderr)

    def test_base_build_failure_rejects_later_v2_build(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            path = self.write_calls(
                Path(temporary),
                [
                    ["buildx", "build", "--tag", "repo:latest"],
                    [
                        "buildx",
                        "build",
                        "-f",
                        "Dockerfile.OpenCode2",
                        "--tag",
                        "repo:opencode2",
                    ],
                ],
            )
            result = self.invoke(path, "build-failure", "base-build")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("base build failure", result.stderr)

    def test_v2_multi_build_failure_rejects_later_native_load(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            path = self.write_calls(
                Path(temporary),
                [
                    [
                        "buildx",
                        "build",
                        "-f",
                        "Dockerfile.OpenCode2",
                        "--tag",
                        "repo:opencode2",
                        "--platform",
                        "linux/amd64,linux/arm64",
                    ],
                    [
                        "buildx",
                        "build",
                        "-f",
                        "Dockerfile.OpenCode2",
                        "--tag",
                        "repo:opencode2",
                        "--platform",
                        "linux/amd64",
                        "--load",
                    ],
                ],
            )
            result = self.invoke(path, "build-failure", "v2-multi-build")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("native v2 load", result.stderr)

    def test_failing_check_remains_active_under_python_optimization(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            path = self.write_calls(Path(temporary), [["image", "inspect"]])
            result = self.invoke(path, "calls", "[]", optimized=True)

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("actual", result.stderr)


if __name__ == "__main__":
    unittest.main()
