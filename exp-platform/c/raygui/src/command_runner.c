#include "command_runner.h"

#include "utils.h"

#include <ctype.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

void* gfc_run_command_thread(void* raw) {
  GfcRunningCommand* running = raw;
  int fds[2];
  if (pipe(fds) != 0) {
    running->output = gfc_strdup("error: could not start command");
    running->exit_code = 127;
    atomic_store(&running->done, true);
    return NULL;
  }
  pid_t pid = fork();
  if (pid < 0) {
    close(fds[0]);
    close(fds[1]);
    running->output = gfc_strdup("error: could not fork command");
    running->exit_code = 127;
    atomic_store(&running->done, true);
    return NULL;
  }
  if (pid == 0) {
    setpgid(0, 0);
    close(fds[0]);
    dup2(fds[1], STDOUT_FILENO);
    dup2(fds[1], STDERR_FILENO);
    close(fds[1]);
    execl("/bin/sh", "sh", "-c", running->command, (char*)NULL);
    _exit(127);
  }
  atomic_store(&running->process_id, (long)pid);
  close(fds[1]);
  size_t capacity = 4096;
  size_t length = 0;
  running->output = gfc_xcalloc(capacity, 1);
  char buffer[1024];
  ssize_t read_bytes = 0;
  while ((read_bytes = read(fds[0], buffer, sizeof(buffer))) > 0) {
    size_t chunk = (size_t)read_bytes;
    if (length + chunk + 1 > capacity) {
      capacity = (capacity + chunk + 4096) * 2;
      running->output = gfc_xrealloc(running->output, capacity);
    }
    memcpy(running->output + length, buffer, chunk);
    length += chunk;
    running->output[length] = '\0';
  }
  close(fds[0]);
  int status = 0;
  waitpid(pid, &status, 0);
  running->exit_code = WIFEXITED(status) ? WEXITSTATUS(status) : WIFSIGNALED(status) ? 128 + WTERMSIG(status) : -1;
  atomic_store(&running->process_id, -1);
  atomic_store(&running->done, true);
  return NULL;
}

static char* env_key(const char* value) {
  char* key = gfc_strdup(value);
  for (char* cursor = key; *cursor != '\0'; cursor++) {
    *cursor = (char)(isalnum((unsigned char)*cursor) ? toupper((unsigned char)*cursor) : '_');
  }
  return key;
}

static char* render_template(const GfcApp* app, const char* value) {
  char* rendered = gfc_interpolate_builtins(value, app->args.bundle);
  for (size_t index = 0; index < app->fields.count; index++) {
    char token[160];
    snprintf(token, sizeof(token), "{{%s}}", app->fields.items[index].key);
    char* next = gfc_replace_all(rendered, token, app->fields.items[index].value);
    free(rendered);
    rendered = next;
  }
  return rendered;
}

static void append_part(char** output, size_t* length, size_t* capacity, const char* part) {
  size_t add = strlen(part == NULL ? "" : part);
  if (*length + add + 1 > *capacity) {
    while (*length + add + 1 > *capacity) {
      *capacity *= 2;
    }
    *output = gfc_xrealloc(*output, *capacity);
  }
  memcpy(*output + *length, part == NULL ? "" : part, add);
  *length += add;
  (*output)[*length] = '\0';
}

char* gfc_command_with_context(const GfcApp* app, const GfcAction* action, const char* preview) {
  if (preview == NULL) {
    preview = "";
  }
  char* cwd_path = action->working_directory[0] == '\0' ? gfc_strdup(app->args.bundle)
                                                        : render_template(app, action->working_directory);
  char* cwd = gfc_shell_quote(cwd_path);
  char* bundle = gfc_shell_quote(app->args.bundle);
  size_t capacity = 512;
  size_t length = 0;
  char* command = gfc_xcalloc(capacity, 1);
  append_part(&command, &length, &capacity, "cd ");
  append_part(&command, &length, &capacity, cwd);
  append_part(&command, &length, &capacity, " && GUI_FOR_CLI_BUNDLE_ROOT=");
  append_part(&command, &length, &capacity, bundle);
  append_part(&command, &length, &capacity, " GUI_FOR_CLI_BUNDLE_WORKSPACE=");
  append_part(&command, &length, &capacity, bundle);
  append_part(&command, &length, &capacity, " ");
  for (size_t index = 0; index < action->environment.count; index++) {
    char* value = render_template(app, action->environment.items[index].value);
    char* quoted = gfc_shell_quote(value);
    append_part(&command, &length, &capacity, action->environment.items[index].key);
    append_part(&command, &length, &capacity, "=");
    append_part(&command, &length, &capacity, quoted);
    append_part(&command, &length, &capacity, " ");
    free(value);
    free(quoted);
  }
  for (size_t index = 0; index < app->fields.count; index++) {
    char* key = env_key(app->fields.items[index].key);
    char* value = gfc_shell_quote(app->fields.items[index].value);
    append_part(&command, &length, &capacity, "GUI_FOR_CLI_FIELD_");
    append_part(&command, &length, &capacity, key);
    append_part(&command, &length, &capacity, "=");
    append_part(&command, &length, &capacity, value);
    append_part(&command, &length, &capacity, " GUI_FOR_CLI_CONFIG_");
    append_part(&command, &length, &capacity, key);
    append_part(&command, &length, &capacity, "=");
    append_part(&command, &length, &capacity, value);
    append_part(&command, &length, &capacity, " ");
    free(key);
    free(value);
  }
  append_part(&command, &length, &capacity, preview);
  append_part(&command, &length, &capacity, " 2>&1");
  free(cwd_path);
  free(cwd);
  free(bundle);
  return command;
}
