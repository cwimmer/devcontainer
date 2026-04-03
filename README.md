# devcontainer

A Docker container used as the base for development containers.
Includes common CLI tools managed by [asdf](https://asdf-vm.com/).

## Installed tools

| Tool | Manager |
|------|---------|
| terraform | asdf |
| golang | asdf |
| kubectl | asdf |
| terraform-docs | asdf |
| tflint | asdf |
| trivy | asdf |
| doctl | binary |
| pre-commit | pipx |
| commitizen | pipx |

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

### Option 2: Environment variable

Add to your shell profile or `.envrc`:

```sh
export ASDF_TOOL_VERSIONS_FILENAME=/usr/local/share/asdf-tool-versions
```

This tells asdf to use the container's file globally without creating
a `.tool-versions` in your project directory.

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
make test_native   # native platform only (faster)
```

### Upgrading tool versions

```sh
make upgrade       # update all tools to latest versions
```
