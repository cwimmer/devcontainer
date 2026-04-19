# devcontainer

A Docker container used as the base for development containers.
Includes common CLI tools managed by [asdf](https://asdf-vm.com/).

## Installed tools

| Tool | Manager |
| ---- | ------- |
| terraform | asdf |
| golang | asdf |
| helm | asdf |
| kind | asdf |
| kubectl | asdf |
| kubectx | asdf |
| kubens | asdf (via kubectx) |
| terraform-docs | asdf |
| tflint | asdf |
| trivy | asdf |
| doctl | binary |
| pre-commit | pipx |
| commitizen | pipx |

The published `ghcr.io/cwimmer/devcontainer:opencode` image layers
Node.js and OpenCode on top of the base tool set.

## Using default tool versions

The container ships a `.tool-versions`-compatible file at
`/usr/local/share/asdf-tool-versions` containing the default versions
of all asdf-managed tools.

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

### Upgrading tool versions

```sh
make upgrade       # update all tools to latest versions
```
