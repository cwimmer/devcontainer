---
description: Weekly update of the Devcontainer
name: update-devcontainer
agent: agent
model: Raptor mini (Preview) (copilot)
tools: [execute/runInTerminal, read/readFile, edit/createFile, edit/editFiles]
---
# Update Devcontainer Image

## Task

- Update devcontainer image versions in `Dockerfile`.
- Use `make upgrade`
- Confirm whether versions changed.
- Run `make test_native` and verify the native Docker build succeeds.

## Expected flow

1. Execute `make upgrade`.
2. If there are no Dockerfile changes, report "no changes" and stop.
3. If there are changes, report updated tool versions (`doctl`, `kubectl`, etc.).
4. Execute `make test_native`.
5. If the build succeeds, report success.
6. If the build fails, include the failing command output.

## Context

- Repo: `cwimmer/devcontainer`
- `Makefile` defines `upgrade` and `test_native`.
- `upgrade` runs `scripts/update-versions.sh --all`.

## Notes

- Always validate the result by checking `git status --short` and `git diff -- Dockerfile`.
- Keep the final summary short and actionable.
