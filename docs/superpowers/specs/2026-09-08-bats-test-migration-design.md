# Migrate ad hoc Bash tests to BATS

## Motivation

The repository's three test scripts — `tests/test-bats-support.sh`,
`tests/test-gh-support.sh`, `tests/test-opencode-support.sh` — are ad hoc
Bash harnesses that duplicate assertion helpers across files, exit on
first failure, and emit a single `PASS:` line that hides which
assertions were actually run. Migrating to BATS:

- preserves the existing behavioral coverage without weakening any
  assertion;
- gives each assertion a name, so failures are immediately
  diagnosable;
- lets the test runner collect and report results instead of bailing
  on the first failure;
- aligns the test framework with the same BATS tool the devcontainer
  already ships (`BATS_VERSION=1.14.0`).

## Conventions observed

- Tools are pinned via `ARG` values in `Dockerfile`, installed with the
  same pattern (asdf where applicable), surfaced through
  `/usr/local/share/asdf-tool-versions`, wired into
  `scripts/update-versions.sh` and `Makefile`, and listed in
  `README.md`.
- Test running is host-driven from `Makefile` and executed inside the
  built devcontainer image so behaviour matches what consumers see.
- `pre-commit` covers `yamllint`, `shellcheck`, and `actionlint` on the
  existing files.
- CI is split: `.github/workflows/image-build.yaml` builds and pushes
  images but does not run tests today.

## Chosen approach

1. Translate each `tests/test-*-support.sh` into a parallel
   `tests/test-*-support.bats` file, one assertion per `@test` block,
   using `bats-assert` and `bats-support`.
2. Install `bats-support` and `bats-assert` into the devcontainer
   image at `/usr/local/share/bats-support` and
   `/usr/local/share/bats-assert` via two pinned `ARG` values and two
   `git clone --branch v<version>` lines in `Dockerfile`. The helpers
   are git-tagged libraries, not GitHub-released binaries, so they do
   not get added to `scripts/update-versions.sh`.
3. Run the BATS suite from the host by `docker run`-ing the built
   image with the whole repo bind-mounted in: `docker run --rm -e
   ASDF_BATS_VERSION=$(BATS_VERSION) -v $(CURDIR):/repo -w /repo/tests
   <image> bats test-bats-support.bats test-gh-support.bats
   test-opencode-support.bats`. The full-repo mount is required
   because `tests/test_helper/common.bash` resolves `REPO_ROOT` from
   `BATS_TEST_DIRNAME`'s parent.
4. Extend the existing `shellcheck-py` pre-commit hook so it also
   lints `.bats` files and follows `load` directives.
5. Add a `test` job to `.github/workflows/image-build.yaml` that builds
   the base image and runs the BATS suite.
6. Delete the three `tests/test-*-support.sh` files once the `.bats`
   versions are passing locally and in CI.

## Alternatives considered

1. **One combined `tests.bats` file.** Breaks the existing
   one-script-per-tool convention. Rejected.
2. **Vendor `bats-support` / `bats-assert` as git submodules.**
   Mirrors the `superpowers` submodule pattern but introduces a second
   submodule, which the repository explicitly avoided for tool
   management. Rejected.
3. **Run BATS on the host instead of in the container.** Diverges
   from the existing `make test` pattern, which already shells into
   the built image for verification. Rejected.
4. **Skip the CI job addition.** Leaves test execution to developer
   machines; CI only builds images, which fails the success criterion
   "CI, Makefile targets, scripts, and other test entry points execute
   the new BATS suite successfully". Rejected.

## Detailed design

### 1. `Dockerfile`

Add two `ARG`s in the existing version block:

```dockerfile
ARG BATS_ASSERT_VERSION=2.1.0
ARG BATS_SUPPORT_VERSION=0.3.0
```

Add a new section after the existing asdf-managed tools but before
`/usr/local/share/asdf-tool-versions`:

```dockerfile
# BATS helper libraries (loaded from /usr/local/share/bats-{support,assert} by .bats tests)
RUN git clone --depth 1 --branch v$BATS_SUPPORT_VERSION \
        https://github.com/bats-core/bats-support.git /usr/local/share/bats-support
RUN git clone --depth 1 --branch v$BATS_ASSERT_VERSION \
        https://github.com/bats-core/bats-assert.git /usr/local/share/bats-assert
```

Do **not** add `bats-support` / `bats-assert` to
`scripts/update-versions.sh`: they are git-tagged bash libraries, not
GitHub-released binaries with versioned API responses, and there is no
precedent in the repo for upgrading git-cloned libraries. They are
pinned manually via the `ARG` values, which is the same pattern used
for `doctl` (pinned in `Dockerfile`, no upgrade script).

### 2. `tests/test_helper/common.bash`

A small shared helper that every `.bats` file loads. It exposes
`REPO_ROOT`.

```bash
# Resolve REPO_ROOT once. BATS_TEST_DIRNAME is the directory of the .bats file
# (i.e. tests/), so its parent is the repository root.
REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
export REPO_ROOT
```

No other shared abstraction unless three or more tests need it
(YAGNI).

### 3. `tests/test-bats-support.bats`

Translates the 6 assertions of `tests/test-bats-support.sh` 1:1, with
one substitution noted below:

The original's static `RUN asdf install bats $BATS_VERSION` line
check is replaced by a dynamic `update-versions.sh --tool bats
--check-only` invocation. This exercises more of the upgrade
workflow but is no longer a literal 1:1 translation of the original
assertion.

```bash
#!/usr/bin/env bats

load 'test_helper/common'
load '/usr/local/share/bats-support/load'
load '/usr/local/share/bats-assert/load'

@test "make upgrade-bats target is available" {
    run make -s -n -C "$REPO_ROOT" upgrade-bats
    assert_success
}

@test "upgrade check for bats succeeds" {
    run bash "$REPO_ROOT/scripts/update-versions.sh" --tool bats --check-only
    assert_success
}

@test "Dockerfile pins BATS_VERSION" {
    run grep -Fq -- "ARG BATS_VERSION=" "$REPO_ROOT/Dockerfile"
    assert_success
}

@test "Dockerfile installs bats via asdf" {
    run grep -Fq -- "RUN asdf plugin add bats https://github.com/timgluz/asdf-bats.git" "$REPO_ROOT/Dockerfile"
    assert_success
}

@test "Dockerfile includes bats in asdf-tool-versions generation" {
    run grep -Fq -- "\"bats \$BATS_VERSION\" \\" "$REPO_ROOT/Dockerfile"
    assert_success
}

@test "README lists bats as asdf-managed" {
    run grep -Fq -- '| bats | asdf |' "$REPO_ROOT/README.md"
    assert_success
}
```

Note: grep patterns that contain shell metacharacters (`$`,
backslashes) are written with **double quotes and escaped `$`** so
that shellcheck does not flag SC2016 and the test passes through the
pre-commit hook. The original `.sh` tests used the same encoding
style; the bats files mirror it.

### 4. `tests/test-gh-support.bats`

Translates the 5 assertions of `tests/test-gh-support.sh` 1:1. Same
shape as section 3 with `gh` substituted. The grep pattern for the
apt-install line uses `"apt-get install -y gh=\$GH_VERSION"` (double
quotes, escaped `$`) for the same reason. The original script had a
sixth assertion checking for `ARG GH_VERSION=`, which was dropped as
redundant with the apt-install-line check that was kept.

### 5. `tests/test-opencode-support.bats`

Translates the 10 assertions of `tests/test-opencode-support.sh`
1:1. Uses `assert_output "2"` for the `--platform linux/arm64 \\`
count assertion:

```bash
@test "Makefile targets linux/arm64 platform twice" {
    run grep -Fc -- "--platform linux/arm64 \\" "$REPO_ROOT/Makefile"
    assert_output "2"
}
```

The `$(CONTAINER_NAME):$(OPENCODE_TAG)` Makefile patterns use the
same double-quoted, escaped-`$` encoding as section 3.

### 6. `Makefile`

In `test:` and `test_native:`, replace:

```makefile
./tests/test-bats-support.sh
./tests/test-gh-support.sh
```

with:

```makefile
docker run --rm -e ASDF_BATS_VERSION=$(BATS_VERSION) \
    -v $(CURDIR):/repo -w /repo/tests \
    $(CONTAINER_NAME):$(TAG) \
    bats test-bats-support.bats test-gh-support.bats test-opencode-support.bats
```

Notes on this invocation:

- The container mount must include the **whole repo** (`/repo`), not
  only `tests/`, because `tests/test_helper/common.bash` resolves
  `REPO_ROOT` from `BATS_TEST_DIRNAME`'s parent (the repo root).
- `ASDF_BATS_VERSION=$(BATS_VERSION)` is needed so the asdf bats
  shim (installed via `Dockerfile:75`) finds a version — the existing
  `Makefile` works around this by `sh -lc`-symlinking
  `/usr/local/share/asdf-tool-versions` to `~/.tool-versions`; passing
  the env var directly is the simpler equivalent.
- bats takes one or more file arguments; passing three files runs the
  three suites sequentially in a single container.

(`test_opencode:` and `test_native_opencode:` do not invoke any tests
today and are not changed; their wiring is asserted by
`tests/test-opencode-support.bats`.)

### 7. `.pre-commit-config.yaml`

Extend the existing hook:

```yaml
  - repo: https://github.com/shellcheck-py/shellcheck-py
    rev: v0.11.0.1
    hooks:
      - id: shellcheck
        files: \.(bash|sh|bats)$
        args: [-x]
```

The primary change is the `files:` regex, which makes the hook match
`.bats` files (pre-commit's type detector does not classify `.bats` as
shell, so shellcheck was previously skipping them entirely). The
`args: [-x]` is mostly a no-op for the `.bats` files themselves —
shellcheck does not recognize bats's `load` as a shell directive — but
it does follow `source` directives inside the loaded helper libraries
(e.g. `bats-support/load.bash` and `bats-assert/load.bash`), which use
`source` to pull in additional files.

### 8. `.github/workflows/image-build.yaml`

Add a single-platform build step to the existing `build` job that
loads the image into the runner's local docker daemon, then add a
new `test` job that consumes the loaded image without rebuilding.

The existing `build` job gains one new step before the multi-arch
build:

```yaml
      - name: Build base image for local testing
        uses: docker/build-push-action@v7
        with:
          context: .
          load: true
          tags: ghcr.io/cwimmer/devcontainer:latest
          platforms: linux/amd64
```

The new `test` job consumes the loaded image and runs the suite:

```yaml
  test:
    runs-on: ubuntu-latest
    needs: build
    steps:
      - name: Checkout repository
        uses: actions/checkout@v6

      - name: Run BATS suite inside the built image
        run: |
          docker run --rm \
            -e ASDF_BATS_VERSION=1.14.0 \
            -v ${{ github.workspace }}:/repo \
            -w /repo/tests \
            ghcr.io/cwimmer/devcontainer:latest \
            bats test-bats-support.bats test-gh-support.bats test-opencode-support.bats
```

This avoids the duplicate build that would otherwise happen because
`docker/build-push-action` cannot `--load` a multi-platform image.
The test job consumes the single-platform build directly, so it no
longer needs to check out the repo or set up Buildx.

Note: the `test` job uses `linux/amd64`. The base image is
platform-agnostic (all tools work on any platform), so this is
sufficient coverage for the BATS suite, which only inspects file
contents and Makefile/Dockerfile wiring.

### 9. `README.md`

Add a short `## Testing` subsection (under `### Building`) with one
paragraph:

> Run `make test` (multi-platform, slower) or `make test_native` (native
> platform, faster) to execute the BATS test suite inside the built
> image. Tests live in `tests/test-*.bats` and assert that the
> devcontainer's tooling, upgrade workflow, and OpenCode wiring are
> all consistent.

### 10. `docs/superpowers/specs/2026-04-25-bats-devcontainer-design.md`

Update the "Out of scope" section to explicitly note that the smoke
test (`tests/test-bats-support.sh`) introduced in that design has been
migrated to BATS as part of the 2026-09-08 BATS migration. Bump the
file's `updated:` frontmatter to `2026-09-08`.

(There is no `docs/wiki/` directory in this repository, so no wiki
updates are needed. The `llm-wiki` skill is not available in this
environment.)

### 11. Cleanup

After the new `.bats` files pass both locally (`make test_native`) and
in CI, delete:

- `tests/test-bats-support.sh`
- `tests/test-gh-support.sh`
- `tests/test-opencode-support.sh`

## Verification plan

1. Run the new bats suite directly:

   ```bash
   docker run --rm -e ASDF_BATS_VERSION=1.14.0 \
     -v "$(pwd):/repo" -w /repo/tests \
     ghcr.io/cwimmer/devcontainer:latest \
     bats test-bats-support.bats test-gh-support.bats test-opencode-support.bats
   ```

   Expected: 21 `@test` blocks pass.
2. Run `make test_native`. Expected: image builds, bats version
   reports present, BATS suite passes.
3. Run `make pre-commit`. Expected: shellcheck lints the new `.bats`
   files without warnings (if it raises SC2317-style warnings, add
   targeted `# shellcheck disable=...` directives inline with
   comments justifying each).
4. Push to a branch and confirm the new `test` job in
   `.github/workflows/image-build.yaml` passes.
5. Cause a representative assertion to fail (e.g. temporarily edit
   `Dockerfile` to remove `BATS_VERSION`), confirm BATS prints the
   failing `@test` name and a useful diff. Revert.
6. `git status --short` should show only the intended changes:
   `Dockerfile`, `tests/test_helper/common.bash`, three new `.bats`
   files, three deleted `.sh` files, `Makefile`,
   `.github/workflows/image-build.yaml`, `.pre-commit-config.yaml`,
   `README.md`, and the spec note in
   `docs/superpowers/specs/2026-04-25-bats-devcontainer-design.md`.

## Scope guardrails

In scope:

- Translating the three existing tests into BATS with `bats-assert`.
- Installing `bats-support` and `bats-assert` into the devcontainer
  image.
- Updating `Makefile`, CI, pre-commit, and `README.md`.
- Updating the existing bats-devcontainer spec note.

Out of scope:

- Running BATS against the OpenCode image (the `test_opencode` target
  builds the image; no existing test exercises it, and adding that is
  a separate piece of work).
- Adding `bats-support` / `bats-assert` to `scripts/update-versions.sh`
  (they are git-tagged libraries, not GitHub-released binaries).
- Refactoring the three tests into shared abstractions beyond the
  single `REPO_ROOT` helper.
- `docs/wiki/` updates (directory does not exist in this repo).
- Production code changes (none required).

## Tests whose semantics may shift

| Behavior change | Old | New | Risk |
|---|---|---|---|
| Tests now run inside the docker image | Bash tests required only `make`/`grep`/`bash` on host | BATS requires the image to have built | Low — image build is already part of `test`/`test_native`; this just makes the dependency explicit |
| Test execution halts on first failure | `set -euo pipefail` + manual `fail` helpers | BATS continues per-file, reports all results | Improvement |
| Single `PASS:` summary line | One line per script at end | Per-`@test` pass/fail with diffs on failure | Improvement |
| Pre-commit shellcheck still lints the test files | Yes (via `.sh` type detection) | Yes (via explicit `files:` regex) | None — coverage is preserved |
| Network call to GitHub releases API in `update-versions.sh --check-only` | Required | Same | None — same dependency as today |

## Expected outcome

After implementation, running `make test` (or `make test_native`, or
the new CI `test` job) executes the BATS suite inside the built
devcontainer image with one named `@test` per existing assertion.
Failures are immediately diagnosable, the ad hoc assertion helpers
are gone, and the devcontainer image ships the helper libraries
needed to run the suite. No production behaviour changes.
