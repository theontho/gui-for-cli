#pragma once

#include <stddef.h>

typedef struct {
  char* key;
  char* value;
} GfcStringPair;

typedef struct {
  GfcStringPair* items;
  size_t count;
  size_t capacity;
} GfcStringMap;

void gfc_map_init(GfcStringMap* map);
void gfc_map_free(GfcStringMap* map);
const char* gfc_map_get(const GfcStringMap* map, const char* key);
void gfc_map_set(GfcStringMap* map, const char* key, const char* value);
char* gfc_localize(const GfcStringMap* map, const char* key, const char* fallback);
void gfc_merge_toml_strings(GfcStringMap* map, const char* path);
