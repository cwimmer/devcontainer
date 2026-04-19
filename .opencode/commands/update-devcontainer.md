---
description: Weekly update of the Devcontainer
name: update-devcontainer
model: github-copilot/gpt-5-mini
---
# Update Devcontainer Image

## Task

- Update devcontainer image versions in `Dockerfile` and `Dockerfile.OpenCode`.
- Use `make upgrade`
- Confirm whether versions changed.
- Run `make test_native` and `make test_native_opencode` and verify the native Docker builds succeed.

## Expected flow

1. Execute `make upgrade`.
2. If there are no `Dockerfile` or `Dockerfile.OpenCode` changes, report "no changes" and stop.
3. If there are changes, report updated tool versions (`doctl`, `kubectl`, `nodejs`, `opencode`, etc.).
4. Execute `make test_native`.
5. Execute `make test_native_opencode`.
6. If the builds succeed, report success.
7. If a build fails, include the failing command output.

## Context

- Repo: `cwimmer/devcontainer`
- `Makefile` defines `upgrade`, `test_native`, and `test_native_opencode`.
- `upgrade` runs `scripts/update-versions.sh --all`.

## Notes

- Always validate the result by checking `git status --short` and `git diff -- Dockerfile Dockerfile.OpenCode`.
- Keep the final summary short and actionable.
