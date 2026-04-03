<!-- SUPERPOWERS-START -->
# SUPERPOWERS PROTOCOL
You are an autonomous coding agent operating on a strict "Loop of Autonomy."

## CORE DIRECTIVE: The Loop
For every request, you must execute the following cycle:
1. **PERCEIVE**: Read `plan.md`. Do not act without checking the plan.
2. **ACT**: Execute the next unchecked step in the plan.
3. **UPDATE**: Check off the step in `plan.md` when verified.
4. **LOOP**: If the task is large, do not stop. Continue to the next step.

## YOUR SKILLS (Slash Commands)
VS Code reserved commands are replaced with these Superpowers equivalents:

- **Use `/write-plan`** (instead of /plan) to interview me and build `plan.md`.
- **Use `/investigate`** (instead of /fix) when tests fail to run a systematic analysis.
- **Use `/tdd`** to write code. NEVER write code without a failing test.

## RULES
- If `plan.md` does not exist, your ONLY valid action is to ask to run `/write-plan`.
- Do not guess. If stuck, write a theory in `scratchpad.md`.

## AVAILABLE SKILLS

All skill definitions are available at `./.superpowers/skills/` (workspace-resident).
This path keeps all Superpowers content within your workspace, preventing permission prompts.
<!-- SUPERPOWERS-END -->

# Project Context

- This is a Docker container I use as the base for most of my devcontainers
- It has a variety of command line tools installed.
- The Makefile target `upgrade` upgrades the version of all components.
- Target environment: Devcontainer

## How agents should behave

- Primary goals: Ensure code functions as documented.  Ensure
    code meets quality standards outlined in README.md and/or
    AGENTS.md.
- Scope: Agents are welcome to change code and documentation. Prefer
    many small changes over large, sweeping changes.

## Code Style

- Bash scripts should be POSIX-compliant where possible
- Include error handling for all external calls
- Add comments for complex logic
- Error handling is mandatory
- Use meaningful variable names
- Use comments to explain complex logic
- Keep functions small and focused
- The project uses pre-commit hooks to apply lint rules
- Use the string `TODO:` to indicate outstanding code, test, or
    documentation work.  This is to support the Todo Tree extension.

## Build & test commands

- Use `make test` to run all tests during development iteration.
- Development workflow - `make test`

## PR / commit guidelines

- Commit messages must comply with
  [Conventional Commits v1.0.0](https://www.conventionalcommits.org/en/v1.0.0/)
- When suggesting commit messages, never use the word "comprehensive"

## Priorities

- Reliability and error handling
- User experience (clear output, helpful errors)

## Constraints

- Must work in a devcontainer environment
- Must be POSIX-compliant where possible
- Must not introduce breaking changes to existing functionality
