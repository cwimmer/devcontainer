---
description: Weekly update of the Devcontainer
name: update-devcontainer
agent: agent
model: Raptor mini (Preview) (copilot)
tools: [execute/runInTerminal, read/readFile, edit/createFile, edit/editFiles]
---
# Update Devcontainer Image

## Task

- Update devcontainer image versions across `Dockerfile` (base tools),
  `Dockerfile.OpenCode` (Node.js plus OpenCode v1), and `Dockerfile.OpenCode2`
  (standalone OpenCode v2).
- Use `make upgrade`, which updates base tools and stable OpenCode 1.x and 2.x.
- Treat OpenCode v1 and v2 as independent upgrades. `make upgrade-opencode`
  updates v1 only; `make upgrade-opencode2` updates v2 only. Node.js continues
  to target v1 only. The updater uses canonical stable versions and does not
  cross OpenCode major versions.

## Expected flow

1. Run `make upgrade`. If it fails, report the failure and command output.
2. Inspect `git status --short` and `git diff -- Dockerfile Dockerfile.OpenCode Dockerfile.OpenCode2`.
3. Report "no changes" and stop only if `make upgrade` succeeded and all
   three Dockerfiles are unchanged.
4. If any Dockerfile changed, report the updated tools and versions, identifying
   `opencode` as v1 and `opencode2` as v2.
5. Run `make test_native`, `make test_native_opencode`, and
   `make test_native_opencode2`, allowing at least 20 minutes for each command.
   Record the host architecture and report base, v1, and v2 outcomes separately.
   The v2 target checks the runtime-reported OpenCode version against the
   `Dockerfile.OpenCode2` pin.
6. When multi-platform verification is appropriate, run `make test` for base,
   `make test_opencode` for v1, and `make test_opencode2` for v2. These targets
   build `linux/amd64` and `linux/arm64`, then load and runtime-check only the
   host-native image. In particular, `make test_opencode2` does not establish
   arm64 runtime evidence on an amd64 host (or amd64 runtime evidence on arm64).
7. The derived-image targets separately build/check the checkout's base as a
   prerequisite, but that local image does not supply the derived build's base.
   The v2 build resolves `ghcr.io/cwimmer/devcontainer:latest` from the
   published registry image. The configured v2 destination is
   `ghcr.io/cwimmer/devcontainer:opencode2`; configured destination is not
   evidence that publication succeeded.
8. Report per-image local tests/builds/runtime results, including failures and
   skipped checks. Keep local evidence separate from workflow/CI evidence and
   registry publication evidence. Report remote CI execution as unverified
   unless observed; publication requires successful main-branch workflow
   evidence and a registry manifest showing both architectures. Do not trigger
   workflows, publish, or push to obtain evidence.

## Context

- Repo: `cwimmer/devcontainer`
- `Makefile` defines `upgrade`, `upgrade-opencode`, `upgrade-opencode2`, and
  six base/v1/v2 native and multi-platform verification targets.
- `upgrade` runs `scripts/update-versions.sh --all`.
- Image tags are `latest` (base), `opencode` (v1), and `opencode2` (v2).
- Derived v2 builds resolve the published `latest` base; their base prerequisite
  independently verifies the local base image and does not supply it to that
  build.

## Notes

- Keep the final summary short and actionable.
- Set a timeout of at least 20 minutes for each native Make target.
