#pragma once

#include "app.h"

#include <stddef.h>

bool gfc_data_source_refresh_page(GfcApp* app, const GfcPage* page);
char* gfc_data_source_control_text(GfcApp* app, const GfcControl* control);
GfcOption* gfc_data_source_options(GfcApp* app, const GfcControl* control, size_t* count);
GfcAction* gfc_data_source_row_actions(GfcApp* app, const GfcPage* page, size_t* count);
void gfc_data_source_free_options(GfcOption* options, size_t count);
void gfc_data_source_free_actions(GfcAction* actions, size_t count);
