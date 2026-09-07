package main

import (
	"fmt"
	"os"
	"runtime"
	"strings"
	"testing"
	"time"

	"github.com/glojurelang/glojure/pkg/glj"
)

const performanceTestEnv = "YAMLSTAR_PERFORMANCE_TEST"

func makeJSONFixture(minimumBytes int) string {
	var output strings.Builder
	output.Grow(minimumBytes + 32)
	output.WriteByte('{')
	for index := 0; output.Len() < minimumBytes; index++ {
		if index > 0 {
			output.WriteByte(',')
		}
		fmt.Fprintf(&output, "%q:%d", fmt.Sprint(index), index)
	}
	output.WriteString("}\n")
	return output.String()
}

func makeCommentFixture(minimumBytes int) string {
	const line = "value: true // comment\n"
	return strings.Repeat(line, minimumBytes/len(line)+1)
}

func elapsed(operation func()) time.Duration {
	runtime.GC()
	start := time.Now()
	operation()
	return time.Since(start)
}

func TestPerformance(t *testing.T) {
	if os.Getenv(performanceTestEnv) == "" {
		t.Skip("run with make benchmark")
	}
	if err := initialize(); err != nil {
		t.Fatal(err)
	}

	parseReference := glj.Var("yaml-parser.core", "parse")
	printValue := glj.Var("clojure.core", "pr-str")
	sanitize := glj.Var(
		"yamlstar-plugin.json-comments", "sanitize-comments")
	input := makeJSONFixture(240 * 1024)

	// Initialize parser paths before measuring either one.
	printValue.Invoke(parseReference.Invoke("{}\n"))
	if _, err := parse("{}\n", "{}"); err != nil {
		t.Fatal(err)
	}

	var referenceOutput string
	referenceTime := elapsed(func() {
		referenceOutput = printValue.Invoke(
			parseReference.Invoke(input)).(string)
	})
	var pluginOutput string
	pluginTime := elapsed(func() {
		var err error
		pluginOutput, err = parse(input, "{}")
		if err != nil {
			t.Fatal(err)
		}
	})
	t.Logf("240 KiB reference: %s", referenceTime)
	t.Logf("240 KiB plugin:    %s", pluginTime)
	if referenceTime > 15*time.Second {
		t.Fatalf("reference parser exceeded 15 seconds: %s",
			referenceTime)
	}
	if pluginOutput != referenceOutput {
		t.Fatal("marker-free plugin output differs from reference output")
	}
	if pluginTime > 2*referenceTime {
		t.Fatalf("plugin took more than 2x reference: %s versus %s",
			pluginTime, referenceTime)
	}

	smallInput := makeCommentFixture(256 * 1024)
	largeInput := makeCommentFixture(1024 * 1024)
	sanitize.Invoke("value: true // comment\n")
	smallTime := elapsed(func() { sanitize.Invoke(smallInput) })
	largeTime := elapsed(func() { sanitize.Invoke(largeInput) })
	t.Logf("256 KiB sanitizer: %s", smallTime)
	t.Logf("1 MiB sanitizer:   %s", largeTime)
	if largeTime > 6*smallTime {
		t.Fatalf("sanitizer scaling is not near-linear: %s versus %s",
			largeTime, smallTime)
	}
}
