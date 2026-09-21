# YAMLStar JSON Comments Plugin

This repository provides the experimental `json-comments` plugin API's
`sanitizer` implementation.
It recognizes JSON-style comments in UTF-8 YAML source, removes their text,
preserves their line endings, and passes the transformed source to the parser
selected by the host.

The sanitizer is independent of a particular YAML parser.
It can be combined with go-yaml, the YAML reference parser, SnakeYAML, or
another parser implementation supplied by the host.
See the [syntax rules](Syntax.md) for exact comment placement and scalar
boundaries.

## Go packages

The `sanitizer` package exposes the text transformation directly:

```go
import "github.com/yamlstar/yamlstar-plugin-json-comments/sanitizer"

clean, err := sanitizer.Sanitize(
    []byte("a: true // comment\n"),
)
```

The `parser` package is a compatibility adapter for existing Go callers.
It sanitizes the input and then uses
`github.com/yamlstar/yamlstar-plugin-parser-reference`:

```go
import "github.com/yamlstar/yamlstar-plugin-json-comments/parser"

events, err := parser.Parse([]byte("a: true // comment\n"))
```

New hosts should compose `sanitizer.Sanitize` with their selected parser
instead of depending on the compatibility adapter.
Both packages are safe for concurrent callers.

## JVM artifact

Clojure and Java hosts use the Clojars artifact directly:

```clojure
[org.yamlstar/yamlstar-plugin-json-comments "0.1.9"]
```

The artifact contains the Clojure sanitizer source.
It does not need a native library or GraalVM.
Build it locally with:

```sh
make jar
```

Publish it manually with configured Clojars credentials by running:

```sh
make deploy-clojars VERSION=0.1.9
```

## Native shared plugin

The native plugin uses YAMLStar shared ABI version 2.
Its manifest identifies plugin API `json-comments`, implementation
`sanitizer`, version `0.1.9`, and kind `text-transform`.
The transform input and successful output are raw UTF-8 bytes.
Only the manifest and options value use EDN.

Build the shared library with:

```sh
make build
```

Select it in YAMLStar after adding its directory to the library search path:

```sh
YAMLSTAR_LIBRARY_PATH=$PWD/lib \
  yaml --plugin=json-comments
```

Version 0.1 supports Unix shared libraries.
Linux releases require glibc 2.28 or newer.
The macOS artifacts are not Developer ID signed or notarized.

## Binary releases

Release archives use YAMLStar platform names:

```text
yamlstar-plugin-json-comments-VERSION-linux-x64.tar.xz
yamlstar-plugin-json-comments-VERSION-linux-aarch64.tar.xz
yamlstar-plugin-json-comments-VERSION-macos-x64.tar.xz
yamlstar-plugin-json-comments-VERSION-macos-arm64.tar.xz
```

Git tags and GitHub releases use only the `vVERSION` form starting with
`v0.1.9`.
Archive names and embedded manifest versions remain unprefixed.
Old tags and assets remain available.

Install the library for the current user by copying it from the unpacked
archive:

```sh
install -d "$HOME/.local/lib"
install -m 755 \
  lib/libyamlstar-plugin-json-comments.so \
  "$HOME/.local/lib/"
```

Use the `.dylib` filename on macOS.

## Python wheels

Install the native plugin for the YAMLStar Python binding with:

```sh
pip install yamlstar-plugin-json-comments
```

The wheel registers the distribution through the `yamlstar.plugins` entry
point and exposes `library_path()` and `library_dir()` from the
`yamlstar_plugin_json_comments` module.
Only platform wheels are published because an sdist would require compiling
the plugin locally.

## Release process

List the release steps with:

```sh
make release-list
```

After changing the source to the next version, run:

```sh
make release o=0.1.8 v=0.1.9
```

The command validates the source, commits the version bump, creates only the
`v0.1.9` tag, and starts the GitHub release workflow.
The workflow publishes the JVM artifact to Clojars, native archives and wheels
to GitHub, and wheels to PyPI.
The repository must provide `CLOJARS_USERNAME` and `CLOJARS_PASSWORD` secrets.
Use `d=1` to preview the process.
Use `a=1` to release from a branch other than `main`.

Retry a failed workflow with:

```sh
make release-retry v=0.1.9
```

A published Go module tag must never be moved.
Release a new version when tagged source needs a fix.
