# YAMLStar JSON Comments Plugin

This repository builds the JSON comments event-source plugin for YAMLStar.
The plugin accepts UTF-8 input through the YAMLStar shared-plugin ABI and
returns YAMLStar parser events as EDN.

Version 0.1 supports Unix shared libraries.
It deliberately has no installation or download side effects.

Build it against the adjacent YAMLStar worktree and reference parser:

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
