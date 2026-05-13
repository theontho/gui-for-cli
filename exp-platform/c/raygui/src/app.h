#pragma once

#include "args.h"
#include "bundle.h"
#include "string_map.h"

#include <pthread.h>
#include <stdatomic.h>

typedef enum {
  GFC_TERMINAL_READY,
  GFC_TERMINAL_RUNNING,
  GFC_TERMINAL_SUCCEEDED,
  GFC_TERMINAL_FAILED
} GfcTerminalStatus;

typedef struct {
  unsigned long id;
  char* title;
  char* output;
  GfcTerminalStatus status;
  bool closable;
} GfcTerminalEntry;

typedef struct {
  pthread_t thread;
  atomic_bool done;
  atomic_long process_id;
  unsigned long terminal_id;
  char* command;
  char* output;
  int exit_code;
} GfcRunningCommand;

typedef struct {
  GfcBundle bundle;
  GfcArgs args;
  GfcStringMap fields;
  GfcStringMap data_values;
  GfcStringMap data_source_cache;
  GfcTerminalEntry* terminals;
  size_t terminal_count;
  size_t selected_terminal;
  GfcRunningCommand** running;
  size_t running_count;
  unsigned long next_terminal_id;
  size_t selected_page;
  bool show_terminal;
  float terminal_height;
  float sidebar_scroll_y;
  float content_scroll_y;
  float terminal_scroll_y;
  char editing_control_id[128];
  char editing_buffer[1024];
  char open_dropdown_id[128];
  size_t data_sources_loaded;
  char* pending_confirmation_action_id;
} GfcApp;

bool gfc_app_init(GfcApp* app, GfcArgs args, GfcBundle bundle, char** error);
void gfc_app_free(GfcApp* app);
void gfc_app_poll(GfcApp* app);
void gfc_app_set_field(GfcApp* app, const char* id, const char* value);
const char* gfc_app_field(const GfcApp* app, const char* id);
bool gfc_app_action_visible(const GfcApp* app, const GfcAction* action);
bool gfc_app_action_enabled(const GfcApp* app, const GfcAction* action);
char* gfc_app_action_preview(const GfcApp* app, const GfcAction* action);
void gfc_app_start_action(GfcApp* app, const GfcAction* action);
void gfc_app_start_setup(GfcApp* app, size_t index);
void gfc_app_terminal_tab_action(GfcApp* app, size_t index);
void gfc_app_open_workspace(GfcApp* app);
void gfc_app_select_page(GfcApp* app, size_t index);
char* gfc_app_setup_preview(const GfcSetupStep* step);
void gfc_app_warm_data_sources(GfcApp* app);
