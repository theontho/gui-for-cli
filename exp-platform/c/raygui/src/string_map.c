#include "string_map.h"

#include "utils.h"

#include <stdbool.h>
#include <stdlib.h>
#include <string.h>

void gfc_map_init(GfcStringMap* map) {
  map->items = NULL;
  map->count = 0;
  map->capacity = 0;
}

void gfc_map_free(GfcStringMap* map) {
  for (size_t index = 0; index < map->count; index++) {
    free(map->items[index].key);
    free(map->items[index].value);
  }
  free(map->items);
  gfc_map_init(map);
}

const char* gfc_map_get(const GfcStringMap* map, const char* key) {
  for (size_t index = 0; index < map->count; index++) {
    if (strcmp(map->items[index].key, key) == 0) {
      return map->items[index].value;
    }
  }
  return NULL;
}

void gfc_map_set(GfcStringMap* map, const char* key, const char* value) {
  for (size_t index = 0; index < map->count; index++) {
    if (strcmp(map->items[index].key, key) == 0) {
      free(map->items[index].value);
      map->items[index].value = gfc_strdup(value);
      return;
    }
  }
  if (map->count == map->capacity) {
    map->capacity = map->capacity == 0 ? 16 : map->capacity * 2;
    map->items = gfc_xrealloc(map->items, map->capacity * sizeof(GfcStringPair));
  }
  map->items[map->count].key = gfc_strdup(key);
  map->items[map->count].value = gfc_strdup(value);
  map->count++;
}

char* gfc_localize(const GfcStringMap* map, const char* key, const char* fallback) {
  if (key == NULL || key[0] == '\0') {
    return gfc_strdup(fallback);
  }
  const char* value = gfc_map_get(map, key);
  return gfc_strdup(value == NULL ? key : value);
}

static char* parse_quoted(const char* start) {
  const char* first = strchr(start, '"');
  if (first == NULL) {
    return NULL;
  }
  const char* cursor = first + 1;
  char* value = gfc_xcalloc(strlen(cursor) + 1, 1);
  char* out = value;
  bool escaped = false;
  while (*cursor != '\0') {
    if (escaped) {
      *out++ = *cursor == 'n' ? '\n' : *cursor;
      escaped = false;
    } else if (*cursor == '\\') {
      escaped = true;
    } else if (*cursor == '"') {
      return value;
    } else {
      *out++ = *cursor;
    }
    cursor++;
  }
  free(value);
  return NULL;
}

void gfc_merge_toml_strings(GfcStringMap* map, const char* path) {
  if (!gfc_file_exists(path)) {
    return;
  }
  char* error = NULL;
  char* text = gfc_read_file(path, &error);
  free(error);
  if (text == NULL) {
    return;
  }
  char* line = strtok(text, "\n");
  while (line != NULL) {
    char* equals = strchr(line, '=');
    if (equals != NULL) {
      char* key = parse_quoted(line);
      char* value = parse_quoted(equals + 1);
      if (key != NULL && value != NULL) {
        gfc_map_set(map, key, value);
      }
      free(key);
      free(value);
    }
    line = strtok(NULL, "\n");
  }
  free(text);
}
