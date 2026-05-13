#include "app.h"

#include "command_runner.h"
#include "data_source.h"
#include "state.h"
#include "utils.h"

#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static char* selected_option_value(const GfcControl* control) {
  for (size_t index = 0; index < control->option_count; index++) {
    if (control->options[index].selected) {
      return gfc_strdup(control->options[index].id);
    }
  }
  return control->option_count == 0 ? gfc_strdup("") : gfc_strdup(control->options[0].id);
}

static void add_terminal(GfcApp* app, const char* title, const char* output, GfcTerminalStatus status, bool closable) {
  app->terminals = gfc_xrealloc(app->terminals, (app->terminal_count + 1) * sizeof(GfcTerminalEntry));
  GfcTerminalEntry* entry = &app->terminals[app->terminal_count++];
  entry->id = app->next_terminal_id++;
  entry->title = gfc_strdup(title);
  entry->output = gfc_strdup(output);
  entry->status = status;
  entry->closable = closable;
  app->selected_terminal = app->terminal_count - 1;
}

bool gfc_app_init(GfcApp* app, GfcArgs args, GfcBundle bundle, char** error) {
  (void)error;
  memset(app, 0, sizeof(GfcApp));
  app->args = args;
  app->bundle = bundle;
  app->show_terminal = true;
  app->terminal_height = 190.0f;
  app->next_terminal_id = 1;
  gfc_map_init(&app->fields);
  gfc_map_init(&app->data_values);
  gfc_map_init(&app->data_source_cache);
  char* selected_page_id = NULL;
  char* state_error = NULL;
  (void)gfc_state_load(app->args.bundle, &selected_page_id, &app->fields, &state_error);
  for (size_t page = 0; page < app->bundle.page_count; page++) {
    if (selected_page_id != NULL && strcmp(selected_page_id, app->bundle.pages[page].id) == 0) {
      app->selected_page = page;
    }
    for (size_t control = 0; control < app->bundle.pages[page].control_count; control++) {
      GfcControl* view = &app->bundle.pages[page].controls[control];
      if (gfc_map_get(&app->fields, view->id) != NULL) {
        continue;
      }
      char* initial = NULL;
      char* config_value = gfc_config_load_value(view);
      if (config_value != NULL) {
        initial = config_value;
      } else if (view->value[0] != '\0') {
        initial = gfc_strdup(view->value);
      } else if (strcmp(view->kind, "dropdown") == 0 || strcmp(view->kind, "checkboxGroup") == 0) {
        initial = selected_option_value(view);
      } else {
        initial = gfc_strdup("");
      }
      gfc_map_set(&app->fields, view->id, initial);
      free(initial);
    }
  }
  free(selected_page_id);
  const char* main_title = gfc_map_get(&app->bundle.strings, "app.terminal.mainTab.title");
  const char* ready = gfc_map_get(&app->bundle.strings, "app.setup.status.ready");
  add_terminal(app, main_title == NULL ? "Main" : main_title, ready == NULL ? "Ready." : ready, GFC_TERMINAL_READY, false);
  app->selected_terminal = 0;
  if (state_error != NULL) {
    add_terminal(app, "State", state_error, GFC_TERMINAL_FAILED, true);
    free(state_error);
  }
  return true;
}

static void free_terminal(GfcTerminalEntry* terminal) {
  free(terminal->title);
  free(terminal->output);
}

void gfc_app_free(GfcApp* app) {
  for (size_t index = 0; index < app->running_count; index++) {
    GfcRunningCommand* running = app->running[index];
    if (!atomic_load(&running->done)) {
      long pid = atomic_load(&running->process_id);
      if (pid > 0) {
        kill((pid_t)-pid, SIGTERM);
      }
    }
    pthread_join(running->thread, NULL);
    free(running->command);
    free(running->output);
    free(running);
  }
  free(app->running);
  for (size_t index = 0; index < app->terminal_count; index++) {
    free_terminal(&app->terminals[index]);
  }
  free(app->terminals);
  gfc_map_free(&app->fields);
  gfc_map_free(&app->data_values);
  gfc_map_free(&app->data_source_cache);
  free(app->pending_confirmation_action_id);
  gfc_bundle_free(&app->bundle);
  gfc_args_free(&app->args);
}

void gfc_app_set_field(GfcApp* app, const char* id, const char* value) {
  gfc_map_set(&app->fields, id, value);
  GfcControl* control = NULL;
  for (size_t page = 0; page < app->bundle.page_count && control == NULL; page++) {
    for (size_t index = 0; index < app->bundle.pages[page].control_count; index++) {
      if (strcmp(app->bundle.pages[page].controls[index].id, id) == 0) {
        control = &app->bundle.pages[page].controls[index];
        break;
      }
    }
  }
  char* error = NULL;
  if (control != NULL && !gfc_config_save_value(control, value, &error)) {
    add_terminal(app, "Config", error, GFC_TERMINAL_FAILED, true);
    free(error);
  }
  const char* selected = app->bundle.page_count == 0 ? "" : app->bundle.pages[app->selected_page].id;
  if (!gfc_state_save(app->args.bundle, selected, &app->fields, &error)) {
    add_terminal(app, "State", error, GFC_TERMINAL_FAILED, true);
    free(error);
  }
  gfc_map_free(&app->data_source_cache);
  gfc_map_init(&app->data_source_cache);
  app->data_sources_loaded = 0;
}

const char* gfc_app_field(const GfcApp* app, const char* id) {
  const char* value = gfc_map_get(&app->fields, id);
  if (value == NULL) {
    value = gfc_map_get(&app->data_values, id);
  }
  return value == NULL ? "" : value;
}

static bool condition_matches(const GfcApp* app, const GfcCondition* condition) {
  const char* value = gfc_app_field(app, condition->placeholder);
  if (condition->has_exists && condition->exists != (value[0] != '\0')) {
    return false;
  }
  if (condition->equals != NULL && strcmp(value, condition->equals) != 0) {
    return false;
  }
  if (condition->not_equals != NULL && strcmp(value, condition->not_equals) == 0) {
    return false;
  }
  if (condition->in_values.count > 0) {
    bool found = false;
    for (size_t index = 0; index < condition->in_values.count; index++) {
      found = found || strcmp(value, condition->in_values.items[index]) == 0;
    }
    if (!found) return false;
  }
  for (size_t index = 0; index < condition->not_in_values.count; index++) {
    if (strcmp(value, condition->not_in_values.items[index]) == 0) {
      return false;
    }
  }
  return true;
}

bool gfc_app_action_visible(const GfcApp* app, const GfcAction* action) {
  for (size_t index = 0; index < action->visible_count; index++) {
    if (!condition_matches(app, &action->visible_when[index])) {
      return false;
    }
  }
  return true;
}

static bool template_missing_value(const GfcApp* app, const char* value) {
  const char* cursor = value;
  while ((cursor = strstr(cursor, "{{")) != NULL) {
    const char* end = strstr(cursor + 2, "}}");
    if (end == NULL) {
      return false;
    }
    size_t length = (size_t)(end - cursor - 2);
    char key[128] = {0};
    snprintf(key, length + 1 < sizeof(key) ? length + 1 : sizeof(key), "%s", cursor + 2);
    if (strcmp(key, "bundleRoot") != 0 && strcmp(key, "bundleWorkspace") != 0 &&
        strcmp(key, "home") != 0 && gfc_app_field(app, key)[0] == '\0') {
      return true;
    }
    cursor = end + 2;
  }
  return false;
}

static bool string_array_missing_value(const GfcApp* app, const GfcStringArray* values) {
  for (size_t index = 0; index < values->count; index++) {
    if (template_missing_value(app, values->items[index])) {
      return true;
    }
  }
  return false;
}

bool gfc_app_action_enabled(const GfcApp* app, const GfcAction* action) {
  for (size_t index = 0; index < action->disabled_count; index++) {
    if (condition_matches(app, &action->disabled_when[index])) {
      return false;
    }
  }
  if (template_missing_value(app, action->executable)) {
    return false;
  }
  for (size_t index = 0; index < action->arguments.count; index++) {
    if (template_missing_value(app, action->arguments.items[index])) {
      return false;
    }
  }
  return true;
}

static char* render_template(const GfcApp* app, const char* value) {
  char* rendered = gfc_interpolate_builtins(value, app->args.bundle);
  for (size_t index = 0; index < app->fields.count; index++) {
    char token[160];
    snprintf(token, sizeof(token), "{{%s}}", app->fields.items[index].key);
    char* next = gfc_replace_all(rendered, token, app->fields.items[index].value);
    free(rendered);
    rendered = next;
  }
  return rendered;
}

static GfcStringArray rendered_action_arguments(const GfcApp* app, const GfcAction* action) {
  size_t extra = 0;
  for (size_t group = 0; group < action->optional_argument_count; group++) {
    if (!string_array_missing_value(app, &action->optional_arguments[group].arguments)) {
      extra += action->optional_arguments[group].arguments.count;
    }
  }
  GfcStringArray rendered = {0};
  rendered.count = action->arguments.count + extra;
  rendered.items = gfc_xcalloc(rendered.count, sizeof(char*));
  size_t output = 0;
  for (size_t index = 0; index < action->arguments.count; index++) {
    rendered.items[output++] = render_template(app, action->arguments.items[index]);
  }
  for (size_t group = 0; group < action->optional_argument_count; group++) {
    if (string_array_missing_value(app, &action->optional_arguments[group].arguments)) {
      continue;
    }
    for (size_t index = 0; index < action->optional_arguments[group].arguments.count; index++) {
      rendered.items[output++] = render_template(app, action->optional_arguments[group].arguments.items[index]);
    }
  }
  return rendered;
}

char* gfc_app_action_preview(const GfcApp* app, const GfcAction* action) {
  GfcStringArray arguments = rendered_action_arguments(app, action);
  char** parts = gfc_xcalloc(arguments.count + 1, sizeof(char*));
  char* executable = render_template(app, action->executable);
  parts[0] = gfc_shell_quote(executable);
  free(executable);
  for (size_t index = 0; index < arguments.count; index++) {
    parts[index + 1] = gfc_shell_quote(arguments.items[index]);
  }
  char* preview = gfc_join_argv(parts, arguments.count + 1, " ");
  gfc_free_strings(arguments.items, arguments.count);
  gfc_free_strings(parts, arguments.count + 1);
  return preview;
}

void gfc_app_start_action(GfcApp* app, const GfcAction* action) {
  if (!gfc_app_action_enabled(app, action)) {
    return;
  }
  if (action->confirmation != NULL &&
      (app->pending_confirmation_action_id == NULL ||
       strcmp(app->pending_confirmation_action_id, action->id) != 0)) {
    free(app->pending_confirmation_action_id);
    app->pending_confirmation_action_id = gfc_strdup(action->id);
    size_t length = strlen(action->confirmation->title) + strlen(action->confirmation->message) +
                    strlen(action->confirmation->confirm_button_title) + 96;
    char* prompt = gfc_xcalloc(length, 1);
    snprintf(
        prompt,
        length,
        "%s\n%s\nClick %s again to confirm.",
        action->confirmation->title,
        action->confirmation->message,
        action->title
    );
    add_terminal(app, "Confirm", prompt, GFC_TERMINAL_READY, true);
    free(prompt);
    return;
  }
  free(app->pending_confirmation_action_id);
  app->pending_confirmation_action_id = NULL;
  char* preview = gfc_app_action_preview(app, action);
  char* command = gfc_command_with_context(app, action, preview);
  char* terminal_output = gfc_xmalloc(strlen(preview) + 16);
  sprintf(terminal_output, "$ %s\n[running]", preview);
  add_terminal(app, action->title, terminal_output, GFC_TERMINAL_RUNNING, true);
  unsigned long terminal_id = app->terminals[app->selected_terminal].id;
  free(terminal_output);
  free(preview);

  app->running = gfc_xrealloc(app->running, (app->running_count + 1) * sizeof(GfcRunningCommand*));
  GfcRunningCommand* running = gfc_xcalloc(1, sizeof(GfcRunningCommand));
  app->running[app->running_count++] = running;
  atomic_init(&running->done, false);
  atomic_init(&running->process_id, -1);
  running->terminal_id = terminal_id;
  running->command = command;
  if (pthread_create(&running->thread, NULL, gfc_run_command_thread, running) != 0) {
    for (size_t terminal = 0; terminal < app->terminal_count; terminal++) {
      if (app->terminals[terminal].id == terminal_id) {
        free(app->terminals[terminal].output);
        app->terminals[terminal].output = gfc_strdup("error: could not start command thread");
        app->terminals[terminal].status = GFC_TERMINAL_FAILED;
        break;
      }
    }
    free(running->command);
    free(running);
    app->running_count--;
  }
}

void gfc_app_poll(GfcApp* app) {
  for (size_t index = 0; index < app->running_count;) {
    GfcRunningCommand* running = app->running[index];
    if (!atomic_load(&running->done)) {
      index++;
      continue;
    }
    pthread_join(running->thread, NULL);
    for (size_t terminal = 0; terminal < app->terminal_count; terminal++) {
      if (app->terminals[terminal].id == running->terminal_id) {
        free(app->terminals[terminal].output);
        const char* body = running->output != NULL && running->output[0] != '\0' ? running->output : "(no output)";
        size_t length = strlen(running->command) + strlen(body) + strlen(app->terminals[terminal].title) + 64;
        app->terminals[terminal].output = gfc_xmalloc(length);
        snprintf(
            app->terminals[terminal].output,
            length,
            "$ %s\n%s\n[%s exit %d]",
            running->command,
            body,
            app->terminals[terminal].title,
            running->exit_code
        );
        app->terminals[terminal].status =
            running->exit_code == 0 ? GFC_TERMINAL_SUCCEEDED : GFC_TERMINAL_FAILED;
      }
    }
    free(running->command);
    free(running->output);
    app->running[index] = app->running[app->running_count - 1];
    free(running);
    app->running_count--;
  }
}

void gfc_app_terminal_tab_action(GfcApp* app, size_t index) {
  if (index == 0 || index >= app->terminal_count || !app->terminals[index].closable) {
    return;
  }
  if (app->terminals[index].status == GFC_TERMINAL_RUNNING) {
    unsigned long id = app->terminals[index].id;
    for (size_t running = 0; running < app->running_count; running++) {
      if (app->running[running]->terminal_id == id) {
        long pid = atomic_load(&app->running[running]->process_id);
        if (pid > 0) {
          kill((pid_t)-pid, SIGTERM);
        }
      }
    }
    size_t length = strlen(app->terminals[index].output) + 28;
    app->terminals[index].output = gfc_xrealloc(app->terminals[index].output, length);
    strcat(app->terminals[index].output, "\n[cancellation requested]");
    return;
  }
  free_terminal(&app->terminals[index]);
  for (size_t move = index + 1; move < app->terminal_count; move++) {
    app->terminals[move - 1] = app->terminals[move];
  }
  app->terminal_count--;
  if (app->selected_terminal >= app->terminal_count) {
    app->selected_terminal = app->terminal_count - 1;
  }
}

void gfc_app_open_workspace(GfcApp* app) {
  GfcAction action = {0};
  action.id = gfc_strdup("open-workspace");
  action.title = gfc_strdup("Open workspace");
  action.role = gfc_strdup("primary");
#if defined(__APPLE__)
  action.executable = gfc_strdup("/usr/bin/open");
  action.arguments.count = 1;
  action.arguments.items = gfc_xcalloc(1, sizeof(char*));
  action.arguments.items[0] = gfc_strdup(app->args.bundle);
#elif defined(__linux__)
  action.executable = gfc_strdup("/usr/bin/env");
  action.arguments.count = 2;
  action.arguments.items = gfc_xcalloc(2, sizeof(char*));
  action.arguments.items[0] = gfc_strdup("xdg-open");
  action.arguments.items[1] = gfc_strdup(app->args.bundle);
#else
  action.executable = gfc_strdup("open");
  action.arguments.count = 1;
  action.arguments.items = gfc_xcalloc(1, sizeof(char*));
  action.arguments.items[0] = gfc_strdup(app->args.bundle);
#endif
  gfc_map_init(&action.environment);
  action.working_directory = gfc_strdup(app->args.bundle);
  action.disabled_tooltip = gfc_strdup("");
  gfc_app_start_action(app, &action);
  gfc_action_free(&action);
}

void gfc_app_select_page(GfcApp* app, size_t index) {
  if (index >= app->bundle.page_count) {
    return;
  }
  app->selected_page = index;
  app->content_scroll_y = 0.0f;
  char* error = NULL;
  if (!gfc_state_save(app->args.bundle, app->bundle.pages[index].id, &app->fields, &error)) {
    add_terminal(app, "State", error, GFC_TERMINAL_FAILED, true);
    free(error);
  }
}

void gfc_app_warm_data_sources(GfcApp* app) {
  app->data_sources_loaded = 0;
  for (size_t page = 0; page < app->bundle.page_count; page++) {
    gfc_data_source_refresh_page(app, &app->bundle.pages[page]);
  }
  app->data_sources_loaded = app->bundle.data_source_count;
}
