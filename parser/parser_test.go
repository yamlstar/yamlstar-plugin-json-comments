package parser_test

import (
	"reflect"
	"testing"

	"github.com/yamlstar/yamlstar-plugin-json-comments/parser"
)

func TestParse(t *testing.T) {
	events, err := parser.Parse([]byte(
		"%YAML 1.2\n--- {a: &a [!!str 1, 'lambda'], b: *a} // comment\n"))
	if err != nil {
		t.Fatal(err)
	}
	var scalars []string
	for _, event := range events {
		if event.Type == "scalar" {
			scalars = append(scalars, event.Value)
		}
	}
	if want := []string{"a", "1", "lambda", "b"}; !reflect.DeepEqual(scalars, want) {
		t.Fatalf("scalars: got %q, want %q", scalars, want)
	}
}

func TestErrors(t *testing.T) {
	for _, input := range [][]byte{[]byte("true/* unfinished"), {0xff}} {
		if _, err := parser.Parse(input); err == nil {
			t.Fatalf("accepted %q", input)
		}
	}
}
