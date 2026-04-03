# Instructions

Use the Superpowers brainstorming skill.

Before asking questions, inspect the current codebase, docs, tests, and recent commits that appear relevant.

Task:
Allow the customers to automatically use the versions in the devcontainer managed by asdf.

Goal:

- There will be an example `.tool-versions` file written in the devcontainer.
  - /usr/local/share/asdf-tool-versions
  - Contains all the default versions from the Dockerfile
- Instructions will be added to README instructing users of this devcontainer how they may optionally use this file.
  - ln -s /usr/local/share/asdf-tool-versions .tool-versions
  - export ASDF_TOOL_VERSIONS_FILENAME=/usr/local/share/asdf-tool-versions
- The `make upgrade` target will automatically generate the version file with the correct versions

Constraints:

- Preserve current architecture where possible
- Keep the first version minimal and incremental
- Accessibility / error handling / tests matter
- Avoid introducing a second way to do the same thing

Non-goals:

- Changing the way versions in the Dockerfile are updated

Success criteria:

- A sufficiently skilled engineer may look at the README.md and add the default versions to their project.

Please ask one question at a time, propose 2–3 approaches, recommend one, and present the design in a compact form for approval before any implementation planning.
