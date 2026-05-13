#include "bundle.h"

#include "utils.h"

#include <cJSON.h>
#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static char* json_text(cJSON* value) {
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
  return gfc_strdup("");
}

static char* localized(cJSON* value, const GfcStringMap* strings, const char* fallback) {
  if (!cJSON_IsString(value)) {
    return gfc_strdup(fallback);
  }
  return gfc_localize(strings, value->valuestring, fallback);
}

static char* interpolated_json_text(cJSON* value, const char* bundle_root) {
  char* raw = json_text(value);
  char* rendered = gfc_interpolate_builtins(raw, bundle_root);
  free(raw);
  return rendered;
}

static cJSON* read_json(const char* path, char** error) {
  char* text = gfc_read_file(path, error);
  if (text == NULL) {
    return NULL;
  }
  cJSON* json = cJSON_Parse(text);
  free(text);
  if (json == NULL) {
    size_t length = strlen(path) + 64;
    *error = gfc_xmalloc(length);
    snprintf(*error, length, "parse %s: %s", path, cJSON_GetErrorPtr());
  }
  return json;
}

static GfcStringArray json_string_array(cJSON* value, const char* bundle_root) {
  GfcStringArray array = {0};
  if (!cJSON_IsArray(value)) {
    return array;
  }
  array.count = cJSON_GetArraySize(value);
  array.items = gfc_xcalloc(array.count, sizeof(char*));
  for (size_t index = 0; index < array.count; index++) {
    char* raw = json_text(cJSON_GetArrayItem(value, (int)index));
    array.items[index] = gfc_interpolate_builtins(raw, bundle_root);
    free(raw);
  }
  return array;
}

static GfcStringMap json_string_map(cJSON* value, const char* bundle_root) {
  GfcStringMap map;
  gfc_map_init(&map);
  if (!cJSON_IsObject(value)) {
    return map;
  }
  cJSON* item = NULL;
  cJSON_ArrayForEach(item, value) {
    char* raw = json_text(item);
    char* rendered = gfc_interpolate_builtins(raw, bundle_root);
    gfc_map_set(&map, item->string, rendered);
    free(rendered);
    free(raw);
  }
  return map;
}

static GfcArgumentGroup* optional_arguments(cJSON* command, const char* bundle_root, size_t* count) {
  *count = 0;
  cJSON* groups = cJSON_GetObjectItem(command, "optionalArguments");
  if (!cJSON_IsArray(groups)) {
    return NULL;
  }
  *count = cJSON_GetArraySize(groups);
  GfcArgumentGroup* result = gfc_xcalloc(*count, sizeof(GfcArgumentGroup));
  for (size_t index = 0; index < *count; index++) {
    result[index].arguments = json_string_array(cJSON_GetArrayItem(groups, (int)index), bundle_root);
  }
  return result;
}

static void append_text(char** body, const char* text) {
  if (text == NULL || text[0] == '\0') {
    return;
  }
  size_t old_len = *body == NULL ? 0 : strlen(*body);
  size_t add_len = strlen(text);
  *body = gfc_xrealloc(*body, old_len + add_len + 3);
  if (old_len == 0) {
    (*body)[0] = '\0';
  } else {
    strcat(*body, "\n");
  }
  strcat(*body, text);
}

static GfcDataSource* parse_data_source(cJSON* value, const char* bundle_root) {
  if (!cJSON_IsObject(value)) {
    return NULL;
  }
  GfcDataSource* source = gfc_xcalloc(1, sizeof(GfcDataSource));
  char* raw_path = json_text(cJSON_GetObjectItem(value, "path"));
  source->path = gfc_interpolate_builtins(raw_path, bundle_root);
  free(raw_path);
  source->arguments = json_string_array(cJSON_GetObjectItem(value, "arguments"), bundle_root);
  source->environment = json_string_map(cJSON_GetObjectItem(value, "environment"), bundle_root);
  cJSON* working_directory = cJSON_GetObjectItem(value, "workingDirectory");
  if (working_directory != NULL) {
    char* raw = json_text(working_directory);
    source->working_directory = gfc_interpolate_builtins(raw, bundle_root);
    free(raw);
  } else {
    source->working_directory = gfc_strdup("");
  }
  return source;
}

static GfcOption* parse_options(cJSON* value, const GfcStringMap* strings, size_t* count) {
  *count = 0;
  if (!cJSON_IsArray(value)) {
    return NULL;
  }
  *count = cJSON_GetArraySize(value);
  GfcOption* options = gfc_xcalloc(*count, sizeof(GfcOption));
  for (size_t index = 0; index < *count; index++) {
    cJSON* item = cJSON_GetArrayItem(value, (int)index);
    options[index].id = json_text(cJSON_GetObjectItem(item, "id"));
    options[index].title = localized(cJSON_GetObjectItem(item, "title"), strings, options[index].id);
    options[index].selected = cJSON_IsTrue(cJSON_GetObjectItem(item, "selected"));
  }
  return options;
}

static GfcCondition* parse_conditions(cJSON* value, const char* bundle_root, size_t* count) {
  *count = 0;
  if (!cJSON_IsArray(value)) {
    return NULL;
  }
  *count = cJSON_GetArraySize(value);
  GfcCondition* conditions = gfc_xcalloc(*count, sizeof(GfcCondition));
  for (size_t index = 0; index < *count; index++) {
    cJSON* item = cJSON_GetArrayItem(value, (int)index);
    conditions[index].placeholder = json_text(cJSON_GetObjectItem(item, "placeholder"));
    cJSON* equals = cJSON_GetObjectItem(item, "equals");
    cJSON* not_equals = cJSON_GetObjectItem(item, "notEquals");
    if (equals != NULL) {
      conditions[index].equals = json_text(equals);
    }
    if (not_equals != NULL) {
      conditions[index].not_equals = json_text(not_equals);
    }
    conditions[index].in_values = json_string_array(cJSON_GetObjectItem(item, "in"), bundle_root);
    conditions[index].not_in_values = json_string_array(cJSON_GetObjectItem(item, "notIn"), bundle_root);
    cJSON* exists = cJSON_GetObjectItem(item, "exists");
    if (cJSON_IsBool(exists)) {
      conditions[index].has_exists = true;
      conditions[index].exists = cJSON_IsTrue(exists);
    }
  }
  return conditions;
}

static GfcConfirmation* parse_confirmation(cJSON* value, const GfcStringMap* strings) {
  if (!cJSON_IsObject(value)) {
    return NULL;
  }
  GfcConfirmation* confirmation = gfc_xcalloc(1, sizeof(GfcConfirmation));
  confirmation->title = localized(cJSON_GetObjectItem(value, "title"), strings, "");
  confirmation->message = localized(cJSON_GetObjectItem(value, "message"), strings, "");
  confirmation->confirm_button_title =
      localized(cJSON_GetObjectItem(value, "confirmButtonTitle"), strings, "Continue");
  confirmation->cancel_button_title =
      localized(cJSON_GetObjectItem(value, "cancelButtonTitle"), strings, "Cancel");
  confirmation->required_text = json_text(cJSON_GetObjectItem(value, "requiredText"));
  confirmation->prompt = localized(cJSON_GetObjectItem(value, "prompt"), strings, "");
  return confirmation;
}

static bool parse_action(cJSON* value, const GfcStringMap* strings, const char* bundle_root, GfcAction* out) {
  memset(out, 0, sizeof(GfcAction));
  cJSON* command = cJSON_GetObjectItem(value, "command");
  if (!cJSON_IsObject(command)) {
    return false;
  }
  out->id = json_text(cJSON_GetObjectItem(value, "id"));
  out->title = localized(cJSON_GetObjectItem(value, "title"), strings, out->id);
  out->role = json_text(cJSON_GetObjectItem(value, "role"));
  if (out->role[0] == '\0') {
    free(out->role);
    out->role = gfc_strdup("primary");
  }
  char* executable = json_text(cJSON_GetObjectItem(command, "executable"));
  out->executable = gfc_interpolate_builtins(executable, bundle_root);
  free(executable);
  out->arguments = json_string_array(cJSON_GetObjectItem(command, "arguments"), bundle_root);
  out->optional_arguments = optional_arguments(command, bundle_root, &out->optional_argument_count);
  out->environment = json_string_map(cJSON_GetObjectItem(command, "environment"), bundle_root);
  cJSON* working_directory = cJSON_GetObjectItem(command, "workingDirectory");
  out->working_directory = working_directory == NULL
      ? gfc_strdup("")
      : interpolated_json_text(working_directory, bundle_root);
  out->visible_when = parse_conditions(cJSON_GetObjectItem(value, "visibleWhen"), bundle_root, &out->visible_count);
  out->disabled_when = parse_conditions(cJSON_GetObjectItem(value, "disabledWhen"), bundle_root, &out->disabled_count);
  out->disabled_tooltip = localized(
      cJSON_GetObjectItem(value, "disabledTooltip"),
      strings,
      "This action is not available."
  );
  out->confirmation = parse_confirmation(cJSON_GetObjectItem(value, "confirm"), strings);
  return true;
}

static bool editable_kind(const char* kind) {
  return strcmp(kind, "text") == 0 || strcmp(kind, "path") == 0 ||
         strcmp(kind, "dropdown") == 0 || strcmp(kind, "toggle") == 0 ||
         strcmp(kind, "checkboxGroup") == 0 || strcmp(kind, "libraryList") == 0 ||
         strcmp(kind, "infoGrid") == 0;
}

static void append_control(
    GfcPage* page,
    cJSON* control,
    const GfcStringMap* strings,
    const char* bundle_root,
    const char* config_file_path
) {
  char* kind = json_text(cJSON_GetObjectItem(control, "kind"));
  if (kind[0] == '\0') {
    free(kind);
    kind = gfc_strdup("text");
  }
  char* label = localized(cJSON_GetObjectItem(control, "label"), strings, "");
  char line[1024];
  snprintf(line, sizeof(line), "- %s (%s)", label, kind);
  append_text(&page->body, line);

  if (editable_kind(kind)) {
    page->controls = gfc_xrealloc(page->controls, (page->control_count + 1) * sizeof(GfcControl));
    GfcControl* view = &page->controls[page->control_count++];
    memset(view, 0, sizeof(GfcControl));
    view->id = json_text(cJSON_GetObjectItem(control, "id"));
    view->label = gfc_strdup(label[0] == '\0' ? view->id : label);
    view->kind = gfc_strdup(kind);
    view->value = json_text(cJSON_GetObjectItem(control, "value"));
    view->placeholder = localized(cJSON_GetObjectItem(control, "placeholder"), strings, "");
    view->helper = localized(cJSON_GetObjectItem(control, "tooltip"), strings, "");
    view->options = parse_options(cJSON_GetObjectItem(control, "options"), strings, &view->option_count);
    view->data_source = parse_data_source(cJSON_GetObjectItem(control, "dataSource"), bundle_root);
    cJSON* row_action = NULL;
    cJSON_ArrayForEach(row_action, cJSON_GetObjectItem(control, "rowActions")) {
      view->row_actions =
          gfc_xrealloc(view->row_actions, (view->row_action_count + 1) * sizeof(GfcAction));
      if (parse_action(row_action, strings, bundle_root, &view->row_actions[view->row_action_count])) {
        view->row_action_count++;
      }
    }
    view->config_file_path = gfc_strdup(config_file_path == NULL ? "" : config_file_path);
    view->config_key = json_text(cJSON_GetObjectItem(control, "key"));
    if (view->config_key[0] == '\0') {
      free(view->config_key);
      view->config_key = gfc_strdup(view->id);
    }
  }
  free(kind);
  free(label);
}

static GfcPage parse_page(cJSON* page_json, const GfcStringMap* strings, const char* bundle_root) {
  GfcPage page = {0};
  page.id = json_text(cJSON_GetObjectItem(page_json, "id"));
  page.title = localized(cJSON_GetObjectItem(page_json, "title"), strings, page.id);
  page.summary = localized(cJSON_GetObjectItem(page_json, "summary"), strings, "");
  page.body = gfc_strdup("");
  cJSON* sections = cJSON_GetObjectItem(page_json, "sections");
  cJSON* section = NULL;
  cJSON_ArrayForEach(section, sections) {
    char* title = localized(cJSON_GetObjectItem(section, "title"), strings, "");
    append_text(&page.body, title);
    cJSON* subtitle_json = cJSON_GetObjectItem(section, "subtitle");
    if (subtitle_json != NULL) {
      char* subtitle = localized(subtitle_json, strings, "");
      append_text(&page.body, subtitle);
      free(subtitle);
    }
    if (cJSON_IsObject(cJSON_GetObjectItem(section, "dataSource"))) {
      page.controls = gfc_xrealloc(page.controls, (page.control_count + 1) * sizeof(GfcControl));
      GfcControl* control = &page.controls[page.control_count++];
      memset(control, 0, sizeof(GfcControl));
      control->id = gfc_strdup("section-data-source");
      control->label = gfc_strdup(title);
      control->kind = gfc_strdup("infoGrid");
      control->value = gfc_strdup("");
      control->placeholder = gfc_strdup("");
      control->helper = gfc_strdup("");
      control->config_file_path = gfc_strdup("");
      control->config_key = gfc_strdup(control->id);
      control->data_source = parse_data_source(cJSON_GetObjectItem(section, "dataSource"), bundle_root);
    }
    cJSON* control = NULL;
    cJSON_ArrayForEach(control, cJSON_GetObjectItem(section, "controls")) {
      cJSON* config = cJSON_GetObjectItem(control, "configFile");
      char* config_path = NULL;
      if (cJSON_IsObject(config)) {
        char* raw = json_text(cJSON_GetObjectItem(config, "path"));
        config_path = gfc_interpolate_builtins(raw, bundle_root);
        free(raw);
      }
      cJSON* settings = cJSON_GetObjectItem(control, "settings");
      if (cJSON_IsArray(settings)) {
        cJSON* setting = NULL;
        cJSON_ArrayForEach(setting, settings) {
          append_control(&page, setting, strings, bundle_root, config_path);
        }
      } else {
        append_control(&page, control, strings, bundle_root, config_path);
      }
      free(config_path);
    }
    cJSON* action = NULL;
    cJSON_ArrayForEach(action, cJSON_GetObjectItem(section, "actions")) {
      page.actions = gfc_xrealloc(page.actions, (page.action_count + 1) * sizeof(GfcAction));
      if (parse_action(action, strings, bundle_root, &page.actions[page.action_count])) {
        page.action_count++;
      }
    }
    free(title);
  }
  return page;
}

static void load_strings(GfcBundle* bundle, const char* repo_root, const char* bundle_root, const char* locale) {
  gfc_map_init(&bundle->strings);
  char* builtins = gfc_path_join3(
      repo_root,
      "platform/apple/shared/Sources/GUIForCLICore/Resources",
      "BuiltinStrings"
  );
  char* builtin_en = gfc_path_join(builtins, "strings.en.toml");
  gfc_merge_toml_strings(&bundle->strings, builtin_en);
  free(builtin_en);
  if (strcmp(locale, "en") != 0) {
    char locale_file[64];
    snprintf(locale_file, sizeof(locale_file), "strings.%s.toml", locale);
    char* builtin_locale = gfc_path_join(builtins, locale_file);
    gfc_merge_toml_strings(&bundle->strings, builtin_locale);
    free(builtin_locale);
  }
  char locale_file[64];
  snprintf(locale_file, sizeof(locale_file), "strings.%s.toml", locale);
  char* bundle_strings_dir = gfc_path_join(bundle_root, "strings");
  char* bundle_strings = gfc_path_join(bundle_strings_dir, locale_file);
  gfc_merge_toml_strings(&bundle->strings, bundle_strings);
  free(bundle_strings);
  free(bundle_strings_dir);
  free(builtins);
}

bool gfc_load_bundle(
    const char* bundle_root,
    const char* repo_root,
    const char* locale,
    GfcBundle* bundle,
    char** error
) {
  memset(bundle, 0, sizeof(GfcBundle));
  load_strings(bundle, repo_root, bundle_root, locale);
  char* manifest_path = gfc_path_join(bundle_root, "manifest.json");
  cJSON* manifest = read_json(manifest_path, error);
  free(manifest_path);
  if (manifest == NULL) {
    return false;
  }
  bundle->title = localized(cJSON_GetObjectItem(manifest, "displayName"), &bundle->strings, "");
  bundle->summary = localized(cJSON_GetObjectItem(manifest, "summary"), &bundle->strings, "");
  char* direction = json_text(cJSON_GetObjectItem(manifest, "terminalTextDirection"));
  for (char* cursor = direction; *cursor != '\0'; cursor++) {
    *cursor = (char)tolower((unsigned char)*cursor);
  }
  bundle->terminal_text_direction = gfc_strdup(strcmp(direction, "rtl") == 0 ? "rtl" : "ltr");
  free(direction);

  cJSON* step = NULL;
  cJSON_ArrayForEach(step, cJSON_GetObjectItem(cJSON_GetObjectItem(manifest, "setup"), "steps")) {
    bundle->setup_steps = gfc_xrealloc(bundle->setup_steps, (bundle->setup_step_count + 1) * sizeof(GfcSetupStep));
    GfcSetupStep* view = &bundle->setup_steps[bundle->setup_step_count++];
    memset(view, 0, sizeof(GfcSetupStep));
    view->label = localized(cJSON_GetObjectItem(step, "label"), &bundle->strings, "");
    view->kind = json_text(cJSON_GetObjectItem(step, "kind"));
    char* raw = json_text(cJSON_GetObjectItem(step, "value"));
    view->value = gfc_interpolate_builtins(raw, bundle_root);
    free(raw);
    view->arguments = json_string_array(cJSON_GetObjectItem(step, "arguments"), bundle_root);
    view->environment = json_string_map(cJSON_GetObjectItem(step, "environment"), bundle_root);
    cJSON* working_directory = cJSON_GetObjectItem(step, "workingDirectory");
    view->working_directory = working_directory == NULL
        ? gfc_strdup("")
        : interpolated_json_text(working_directory, bundle_root);
    view->optional = cJSON_IsTrue(cJSON_GetObjectItem(step, "optional"));
  }

  cJSON* page_ref = NULL;
  cJSON_ArrayForEach(page_ref, cJSON_GetObjectItem(manifest, "pages")) {
    char* page_path = NULL;
    cJSON* page_json = page_ref;
    if (cJSON_IsString(page_ref)) {
      page_path = gfc_path_join3(bundle_root, "pages", page_ref->valuestring);
      page_json = read_json(page_path, error);
      free(page_path);
      if (page_json == NULL) {
        cJSON_Delete(manifest);
        return false;
      }
    }
    bundle->pages = gfc_xrealloc(bundle->pages, (bundle->page_count + 1) * sizeof(GfcPage));
    bundle->pages[bundle->page_count++] = parse_page(page_json, &bundle->strings, bundle_root);
    if (page_json != page_ref) {
      cJSON_Delete(page_json);
    }
  }
  for (size_t page = 0; page < bundle->page_count; page++) {
    bundle->control_count += bundle->pages[page].control_count;
    bundle->action_count += bundle->pages[page].action_count;
    for (size_t control = 0; control < bundle->pages[page].control_count; control++) {
      if (bundle->pages[page].controls[control].data_source != NULL) {
        bundle->data_source_count++;
      }
    }
  }
  cJSON_Delete(manifest);
  return true;
}
