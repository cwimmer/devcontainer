# Bats in Devcontainer

Add the `bats` shell testing framework to the base devcontainer image in the same style as the other asdf-managed CLI tools already shipped by this repository.

## Motivation

The devcontainer currently does not include `bats`, so shell-based test workflows cannot rely on it being present by default. This repo already has a clear convention for adding tooling to the base image: pin the version in `Dockerfile`, install with asdf when the tool fits that model, surface the pinned version through `/usr/local/share/asdf-tool-versions`, wire the tool into `scripts/update-versions.sh` and `Makefile`, and document it in `README.md`.

The goal is to add Bats by following that convention with the smallest change that keeps upgrades and documentation consistent.

## Conventions Observed

- Base image tools belong in `Dockerfile`; `Dockerfile.OpenCode` is only for the OpenCode-specific layer.
- Versions are pinned with Dockerfile `ARG` values for reproducible default builds.
- asdf-managed tools use `asdf plugin add` plus `asdf install` in `Dockerfile`.
- All asdf-managed tools are listed in `/usr/local/share/asdf-tool-versions` so consumers can adopt the image defaults.
- Upgrades are centralized in `scripts/update-versions.sh`, with one matching `upgrade-<tool>` target in `Makefile`.
- `README.md` is the primary place that documents installed tools and the upgrade/build workflow.
- Verification is intentionally lightweight: use existing `make` targets and small smoke tests rather than introducing a large new test suite.

## Chosen Approach

Install Bats in the base image as an asdf-managed tool.

This matches the existing pattern used for `terraform`, `golang`, `kubectl`, `helm`, `kind`, `kubectx`, `terraform-docs`, `tflint`, and `trivy`. It keeps version pinning, upgrade automation, and `/usr/local/share/asdf-tool-versions` aligned with the existing design.

The asdf plugin to use is `https://github.com/timgluz/asdf-bats.git`. Its install flow expects version strings without the leading `v`, which fits the repo's current `update-versions.sh` convention of stripping `v` from GitHub release tags before writing Dockerfile `ARG` values.

## Alternatives Considered

### 1. Install Bats via `apt`

Pros:
- Smallest possible Dockerfile change
- Uses Ubuntu packaging already available in the base image

Cons:
- Does not match the repo's established per-tool version pinning and upgrade-target pattern for comparable CLI tools
- Would either skip `/usr/local/share/asdf-tool-versions` or create a special-case documentation path
- Reproducibility would be tied more directly to the base image's apt state unless extra pinning work was added

### 2. Install Bats from a GitHub release tarball

Pros:
- Can be tightly pinned
- Could support checksum verification later if needed

Cons:
- Introduces a one-off install/update path not currently needed
- Adds maintenance complexity compared with reusing the existing asdf workflow

Neither alternative is as consistent with the current repository conventions as the asdf-based approach.

## Detailed Design

### 1. `Dockerfile`

Add a new pinned `ARG BATS_VERSION` in the existing version block, with the concrete value set during implementation.

Install Bats in the existing asdf tool section:

```dockerfile
RUN asdf plugin add bats https://github.com/timgluz/asdf-bats.git
RUN asdf install bats $BATS_VERSION
```

Add `bats $BATS_VERSION` to the `printf` block that writes `/usr/local/share/asdf-tool-versions`.

This keeps Bats visible to consumers in the same way as every other asdf-managed tool in the image.

### 2. `scripts/update-versions.sh`

Extend the existing upgrade script with `bats` support:

- Add `bats` to `TOOL_ARG_NAMES`
- Add `bats` to `TOOL_DOCKERFILE_PATHS`
- Add `get_latest_bats_version()` using the `bats-core/bats-core` GitHub releases API
- Add a `bats)` branch in `get_latest_version()`
- Add `bats` to the help output

The version-fetch function should strip the leading `v` from the release tag so the Dockerfile stores plain versions like `1.13.0`, matching the plugin's expected install input.

### 3. `Makefile`

Add:

```makefile
.PHONY: upgrade-bats
upgrade-bats:
	@echo "Updating bats version in Dockerfile..."
	@bash scripts/update-versions.sh --tool bats
```

This follows the exact structure already used for the other tool-specific upgrade targets.

`make upgrade` needs no structural change because it already delegates to `scripts/update-versions.sh --all`, which will pick up the new tool automatically.

### 4. `README.md`

Update the installed tools table to include `bats | asdf`.

Also add a short maintenance note in the development or upgrade section documenting the convention for future contributors: when a new asdf-managed tool is added, update all of the following together:

- `Dockerfile`
- `/usr/local/share/asdf-tool-versions` generation in `Dockerfile`
- `scripts/update-versions.sh`
- `Makefile`
- `README.md`

This is intentionally brief. The repo already implies this pattern; the goal is to make it explicit enough for future agents without introducing a large process document.

### 5. Minimal Smoke Test

Add one small top-level smoke test file rather than expanding the OpenCode-specific test.

The test should assert only the wiring that is already conventional in this repo:

- `make -n` recognizes `upgrade-bats`
- `bash scripts/update-versions.sh --tool bats --check-only` succeeds
- `Dockerfile` contains the expected asdf install lines for Bats
- `README.md` lists Bats in the installed tools table

This keeps verification lightweight and focused on the new integration points.

## Verification Plan

Run the existing verification commands plus the requested repo hygiene check:

1. `bash scripts/update-versions.sh --tool bats --check-only`
2. `make test_native`
3. `docker run --rm ghcr.io/cwimmer/devcontainer:latest bats --version`
4. `docker run --rm ghcr.io/cwimmer/devcontainer:latest cat /usr/local/share/asdf-tool-versions`
   Confirm `bats` appears in the file.
5. `make pre-commit`

Note: in this repository, `make pre-commit` runs `pre-commit install`,
`pre-commit autoupdate`, and `pre-commit run --all-files`. That means
this verification step is not a pure read-only check. If it updates
`.pre-commit-config.yaml`, those hook-version changes should be treated
as a separate user-visible outcome rather than being silently folded
into the Bats change.

If the new smoke test is added, it should also be run directly or through whatever existing verification entrypoint is most natural once the file is in place.

## Scope Guardrails

In scope:

- Add Bats to the base image
- Pin its version
- Support upgrades through the existing script and Makefile pattern
- Document the installed tool and the discovered maintenance convention
- Add only a minimal smoke test if needed to match the repo's current style

Out of scope:

- Introducing a new tool-management framework
- Refactoring unrelated devcontainer logic
- Adding a broad Bats-based test suite for the repository itself
- Reworking `Dockerfile.OpenCode` beyond inheriting the base-image change

## Expected Outcome

After implementation, `bats` will be available in the base devcontainer image and in the OpenCode variant via inheritance. Its version will be pinned and upgradeable through the same repo workflow used for the existing asdf-managed tools, and the README will explicitly document the maintenance pattern future agents should follow when adding similar tools.
