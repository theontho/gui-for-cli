#pragma once

#include <stdbool.h>

typedef struct {
  char* bundle;
  char* repo_root;
  char* locale;
  bool benchmark;
  bool benchmark_full;
  bool once;
  bool version;
} GfcArgs;

bool gfc_parse_args(int argc, char** argv, GfcArgs* args, char** error);
void gfc_args_free(GfcArgs* args);
const char* gfc_usage(void);
