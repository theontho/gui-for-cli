#pragma once

#include <stdbool.h>
#include <stddef.h>

void* gfc_xmalloc(size_t size);
void* gfc_xcalloc(size_t count, size_t size);
void* gfc_xrealloc(void* pointer, size_t size);
char* gfc_strdup(const char* value);
char* gfc_read_file(const char* path, char** error);
char* gfc_path_join(const char* left, const char* right);
char* gfc_path_join3(const char* first, const char* second, const char* third);
bool gfc_file_exists(const char* path);
char* gfc_replace_all(const char* value, const char* from, const char* to);
char* gfc_interpolate_builtins(const char* value, const char* bundle_root);
char* gfc_shell_quote(const char* value);
char* gfc_join_argv(char** values, size_t count, const char* separator);
void gfc_free_strings(char** values, size_t count);
