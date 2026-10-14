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
5. Run `make test_native`, then `make test_native_opencode`, allowing at least
   20 minutes for each command. These targets verify base and v1 only; do not
   treat their results as v2 verification.
6. Directly build and run v2, allowing at least 20 minutes for the build:

   ```sh
   docker build -f Dockerfile.OpenCode2 -t devcontainer-opencode2-local .
   expected=$(sed -n 's/^ARG OPENCODE_VERSION=//p' Dockerfile.OpenCode2)
   actual=$(docker run --rm --pull=never devcontainer-opencode2-local opencode --version) &&
     actual=${actual##* } && test "${actual#v}" = "$expected"
   ```

7. Report base, v1, and v2 results separately. Include failing command output
   and identify checks that were not run; a success for one image is not
   evidence for another.

## Context

- Repo: `cwimmer/devcontainer`
- `Makefile` defines `upgrade`, `upgrade-opencode`, `upgrade-opencode2`,
  `test_native`, and `test_native_opencode`.
- `upgrade` runs `scripts/update-versions.sh --all`.
- `Dockerfile.OpenCode2` can be built locally; the existing native Make targets
  cover only base and v1.

## Notes

- Preserve the build/run command line breaks and shell quoting in the v2
  version-comparison block.
- Keep the final summary short and actionable.
- Set a timeout of at least 20 minutes for each native Make target and for the
  direct v2 Docker build.
