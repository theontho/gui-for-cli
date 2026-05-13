#include "data_source.h"

#include "utils.h"

#include <cJSON.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static char* render_template(const GfcApp* app, const char* value) {
  char* rendered = gfc_interpolate_builtins(value, app->args.bundle);
  for (size_t index = 0; index < app->fields.count; index++) {
    char token[160];
    snprintf(token, sizeof(token), "{{%s}}", app->fields.items[index].key);
    char* next = gfc_replace_all(rendered, token, app->fields.items[index].value);
    free(rendered);
    rendered = next;
  }
  for (size_t index = 0; index < app->data_values.count; index++) {
    char token[160];
    snprintf(token, sizeof(token), "{{%s}}", app->data_values.items[index].key);
    char* next = gfc_replace_all(rendered, token, app->data_values.items[index].value);
    free(rendered);
    rendered = next;
  }
  return rendered;
}

static char* cache_key(const GfcApp* app, const GfcDataSource* source) {
  size_t length = strlen(source->path) + 64;
  for (size_t index = 0; index < source->arguments.count; index++) {
    length += strlen(source->arguments.items[index]) + 8;
  }
  for (size_t index = 0; index < app->fields.count; index++) {
    length += strlen(app->fields.items[index].key) + strlen(app->fields.items[index].value) + 4;
  }
  for (size_t index = 0; index < app->data_values.count; index++) {
    length += strlen(app->data_values.items[index].key) + strlen(app->data_values.items[index].value) + 4;
  }
  char* key = gfc_xcalloc(length, 1);
  strcat(key, source->path);
  for (size_t index = 0; index < source->arguments.count; index++) {
    strcat(key, "\x1f");
    strcat(key, source->arguments.items[index]);
  }
  for (size_t index = 0; index < app->fields.count; index++) {
    strcat(key, "\x1f");
    strcat(key, app->fields.items[index].key);
    strcat(key, "=");
    strcat(key, app->fields.items[index].value);
  }
  for (size_t index = 0; index < app->data_values.count; index++) {
    strcat(key, "\x1f");
    strcat(key, app->data_values.items[index].key);
    strcat(key, "=");
    strcat(key, app->data_values.items[index].value);
  }
  return key;
}

static char* data_source_command(const GfcApp* app, const GfcDataSource* source) {
  char* executable = source->path[0] == '/' ? gfc_strdup(source->path) : gfc_path_join(app->args.bundle, source->path);
  char** parts = gfc_xcalloc(source->arguments.count + 1, sizeof(char*));
  parts[0] = gfc_shell_quote(executable);
  for (size_t index = 0; index < source->arguments.count; index++) {
    char* rendered = render_template(app, source->arguments.items[index]);
    parts[index + 1] = gfc_shell_quote(rendered);
    free(rendered);
  }
  char* command = gfc_join_argv(parts, source->arguments.count + 1, " ");
  gfc_free_strings(parts, source->arguments.count + 1);
  char* cwd_path = source->working_directory[0] == '\0' ? gfc_strdup(app->args.bundle)
                                                        : render_template(app, source->working_directory);
  char* cwd = gfc_shell_quote(cwd_path);
  free(cwd_path);
  size_t length = strlen(cwd) + strlen(command) + 128;
  for (size_t index = 0; index < source->environment.count; index++) {
    length += strlen(source->environment.items[index].key) + strlen(source->environment.items[index].value) + 8;
  }
  char* full = gfc_xcalloc(length, 1);
  strcat(full, "cd ");
  strcat(full, cwd);
  strcat(full, " && GUI_FOR_CLI_DATA_SOURCE=1 ");
  for (size_t index = 0; index < source->environment.count; index++) {
    char* value = render_template(app, source->environment.items[index].value);
    char* quoted = gfc_shell_quote(value);
    strcat(full, source->environment.items[index].key);
    strcat(full, "=");
    strcat(full, quoted);
    strcat(full, " ");
    free(quoted);
    free(value);
  }
  strcat(full, command);
  strcat(full, " 2>/dev/null");
  free(cwd);
  free(command);
  free(executable);
  return full;
}

static cJSON* data_source_payload(GfcApp* app, const GfcDataSource* source) {
  char* key = cache_key(app, source);
  const char* cached = gfc_map_get(&app->data_source_cache, key);
  if (cached != NULL) {
    cJSON* parsed = cJSON_Parse(cached);
    free(key);
    return parsed;
  }
  char* command = data_source_command(app, source);
  FILE* pipe = popen(command, "r");
  free(command);
  if (pipe == NULL) {
    free(key);
    return NULL;
  }
  size_t capacity = 16384;
  size_t length = 0;
  char* output = gfc_xcalloc(capacity, 1);
  char buffer[1024];
  while (fgets(buffer, sizeof(buffer), pipe) != NULL && length < 1024 * 1024) {
    size_t chunk = strlen(buffer);
    if (length + chunk + 1 > capacity) {
      capacity = (capacity + chunk + 4096) * 2;
      output = gfc_xrealloc(output, capacity);
    }
    memcpy(output + length, buffer, chunk);
    length += chunk;
    output[length] = '\0';
  }
  int status = pclose(pipe);
  if (status != 0 || output[0] == '\0') {
    free(output);
    free(key);
    return NULL;
  }
  cJSON* parsed = cJSON_Parse(output);
  if (parsed != NULL) {
    gfc_map_set(&app->data_source_cache, key, output);
  }
  free(output);
  free(key);
  return parsed;
}

static char* json_scalar(cJSON* value) {
  if (cJSON_IsString(value)) {
    return gfc_strdup(value->valuestring);
  }
  if (cJSON_IsBool(value)) {
    return gfc_strdup(cJSON_IsTrue(value) ? "true" : "false");
  }
  if (cJSON_IsNumber(value)) {
    char buffer[64];
    snprintf(buffer, sizeof(buffer), "%g", value->valuedouble);
    return gfc_strdup(buffer);
  }
  char* encoded = cJSON_PrintUnformatted(value);
  char* result = gfc_strdup(encoded == NULL ? "" : encoded);
  free(encoded);
  return result;
}

static void extract_values(GfcApp* app, cJSON* payload) {
  cJSON* values = cJSON_GetObjectItem(payload, "values");
  cJSON* item = NULL;
  cJSON_ArrayForEach(item, values) {
    char* scalar = json_scalar(item);
    gfc_map_set(&app->data_values, item->string, scalar);
    free(scalar);
  }
}

bool gfc_data_source_refresh_page(GfcApp* app, const GfcPage* page) {
  gfc_map_free(&app->data_values);
  gfc_map_init(&app->data_values);
  bool ok = true;
  for (size_t index = 0; index < page->control_count; index++) {
    const GfcControl* control = &page->controls[index];
    if (control->data_source == NULL) {
      continue;
    }
    cJSON* payload = data_source_payload(app, control->data_source);
    if (payload == NULL) {
      ok = false;
      continue;
    }
    if (app->data_sources_loaded < app->bundle.data_source_count) {
      app->data_sources_loaded++;
    }
    extract_values(app, payload);
    cJSON_Delete(payload);
  }
  return ok;
}

char* gfc_data_source_control_text(GfcApp* app, const GfcControl* control) {
  if (control->data_source == NULL) {
    return gfc_strdup("No data source");
  }
  cJSON* payload = data_source_payload(app, control->data_source);
  if (payload == NULL) {
    return gfc_strdup("data source error");
  }
  char* result = NULL;
  cJSON* values = cJSON_GetObjectItem(payload, "values");
  cJSON* options = cJSON_GetObjectItem(payload, "options");
  cJSON* items = cJSON_GetObjectItem(payload, "items");
  if (cJSON_IsObject(values)) {
    result = cJSON_PrintUnformatted(values);
  } else if (cJSON_IsArray(options)) {
    size_t count = (size_t)cJSON_GetArraySize(options);
    size_t length = 32;
    for (size_t index = 0; index < count; index++) {
      cJSON* item = cJSON_GetArrayItem(options, (int)index);
      cJSON* title = cJSON_GetObjectItem(item, "title");
      length += strlen(cJSON_IsString(title) ? title->valuestring : "option") + 4;
    }
    result = gfc_xcalloc(length, 1);
    strcat(result, "options: ");
    for (size_t index = 0; index < count; index++) {
      cJSON* item = cJSON_GetArrayItem(options, (int)index);
      cJSON* title = cJSON_GetObjectItem(item, "title");
      if (index > 0) strcat(result, ", ");
      strcat(result, cJSON_IsString(title) ? title->valuestring : "option");
    }
  } else if (cJSON_IsArray(items)) {
    char buffer[80];
    snprintf(buffer, sizeof(buffer), "items: %d rows", cJSON_GetArraySize(items));
    result = gfc_strdup(buffer);
  }
  cJSON_Delete(payload);
  return result == NULL ? gfc_strdup("data source: no rows") : result;
}

GfcOption* gfc_data_source_options(GfcApp* app, const GfcControl* control, size_t* count) {
  *count = 0;
  if (control->data_source == NULL) {
    return NULL;
  }
  cJSON* payload = data_source_payload(app, control->data_source);
  if (payload == NULL) {
    return NULL;
  }
  cJSON* options_json = cJSON_GetObjectItem(payload, "options");
  if (!cJSON_IsArray(options_json)) {
    cJSON_Delete(payload);
    return NULL;
  }
  *count = cJSON_GetArraySize(options_json);
  GfcOption* options = gfc_xcalloc(*count, sizeof(GfcOption));
  for (size_t index = 0; index < *count; index++) {
    cJSON* item = cJSON_GetArrayItem(options_json, (int)index);
    cJSON* id = cJSON_GetObjectItem(item, "id");
    cJSON* title = cJSON_GetObjectItem(item, "title");
    options[index].id = gfc_strdup(cJSON_IsString(id) ? id->valuestring : "");
    options[index].title = gfc_strdup(cJSON_IsString(title) ? title->valuestring : options[index].id);
    options[index].selected = cJSON_IsTrue(cJSON_GetObjectItem(item, "selected"));
  }
  cJSON_Delete(payload);
  return options;
}

static bool condition_matches(const GfcCondition* condition, const GfcStringMap* context) {
  const char* value = gfc_map_get(context, condition->placeholder);
  if (value == NULL) value = "";
  if (condition->has_exists && condition->exists != (value[0] != '\0')) return false;
  if (condition->equals != NULL && strcmp(value, condition->equals) != 0) return false;
  if (condition->not_equals != NULL && strcmp(value, condition->not_equals) == 0) return false;
  if (condition->in_values.count > 0) {
    bool found = false;
    for (size_t index = 0; index < condition->in_values.count; index++) {
      found = found || strcmp(value, condition->in_values.items[index]) == 0;
    }
    if (!found) return false;
  }
  if (condition->not_in_values.count > 0) {
    for (size_t index = 0; index < condition->not_in_values.count; index++) {
      if (strcmp(value, condition->not_in_values.items[index]) == 0) return false;
    }
  }
  return true;
}

static char* render_with_context(const GfcStringMap* context, const char* value) {
  char* rendered = gfc_strdup(value);
  for (size_t index = 0; index < context->count; index++) {
    char token[160];
    snprintf(token, sizeof(token), "{{%s}}", context->items[index].key);
    char* next = gfc_replace_all(rendered, token, context->items[index].value);
    free(rendered);
    rendered = next;
  }
  return rendered;
}

static void materialize_action(const GfcAction* source, const GfcStringMap* context, const char* prefix, GfcAction* out) {
  memset(out, 0, sizeof(GfcAction));
  out->id = render_with_context(context, source->id);
  char* title = render_with_context(context, source->title);
  out->title = prefix == NULL || prefix[0] == '\0' ? title : NULL;
  if (out->title == NULL) {
    size_t length = strlen(prefix) + strlen(title) + 4;
    out->title = gfc_xmalloc(length);
    snprintf(out->title, length, "%s: %s", prefix, title);
    free(title);
  }
  out->role = gfc_strdup(source->role);
  out->executable = render_with_context(context, source->executable);
  out->arguments.count = source->arguments.count;
  out->arguments.items = gfc_xcalloc(out->arguments.count, sizeof(char*));
  for (size_t index = 0; index < source->arguments.count; index++) {
    out->arguments.items[index] = render_with_context(context, source->arguments.items[index]);
  }
  out->optional_argument_count = source->optional_argument_count;
  out->optional_arguments = gfc_xcalloc(out->optional_argument_count, sizeof(GfcArgumentGroup));
  for (size_t index = 0; index < out->optional_argument_count; index++) {
    out->optional_arguments[index].arguments.count = source->optional_arguments[index].arguments.count;
    out->optional_arguments[index].arguments.items =
        gfc_xcalloc(out->optional_arguments[index].arguments.count, sizeof(char*));
    for (size_t arg = 0; arg < out->optional_arguments[index].arguments.count; arg++) {
      out->optional_arguments[index].arguments.items[arg] =
          render_with_context(context, source->optional_arguments[index].arguments.items[arg]);
    }
  }
  gfc_map_init(&out->environment);
  for (size_t index = 0; index < source->environment.count; index++) {
    char* value = render_with_context(context, source->environment.items[index].value);
    gfc_map_set(&out->environment, source->environment.items[index].key, value);
    free(value);
  }
  out->working_directory = render_with_context(context, source->working_directory);
  out->disabled_tooltip = render_with_context(context, source->disabled_tooltip);
}

GfcAction* gfc_data_source_row_actions(GfcApp* app, const GfcPage* page, size_t* count) {
  *count = 0;
  GfcAction* actions = NULL;
  for (size_t control_index = 0; control_index < page->control_count; control_index++) {
    const GfcControl* control = &page->controls[control_index];
    if (control->data_source == NULL || control->row_action_count == 0) {
      continue;
    }
    cJSON* payload = data_source_payload(app, control->data_source);
    cJSON* items = payload == NULL ? NULL : cJSON_GetObjectItem(payload, "items");
    if (!cJSON_IsArray(items)) {
      cJSON_Delete(payload);
      continue;
    }
    cJSON* item = NULL;
    cJSON_ArrayForEach(item, items) {
      cJSON* row_values = cJSON_GetObjectItem(item, "values");
      if (!cJSON_IsObject(row_values)) continue;
      GfcStringMap context;
      gfc_map_init(&context);
      for (size_t field = 0; field < app->fields.count; field++) {
        gfc_map_set(&context, app->fields.items[field].key, app->fields.items[field].value);
      }
      cJSON* row_value = NULL;
      cJSON_ArrayForEach(row_value, row_values) {
        char* scalar = json_scalar(row_value);
        gfc_map_set(&context, row_value->string, scalar);
        char row_key[160];
        snprintf(row_key, sizeof(row_key), "row.%s", row_value->string);
        gfc_map_set(&context, row_key, scalar);
        free(scalar);
      }
      cJSON* title_json = cJSON_GetObjectItem(item, "title");
      const char* row_title = cJSON_IsString(title_json) ? title_json->valuestring : gfc_map_get(&context, "name");
      for (size_t action_index = 0; action_index < control->row_action_count; action_index++) {
        const GfcAction* source = &control->row_actions[action_index];
        bool visible = true;
        for (size_t condition = 0; condition < source->visible_count; condition++) {
          visible = visible && condition_matches(&source->visible_when[condition], &context);
        }
        if (!visible) continue;
        actions = gfc_xrealloc(actions, (*count + 1) * sizeof(GfcAction));
        materialize_action(source, &context, row_title == NULL ? "row" : row_title, &actions[*count]);
        *count += 1;
      }
      gfc_map_free(&context);
    }
    cJSON_Delete(payload);
  }
  return actions;
}

void gfc_data_source_free_options(GfcOption* options, size_t count) {
  for (size_t index = 0; index < count; index++) {
    free(options[index].id);
    free(options[index].title);
  }
  free(options);
}

void gfc_data_source_free_actions(GfcAction* actions, size_t count) {
  for (size_t index = 0; index < count; index++) {
    gfc_action_free(&actions[index]);
  }
  free(actions);
}
