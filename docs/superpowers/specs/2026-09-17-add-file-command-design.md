# Add `file` Command to the Devcontainer

**Date:** 2026-09-17
**Status:** Proposed (revision 4)

## Motivation

The `file` command is missing from this devcontainer. It is needed by
developers (and by several automation scripts the author uses) to
determine file types via magic numbers. The Ubuntu base image
(`public.ecr.aws/ubuntu/ubuntu:24.04_stable`) does not ship `file`, so
it must be installed explicitly.

The change should follow the project's existing per-tool BATS test
convention so the install is locked in against future drift, and the
CI workflow should actually validate the freshly built image rather
than pulling a previously-published `latest` tag.

## Conventions observed

- System packages install via the single `RUN apt-get update &&
  apt-get install -y \` block at `Dockerfile:19-35`. The `gh` row is
  the precedent for an apt-managed developer tool that is also pinned
  in version and listed in the README tool table.
- Tools get a BATS file under `tests/test-<tool>-support.bats`,
  patterned on `tests/test-gh-support.bats`. The Makefile's `test` and
  `test_native` targets run the full suite inside the freshly built
  image via `docker run --rm ... bats <files>`.
- The README's "Installed tools" table (`README.md:6-25`) lists every
  tool that required deliberate installation work, with the manager
  column (asdf / apt / binary / pipx).
- `scripts/update-versions.sh` is only for tools with explicit
  version pins. `file` has no version pin in this design.
- The devcontainer uses `Dockerfile.OpenCode` (per
  `.devcontainer/devcontainer.json:6`), which extends
  `ghcr.io/cwimmer/devcontainer:latest` — the published image built
  from the base `Dockerfile`. Rebuilding and pushing the new base
  does **not** automatically update consumers: the OpenCode layer
  (`Dockerfile.OpenCode`) and every downstream devcontainer that
  extends `ghcr.io/cwimmer/devcontainer:latest` must be rebuilt
  against the updated base to consume the new `file` binary.
- The Makefile uses a dedicated Buildx builder (`builder`) declared
  in `Makefile:33-37`. `docker buildx create --name builder` with no
  `--driver` flag defaults to the **`docker-container`** driver
  (not `docker`), which keeps its image store in a separate
  container rather than sharing the local Docker daemon's store.
  This is a load-bearing detail for any verification that claims the
  OpenCode build consumes a locally-built base.

## CI gap motivating the workflow change

The current `.github/workflows/image-build.yaml` runs `build` and
`test` as two separate jobs on independent runners. The `build` job
loads the base image into its local Docker daemon
(`docker/build-push-action` with `load: true`), then pushes the
multi-arch image only on `main`
(`push: ${{ github.ref == 'refs/heads/main' }}`).

On a pull request, the `test` job therefore has no access to the
locally-loaded image and falls through to `docker run ... ghcr.io/cwimmer/devcontainer:latest`,
which pulls the **previously-published** `latest` tag from the
registry — i.e. the last successful `main` build. This means PRs do
not actually validate their own image: a PR that breaks the BATS
suite can pass CI, and a PR that adds a working tool can fail CI for
reasons unrelated to its own change.

The smallest change that closes this gap is to run the BATS suite
inside the same job that builds the image, against the locally-loaded
`linux/amd64` artifact produced by the `load: true` step.

## Chosen approach

1. Append `file` to the existing `apt-get install` block in the base
   `Dockerfile`.
2. Add a new row `| file | apt |` to the README's "Installed tools"
   table, immediately above the `pre-commit` / `commitizen` pipx rows
   so the apt-managed group stays together.
3. Add a regression BATS file `tests/test-file-support.bats` with one
   docs-locking assertion (README row) and three functional smoke
   tests (`file --version`, text identification, ELF identification).
   No Dockerfile-text grep: the functional tests already establish
   that `file` is actually present in the built image, which is a
   stronger signal than matching a recipe string.
4. Register the new BATS file in the `bats` invocation in both
   `test` (multi-platform) and `test_native` (single-platform)
   targets in the `Makefile`.
5. Move the BATS test step from the separate `test` job into the
   `build` job in `.github/workflows/image-build.yaml`, so PRs
   validate their own freshly-built image. Delete the now-redundant
   `test` job.

## Alternatives considered

1. **Add `file` to `Dockerfile.OpenCode` only.** Wrong architecturally
   — the base image is published as `ghcr.io/cwimmer/devcontainer:latest`
   and is explicitly "the base for development containers" (`README.md:3`).
   Other downstream devcontainer variants would still miss `file`.
   Rejected.
2. **Add `file` to both `Dockerfile` and `Dockerfile.OpenCode`.**
   Belt-and-suspenders, but the OpenCode layer's purpose is to add
   Node.js/opencode, not to re-install system packages already in the
   base. Risks drift if `file` is later upgraded or removed in only
   one place. Rejected.
3. **Pin `file` via an `ARG FILE_VERSION=...`.** The repo has no
   precedent for pinning system packages that are not version-managed
   (none of `unzip`, `curl`, `git`, `make`, `jq`, `wget`, `direnv`,
   `httpie`, `iproute2`, `iputils-ping`, `socat`, `dnsutils`, or
   `ripgrep` have an `ARG` pin). Pinning `file` alone would introduce
   inconsistency. Rejected.
4. **Add a `make upgrade-file` target and a `file` entry in
   `scripts/update-versions.sh`.** Same reasoning as option 3 — the
   tool is not version-managed, so there is nothing to upgrade.
   Rejected.
5. **Fix the CI gap by always pushing the PR-built image to
   `ghcr.io/cwimmer/devcontainer:latest`.** One-line change, but
   pollutes the published tag with every PR and races with concurrent
   PRs and pushes. Rejected.
6. **Fix the CI gap by pushing to a per-PR tag
   (`ghcr.io/cwimmer/devcontainer:pr-${{ github.event.pull_request.number }}`).
   Avoids tag pollution but adds two-step workflow complexity for a
   problem the in-job test step solves directly. Rejected.
7. **Keep the separate `test` job but have it pull from a fixed
   image tag.** Same as the current behaviour; does not validate the
   PR's build. Rejected.
8. **Skip the BATS regression test.** Inconsistent with the project's
   per-tool BATS convention (`test-bats-support.bats`,
   `test-gh-support.bats`, `test-opencode-support.bats`).
   Rejected.

## Detailed design

### 1. `Dockerfile`

Append `file` as the last entry of the existing apt-get install block
at `Dockerfile:19-35`. The block has no enforced ordering; appending
is the least-churn option.

After:

```dockerfile
RUN apt-get update && apt-get install -y \
    unzip \
    curl \
    git \
    make \
    python3-pip \
    pipx \
    jq \
    wget \
    direnv \
    golang-go \
    httpie \
    iproute2 \
    iputils-ping \
    socat \
    dnsutils \
    ripgrep \
    file
```

No `ARG FILE_VERSION` is added (see Alternatives #3). No other
`Dockerfile` change.

### 2. `README.md`

Add one row to the "Installed tools" table at `README.md:6-25`,
placed immediately before the `pre-commit` row so the apt-managed
entries group together.

After:

```markdown
| doctl | binary |
| gh | apt |
| file | apt |
| pre-commit | pipx |
| commitizen | pipx |
```

No other `README.md` change.

### 3. `tests/test-file-support.bats` (new file)

Four `@test` blocks. The README assertion locks the docs entry
(there's no functional equivalent for that). The three functional
tests run inside the freshly built image and are the actual proof
that `file` is installed and works; running inside a built image
without a `file` invocation does not prove anything, so the grep on
`Dockerfile` text from revision 1 is intentionally dropped.

```bash
#!/usr/bin/env bats

load 'test_helper/common'
load '/usr/local/share/bats-support/load'
load '/usr/local/share/bats-assert/load'

@test "README lists file as apt-managed" {
    run grep -Fq -- '| file | apt |' "$REPO_ROOT/README.md"
    assert_success
}

@test "file --version succeeds" {
    run file --version
    assert_success
}

@test "file identifies /etc/passwd as text" {
    run file /etc/passwd
    assert_success
    assert_output --partial "text"
}

@test "file identifies /usr/bin/ls as ELF" {
    run file /usr/bin/ls
    assert_success
    assert_output --partial "ELF"
}
```

### 4. `Makefile`

Append `test-file-support.bats` to the existing `bats` invocation in
both the `test` target (line 20) and the `test_native` target
(line 55). No Makefile target name, no `upgrade-file` target, no
`scripts/update-versions.sh` changes.

`Makefile:20`:

```makefile
		bats test-bats-support.bats test-gh-support.bats test-opencode-support.bats \
		     test-file-support.bats
```

`Makefile:55`: same change.

### 5. `.github/workflows/image-build.yaml`

Two changes: register `test-file-support.bats` in the BATS
invocation, and move the test step from the separate `test` job
into the `build` job, immediately after the
"Build base image for local testing" step and **before** either
publishing step. The `docker run` uses `--pull=never` so it cannot
silently fetch a registry copy.

The reordered `build` job steps become:

```yaml
      - name: Build base image for local testing
        uses: docker/build-push-action@v7
        with:
          context: .
          load: true
          tags: ghcr.io/cwimmer/devcontainer:latest
          platforms: linux/amd64

      - name: Run BATS suite against locally-built image
        run: |
          docker run --rm --pull=never \
            -e ASDF_BATS_VERSION=1.14.0 \
            -v ${{ github.workspace }}:/repo \
            -w /repo/tests \
            ghcr.io/cwimmer/devcontainer:latest \
            bats \
              test-bats-support.bats \
              test-gh-support.bats \
              test-opencode-support.bats \
              test-file-support.bats

      - name: Build and push base multi-architecture image
        uses: docker/build-push-action@v7
        with:
          context: .
          push: ${{ github.ref == 'refs/heads/main' }}
          tags: |
            ghcr.io/cwimmer/devcontainer:latest
          platforms: linux/amd64,linux/arm64

      - name: Build and push OpenCode multi-architecture image
        uses: docker/build-push-action@v7
        with:
          context: .
          file: Dockerfile.OpenCode
          push: ${{ github.ref == 'refs/heads/main' }}
          tags: |
            ghcr.io/cwimmer/devcontainer:opencode
          platforms: linux/amd64,linux/arm64
```

The standalone `test:` job (lines 63-80) is removed.

Net effect on CI: PRs now run the BATS suite against the image
built from the PR's revision, between the local build and the
publishing steps. `--pull=never` makes the test step hard-fail if
the locally-loaded image is somehow missing rather than silently
fetching the previously-published `latest` tag from the registry.
The `ASDF_BATS_VERSION` environment variable continues to match
the `ARG BATS_VERSION` value in `Dockerfile:4` (`1.14.0`), so the
asdf bats shim resolves correctly inside the container.

## Verification plan

The verification uses only direct `docker` / `docker buildx`
commands with `--builder default` (which uses the `docker` driver
and therefore the local daemon's image store). It does **not** rely
on the Makefile's `test_native_opencode` target — that target
creates and uses a `builder` instance whose driver may differ from
the local daemon. Local verification is also distinguished from
the publish-and-rebuild sequence needed by downstream consumers,
which never happens automatically.

### Local verification (commands to run)

The verification is a single bash script. Each step's nonzero exit
status indicates failure; the script stops at the first failure.

```bash
set -e
set -o pipefail

# 1. Verify the `default` builder uses the `docker` driver.
docker buildx inspect default
```

The last command's output is human-readable YAML. Check that the
output contains a `Driver: docker` line; if it contains anything
else (`Driver: docker-container`, `Driver: remote`, `Driver: kubernetes`,
etc.), stop — the next steps would build into a separate image
store and would not see the locally-built base.

```bash
# 2. Build the base image with the verified `default` builder,
#    same platform throughout, with the published tag.
docker buildx build --builder default --load \
  --platform linux/amd64 \
  --tag ghcr.io/cwimmer/devcontainer:latest \
  .

# 3. Smoke-test the base image directly with `--pull=never`.
docker run --rm --pull=never ghcr.io/cwimmer/devcontainer:latest file --version
docker run --rm --pull=never ghcr.io/cwimmer/devcontainer:latest file /etc/passwd | grep -q text
docker run --rm --pull=never ghcr.io/cwimmer/devcontainer:latest file /usr/bin/ls | grep -q ELF

# 4. Build the OpenCode layer on top of the local base, using the
#    same `default` builder and same platform.
docker buildx build --builder default --load \
  --platform linux/amd64 \
  --tag ghcr.io/cwimmer/devcontainer:opencode \
  -f Dockerfile.OpenCode \
  .

# 5. Smoke-test the OpenCode image under its development user
#    (root, since neither `Dockerfile` nor `Dockerfile.OpenCode`
#    sets `USER`).
docker run --rm --pull=never --user root \
  ghcr.io/cwimmer/devcontainer:opencode file --version
docker run --rm --pull=never --user root \
  ghcr.io/cwimmer/devcontainer:opencode file /etc/passwd | grep -q text
docker run --rm --pull=never --user root \
  ghcr.io/cwimmer/devcontainer:opencode file /usr/bin/ls | grep -q ELF
```

Expected output:

- Step 2 / step 4: buildkit progress to stderr (BuildKit's default).
  Success is the absence of a nonzero exit; the build's last line
  may report a load summary.
- Step 3 / step 5 (`file --version`): prints a one-line version
  banner such as `file-5.45` to stdout. That line is the only
  stdout output; no further assertion is needed.
- Step 3 / step 5 (`file /etc/passwd` and `file /usr/bin/ls`):
  silent. The `grep -q text` and `grep -q ELF` halves consume the
  classification output and exit zero only on match. With `pipefail`
  active, a non-matching `file` output propagates `grep`'s exit 1
  and aborts the script.

`--pull=never` prevents the daemon from silently fetching a
registry copy if the local tag is somehow missing. This is the
load-bearing evidence that `file` propagated through the layer
chain into the OpenCode image — a non-zero exit on any of the
three indicates either the base was not consumed (e.g. the
OpenCode build silently pulled from the registry) or `file` is
missing. To distinguish the two, repeat steps 2 and 4 and re-run
this step; if the failure persists, the implementer must inspect
whether the Makefile's `test_native_opencode` target is being used
inadvertently, since it routes through the `builder` Buildx
instance which may use a different driver.

### Downstream-consumer sequence (documentation, not run)

For projects that consume `ghcr.io/cwimmer/devcontainer:latest` as
their base — including this repository's `Dockerfile.OpenCode`
layer — pushing a new base to `ghcr.io` does **not** propagate the
change. The derived image or devcontainer must be rebuilt against
the new base explicitly.

Concretely, for a downstream consumer:

1. Wait for this repository's `main` branch CI to complete (the
   multi-arch push step then publishes the new tag).
2. `docker pull ghcr.io/cwimmer/devcontainer:latest` in the
   downstream project's environment to refresh the local daemon.
3. Rebuild the derived image or devcontainer so its `FROM` clause
   resolves to the refreshed tag.

For this repository itself, the same three steps apply between
releases of the base image: any change to `Dockerfile` (including
this one) requires `Dockerfile.OpenCode` to be rebuilt by running
`make test_native_opencode` (or its CI equivalent) to consume the
updated base. The base push on its own is not sufficient.

This PR cannot exercise the downstream sequence; it is documented for
the implementer's future reference and will not be verified in this
change.

### CI verification (run by the workflow, not by me locally)

The modified `image-build.yaml` runs the BATS suite inside the
`build` job, on the runner's locally-loaded image, between the
local build and the publishing steps, with `--pull=never` so a
missing local image hard-fails rather than silently pulling from
the registry. PRs targeting `main` will exercise this path
automatically; I cannot trigger the workflow from this environment,
so I will report the YAML diff and the local-verification results
but not a green CI run.

### Checks I cannot perform from this environment

- A real `docker buildx build` invocation requires a Docker
  daemon. The current container has `docker` available but no
  daemon is running; the verification commands in steps 1-5 above
  cannot complete end-to-end here. The implementer (or a CI
  runner) is the only place these will execute.
- A live `Rebuild Container` inside VS Code against
  `.devcontainer/devcontainer.json` requires a host with the
  Dev Containers extension and a running Docker daemon. The
  `docker-in-docker` feature in `.devcontainer/devcontainer.json`
  is not exercised by this change and is not validated here.
- The `image-build.yaml` workflow can only be validated by opening
  a PR; the YAML change is reviewed for shape, not executed.

## Scope guardrails

In scope:

- One-line addition to the `apt-get install` block in `Dockerfile`.
- One row added to the "Installed tools" table in `README.md`.
- New `tests/test-file-support.bats` (4 `@test` blocks).
- Registering the new BATS file in `Makefile`'s `test` and
  `test_native` targets.
- Moving the BATS test step from the standalone `test` job into the
  `build` job in `.github/workflows/image-build.yaml`, and deleting
  the now-redundant `test` job. The multi-arch build and push steps
  remain unchanged.

Out of scope:

- Changing the base image (`FROM public.ecr.aws/ubuntu/ubuntu:24.04_stable`).
- Changing `Dockerfile.OpenCode`, `.devcontainer/devcontainer.json`,
  `scripts/update-versions.sh`, or `.pre-commit-config.yaml`.
- Adding a version pin (`ARG FILE_VERSION`) or an `upgrade-file`
  Makefile target.
- Modifying any existing BATS file
  (`test-bats-support.bats`, `test-gh-support.bats`,
  `test-opencode-support.bats`).
- Verifying downstream consumers (documented, not run).
- `docs/wiki/` updates (directory does not exist in this repository,
  so the wiki-context instruction is N/A).

## Expected outcome

After implementation, the verification sequence above (steps 1-5)
confirms: the `default` builder uses the `docker` driver; both the
base and the OpenCode image build successfully against the same
local context and platform; `file --version`, text-file
identification, and ELF-binary identification all succeed inside
the base image (steps 3); and the same three invocations succeed
inside the OpenCode image under its development user (root, step
5), which is the load-bearing evidence that `file` propagated
through the layer chain.

CI behaviour changes: PRs now run the BATS suite against the image
built from the PR's own revision (inside the `build` job, between
the local build and the publishing steps, with `--pull=never`),
instead of pulling the previously-published `latest` tag from the
registry on a separate runner. The multi-arch build and push steps,
asdf plugins, OpenCode layer, pre-commit hooks, and existing
devcontainer behaviour remain intact. The Makefile
`test_native_opencode` target is unchanged (it routes through the
Makefile's `builder` Buildx instance, whose driver is not
guaranteed to be `docker`); the implementation does not rely on it
for verification.