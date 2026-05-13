#pragma once

#include "app.h"

char* gfc_command_with_context(const GfcApp* app, const GfcAction* action, const char* preview);
void* gfc_run_command_thread(void* raw);
