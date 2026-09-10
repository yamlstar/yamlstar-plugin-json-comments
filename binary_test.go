package main

import (
	"fmt"
	"os"
	"strings"
	"testing"

	"github.com/glojurelang/glojure/pkg/glj"
	"github.com/glojurelang/glojure/pkg/lang"
	binaryevents "github.com/yamlstar/yaml-events-binary-protocol/glojure"
)

func TestBinaryEquivalence(t *testing.T) {
	for _, input := range []string{
		"", "// comment\n", "a: true// comment\nb: foo// text\n",
		"[null, true, false, 1, 'two', \"ascii\\0\\n\"]",
		"%YAML 1.2\n---\na: &x [!!str 1, !local value]\nb: *x\n...\n--- {}\n",
		"literal: |\n  // content\nfolded: >\n  folded\n  lines\n",
		"? [a, b]\n: {x: y}\n",
	} {
		packet, err := parseBinary(input, "{}")
		if err != nil {
			t.Fatalf("binary %q: %v", input, err)
		}
		decoded, err := binaryevents.Decode(packet)
		if err != nil {
			t.Fatal(err)
		}
		original := glj.Var("yamlstar-plugin.json-comments", "parse-events").Invoke(input, "{}")
		if !lang.Equals(original, decoded) {
			t.Fatalf("events differ for %q", input)
		}
	}
	for _, input := range []string{"[unterminated", "x: true/* unfinished"} {
		if _, err := parseBinary(input, "{}"); err == nil {
			t.Fatalf("accepted invalid input %q", input)
		}
	}
	if _, err := parseBinary("x", "[]"); err == nil {
		t.Fatal("accepted invalid options")
	}
}

// BenchmarkTransport isolates the serialization cost from the parser.
// YAMLStar's integration benchmark additionally measures complete FFI loads.
func BenchmarkTransport(b *testing.B) {
	if err := initialize(); err != nil {
		b.Fatal(err)
	}
	parseEvents := glj.Var("yamlstar-plugin.json-comments", "parse-events")
	for _, size := range []int{1024, 32 * 1024, 240 * 1024} {
		for _, kind := range []string{"scalars", "strings"} {
			input := makeJSONFixture(size)
			if kind == "strings" {
				input = "value: \"" + strings.Repeat("x", size) + "\"\n"
			}
			vector := parseEvents.Invoke(input, "{}")
			packet, err := binaryevents.Encode(vector)
			if err != nil {
				b.Fatal(err)
			}
			prefix := fmt.Sprintf("%s/%d", kind, size)
			for _, operation := range []struct {
				name  string
				bytes int
				run   func()
			}{
				{"binary/encode", len(packet), func() {
					if _, err := binaryevents.Encode(vector); err != nil {
						b.Fatal(err)
					}
				}},
				{"binary/decode", len(packet), func() {
					if _, err := binaryevents.Decode(packet); err != nil {
						b.Fatal(err)
					}
				}},
			} {
				operation.run()
				b.Run(prefix+"/"+operation.name, func(b *testing.B) {
					b.ReportAllocs()
					b.ResetTimer()
					for i := 0; i < b.N; i++ {
						operation.run()
					}
					b.StopTimer()
					b.ReportMetric(float64(operation.bytes), "wire-bytes")
				})
			}
		}
	}
}

func TestBinaryPreservesUnicode(t *testing.T) {
	input := "[\"λ\\0\\n\", 注]"
	packet, err := parseBinary(input, "{}")
	if err != nil {
		t.Fatal(err)
	}
	decoded, err := binaryevents.Decode(packet)
	if err != nil {
		t.Fatal(err)
	}
	original := glj.Var("yamlstar-plugin.json-comments", "parse-events").Invoke(input, "{}")
	if !lang.Equals(original, decoded) {
		t.Fatal("binary changed Unicode events")
	}
	value := lang.NewKeyword("value").Invoke(decoded.Nth(3))
	if value != "λ\x00\n" {
		t.Fatalf("Unicode scalar: %q", value)
	}

}

// Wire measurements are separate from ordinary correctness tests.
func TestBinaryWireSizes(t *testing.T) {
	if os.Getenv("YAMLSTAR_BINARY_SIZES") == "" {
		t.Skip("run make binary-sizes")
	}
	if err := initialize(); err != nil {
		t.Fatal(err)
	}
	for _, size := range []int{1024, 32 * 1024, 240 * 1024} {
		for _, kind := range []string{"scalars", "strings"} {
			input := makeJSONFixture(size)
			if kind == "strings" {
				input = "value: \"" + strings.Repeat("x", size) + "\"\n"
			}
			vector := glj.Var("yamlstar-plugin.json-comments", "parse-events").Invoke(input, "{}")
			packet, err := binaryevents.Encode(vector)
			if err != nil {
				t.Fatal(err)
			}
			fmt.Printf("WIRE %s/%d %d\n", kind, size, len(packet))
		}
	}
}
