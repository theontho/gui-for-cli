#pragma once

#include "string_map.h"

#include <stdbool.h>
#include <stddef.h>

typedef struct {
  char** items;
  size_t count;
} GfcStringArray;

typedef struct {
  GfcStringArray arguments;
} GfcArgumentGroup;

typedef struct {
  char* id;
  char* title;
  bool selected;
} GfcOption;

typedef struct {
  char* placeholder;
  char* equals;
  char* not_equals;
  GfcStringArray in_values;
  GfcStringArray not_in_values;
  bool has_exists;
  bool exists;
} GfcCondition;

typedef struct {
  char* path;
  GfcStringArray arguments;
  GfcStringMap environment;
  char* working_directory;
} GfcDataSource;

typedef struct {
  char* title;
  char* message;
  char* confirm_button_title;
  char* cancel_button_title;
  char* required_text;
  char* prompt;
} GfcConfirmation;

typedef struct {
  char* id;
  char* title;
  char* role;
  char* executable;
  GfcStringArray arguments;
  GfcArgumentGroup* optional_arguments;
  size_t optional_argument_count;
  GfcStringMap environment;
  char* working_directory;
  GfcCondition* visible_when;
  size_t visible_count;
  GfcCondition* disabled_when;
  size_t disabled_count;
  char* disabled_tooltip;
  GfcConfirmation* confirmation;
} GfcAction;

typedef struct {
  char* id;
  char* label;
  char* kind;
  char* value;
  char* placeholder;
  char* helper;
  GfcOption* options;
  size_t option_count;
  GfcDataSource* data_source;
  GfcAction* row_actions;
  size_t row_action_count;
  char* config_file_path;
  char* config_key;
} GfcControl;

typedef struct {
  char* label;
  char* kind;
  char* value;
  GfcStringArray arguments;
  GfcStringMap environment;
  char* working_directory;
  bool optional;
} GfcSetupStep;

typedef struct {
  char* id;
  char* title;
  char* summary;
  char* body;
  GfcControl* controls;
  size_t control_count;
  GfcAction* actions;
  size_t action_count;
} GfcPage;

typedef struct {
  char* title;
  char* summary;
  char* terminal_text_direction;
  GfcStringMap strings;
  GfcSetupStep* setup_steps;
  size_t setup_step_count;
  GfcPage* pages;
  size_t page_count;
  size_t control_count;
  size_t action_count;
  size_t data_source_count;
} GfcBundle;

bool gfc_load_bundle(
    const char* bundle_root,
    const char* repo_root,
    const char* locale,
    GfcBundle* bundle,
    char** error
);
void gfc_bundle_free(GfcBundle* bundle);
void gfc_action_free(GfcAction* action);
