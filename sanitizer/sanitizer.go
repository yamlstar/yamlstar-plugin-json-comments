// Package sanitizer removes JSON-style comments from YAML input.
package sanitizer

import (
	"fmt"
	"sync"
	"unicode/utf8"

	"github.com/glojurelang/glojure/pkg/glj"
	"github.com/glojurelang/glojure/pkg/lang"

	_ "github.com/yamlstar/yamlstar-plugin-json-comments/internal/glojure/pkg/yamlstar_plugin/json_comments"
)

// Version is the plugin release version.
const Version = "0.1.9"

var (
	sanitizeMu     sync.Mutex
	initializeOnce sync.Once
	initializeErr  error
)

// Initialize loads the generated sanitizer namespace once.
func Initialize() error {
	initializeOnce.Do(func() {
		defer func() {
			if value := recover(); value != nil {
				initializeErr = fmt.Errorf("initialize plugin: %v", value)
			}
		}()
		glj.Var("clojure.core", "require").Invoke(
			lang.NewSymbol("yamlstar-plugin.json-comments"))
	})
	return initializeErr
}

// Sanitize removes recognized JSON-style comments while preserving line
// endings and comment markers inside scalar content.
func Sanitize(input []byte) (output []byte, err error) {
	sanitizeMu.Lock()
	defer sanitizeMu.Unlock()
	if !utf8.Valid(input) {
		return nil, fmt.Errorf("json-comments input must be UTF-8")
	}
	if err := Initialize(); err != nil {
		return nil, err
	}
	defer func() {
		if value := recover(); value != nil {
			output = nil
			if cause, ok := value.(error); ok {
				err = fmt.Errorf("sanitize: %w", cause)
			} else {
				err = fmt.Errorf("sanitize: %v", value)
			}
		}
	}()
	value := glj.Var(
		"yamlstar-plugin.json-comments", "sanitize-comments").Invoke(
		string(input))
	text, ok := value.(string)
	if !ok {
		return nil, fmt.Errorf("sanitizer returned %T", value)
	}
	return []byte(text), nil
}
