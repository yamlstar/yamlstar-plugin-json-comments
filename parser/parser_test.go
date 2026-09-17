package parser_test

import (
	"reflect"
	"strings"
	"sync"
	"testing"

	"github.com/glojurelang/glojure/pkg/glj"
	"github.com/glojurelang/glojure/pkg/lang"
	"github.com/yamlstar/yamlstar-plugin-json-comments/parser"
)

func TestGoAndEDNEvents(t *testing.T) {
	input := "%YAML 1.2\n--- {a: &a [!!str 1, 'λ🧩'], b: *a} // comment\n"
	events, err := parser.Parse([]byte(input))
	if err != nil {
		t.Fatal(err)
	}
	edn, err := parser.ParseEDN(input, "{}")
	if err != nil {
		t.Fatal(err)
	}
	// Independently reconstruct EDN maps from the Go API and compare values.
	maps := make([]any, len(events))
	for i, event := range events {
		pairs := []any{lang.NewKeyword("event"), event.Type}
		for name, value := range map[string]string{
			"value": event.Value, "anchor": event.Anchor, "tag": event.Tag,
			"name": event.Name, "version": event.Version, "style": event.Style,
		} {
			if value != "" || (name == "value" && event.Type == "scalar") {
				pairs = append(pairs, lang.NewKeyword(name), value)
			}
		}
		if event.Type == "mapping_start" || event.Type == "sequence_start" {
			pairs = append(pairs, lang.NewKeyword("flow"), event.Flow)
		}
		if event.Explicit {
			pairs = append(pairs, lang.NewKeyword("explicit"), true)
		}
		maps[i] = lang.NewMap(pairs...)
	}
	want := glj.Var("clojure.core", "read-string").Invoke(edn)
	if !lang.Equiv(lang.NewVector(maps...), want) {
		t.Fatalf("Go events differ from EDN: %s", edn)
	}
	again, err := parser.Parse([]byte(input))
	if err != nil || !reflect.DeepEqual(events, again) {
		t.Fatalf("repeat parse: %v", err)
	}
}

func TestErrors(t *testing.T) {
	for _, input := range [][]byte{[]byte("true/* unfinished"), {0xff}} {
		if _, err := parser.Parse(input); err == nil {
			t.Fatalf("accepted %q", input)
		}
	}
	if _, err := parser.ParseEDN("x", "[]"); err == nil || !strings.Contains(err.Error(), "EDN map") {
		t.Fatalf("got %v", err)
	}
}

func TestEDNPreservesUnicodeAndControls(t *testing.T) {
	text, err := parser.ParseEDN("value: \"a\\0b\\nλ\"\n", "{}")
	if err != nil {
		t.Fatal(err)
	}
	decoded := glj.Var("clojure.core", "read-string").Invoke(text)
	value := "a\x00b\nλ"
	found := false
	for seq := lang.Seq(decoded); seq != nil; seq = seq.Next() {
		item := seq.First()
		if lang.Get(item, lang.NewKeyword("value")) == value {
			found = true
		}
	}
	if !found {
		t.Fatalf("EDN lost scalar %q: %s", value, text)
	}
}

// Exercise both Go entry points together because they share generated
// parser state.
func TestConcurrentEntryPoints(t *testing.T) {
	var wg sync.WaitGroup
	for range 8 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for range 20 {
				events, err := parser.Parse([]byte("[true/* yes */, false]"))
				if err != nil || len(events) != 8 {
					t.Errorf("Go parse: %d events, %v", len(events), err)
				}
				text, err := parser.ParseEDN("[true/* yes */, false]", "{}")
				if err != nil || !strings.Contains(text, "stream_end") {
					t.Errorf("EDN parse: %q, %v", text, err)
				}
			}
		}()
	}
	wg.Wait()
}
