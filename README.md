# devcontainer

A Docker container used as the base for development containers.
Includes common CLI tools managed by [asdf](https://asdf-vm.com/).

## Installed tools

| Tool | Manager |
| ---- | ------- |
| terraform | asdf |
| golang | asdf |
| bats | asdf |
| helm | asdf |
| kind | asdf |
| kubectl | asdf |
| kubectx | asdf |
| kubens | asdf (via kubectx) |
| terraform-docs | asdf |
| tflint | asdf |
| trivy | asdf |
| doctl | binary |
| gh | apt |
| file | apt |
| pre-commit | pipx |
| commitizen | pipx |

## Image variants

| Dockerfile | Image recipe | Availability |
| ---------- | ------------ | ------------ |
| `Dockerfile` | Base development tools | `ghcr.io/cwimmer/devcontainer:latest` |
| `Dockerfile.OpenCode` | Base tools, Node.js, and OpenCode v1 | `ghcr.io/cwimmer/devcontainer:opencode` |
| `Dockerfile.OpenCode2` | Base tools and standalone OpenCode v2, without Node.js | Configured publication destination: `ghcr.io/cwimmer/devcontainer:opencode2` |

## Using default tool versions

The image installs all asdf-managed tools and ships a
`.tool-versions`-compatible file at
`/usr/local/share/asdf-tool-versions` containing their default
versions. Those tools become active when asdf finds a
`.tool-versions` file in the current directory or home directory.

For ad hoc `docker run` checks, the supported path is to link
`/usr/local/share/asdf-tool-versions` to `~/.tool-versions` before
invoking the tool.

You can adopt these defaults in your project using either method:

### Option 1: Symlink

```sh
ln -s /usr/local/share/asdf-tool-versions .tool-versions
```

This makes your project use the container's default versions. The
symlink target updates automatically when the container is rebuilt.

**Note:** The symlink points into the container filesystem and will be
broken outside the devcontainer. Add `.tool-versions` to your
`.gitignore` to avoid committing it:

```sh
echo '.tool-versions' >> .gitignore
```

### Option 2: Global home symlink

Create a symlink in your home directory so asdf uses the container's
defaults globally:

> **Note:** This will overwrite any existing `~/.tool-versions`.

```sh
ln -sf /usr/local/share/asdf-tool-versions ~/.tool-versions
```

**Note:** The home directory is ephemeral in most devcontainers — this
symlink is lost when the container is rebuilt. To persist it, add the
`ln` command to your dotfiles or a `postCreateCommand` in
`devcontainer.json`.

This applies to all directories that don't have a project-level
`.tool-versions` file.

### Overriding individual tools

If you need a different version of one tool, create your own
`.tool-versions` file in your project instead of symlinking. You can
copy the defaults as a starting point:

```sh
cp /usr/local/share/asdf-tool-versions .tool-versions
```

Then edit the version for the tool you want to change.

## Development

### Building

The verification targets cover the base image, OpenCode v1, and OpenCode v2.
The `test*` targets build both `linux/amd64` and `linux/arm64`; the
`test_native*` targets build only the host's native platform. Each target runs
runtime checks on the locally loaded image for the relevant variant. A
multi-platform target also loads its native-platform image for those runtime
checks; it does not runtime-test the other architecture.

```sh
make test                    # base: multi-platform build, native runtime checks
make test_opencode           # v1: multi-platform build, native runtime checks
make test_opencode2          # v2: multi-platform build, native runtime checks
make test_native             # base: host-native build and runtime checks
make test_native_opencode    # v1: host-native build and runtime checks
make test_native_opencode2   # v2: host-native build and runtime checks
```

The v1 and v2 targets depend on the base target, which independently builds and
checks the base image from this checkout. That local base image is not passed to
the derived-image build: derived builds explicitly resolve their base from the
published `ghcr.io/cwimmer/devcontainer:latest` image. The v2 image is configured
for the `opencode2` destination above; this configuration alone is not evidence
of a completed registry publication.

### Testing

The BATS test suite lives in `tests/test-*.bats` and asserts that the
devcontainer's tooling, upgrade workflow, and OpenCode wiring stay
consistent. The base targets invoke the suite inside the freshly built base
image; the derived-image targets first run their base prerequisite and then
build and check the requested OpenCode variant.

### Upgrading tool versions

```sh
make upgrade                  # base tools plus stable OpenCode 1.x and 2.x
make upgrade-opencode         # OpenCode v1 only
make upgrade-opencode2        # OpenCode v2 only
bash scripts/update-versions.sh --all --check-only
bash scripts/update-versions.sh --tool opencode2 --version 2.0.29
```

For OpenCode, discovery selects the highest canonical stable 1.x version for
`opencode` and 2.x version for `opencode2`. Explicit OpenCode versions must
also be canonical stable versions, and the two updates are independent. Other
tools retain their existing source behavior. Node.js continues to target only
`Dockerfile.OpenCode` (v1).

Use `make test_native_opencode2` to build and verify v2 on the host-native
platform, or `make test_opencode2` to build both supported platforms and verify
the native image. The v2 runtime check compares the reported OpenCode version
with the pin in `Dockerfile.OpenCode2`. These checks establish local build and
runtime results only; report workflow/CI execution and registry publication as
separate evidence.

When adding a new asdf-managed tool to this repository, update these
together: `Dockerfile`, the `/usr/local/share/asdf-tool-versions`
block in `Dockerfile`, `scripts/update-versions.sh`, `Makefile`,
`README.md`, and any related smoke tests.
