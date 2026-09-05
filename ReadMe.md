# YAMLStar JSON Comments Plugin

This repository builds the JSON comments event-source plugin for YAMLStar.
The plugin accepts UTF-8 input through the YAMLStar shared-plugin ABI and
returns YAMLStar parser events as EDN.

Version 0.1 supports Unix shared libraries.
It deliberately has no installation or download side effects.

Build it against a reference-parser checkout at
`repos/yaml-reference-parser-clj`, or against an adjacent checkout when this
repository is used from a YAMLStar worktree:

```sh
make build
```

Select the resulting library by adding its directory to the search path:

```sh
YAMLSTAR_PLUGIN_PATH=$PWD/lib yaml --plugin=json-comments
```

The plugin recognizes `//` line comments and `/* ... */` block comments.
A comment can directly follow JSON literals and numbers.
A comment after any other plain scalar requires separating whitespace.

## Binary Releases

Experimental releases provide native shared libraries for Linux and macOS on
x86-64 and ARM64.
Linux release libraries require glibc 2.28 or newer.
The initial macOS artifacts are not Developer ID signed or notarized.

The release archives use the same platform names as YAMLStar:

```text
yamlstar-plugin-json-comments-VERSION-linux-x64.tar.xz
yamlstar-plugin-json-comments-VERSION-linux-aarch64.tar.xz
yamlstar-plugin-json-comments-VERSION-macos-x64.tar.xz
yamlstar-plugin-json-comments-VERSION-macos-arm64.tar.xz
```

Install the library for the current user by copying it from the unpacked
archive:

```sh
install -d "$HOME/.local/lib/yamlstar/plugins"
install -m 755 \
  lib/yamlstar/plugins/libyamlstar-plugin-json-comments.so \
  "$HOME/.local/lib/yamlstar/plugins/"
```

Use the `.dylib` filename on macOS.

Maintainers build and validate a release archive with:

```sh
make dist VERSION=0.1.0
```

On Linux this runs the final shared-library build and archive checks in the
pinned manylinux container, so Docker must be available.
On macOS it builds natively and uses GNU tar as `gtar`.

The GitHub release workflow is dispatched manually with an existing plain
version tag such as `0.1.0`.
It does not download, build, or test YAMLStar.
