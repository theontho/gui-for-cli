#include "bundle.h"

#include "utils.h"

#include <stdlib.h>

void gfc_action_free(GfcAction* action) {
  free(action->id);
  free(action->title);
  free(action->role);
  free(action->executable);
  gfc_free_strings(action->arguments.items, action->arguments.count);
  for (size_t index = 0; index < action->optional_argument_count; index++) {
    gfc_free_strings(
        action->optional_arguments[index].arguments.items,
        action->optional_arguments[index].arguments.count
    );
  }
  free(action->optional_arguments);
  gfc_map_free(&action->environment);
  free(action->working_directory);
  for (size_t index = 0; index < action->visible_count; index++) {
    free(action->visible_when[index].placeholder);
    free(action->visible_when[index].equals);
    free(action->visible_when[index].not_equals);
    gfc_free_strings(action->visible_when[index].in_values.items, action->visible_when[index].in_values.count);
    gfc_free_strings(action->visible_when[index].not_in_values.items, action->visible_when[index].not_in_values.count);
  }
  for (size_t index = 0; index < action->disabled_count; index++) {
    free(action->disabled_when[index].placeholder);
    free(action->disabled_when[index].equals);
    free(action->disabled_when[index].not_equals);
    gfc_free_strings(action->disabled_when[index].in_values.items, action->disabled_when[index].in_values.count);
    gfc_free_strings(action->disabled_when[index].not_in_values.items, action->disabled_when[index].not_in_values.count);
  }
  free(action->visible_when);
  free(action->disabled_when);
  free(action->disabled_tooltip);
  if (action->confirmation != NULL) {
    free(action->confirmation->title);
    free(action->confirmation->message);
    free(action->confirmation->confirm_button_title);
    free(action->confirmation->cancel_button_title);
    free(action->confirmation->required_text);
    free(action->confirmation->prompt);
    free(action->confirmation);
  }
}

static void free_control(GfcControl* control) {
  free(control->id);
  free(control->label);
  free(control->kind);
  free(control->value);
  free(control->placeholder);
  free(control->helper);
  for (size_t index = 0; index < control->option_count; index++) {
    free(control->options[index].id);
    free(control->options[index].title);
  }
  free(control->options);
  if (control->data_source != NULL) {
    free(control->data_source->path);
    gfc_free_strings(control->data_source->arguments.items, control->data_source->arguments.count);
    gfc_map_free(&control->data_source->environment);
    free(control->data_source->working_directory);
    free(control->data_source);
  }
  for (size_t index = 0; index < control->row_action_count; index++) {
    gfc_action_free(&control->row_actions[index]);
  }
  free(control->row_actions);
  free(control->config_file_path);
  free(control->config_key);
}

void gfc_bundle_free(GfcBundle* bundle) {
  free(bundle->title);
  free(bundle->summary);
  free(bundle->terminal_text_direction);
  for (size_t index = 0; index < bundle->setup_step_count; index++) {
    free(bundle->setup_steps[index].label);
    free(bundle->setup_steps[index].kind);
    free(bundle->setup_steps[index].value);
    gfc_free_strings(bundle->setup_steps[index].arguments.items, bundle->setup_steps[index].arguments.count);
    gfc_map_free(&bundle->setup_steps[index].environment);
    free(bundle->setup_steps[index].working_directory);
  }
  free(bundle->setup_steps);
  for (size_t page = 0; page < bundle->page_count; page++) {
    free(bundle->pages[page].id);
    free(bundle->pages[page].title);
    free(bundle->pages[page].summary);
    free(bundle->pages[page].body);
    for (size_t control = 0; control < bundle->pages[page].control_count; control++) {
      free_control(&bundle->pages[page].controls[control]);
    }
    for (size_t action = 0; action < bundle->pages[page].action_count; action++) {
      gfc_action_free(&bundle->pages[page].actions[action]);
    }
    free(bundle->pages[page].controls);
    free(bundle->pages[page].actions);
  }
  free(bundle->pages);
  gfc_map_free(&bundle->strings);
}
