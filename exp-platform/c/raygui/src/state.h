#pragma once

#include "bundle.h"
#include "string_map.h"

#include <stdbool.h>

bool gfc_state_load(const char* bundle_root, char** selected_page_id, GfcStringMap* fields, char** error);
bool gfc_state_save(const char* bundle_root, const char* selected_page_id, const GfcStringMap* fields, char** error);
char* gfc_config_load_value(const GfcControl* control);
bool gfc_config_save_value(const GfcControl* control, const char* value, char** error);
