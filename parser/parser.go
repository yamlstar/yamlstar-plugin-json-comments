// Package parser is a compatibility adapter that sanitizes JSON-style
// comments and then invokes the YAMLStar reference parser.
package parser

import (
	"github.com/yamlstar/yamlstar-plugin-json-comments/sanitizer"
	reference "github.com/yamlstar/yamlstar-plugin-parser-reference/parser"
)

// Event is a reference-parser event.
type Event = reference.Event

// Initialize loads the sanitizer and reference parser namespaces.
func Initialize() error {
	if err := sanitizer.Initialize(); err != nil {
		return err
	}
	return reference.Initialize()
}

// Parse sanitizes input and returns reference-parser events.
func Parse(input []byte) ([]Event, error) {
	clean, err := sanitizer.Sanitize(input)
	if err != nil {
		return nil, err
	}
	return reference.Parse(clean)
}
