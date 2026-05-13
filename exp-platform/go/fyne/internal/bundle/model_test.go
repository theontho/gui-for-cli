package bundle

import (
	"encoding/json"
	"testing"
)

func TestListItemUnmarshalRootValuesOverrideNestedValues(t *testing.T) {
	var item ListItem
	data := []byte(`{"id":"root-id","status":"root-status","values":{"id":"nested-id","name":"Nested","status":"nested-status"}}`)

	if err := json.Unmarshal(data, &item); err != nil {
		t.Fatal(err)
	}

	if item.Values["id"] != "root-id" {
		t.Fatalf("id = %q, want root-id", item.Values["id"])
	}
	if item.Values["status"] != "root-status" {
		t.Fatalf("status = %q, want root-status", item.Values["status"])
	}
	if item.Values["name"] != "Nested" {
		t.Fatalf("name = %q, want Nested", item.Values["name"])
	}
}
