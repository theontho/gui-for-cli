#include "app.h"

#include "utils.h"

#include <stdlib.h>
#include <string.h>

char* gfc_app_setup_preview(const GfcSetupStep* step) {
  GfcStringArray parts = {0};
  parts.count = step->arguments.count + 3;
  parts.items = gfc_xcalloc(parts.count, sizeof(char*));
  size_t count = 0;
  if (strcmp(step->kind, "pathTool") == 0) {
    parts.items[count++] = gfc_strdup("which");
    parts.items[count++] = gfc_strdup(step->value);
  } else if (strcmp(step->kind, "setupScript") == 0 || strcmp(step->kind, "bundledScript") == 0) {
    parts.items[count++] = gfc_strdup("sh");
    parts.items[count++] = gfc_strdup(step->value);
  } else if (strcmp(step->kind, "pixiInstall") == 0) {
    parts.items[count++] = gfc_strdup("pixi");
    parts.items[count++] = gfc_strdup("install");
  } else if (strcmp(step->kind, "pixiRun") == 0) {
    parts.items[count++] = gfc_strdup("pixi");
    parts.items[count++] = gfc_strdup("run");
    parts.items[count++] = gfc_strdup(step->value);
  } else if (strcmp(step->kind, "homebrewPackage") == 0) {
    parts.items[count++] = gfc_strdup("brew");
    parts.items[count++] = gfc_strdup("list");
    parts.items[count++] = gfc_strdup(step->value);
  } else {
    parts.items[count++] = gfc_strdup(step->value);
  }
  for (size_t index = 0; index < step->arguments.count; index++) {
    parts.items[count++] = gfc_strdup(step->arguments.items[index]);
  }
  char* result = gfc_join_argv(parts.items, count, " ");
  gfc_free_strings(parts.items, count);
  return result;
}

static GfcAction setup_as_action(const GfcSetupStep* step) {
  GfcAction action = {0};
  action.id = gfc_strdup(step->label);
  action.title = gfc_strdup(step->label);
  action.role = gfc_strdup("primary");
  gfc_map_init(&action.environment);
  for (size_t index = 0; index < step->environment.count; index++) {
    gfc_map_set(&action.environment, step->environment.items[index].key, step->environment.items[index].value);
  }
  action.working_directory = gfc_strdup(step->working_directory);
  if (strcmp(step->kind, "pathTool") == 0) {
    action.executable = gfc_strdup("/usr/bin/env");
    action.arguments.count = 2;
    action.arguments.items = gfc_xcalloc(2, sizeof(char*));
    action.arguments.items[0] = gfc_strdup("which");
    action.arguments.items[1] = gfc_strdup(step->value);
  } else if (strcmp(step->kind, "setupScript") == 0 || strcmp(step->kind, "bundledScript") == 0) {
    action.executable = gfc_strdup("/bin/sh");
    action.arguments.count = step->arguments.count + 1;
    action.arguments.items = gfc_xcalloc(action.arguments.count, sizeof(char*));
    action.arguments.items[0] = gfc_strdup(step->value);
    for (size_t index = 0; index < step->arguments.count; index++) {
      action.arguments.items[index + 1] = gfc_strdup(step->arguments.items[index]);
    }
  } else if (strcmp(step->kind, "pixiInstall") == 0) {
    action.executable = gfc_strdup("/usr/bin/env");
    action.arguments.count = step->arguments.count + 2;
    action.arguments.items = gfc_xcalloc(action.arguments.count, sizeof(char*));
    action.arguments.items[0] = gfc_strdup("pixi");
    action.arguments.items[1] = gfc_strdup("install");
    for (size_t index = 0; index < step->arguments.count; index++) {
      action.arguments.items[index + 2] = gfc_strdup(step->arguments.items[index]);
    }
  } else if (strcmp(step->kind, "pixiRun") == 0) {
    action.executable = gfc_strdup("/usr/bin/env");
    action.arguments.count = step->arguments.count + 3;
    action.arguments.items = gfc_xcalloc(action.arguments.count, sizeof(char*));
    action.arguments.items[0] = gfc_strdup("pixi");
    action.arguments.items[1] = gfc_strdup("run");
    action.arguments.items[2] = gfc_strdup(step->value);
    for (size_t index = 0; index < step->arguments.count; index++) {
      action.arguments.items[index + 3] = gfc_strdup(step->arguments.items[index]);
    }
  } else if (strcmp(step->kind, "homebrewPackage") == 0) {
    action.executable = gfc_strdup("/usr/bin/env");
    action.arguments.count = step->arguments.count + 3;
    action.arguments.items = gfc_xcalloc(action.arguments.count, sizeof(char*));
    action.arguments.items[0] = gfc_strdup("brew");
    action.arguments.items[1] = gfc_strdup("list");
    action.arguments.items[2] = gfc_strdup(step->value);
    for (size_t index = 0; index < step->arguments.count; index++) {
      action.arguments.items[index + 3] = gfc_strdup(step->arguments.items[index]);
    }
  } else {
    action.executable = gfc_strdup(step->value);
    action.arguments.count = step->arguments.count;
    action.arguments.items = gfc_xcalloc(action.arguments.count, sizeof(char*));
    for (size_t index = 0; index < step->arguments.count; index++) {
      action.arguments.items[index] = gfc_strdup(step->arguments.items[index]);
    }
  }
  action.disabled_tooltip = gfc_strdup("");
  return action;
}

void gfc_app_start_setup(GfcApp* app, size_t index) {
  if (index >= app->bundle.setup_step_count) {
    return;
  }
  GfcAction action = setup_as_action(&app->bundle.setup_steps[index]);
  gfc_app_start_action(app, &action);
  gfc_action_free(&action);
}
