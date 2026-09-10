package main

/*
#include <stdint.h>
#include <stdlib.h>
*/
import "C"

import (
	_ "embed"
	"fmt"
	"strconv"
	"sync"
	"unsafe"

	"github.com/glojurelang/glojure/pkg/glj"
	"github.com/glojurelang/glojure/pkg/lang"
	binaryevents "github.com/yamlstar/yaml-events-binary-protocol/glojure"
	_ "github.com/yamlstar/yamlstar-plugin-json-comments/internal/glojure/pkg/yaml_parser/core"
	_ "github.com/yamlstar/yamlstar-plugin-json-comments/internal/glojure/pkg/yaml_parser/grammar"
	_ "github.com/yamlstar/yamlstar-plugin-json-comments/internal/glojure/pkg/yaml_parser/parser"
	_ "github.com/yamlstar/yamlstar-plugin-json-comments/internal/glojure/pkg/yaml_parser/prelude"
	_ "github.com/yamlstar/yamlstar-plugin-json-comments/internal/glojure/pkg/yaml_parser/receiver"
	_ "github.com/yamlstar/yamlstar-plugin-json-comments/internal/glojure/pkg/yamlstar_plugin/json_comments"
)

//go:embed plugin.edn
var manifest string

var initializeOnce sync.Once
var initializeErr error

func initialize() error {
	initializeOnce.Do(func() {
		defer func() {
			if value := recover(); value != nil {
				initializeErr = fmt.Errorf("initialize plugin: %v", value)
			}
		}()
		require := glj.Var("clojure.core", "require")
		for _, namespace := range []string{
			"yaml-parser.prelude",
			"yaml-parser.grammar",
			"yaml-parser.parser",
			"yaml-parser.receiver",
			"yaml-parser.core",
			"yamlstar-plugin.json-comments",
		} {
			require.Invoke(lang.NewSymbol(namespace))
		}
	})
	return initializeErr
}

func writeOutput(text string, output **C.uint8_t, length *C.size_t) C.int32_t {
	return writeBytes([]byte(text), output, length)
}

func writeBytes(data []byte, output **C.uint8_t, length *C.size_t) C.int32_t {
	if output == nil || length == nil {
		return 2
	}
	var pointer unsafe.Pointer
	if len(data) > 0 {
		pointer = C.CBytes(data)
	}
	*output = (*C.uint8_t)(pointer)
	*length = C.size_t(len(data))
	return 0
}

func parseBinary(input, options string) (output []byte, err error) {
	if err := initialize(); err != nil {
		return nil, err
	}
	defer func() {
		if value := recover(); value != nil {
			output = nil
			err = fmt.Errorf("%v", value)
		}
	}()
	value := glj.Var("yamlstar-plugin.json-comments", "parse-events").Invoke(input, options)
	return binaryevents.Encode(value)
}

func errorEDN(kind string, err error) string {
	return "{:error {:type " + strconv.Quote(kind) +
		" :message " + strconv.Quote(err.Error()) + " :data {}}}"
}

//export yamlstar_plugin_v1_abi
func yamlstar_plugin_v1_abi() C.uint64_t {
	return 1
}

//export yamlstar_plugin_v1_manifest
func yamlstar_plugin_v1_manifest(
	output **C.uint8_t,
	length *C.size_t,
) C.int32_t {
	return writeOutput(manifest, output, length)
}

//export yamlstar_plugin_v1_free
func yamlstar_plugin_v1_free(output *C.uint8_t) {
	C.free(unsafe.Pointer(output))
}

func main() {}
