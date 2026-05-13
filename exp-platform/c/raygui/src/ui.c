#include "ui.h"

#include "data_source.h"
#include "raygui.h"
#include "utils.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const Color BG = {245, 247, 250, 255};
static const Color PANEL = {255, 255, 255, 255};
static const Color SUBTLE = {248, 250, 252, 255};
static const Color BORDER = {204, 213, 225, 255};
static const Color TEXT = {20, 28, 42, 255};
static const Color MUTED = {89, 103, 124, 255};
static const Color DANGER = {185, 28, 28, 255};

static bool app_is_rtl(const GfcApp* app) {
  const char* direction = gfc_map_get(&app->bundle.strings, "language.layoutDirection");
  return direction != NULL && strcmp(direction, "rtl") == 0;
}

static void panel(Rectangle bounds) {
  DrawRectangleRounded(bounds, 0.045f, 8, PANEL);
  DrawRectangleRoundedLines(bounds, 0.045f, 8, BORDER);
}

static float wrapped_text(const char* text, float x, float y, float width, int size, Color color) {
  if (text == NULL || text[0] == '\0') {
    return 0.0f;
  }
  size_t length = strlen(text);
  size_t start = 0;
  float line_height = (float)size + 6.0f;
  float current_y = y;
  size_t max_chars = (size_t)(width / ((float)size * 0.55f));
  if (max_chars < 12) {
    max_chars = 12;
  }
  while (start < length) {
    size_t end = start;
    size_t last_space = start;
    while (end < length && end - start < max_chars && text[end] != '\n') {
      if (text[end] == ' ') {
        last_space = end;
      }
      end++;
    }
    if (end < length && text[end] != '\n' && last_space > start) {
      end = last_space;
    }
    char line[512];
    size_t line_len = end - start;
    if (line_len >= sizeof(line)) {
      line_len = sizeof(line) - 1;
    }
    memcpy(line, text + start, line_len);
    line[line_len] = '\0';
    DrawText(line, (int)x, (int)current_y, size, color);
    current_y += line_height;
    start = end;
    while (start < length && (text[start] == ' ' || text[start] == '\n')) {
      start++;
    }
  }
  return current_y - y;
}

static float estimated_page_height(const GfcPage* page) {
  return 150.0f + (float)strlen(page->body) * 0.08f + (float)page->control_count * 112.0f +
         (float)page->action_count * 78.0f;
}

static void draw_sidebar(GfcApp* app, Rectangle bounds) {
  panel(bounds);
  float y = bounds.y + 16;
  DrawText(app->bundle.title, (int)bounds.x + 16, (int)y, 22, TEXT);
  y += 30;
  y += wrapped_text(app->bundle.summary, bounds.x + 16, y, bounds.width - 32, 13, MUTED) + 8;
  char meta[160];
  snprintf(
      meta,
      sizeof(meta),
      "%zu controls / %zu actions / %zu data sources",
      app->bundle.control_count,
      app->bundle.action_count,
      app->bundle.data_source_count
  );
  DrawText(meta, (int)bounds.x + 16, (int)y, 11, MUTED);
  y += 18;
  if (GuiButton((Rectangle){bounds.x + 16, y, bounds.width - 32, 28}, "Open workspace")) {
    gfc_app_open_workspace(app);
  }
  y += 38;
  DrawText("Setup", (int)bounds.x + 16, (int)y, 16, TEXT);
  y += 22;
  for (size_t index = 0; index < app->bundle.setup_step_count; index++) {
    if (GuiButton((Rectangle){bounds.x + 16, y, bounds.width - 32, 26}, app->bundle.setup_steps[index].label)) {
      gfc_app_start_setup(app, index);
    }
    y += 30;
    char* preview = gfc_app_setup_preview(&app->bundle.setup_steps[index]);
    y += wrapped_text(preview, bounds.x + 18, y, bounds.width - 36, 10, MUTED) + 5;
    free(preview);
  }
  y += 6;
  Rectangle list = {bounds.x + 8, y, bounds.width - 16, bounds.y + bounds.height - y - 8};
  Rectangle content = {list.x, list.y, list.width - 16, (float)app->bundle.page_count * 42.0f + 42.0f};
  Rectangle view = {0};
  Vector2 scroll = {0, app->sidebar_scroll_y};
  GuiScrollPanel(list, "", content, &scroll, &view);
  app->sidebar_scroll_y = scroll.y;
  BeginScissorMode((int)view.x, (int)view.y, (int)view.width, (int)view.height);
  y = content.y + scroll.y + 6.0f;
  DrawText("Pages", (int)content.x + 4, (int)y, 16, TEXT);
  y += 26;
  for (size_t index = 0; index < app->bundle.page_count; index++) {
    Rectangle item = {content.x + 4, y, content.width - 8, 34};
    if (index == app->selected_page) {
      DrawRectangleRounded(item, 0.16f, 8, (Color){224, 233, 246, 255});
    }
    if (GuiButton(item, app->bundle.pages[index].title)) {
      gfc_app_select_page(app, index);
    }
    y += 40.0f;
  }
  EndScissorMode();
}

static void draw_toggle(GfcApp* app, const GfcControl* control, float x, float y) {
  bool checked = strcmp(gfc_app_field(app, control->id), "true") == 0;
  bool before = checked;
  GuiCheckBox((Rectangle){x, y, 22, 22}, "Enabled", &checked);
  if (checked != before) {
    gfc_app_set_field(app, control->id, checked ? "true" : "false");
  }
}

static void draw_dropdown(GfcApp* app, const GfcControl* control, float x, float y, float width) {
  size_t dynamic_count = 0;
  GfcOption* dynamic_options = gfc_data_source_options(app, control, &dynamic_count);
  const GfcOption* options_source = dynamic_count > 0 ? dynamic_options : control->options;
  size_t option_count = dynamic_count > 0 ? dynamic_count : control->option_count;
  if (option_count == 0) {
    DrawText("No options loaded", (int)x, (int)y + 6, 13, MUTED);
    gfc_data_source_free_options(dynamic_options, dynamic_count);
    return;
  }
  size_t text_len = 1;
  for (size_t index = 0; index < option_count; index++) {
    text_len += strlen(options_source[index].title) + 1;
  }
  char* options = gfc_xcalloc(text_len, 1);
  for (size_t index = 0; index < option_count; index++) {
    if (index > 0) {
      strcat(options, ";");
    }
    strcat(options, options_source[index].title);
  }
  int active = 0;
  const char* value = gfc_app_field(app, control->id);
  for (size_t index = 0; index < option_count; index++) {
    if (strcmp(value, options_source[index].id) == 0) {
      active = (int)index;
    }
  }
  bool editing = strcmp(app->open_dropdown_id, control->id) == 0;
  if (GuiDropdownBox((Rectangle){x, y, width, 28}, options, &active, editing)) {
    if (editing) {
      gfc_app_set_field(app, control->id, options_source[active].id);
      app->open_dropdown_id[0] = '\0';
    } else {
      snprintf(app->open_dropdown_id, sizeof(app->open_dropdown_id), "%s", control->id);
    }
  }
  free(options);
  gfc_data_source_free_options(dynamic_options, dynamic_count);
}

static void draw_text_field(GfcApp* app, const GfcControl* control, float x, float y, float width) {
  bool editing = strcmp(app->editing_control_id, control->id) == 0;
  char buffer[1024];
  if (editing) {
    snprintf(buffer, sizeof(buffer), "%s", app->editing_buffer);
  } else {
    const char* value = gfc_app_field(app, control->id);
    snprintf(buffer, sizeof(buffer), "%s", value[0] == '\0' ? control->placeholder : value);
  }
  if (GuiTextBox((Rectangle){x, y, width, 28}, buffer, sizeof(buffer), editing)) {
    if (editing) {
      gfc_app_set_field(app, control->id, buffer);
      app->editing_control_id[0] = '\0';
      app->editing_buffer[0] = '\0';
    } else {
      snprintf(app->editing_control_id, sizeof(app->editing_control_id), "%s", control->id);
      snprintf(app->editing_buffer, sizeof(app->editing_buffer), "%s", gfc_app_field(app, control->id));
    }
  }
  if (editing) {
    snprintf(app->editing_buffer, sizeof(app->editing_buffer), "%s", buffer);
  }
}

static float draw_control(GfcApp* app, const GfcControl* control, float x, float y, float width) {
  Rectangle bounds = {x, y, width, 96};
  DrawRectangleRounded(bounds, 0.04f, 6, SUBTLE);
  DrawRectangleRoundedLines(bounds, 0.04f, 6, BORDER);
  DrawText(control->label, (int)x + 10, (int)y + 9, 15, TEXT);
  float input_y = y + 34.0f;
  if (strcmp(control->kind, "toggle") == 0) {
    draw_toggle(app, control, x + 10, input_y + 3);
  } else if (strcmp(control->kind, "dropdown") == 0 || strcmp(control->kind, "checkboxGroup") == 0) {
    draw_dropdown(app, control, x + 10, input_y, width - 20);
  } else if (strcmp(control->kind, "libraryList") == 0 || strcmp(control->kind, "infoGrid") == 0) {
    char* text = gfc_data_source_control_text(app, control);
    wrapped_text(text, x + 10, input_y + 4, width - 20, 12, MUTED);
    free(text);
  } else {
    draw_text_field(app, control, x + 10, input_y, width - 20);
  }
  if (control->helper[0] != '\0') {
    wrapped_text(control->helper, x + 10, y + 68, width - 20, 11, MUTED);
  }
  return y + bounds.height + 10.0f;
}

static float draw_action(GfcApp* app, const GfcAction* action, float x, float y, float width) {
  if (!gfc_app_action_visible(app, action)) {
    return y;
  }
  bool enabled = gfc_app_action_enabled(app, action);
  Rectangle bounds = {x, y, width, 64};
  DrawRectangleRounded(bounds, 0.04f, 6, SUBTLE);
  DrawRectangleRoundedLines(bounds, 0.04f, 6, BORDER);
  if (!enabled) {
    GuiSetState(STATE_DISABLED);
  }
  Rectangle button = {x + 10, y + 10, 170, 28};
  if (GuiButton(button, action->title)) {
    gfc_app_start_action(app, action);
  }
  if (!enabled) {
    GuiSetState(STATE_NORMAL);
  }
  char* preview = gfc_app_action_preview(app, action);
  Color preview_color = strcmp(action->role, "destructive") == 0 ? DANGER : MUTED;
  wrapped_text(enabled ? preview : action->disabled_tooltip, x + 190, y + 12, width - 200, 12, preview_color);
  free(preview);
  return y + bounds.height + 8.0f;
}

static void draw_page(GfcApp* app, Rectangle bounds) {
  panel(bounds);
  if (app->bundle.page_count == 0) {
    DrawText("No pages in bundle", (int)bounds.x + 16, (int)bounds.y + 16, 18, DANGER);
    return;
  }
  GfcPage* page = &app->bundle.pages[app->selected_page];
  gfc_data_source_refresh_page(app, page);
  Rectangle content = {bounds.x + 12, bounds.y + 12, bounds.width - 30, estimated_page_height(page)};
  Rectangle view = {0};
  Vector2 scroll = {0, app->content_scroll_y};
  GuiScrollPanel(bounds, "", content, &scroll, &view);
  app->content_scroll_y = scroll.y;
  BeginScissorMode((int)view.x, (int)view.y, (int)view.width, (int)view.height);
  float y = content.y + scroll.y + 8.0f;
  DrawText(page->title, (int)content.x + 8, (int)y, 26, TEXT);
  y += 38.0f;
  y += wrapped_text(page->summary, content.x + 8, y, content.width - 16, 15, MUTED) + 10.0f;
  y += wrapped_text(page->body, content.x + 8, y, content.width - 16, 13, TEXT) + 14.0f;
  for (size_t index = 0; index < page->control_count; index++) {
    y = draw_control(app, &page->controls[index], content.x + 8, y, content.width - 16);
  }
  size_t row_action_count = 0;
  GfcAction* row_actions = gfc_data_source_row_actions(app, page, &row_action_count);
  if (page->action_count + row_action_count > 0) {
    DrawText("Actions", (int)content.x + 8, (int)y, 18, TEXT);
    y += 28.0f;
    for (size_t index = 0; index < page->action_count; index++) {
      y = draw_action(app, &page->actions[index], content.x + 8, y, content.width - 16);
    }
    for (size_t index = 0; index < row_action_count; index++) {
      y = draw_action(app, &row_actions[index], content.x + 8, y, content.width - 16);
    }
  }
  gfc_data_source_free_actions(row_actions, row_action_count);
  EndScissorMode();
}

static void draw_terminal(GfcApp* app, Rectangle bounds) {
  panel(bounds);
  Rectangle toggle = {bounds.x + bounds.width - 92, bounds.y + 8, 76, 26};
  if (GuiButton(toggle, app->show_terminal ? "Hide" : "Show")) {
    app->show_terminal = !app->show_terminal;
  }
  DrawText("Terminal", (int)bounds.x + 14, (int)bounds.y + 12, 18, TEXT);
  if (!app->show_terminal) {
    return;
  }
  float x = bounds.x + 12;
  for (size_t index = 0; index < app->terminal_count; index++) {
    Rectangle tab = {x, bounds.y + 42, 120, 28};
    if (index == app->selected_terminal) {
      DrawRectangleRounded(tab, 0.12f, 6, (Color){224, 233, 246, 255});
    }
    char label[160];
    snprintf(label, sizeof(label), "%s [%s]", app->terminals[index].title,
             app->terminals[index].status == GFC_TERMINAL_RUNNING ? "running" :
             app->terminals[index].status == GFC_TERMINAL_FAILED ? "failed" : "ok");
    if (GuiButton(tab, label)) {
      app->selected_terminal = index;
    }
    x += 126;
    if (app->terminals[index].closable) {
      if (GuiButton((Rectangle){x, bounds.y + 42, 42, 28},
                    app->terminals[index].status == GFC_TERMINAL_RUNNING ? "Stop" : "X")) {
        gfc_app_terminal_tab_action(app, index);
      }
      x += 48;
    }
    if (x > bounds.x + bounds.width - 130) {
      break;
    }
  }
  GfcTerminalEntry* terminal = &app->terminals[app->selected_terminal];
  Color status = terminal->status == GFC_TERMINAL_FAILED ? DANGER : MUTED;
  DrawText(
      terminal->status == GFC_TERMINAL_RUNNING ? "running" : "ready",
      (int)bounds.x + 14,
      (int)bounds.y + 76,
      12,
      status
  );
  Rectangle log_bounds = {bounds.x + 12, bounds.y + 96, bounds.width - 24, bounds.height - 108};
  Rectangle content = {log_bounds.x, log_bounds.y, log_bounds.width - 18, log_bounds.height + 800};
  Rectangle view = {0};
  Vector2 scroll = {0, app->terminal_scroll_y};
  GuiScrollPanel(log_bounds, "", content, &scroll, &view);
  app->terminal_scroll_y = scroll.y;
  BeginScissorMode((int)view.x, (int)view.y, (int)view.width, (int)view.height);
  wrapped_text(terminal->output, content.x + 8, content.y + scroll.y + 8, content.width - 16, 12, TEXT);
  EndScissorMode();
}

void gfc_ui_draw(GfcApp* app) {
  ClearBackground(BG);
  float width = (float)GetScreenWidth();
  float height = (float)GetScreenHeight();
  float gap = 14.0f;
  float sidebar_width = 280.0f;
  bool rtl = app_is_rtl(app);
  float terminal_height = app->show_terminal ? app->terminal_height : 42.0f;
  if (IsMouseButtonDown(MOUSE_BUTTON_LEFT)) {
    Vector2 mouse = GetMousePosition();
    float terminal_top = height - terminal_height - gap;
    if (app->show_terminal && mouse.y > terminal_top - 8 && mouse.y < terminal_top + 8) {
      app->terminal_height = height - mouse.y - gap;
      if (app->terminal_height < 120) app->terminal_height = 120;
      if (app->terminal_height > height * 0.45f) app->terminal_height = height * 0.45f;
    }
  }
  Rectangle sidebar = {
      rtl ? width - sidebar_width - gap : gap,
      gap,
      sidebar_width,
      height - gap * 2
  };
  Rectangle content = {
      rtl ? gap : sidebar_width + gap * 2,
      gap,
      width - sidebar_width - gap * 3,
      height - terminal_height - gap * 2
  };
  Rectangle terminal = {
      content.x,
      height - terminal_height - gap,
      content.width,
      terminal_height
  };
  draw_sidebar(app, sidebar);
  draw_page(app, content);
  draw_terminal(app, terminal);
}
