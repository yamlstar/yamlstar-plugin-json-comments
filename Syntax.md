# JSON Comments Syntax

This plugin removes recognized JSON-style comments and sends the remaining
input to the selected YAML parser.
It extends YAML input with comments used by JSONC without adding other JSON5
syntax.

## Comment Forms

A line comment begins with `//` and continues up to, but not including, the
next carriage return or line feed.

A block comment begins with `/*` and ends at the first following `*/`.
Block comments do not nest.
An unterminated block comment is an error.

Comments may occur at the start of input or after YAML whitespace and flow
punctuation such as `[`, `]`, `{`, `}`, and `,`.
They may also directly follow quoted scalars, JSON literals, JSON numbers,
document markers, and block scalar headers.
Comments may appear between a quoted mapping key and its colon or between that
colon and its value.
Recognized comments are transparent, so these placements can be chained.

For example, this is accepted:

```yaml
{
  /* before */ "enabled" /* key */ : /* value */ true /* after */
}
```

The lowercase JSON literals are `null`, `true`, and `false`.
JSON numbers use the JSON number grammar, including negative, fractional, and
exponent forms.
A comment may directly follow those tokens without separating whitespace.

A comment after any other plain scalar requires separating whitespace.
An adjacent marker remains scalar content, so this mapping has the key
`foo/*bar*/`:

```yaml
{foo/*bar*/: null}
```

Markers inside quoted scalars and block scalar content remain part of the
scalar value.
This preserves strings such as `http://example.com` and block scalar text that
contains `/*` or `//`.

## Removal and Positions

Recognized comment text is removed before parsing.
Whitespace outside the comment is retained.
For example, `{a: b /*xxxxx*/ c}` produces the scalar value `b  c` because the
spaces on both sides of the block comment remain.

Line endings are retained, including line endings inside block comments.
Parser line numbers therefore continue to match the original input.
Columns following a removed comment refer to the comment-free input.

Comments are discarded and do not appear in parser events.
