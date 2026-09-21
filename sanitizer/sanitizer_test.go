package sanitizer_test

import (
	"bytes"
	"strings"
	"sync"
	"testing"

	"github.com/yamlstar/yamlstar-plugin-json-comments/sanitizer"
)

func TestSanitize(t *testing.T) {
	input := []byte("a: true// comment\r\nb: 'http://example.com'\n")
	got, err := sanitizer.Sanitize(input)
	if err != nil {
		t.Fatal(err)
	}
	want := []byte("a: true\r\nb: 'http://example.com'\n")
	if !bytes.Equal(got, want) {
		t.Fatalf("got %q, want %q", got, want)
	}
}

func TestErrors(t *testing.T) {
	for _, input := range [][]byte{[]byte("true/* unfinished"), {0xff}} {
		if _, err := sanitizer.Sanitize(input); err == nil {
			t.Fatalf("accepted %q", input)
		}
	}
}

func TestConcurrent(t *testing.T) {
	const callers = 8
	var wait sync.WaitGroup
	errors := make(chan error, callers)
	for range callers {
		wait.Add(1)
		go func() {
			defer wait.Done()
			output, err := sanitizer.Sanitize(
				[]byte("a: true // comment\n"))
			if err == nil && strings.Contains(string(output), "comment") {
				err = bytes.ErrTooLarge
			}
			errors <- err
		}()
	}
	wait.Wait()
	close(errors)
	for err := range errors {
		if err != nil {
			t.Fatal(err)
		}
	}
}
