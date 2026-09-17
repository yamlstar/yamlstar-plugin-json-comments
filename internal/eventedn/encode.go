// Package eventedn writes YAMLStar parser events without losing Unicode.
package eventedn

import (
	"encoding/json"
	"fmt"
	"strings"
	"unicode/utf8"

	"github.com/glojurelang/glojure/pkg/lang"
)

var fields = [...]string{
	"event", "value", "anchor", "tag", "style", "name", "version",
	"flow", "explicit",
}

var keys = func() []lang.Keyword {
	result := make([]lang.Keyword, len(fields))
	for i, field := range fields {
		result[i] = lang.NewKeyword(field)
	}
	return result
}()

// Encode writes the event vector as EDN accepted by existing YAMLStar hosts.
func Encode(events any) (string, error) {
	vector, ok := events.(lang.IPersistentVector)
	if !ok {
		return "", fmt.Errorf("events must be a vector")
	}
	var output strings.Builder
	output.WriteByte('[')
	for seq := vector.Seq(); seq != nil; seq = seq.Next() {
		event, ok := seq.First().(lang.IPersistentMap)
		if !ok {
			return "", fmt.Errorf("event must be a map")
		}
		if output.Len() > 1 {
			output.WriteByte(' ')
		}
		output.WriteByte('{')
		count := 0
		for i, key := range keys {
			if !event.ContainsKey(key) {
				continue
			}
			if count > 0 {
				output.WriteByte(' ')
			}
			count++
			output.WriteByte(':')
			output.WriteString(fields[i])
			output.WriteByte(' ')
			value := event.ValAt(key)
			if i < 7 {
				text, ok := value.(string)
				if !ok || !utf8.ValidString(text) {
					return "", fmt.Errorf("invalid event field %s", fields[i])
				}
				quoted, err := json.Marshal(text)
				if err != nil {
					return "", err
				}
				output.Write(quoted)
			} else {
				flag, ok := value.(bool)
				if !ok {
					return "", fmt.Errorf("invalid event field %s", fields[i])
				}
				if flag {
					output.WriteString("true")
				} else {
					output.WriteString("false")
				}
			}
		}
		if count == 0 || count != event.Count() ||
			!event.ContainsKey(keys[0]) {
			return "", fmt.Errorf("invalid event fields")
		}
		output.WriteByte('}')
	}
	output.WriteByte(']')
	return output.String(), nil
}
