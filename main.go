package main

/*
#include <stdint.h>
#include <stdlib.h>
*/
import "C"

import (
	_ "embed"
	"fmt"
	"unsafe"

	"github.com/yamlstar/yamlstar-plugin-json-comments/sanitizer"
)

//go:embed plugin.edn
var manifest string

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

//export yamlstar_plugin_v2_abi
func yamlstar_plugin_v2_abi() C.uint64_t {
	return 2
}

//export yamlstar_plugin_v2_manifest
func yamlstar_plugin_v2_manifest(
	output **C.uint8_t,
	length *C.size_t,
) C.int32_t {
	return writeBytes([]byte(manifest), output, length)
}

//export yamlstar_plugin_v2_transform
func yamlstar_plugin_v2_transform(
	input *C.uint8_t, inputLength C.size_t,
	options *C.uint8_t, optionsLength C.size_t,
	output **C.uint8_t, outputLength *C.size_t,
) C.int32_t {
	if output == nil || outputLength == nil {
		return 2
	}
	*output = nil
	*outputLength = 0
	maxLength := uint64(^uint32(0))
	if (input == nil && inputLength != 0) ||
		(options == nil && optionsLength != 0) ||
		uint64(inputLength) > maxLength || uint64(optionsLength) > maxLength {
		_ = writeBytes([]byte("invalid input buffer"), output, outputLength)
		return 2
	}
	inputBytes := unsafe.Slice((*byte)(unsafe.Pointer(input)), int(inputLength))
	result, err := sanitizer.Sanitize(inputBytes)
	if err != nil {
		_ = writeBytes([]byte(err.Error()), output, outputLength)
		return 1
	}
	return writeBytes(result, output, outputLength)
}

//export yamlstar_plugin_v2_free
func yamlstar_plugin_v2_free(output *C.uint8_t) {
	C.free(unsafe.Pointer(output))
}

func main() {
	if manifest == "" {
		panic(fmt.Errorf("plugin manifest is empty"))
	}
}
