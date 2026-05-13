#include "utils.h"

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

void* gfc_xmalloc(size_t size) {
  void* pointer = malloc(size == 0 ? 1 : size);
  if (pointer == NULL) {
    fputs("gui-for-cli-raygui-c: out of memory\n", stderr);
    abort();
  }
  return pointer;
}

void* gfc_xcalloc(size_t count, size_t size) {
  void* pointer = calloc(count == 0 ? 1 : count, size == 0 ? 1 : size);
  if (pointer == NULL) {
    fputs("gui-for-cli-raygui-c: out of memory\n", stderr);
    abort();
  }
  return pointer;
}

void* gfc_xrealloc(void* pointer, size_t size) {
  void* resized = realloc(pointer, size == 0 ? 1 : size);
  if (resized == NULL) {
    fputs("gui-for-cli-raygui-c: out of memory\n", stderr);
    abort();
  }
  return resized;
}

char* gfc_strdup(const char* value) {
  const char* source = value == NULL ? "" : value;
  size_t length = strlen(source) + 1;
  char* copy = gfc_xmalloc(length);
  memcpy(copy, source, length);
  return copy;
}

char* gfc_read_file(const char* path, char** error) {
  FILE* file = fopen(path, "rb");
  if (file == NULL) {
    if (error != NULL) {
      size_t length = strlen(path) + 32;
      *error = gfc_xmalloc(length);
      snprintf(*error, length, "could not read %s", path);
    }
    return NULL;
  }
  if (fseek(file, 0, SEEK_END) != 0) {
    fclose(file);
    if (error != NULL) {
      *error = gfc_strdup("could not seek file");
    }
    return NULL;
  }
  long size = ftell(file);
  if (size < 0) {
    fclose(file);
    if (error != NULL) {
      *error = gfc_strdup("could not determine file size");
    }
    return NULL;
  }
  rewind(file);
  char* data = gfc_xcalloc((size_t)size + 1, 1);
  if (fread(data, 1, (size_t)size, file) != (size_t)size) {
    free(data);
    fclose(file);
    if (error != NULL) {
      *error = gfc_strdup("could not allocate file buffer");
    }
    return NULL;
  }
  fclose(file);
  return data;
}

char* gfc_path_join(const char* left, const char* right) {
  if (right == NULL || right[0] == '/') {
    return gfc_strdup(right);
  }
  size_t left_len = strlen(left);
  bool slash = left_len > 0 && left[left_len - 1] == '/';
  size_t length = left_len + strlen(right) + (slash ? 1 : 2);
  char* joined = gfc_xmalloc(length);
  snprintf(joined, length, "%s%s%s", left, slash ? "" : "/", right);
  return joined;
}

char* gfc_path_join3(const char* first, const char* second, const char* third) {
  char* prefix = gfc_path_join(first, second);
  char* result = gfc_path_join(prefix, third);
  free(prefix);
  return result;
}

bool gfc_file_exists(const char* path) {
  struct stat info;
  return path != NULL && stat(path, &info) == 0;
}

char* gfc_replace_all(const char* value, const char* from, const char* to) {
  if (value == NULL || from == NULL || from[0] == '\0') {
    return gfc_strdup(value);
  }
  if (to == NULL) {
    to = "";
  }
  size_t from_len = strlen(from);
  size_t to_len = strlen(to);
  size_t count = 0;
  for (const char* cursor = value; (cursor = strstr(cursor, from)) != NULL; cursor += from_len) {
    count++;
  }
  size_t length = strlen(value) + 1;
  if (to_len >= from_len) {
    length += count * (to_len - from_len);
  } else {
    length -= count * (from_len - to_len);
  }
  char* result = gfc_xmalloc(length);
  char* output = result;
  const char* cursor = value;
  const char* match = NULL;
  while ((match = strstr(cursor, from)) != NULL) {
    size_t chunk = (size_t)(match - cursor);
    memcpy(output, cursor, chunk);
    output += chunk;
    memcpy(output, to, to_len);
    output += to_len;
    cursor = match + from_len;
  }
  strcpy(output, cursor);
  return result;
}

char* gfc_interpolate_builtins(const char* value, const char* bundle_root) {
  char* with_bundle = gfc_replace_all(value, "{{bundleRoot}}", bundle_root);
  char* with_workspace = gfc_replace_all(with_bundle, "{{bundleWorkspace}}", bundle_root);
  const char* home = getenv("HOME");
  char* result = gfc_replace_all(with_workspace, "{{home}}", home == NULL ? "" : home);
  free(with_bundle);
  free(with_workspace);
  return result;
}

char* gfc_shell_quote(const char* value) {
  if (value == NULL || value[0] == '\0') {
    return gfc_strdup("''");
  }
  bool simple = true;
  for (const unsigned char* cursor = (const unsigned char*)value; *cursor != '\0'; cursor++) {
    if (!(isalnum(*cursor) || *cursor == '_' || *cursor == '-' || *cursor == '.' ||
          *cursor == '/' || *cursor == ':' || *cursor == '=')) {
      simple = false;
      break;
    }
  }
  if (simple) {
    return gfc_strdup(value);
  }
  size_t extra = 0;
  for (const char* cursor = value; *cursor != '\0'; cursor++) {
    if (*cursor == '\'') {
      extra += 3;
    }
  }
  char* result = gfc_xmalloc(strlen(value) + extra + 3);
  char* output = result;
  *output++ = '\'';
  for (const char* cursor = value; *cursor != '\0'; cursor++) {
    if (*cursor == '\'') {
      memcpy(output, "'\\''", 4);
      output += 4;
    } else {
      *output++ = *cursor;
    }
  }
  *output++ = '\'';
  *output = '\0';
  return result;
}

char* gfc_join_argv(char** values, size_t count, const char* separator) {
  size_t sep_len = strlen(separator);
  size_t length = 1;
  for (size_t index = 0; index < count; index++) {
    length += strlen(values[index]) + (index == 0 ? 0 : sep_len);
  }
  char* result = gfc_xcalloc(length, 1);
  for (size_t index = 0; index < count; index++) {
    if (index > 0) {
      strcat(result, separator);
    }
    strcat(result, values[index]);
  }
  return result;
}

void gfc_free_strings(char** values, size_t count) {
  for (size_t index = 0; index < count; index++) {
    free(values[index]);
  }
  free(values);
}
