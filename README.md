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
| `Dockerfile` | Base development tools | Published as `ghcr.io/cwimmer/devcontainer:latest` |
| `Dockerfile.OpenCode` | Base tools, Node.js, and OpenCode v1 | The published `ghcr.io/cwimmer/devcontainer:opencode` image layers Node.js and OpenCode on top of the base tool set. |
| `Dockerfile.OpenCode2` | Standalone OpenCode v2 on the base tools, without Node.js | Locally buildable at this stage; no published v2 image is documented. |

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

```sh
make test          # multi-platform build (amd64 + arm64)
make test_opencode # multi-platform OpenCode image build (amd64 + arm64)
make test_native   # native platform only (faster)
make test_native_opencode # native OpenCode image build (faster)
```

### Testing

The BATS test suite lives in `tests/test-*.bats` and asserts that the
devcontainer's tooling, upgrade workflow, and OpenCode wiring stay
consistent. Run `make test` for the multi-platform build or
`make test_native` for the faster native build; both invoke the suite
inside the freshly built devcontainer image.

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

Build and verify the standalone v2 image directly (the version comparison
checks the runtime-reported version against the Dockerfile pin):

```sh
docker build -f Dockerfile.OpenCode2 -t devcontainer-opencode2-local .
expected=$(sed -n 's/^ARG OPENCODE_VERSION=//p' Dockerfile.OpenCode2)
actual=$(docker run --rm --pull=never devcontainer-opencode2-local opencode --version) &&
  actual=${actual##* } && test "${actual#v}" = "$expected"
```

The existing `make test_native` and `make test_native_opencode` targets build
and check the base and v1 images, respectively; they do not build or establish
runtime verification for v2. Use the direct build and version comparison above
for v2 verification.

When adding a new asdf-managed tool to this repository, update these
together: `Dockerfile`, the `/usr/local/share/asdf-tool-versions`
block in `Dockerfile`, `scripts/update-versions.sh`, `Makefile`,
`README.md`, and any related smoke tests.
