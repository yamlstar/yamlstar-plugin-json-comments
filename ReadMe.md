# YAMLStar JSON Comments Plugin

This repository builds the JSON comments event-source plugin for YAMLStar.
The plugin accepts UTF-8 input through the YAMLStar shared-plugin ABI and
returns YAMLStar parser events as EDN.

Version 0.1 supports Unix shared libraries.
It deliberately has no installation or download side effects.

The build downloads the same released reference-parser artifact used by
YAMLStar:

```sh
make build
```

Run the performance regression gate with:

```sh
make benchmark
```

This compares the plugin with the reference parser on a generated 240 KiB
document and checks sanitizer scaling from 256 KiB to 1 MiB.

Select the resulting library by adding its directory to the search path:

```sh
YAMLSTAR_LIBRARY_PATH=$PWD/lib yaml --plugin=json-comments
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
install -d "$HOME/.local/lib"
install -m 755 \
  lib/libyamlstar-plugin-json-comments.so \
  "$HOME/.local/lib/"
```

Use the `.dylib` filename on macOS.

## Python Wheels

Install the plugin for the YAMLStar Python binding with:

```sh
pip install yamlstar-plugin-json-comments
```

The package registers the plugin through the `yamlstar.plugins` entry-point
group.
YAMLStar bindings that support this entry point find the installed shared
library automatically when `json-comments` is selected.
The package also exposes `library_path()` and `library_dir()` from the
`yamlstar_plugin_json_comments` module.

Only platform wheels are published because installing from an sdist would
require compiling the native plugin locally.

Maintainers build and validate a release archive with:

```sh
make wheel VERSION=0.1.1
```

On Linux this runs the final shared-library build and archive checks in the
pinned manylinux container, so Docker must be available.
On macOS it builds natively and uses GNU tar as `gtar`.
The wheel wraps the library from that validated archive.

List the complete release process with:

```sh
make release-list
```

Publish an already-versioned first release with:

```sh
make release v=0.1.0
```

For subsequent releases, provide the old and new versions:

```sh
make release o=0.1.1 v=0.1.2
```

The interactive command checks the version and working tree, updates the
version files when needed, commits and tags the release, publishes the branch
and tag, then dispatches and watches the GitHub release workflow.
The workflow publishes the native archives and wheels to GitHub, then
publishes the wheels to PyPI.
PyPI trusted publishing must authorize the `release.yaml` workflow in the
`pypi` GitHub environment for the
`yamlstar/yamlstar-plugin-json-comments` repository.
Use `d=1` to preview the release without changing anything.
Use `a=1` to allow the full release command to run from a branch other than
`main`.
Retry a failed release workflow with:

```sh
make release-retry v=0.1.2
```

Before GitHub assets exist, retry updates the release tag and starts a new
workflow run.
After assets exist, it reruns the failed jobs so a failed PyPI publication can
resume without rebuilding or replacing immutable files.

The GitHub release workflow requires an existing plain version tag such as
`0.1.0`.
It does not download, build, or test YAMLStar.
