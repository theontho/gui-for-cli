#include "state.h"

#include "utils.h"

#include <cJSON.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

static char* state_path(const char* bundle_root) {
  const char* override = getenv("GUI_FOR_CLI_RAYGUI_C_STATE");
  if (override != NULL && override[0] != '\0') {
    return gfc_strdup(override);
  }
  return gfc_path_join(bundle_root, "state.json");
}

static bool mkdirs_for_file(const char* path, char** error) {
  char* copy = gfc_strdup(path);
  for (char* cursor = copy + 1; *cursor != '\0'; cursor++) {
    if (*cursor == '/') {
      *cursor = '\0';
      if (mkdir(copy, 0755) != 0 && errno != EEXIST) {
        size_t length = strlen(copy) + 48;
        *error = gfc_xmalloc(length);
        snprintf(*error, length, "create directory %s failed", copy);
        free(copy);
        return false;
      }
      *cursor = '/';
    }
  }
  free(copy);
  return true;
}

bool gfc_state_load(const char* bundle_root, char** selected_page_id, GfcStringMap* fields, char** error) {
  *selected_page_id = gfc_strdup("");
  char* path = state_path(bundle_root);
  if (!gfc_file_exists(path)) {
    free(path);
    return true;
  }
  char* text = gfc_read_file(path, error);
  if (text == NULL) {
    free(path);
    return false;
  }
  cJSON* root = cJSON_Parse(text);
  free(text);
  if (root == NULL) {
    size_t length = strlen(path) + 64;
    *error = gfc_xmalloc(length);
    snprintf(*error, length, "parse %s: %s", path, cJSON_GetErrorPtr());
    free(path);
    return false;
  }
  cJSON* selected = cJSON_GetObjectItem(root, "selectedPageID");
  if (cJSON_IsString(selected)) {
    free(*selected_page_id);
    *selected_page_id = gfc_strdup(selected->valuestring);
  }
  cJSON* values = cJSON_GetObjectItem(root, "fieldValues");
  cJSON* item = NULL;
  cJSON_ArrayForEach(item, values) {
    if (cJSON_IsString(item)) {
      gfc_map_set(fields, item->string, item->valuestring);
    } else if (cJSON_IsBool(item)) {
      gfc_map_set(fields, item->string, cJSON_IsTrue(item) ? "true" : "false");
    } else if (cJSON_IsNumber(item)) {
      char number[64];
      snprintf(number, sizeof(number), "%g", item->valuedouble);
      gfc_map_set(fields, item->string, number);
    }
  }
  cJSON_Delete(root);
  free(path);
  return true;
}

bool gfc_state_save(const char* bundle_root, const char* selected_page_id, const GfcStringMap* fields, char** error) {
  char* path = state_path(bundle_root);
  if (!mkdirs_for_file(path, error)) {
    free(path);
    return false;
  }
  cJSON* root = cJSON_CreateObject();
  cJSON_AddStringToObject(root, "selectedPageID", selected_page_id == NULL ? "" : selected_page_id);
  cJSON* values = cJSON_AddObjectToObject(root, "fieldValues");
  for (size_t index = 0; index < fields->count; index++) {
    cJSON_AddStringToObject(values, fields->items[index].key, fields->items[index].value);
  }
  char* encoded = cJSON_Print(root);
  cJSON_Delete(root);
  FILE* file = fopen(path, "wb");
  if (file == NULL) {
    size_t length = strlen(path) + 32;
    *error = gfc_xmalloc(length);
    snprintf(*error, length, "write %s failed", path);
    free(encoded);
    free(path);
    return false;
  }
  fputs(encoded, file);
  fclose(file);
  free(encoded);
  free(path);
  return true;
}

static char* parse_toml_value(const char* line) {
  const char* equals = strchr(line, '=');
  if (equals == NULL) {
    return NULL;
  }
  while (*++equals == ' ' || *equals == '\t') {}
  if (*equals == '"') {
    equals++;
    const char* end = strchr(equals, '"');
    if (end == NULL) {
      return NULL;
    }
    size_t length = (size_t)(end - equals);
    char* value = gfc_xcalloc(length + 1, 1);
    memcpy(value, equals, length);
    return value;
  }
  const char* end = equals;
  while (*end != '\0' && *end != '\n' && *end != '#') {
    end++;
  }
  while (end > equals && (*(end - 1) == ' ' || *(end - 1) == '\t')) {
    end--;
  }
  size_t length = (size_t)(end - equals);
  char* value = gfc_xcalloc(length + 1, 1);
  memcpy(value, equals, length);
  return value;
}

char* gfc_config_load_value(const GfcControl* control) {
  if (control->config_file_path[0] == '\0' || control->config_key[0] == '\0') {
    return NULL;
  }
  char* error = NULL;
  char* text = gfc_read_file(control->config_file_path, &error);
  free(error);
  if (text == NULL) {
    return NULL;
  }
  char* line = strtok(text, "\n");
  while (line != NULL) {
    char* equals = strchr(line, '=');
    if (equals != NULL) {
      size_t key_len = (size_t)(equals - line);
      while (key_len > 0 && (line[key_len - 1] == ' ' || line[key_len - 1] == '\t')) {
        key_len--;
      }
      if (strlen(control->config_key) == key_len && strncmp(line, control->config_key, key_len) == 0) {
        char* value = parse_toml_value(line);
        free(text);
        return value;
      }
    }
    line = strtok(NULL, "\n");
  }
  free(text);
  return NULL;
}

bool gfc_config_save_value(const GfcControl* control, const char* value, char** error) {
  if (control->config_file_path[0] == '\0' || control->config_key[0] == '\0') {
    return true;
  }
  if (!mkdirs_for_file(control->config_file_path, error)) {
    return false;
  }
  char* old_error = NULL;
  char* old = gfc_read_file(control->config_file_path, &old_error);
  free(old_error);
  size_t capacity = (old == NULL ? 0 : strlen(old)) + strlen(control->config_key) + strlen(value) + 64;
  char* output = gfc_xcalloc(capacity, 1);
  bool replaced = false;
  if (old != NULL) {
    char* save = NULL;
    char* line = strtok_r(old, "\n", &save);
    while (line != NULL) {
      char* equals = strchr(line, '=');
      bool matches = false;
      if (equals != NULL) {
        size_t key_len = (size_t)(equals - line);
        while (key_len > 0 && (line[key_len - 1] == ' ' || line[key_len - 1] == '\t')) {
          key_len--;
        }
        matches = strlen(control->config_key) == key_len && strncmp(line, control->config_key, key_len) == 0;
      }
      if (matches) {
        strcat(output, control->config_key);
        strcat(output, strcmp(control->kind, "toggle") == 0 ? " = " : " = \"");
        strcat(output, value);
        strcat(output, strcmp(control->kind, "toggle") == 0 ? "\n" : "\"\n");
        replaced = true;
      } else {
        strcat(output, line);
        strcat(output, "\n");
      }
      line = strtok_r(NULL, "\n", &save);
    }
  }
  if (!replaced) {
    strcat(output, control->config_key);
    strcat(output, strcmp(control->kind, "toggle") == 0 ? " = " : " = \"");
    strcat(output, value);
    strcat(output, strcmp(control->kind, "toggle") == 0 ? "\n" : "\"\n");
  }
  FILE* file = fopen(control->config_file_path, "wb");
  if (file == NULL) {
    size_t length = strlen(control->config_file_path) + 32;
    *error = gfc_xmalloc(length);
    snprintf(*error, length, "write %s failed", control->config_file_path);
    free(old);
    free(output);
    return false;
  }
  fputs(output, file);
  fclose(file);
  free(old);
  free(output);
  return true;
}
