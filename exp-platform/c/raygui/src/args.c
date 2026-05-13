#include "args.h"

#include "utils.h"

#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static char* parent_dir(const char* path) {
  char* copy = gfc_strdup(path);
  char* slash = strrchr(copy, '/');
  if (slash == NULL || slash == copy) {
    strcpy(copy, "/");
  } else {
    *slash = '\0';
  }
  return copy;
}

static char* find_repo_root(void) {
  char current[PATH_MAX];
  if (getcwd(current, sizeof(current)) == NULL) {
    return gfc_strdup(".");
  }
  char* cursor = gfc_strdup(current);
  while (cursor[0] != '\0') {
    char* manifest = gfc_path_join3(cursor, "examples", "WGSExtract");
    char* makefile = gfc_path_join(cursor, "Makefile");
    bool found = gfc_file_exists(manifest) && gfc_file_exists(makefile);
    free(manifest);
    free(makefile);
    if (found) {
      return cursor;
    }
    char* parent = parent_dir(cursor);
    if (strcmp(parent, cursor) == 0) {
      free(parent);
      break;
    }
    free(cursor);
    cursor = parent;
  }
  free(cursor);
  return gfc_strdup(current);
}

static bool next_value(int argc, char** argv, int* index, const char* flag, char** value, char** error) {
  if (*index + 1 >= argc || argv[*index + 1][0] == '-') {
    size_t length = strlen(flag) + 32;
    *error = gfc_xmalloc(length);
    snprintf(*error, length, "%s requires a value", flag);
    return false;
  }
  *index += 1;
  *value = gfc_strdup(argv[*index]);
  return true;
}

bool gfc_parse_args(int argc, char** argv, GfcArgs* args, char** error) {
  args->repo_root = find_repo_root();
  args->bundle = gfc_path_join3(args->repo_root, "examples", "WGSExtract");
  args->locale = gfc_strdup("en");
  args->benchmark = false;
  args->benchmark_full = false;
  args->once = false;
  args->version = false;
  bool bundle_provided = false;

  for (int index = 1; index < argc; index++) {
    const char* argument = argv[index];
    if (strcmp(argument, "--bundle") == 0) {
      free(args->bundle);
      if (!next_value(argc, argv, &index, argument, &args->bundle, error)) {
        return false;
      }
      bundle_provided = true;
    } else if (strcmp(argument, "--repo-root") == 0) {
      free(args->repo_root);
      if (!next_value(argc, argv, &index, argument, &args->repo_root, error)) {
        return false;
      }
      if (!bundle_provided) {
        free(args->bundle);
        args->bundle = gfc_path_join3(args->repo_root, "examples", "WGSExtract");
      }
    } else if (strcmp(argument, "--locale") == 0) {
      free(args->locale);
      if (!next_value(argc, argv, &index, argument, &args->locale, error)) {
        return false;
      }
    } else if (strcmp(argument, "--benchmark") == 0) {
      args->benchmark = true;
    } else if (strcmp(argument, "--benchmark-full") == 0) {
      args->benchmark = true;
      args->benchmark_full = true;
    } else if (strcmp(argument, "--once") == 0) {
      args->once = true;
    } else if (strcmp(argument, "--version") == 0 || strcmp(argument, "-V") == 0) {
      args->version = true;
    } else if (strcmp(argument, "--help") == 0 || strcmp(argument, "-h") == 0) {
      *error = gfc_strdup(gfc_usage());
      return false;
    } else {
      size_t length = strlen(argument) + strlen(gfc_usage()) + 32;
      *error = gfc_xmalloc(length);
      snprintf(*error, length, "unknown argument: %s\n%s", argument, gfc_usage());
      return false;
    }
  }

  if (args->bundle[0] != '/') {
    char* absolute = gfc_path_join(args->repo_root, args->bundle);
    free(args->bundle);
    args->bundle = absolute;
  }
  return true;
}

void gfc_args_free(GfcArgs* args) {
  free(args->bundle);
  free(args->repo_root);
  free(args->locale);
}

const char* gfc_usage(void) {
  return "Usage: gui-for-cli-raygui-c [--bundle PATH] [--repo-root PATH] [--locale CODE] "
         "[--benchmark] [--benchmark-full] [--once] [--version]";
}
