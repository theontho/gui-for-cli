#include "Renderer.hpp"

#include "Execution.hpp"
#include "Utils.hpp"

#include <GLFW/glfw3.h>
#include <imgui.h>
#include <imgui_impl_glfw.h>
#include <imgui_impl_opengl3.h>

#include <algorithm>
#include <array>
#include <cstdio>
#include <iostream>
#include <set>
#include <sstream>
#include <stdexcept>

namespace {

struct Fonts {
  ImFont* section = nullptr;
};

std::string label(AppState& state, const std::string& key) {
  auto found = state.bundle.strings.find(key);
  return found == state.bundle.strings.end() ? key : found->second;
}

void sectionHeading(const char* title, const Fonts& fonts) {
  if (fonts.section != nullptr) {
    ImGui::PushFont(fonts.section);
  }
  ImGui::SeparatorText(title);
  if (fonts.section != nullptr) {
    ImGui::PopFont();
  }
}

void renderBodyText(const std::string& body, const Fonts& fonts) {
  std::istringstream input(body);
  std::string line;
  while (std::getline(input, line)) {
    if (line.empty()) {
      ImGui::Spacing();
    } else if (line.starts_with("## ")) {
      sectionHeading(line.substr(3).c_str(), fonts);
    } else {
      ImGui::TextWrapped("%s", line.c_str());
    }
  }
}

void renderTerminal(AppState& state) {
  if (!state.terminalVisible) {
    auto show = label(state, "app.terminal.showOutput.label");
    if (ImGui::SmallButton(show.c_str())) {
      state.terminalVisible = true;
    }
    return;
  }

  ImGui::Text("%s", label(state, "app.terminal.commandOutput.label").c_str());
  ImGui::SameLine();
  ImGui::SetNextItemWidth(160.0F);
  ImGui::SliderFloat("##terminal-height", &state.terminalHeight, 120.0F, 420.0F);
  ImGui::SameLine();
  ImGui::Checkbox(label(state, "app.terminal.autoscroll.label").c_str(), &state.terminalAutoscroll);

  ImGui::BeginChild("terminal", ImVec2(0, state.terminalHeight), true);
  for (int index = 0; index < static_cast<int>(state.terminals.size()); ++index) {
    auto& entry = state.terminals[index];
    auto title = entry.title + "##terminal-" + std::to_string(index);
    if (ImGui::SmallButton(title.c_str())) {
      state.selectedTerminal = index;
    }
    ImGui::SameLine();
  }
  auto hide = label(state, "app.terminal.hideOutput.label");
  if (ImGui::SmallButton(hide.c_str())) {
    state.terminalVisible = false;
  }
  ImGui::Separator();
  if (state.selectedTerminal >= 0 && state.selectedTerminal < static_cast<int>(state.terminals.size())) {
    ImGui::TextWrapped("%s", state.terminals[state.selectedTerminal].output.c_str());
  }
  if (state.terminalAutoscroll) {
    ImGui::SetScrollHereY(1.0F);
  }
  ImGui::EndChild();
}

std::string jsonText(const nlohmann::json& value) {
  if (value.is_string()) {
    return value.get<std::string>();
  }
  if (value.is_null()) {
    return "";
  }
  return value.dump();
}

std::string rowValue(const nlohmann::json& row, const std::string& column) {
  if (row.contains("values") && row["values"].is_object() && row["values"].contains(column)) {
    return jsonText(row["values"][column]);
  }
  if (row.contains(column)) {
    return jsonText(row[column]);
  }
  if (row.contains("label")) {
    return jsonText(row["label"]);
  }
  return row.dump();
}

void renderActionButton(
    AppState& state,
    const ActionView& action,
    const std::map<std::string, std::string>& values,
    const std::string& suffix
) {
  auto unavailable = actionUnavailableReason(action, values);
  auto title = action.title + "##" + suffix;
  bool enabled = unavailable.empty();
  if (!enabled) {
    ImGui::BeginDisabled();
  }
  if (ImGui::Button(title.c_str())) {
    state.requestAction(action, values, suffix);
  }
  if (!enabled) {
    ImGui::EndDisabled();
  }
  if (ImGui::IsItemHovered()) {
    ImGui::SetTooltip("%s", (enabled ? commandPreview(action, values) : unavailable).c_str());
  }
}

std::map<std::string, std::string> rowContext(
    AppState& state,
    const nlohmann::json& row
) {
  auto values = state.fieldValues;
  if (row.contains("values") && row["values"].is_object()) {
    for (auto iterator = row["values"].begin(); iterator != row["values"].end(); ++iterator) {
      auto value = jsonText(iterator.value());
      values[iterator.key()] = value;
      values["row." + iterator.key()] = value;
    }
  }
  return values;
}

std::string rowLabel(const nlohmann::json& row, std::size_t index) {
  if (row.contains("title") && row["title"].is_string()) {
    return row["title"].get<std::string>();
  }
  if (row.contains("values") && row["values"].is_object()) {
    for (const auto& key : {"name", "final", "code", "id"}) {
      if (row["values"].contains(key) && row["values"][key].is_string()) {
        return row["values"][key].get<std::string>();
      }
    }
  }
  return "row " + std::to_string(index + 1);
}

std::string optionId(const nlohmann::json& row, std::size_t index) {
  for (const auto& key : {"id", "value", "key"}) {
    if (row.contains(key)) {
      auto value = jsonText(row[key]);
      if (!value.empty()) {
        return value;
      }
    }
  }
  if (row.contains("values") && row["values"].is_object()) {
    for (const auto& key : {"id", "value", "name", "code"}) {
      if (row["values"].contains(key)) {
        auto value = jsonText(row["values"][key]);
        if (!value.empty()) {
          return value;
        }
      }
    }
  }
  return std::to_string(index);
}

std::set<std::string> commaSeparatedValues(const std::string& value) {
  std::set<std::string> result;
  std::istringstream input(value);
  std::string item;
  while (std::getline(input, item, ',')) {
    item.erase(0, item.find_first_not_of(" \t"));
    auto last = item.find_last_not_of(" \t");
    if (last == std::string::npos) {
      continue;
    }
    result.insert(item.substr(0, last + 1));
  }
  return result;
}

std::string joinSelectedValues(const std::set<std::string>& values) {
  return join(std::vector<std::string>(values.begin(), values.end()), ",");
}

void renderDataControl(AppState& state, const ControlView& control) {
  auto rows = state.dataRows(control);
  if (!rows.error.empty()) {
    ImGui::TextColored(ImVec4(0.75F, 0.12F, 0.12F, 1.0F), "%s: %s",
                       label(state, "app.dataSource.error.title").c_str(), rows.error.c_str());
    return;
  }
  if (rows.rows.empty()) {
    ImGui::TextDisabled("%s", label(state, "app.library.empty").c_str());
    return;
  }

  int columns = std::max(1, static_cast<int>(control.columns.size())) + 1;
  if (ImGui::BeginTable((control.id + "-table").c_str(), columns,
                        ImGuiTableFlags_Borders | ImGuiTableFlags_RowBg | ImGuiTableFlags_Resizable)) {
    if (control.columns.empty()) {
      ImGui::TableSetupColumn("value");
    } else {
      for (const auto& column : control.columns) {
        ImGui::TableSetupColumn(column.title.c_str());
      }
    }
    ImGui::TableSetupColumn(label(state, "app.actionsColumn.title").c_str());
    ImGui::TableHeadersRow();
    for (std::size_t rowIndex = 0; rowIndex < rows.rows.size(); ++rowIndex) {
      const auto& row = rows.rows[rowIndex];
      auto values = rowContext(state, row);
      ImGui::TableNextRow();
      if (control.columns.empty()) {
        ImGui::TableNextColumn();
        ImGui::TextWrapped("%s", row.dump().c_str());
      } else {
        for (const auto& column : control.columns) {
          ImGui::TableNextColumn();
          ImGui::TextWrapped("%s", rowValue(row, column.id).c_str());
        }
      }
      ImGui::TableNextColumn();
      for (std::size_t actionIndex = 0; actionIndex < control.rowActions.size(); ++actionIndex) {
        if (!isActionVisible(control.rowActions[actionIndex], values)) {
          continue;
        }
        auto action = control.rowActions[actionIndex];
        action.title = rowLabel(row, rowIndex) + ": " + action.title;
        renderActionButton(
            state,
            action,
            values,
            control.id + "-row-" + std::to_string(rowIndex) + "-action-" + std::to_string(actionIndex)
        );
        ImGui::SameLine();
      }
    }
    ImGui::EndTable();
  }
}

bool renderDropdownFromRows(AppState& state, const ControlView& control, std::string& value) {
  auto rows = state.dataRows(control);
  if (!rows.error.empty()) {
    ImGui::TextColored(ImVec4(0.75F, 0.12F, 0.12F, 1.0F), "%s: %s",
                       label(state, "app.dataSource.error.title").c_str(), rows.error.c_str());
    return false;
  }

  std::vector<OptionView> options;
  for (std::size_t index = 0; index < rows.rows.size(); ++index) {
    options.push_back(OptionView{optionId(rows.rows[index], index), rowLabel(rows.rows[index], index)});
  }
  if (options.empty()) {
    ImGui::TextDisabled("%s", label(state, "app.library.empty").c_str());
    return false;
  }

  int current = 0;
  bool matched = false;
  for (int index = 0; index < static_cast<int>(options.size()); ++index) {
    if (options[index].id == value) {
      current = index;
      matched = true;
    }
  }
  bool edited = false;
  auto preview = matched ? options[current].title : (value.empty() ? control.placeholder : value);
  if (ImGui::BeginCombo(("##" + control.id).c_str(), preview.c_str())) {
    for (int index = 0; index < static_cast<int>(options.size()); ++index) {
      bool selected = options[index].id == value;
      if (ImGui::Selectable(options[index].title.c_str(), selected)) {
        value = options[index].id;
        edited = true;
      }
    }
    ImGui::EndCombo();
  }
  return edited;
}

void renderControl(AppState& state, const ControlView& control) {
  ImGui::Separator();
  ImGui::Text("%s", control.label.c_str());
  auto value = state.fieldValues.contains(control.id) ? state.fieldValues[control.id] : control.value;
  bool edited = false;

  if (control.kind == "toggle") {
    bool checked = value == "true";
    edited = ImGui::Checkbox(("##" + control.id).c_str(), &checked);
    value = checked ? "true" : "false";
  } else if (control.kind == "checkboxGroup") {
    auto selected = commaSeparatedValues(value);
    for (const auto& option : control.optionItems) {
      bool checked = selected.contains(option.id);
      if (ImGui::Checkbox((option.title + "##" + control.id + "-" + option.id).c_str(), &checked)) {
        if (checked) {
          selected.insert(option.id);
        } else {
          selected.erase(option.id);
        }
        value = joinSelectedValues(selected);
        edited = true;
      }
    }
  } else if (control.kind == "dropdown" && !control.optionItems.empty()) {
    int current = 0;
    for (int index = 0; index < static_cast<int>(control.optionItems.size()); ++index) {
      if (control.optionItems[index].id == value) {
        current = index;
      }
    }
    if (ImGui::BeginCombo(("##" + control.id).c_str(), control.optionItems[current].title.c_str())) {
      for (int index = 0; index < static_cast<int>(control.optionItems.size()); ++index) {
        bool selected = index == current;
        if (ImGui::Selectable(control.optionItems[index].title.c_str(), selected)) {
          current = index;
          value = control.optionItems[index].id;
          edited = true;
        }
      }
      ImGui::EndCombo();
    }
  } else if (control.kind == "dropdown" && control.dataSource) {
    edited = renderDropdownFromRows(state, control, value);
  } else if (control.kind == "infoGrid" || control.kind == "libraryList") {
    renderDataControl(state, control);
  } else {
    std::array<char, 4096> buffer{};
    std::snprintf(buffer.data(), buffer.size(), "%s", value.c_str());
    edited = ImGui::InputTextWithHint(
        ("##" + control.id).c_str(),
        control.placeholder.c_str(),
        buffer.data(),
        buffer.size()
    );
    value = buffer.data();
  }

  if (edited) {
    state.setControlValue(control, value);
  }
  if (!control.helper.empty()) {
    ImGui::TextDisabled("%s", control.helper.c_str());
  }
}

void renderConfirmationModal(AppState& state) {
  if (!state.pendingConfirmation) {
    return;
  }
  auto& pending = *state.pendingConfirmation;
  const auto& confirmation = *pending.action.confirmation;
  auto title = confirmation.title.empty() ? pending.action.title : confirmation.title;
  auto popupTitle = title + "###confirm-action";
  ImGui::OpenPopup(popupTitle.c_str());
  if (!ImGui::BeginPopupModal(popupTitle.c_str(), nullptr, ImGuiWindowFlags_AlwaysAutoResize)) {
    return;
  }

  ImGui::TextWrapped("%s", title.c_str());
  if (!confirmation.message.empty()) {
    ImGui::TextWrapped("%s", confirmation.message.c_str());
  }

  bool canConfirm = true;
  if (!confirmation.requiredText.empty()) {
    if (!confirmation.prompt.empty()) {
      ImGui::TextWrapped("%s", confirmation.prompt.c_str());
    }
    std::array<char, 256> buffer{};
    std::snprintf(buffer.data(), buffer.size(), "%s", pending.typedText.c_str());
    if (ImGui::InputText("##confirm-required-text", buffer.data(), buffer.size())) {
      pending.typedText = buffer.data();
    }
    canConfirm = pending.typedText == confirmation.requiredText;
  }

  if (!canConfirm) {
    ImGui::BeginDisabled();
  }
  if (ImGui::Button(confirmation.confirmButtonTitle.c_str())) {
    ImGui::CloseCurrentPopup();
    state.confirmPendingAction();
  }
  if (!canConfirm) {
    ImGui::EndDisabled();
  }
  ImGui::SameLine();
  if (ImGui::Button(confirmation.cancelButtonTitle.c_str())) {
    ImGui::CloseCurrentPopup();
    state.cancelPendingAction();
  }
  ImGui::EndPopup();
}

void renderPage(AppState& state, const Fonts& fonts) {
  if (state.bundle.pages.empty()) {
    return;
  }
  auto& page = state.bundle.pages[state.selectedPage];
  sectionHeading(page.title.c_str(), fonts);
  if (!page.summary.empty()) {
    ImGui::TextWrapped("%s", page.summary.c_str());
  }
  renderBodyText(page.body, fonts);
  for (const auto& control : page.controls) {
    renderControl(state, control);
  }
  sectionHeading(label(state, "app.actionsColumn.title").c_str(), fonts);
  auto values = state.effectiveFieldValues(page);
  for (const auto& action : state.visibleActions(page)) {
    renderActionButton(state, action, values, "page-action-" + action.id);
    ImGui::TextWrapped("%s", commandPreview(action, values).c_str());
  }
}

void renderSetupSteps(AppState& state) {
  if (state.bundle.setupSteps.empty()) {
    return;
  }
  ImGui::SeparatorText(label(state, "app.setup.status.title").c_str());
  for (std::size_t index = 0; index < state.bundle.setupSteps.size(); ++index) {
    const auto& step = state.bundle.setupSteps[index];
    auto buttonTitle = step.label + "##setup-step-" + std::to_string(index);
    if (ImGui::SmallButton(buttonTitle.c_str())) {
      state.startSetupStep(step);
    }
    if (ImGui::IsItemHovered()) {
      ImGui::SetTooltip("%s", setupCommandPreview(step, state.args.bundle).c_str());
    }
  }
}

void renderSidebar(AppState& state) {
  ImGui::BeginChild("sidebar", ImVec2(270.0F, 0), true);
  ImGui::TextWrapped("%s", state.bundle.title.c_str());
  if (!state.bundle.summary.empty()) {
    ImGui::TextWrapped("%s", state.bundle.summary.c_str());
  }
  if (!state.bundle.setupLines.empty()) {
    ImGui::SeparatorText(label(state, "app.setup.status.title").c_str());
    for (const auto& line : state.bundle.setupLines) {
      ImGui::TextWrapped("%s", line.c_str());
    }
  }
  renderSetupSteps(state);
  ImGui::SeparatorText(label(state, "app.standardOptions.title").c_str());
  ImGui::SliderFloat(label(state, "app.fontSize.label").c_str(), &state.fontScale, 0.8F, 1.6F);
  ImGui::Separator();
  for (int index = 0; index < static_cast<int>(state.bundle.pages.size()); ++index) {
    if (ImGui::Selectable(state.bundle.pages[index].title.c_str(), index == state.selectedPage)) {
      state.selectedPage = index;
    }
  }
  ImGui::EndChild();
}

void renderRoot(AppState& state, const Fonts& fonts) {
  state.pollFinishedActions();
  ImGui::SetNextWindowPos(ImVec2(0, 0), ImGuiCond_Always);
  ImGui::SetNextWindowSize(ImGui::GetIO().DisplaySize, ImGuiCond_Always);
  ImGui::Begin(
      "##gui-for-cli-imgui-cpp-root",
      nullptr,
      ImGuiWindowFlags_NoDecoration | ImGuiWindowFlags_NoMove | ImGuiWindowFlags_NoResize
  );
  ImGui::SetWindowFontScale(state.fontScale);
  renderSidebar(state);
  ImGui::SameLine();
  ImGui::BeginChild("detail", ImVec2(0, 0), true);
  float terminalSpace = state.terminalVisible ? state.terminalHeight + 58.0F : 34.0F;
  ImGui::BeginChild("page", ImVec2(0, -terminalSpace), false);
  renderPage(state, fonts);
  ImGui::EndChild();
  ImGui::Separator();
  renderTerminal(state);
  renderConfirmationModal(state);
  ImGui::EndChild();
  ImGui::End();
}

}  // namespace

void runRenderer(AppState& state) {
  glfwSetErrorCallback([](int, const char* description) {
    std::cerr << "glfw: " << description << '\n';
  });
  if (!glfwInit()) {
    throw std::runtime_error("initialize GLFW");
  }

  const char* glslVersion = "#version 150";
  glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 3);
  glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 2);
  glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);
  glfwWindowHint(GLFW_OPENGL_FORWARD_COMPAT, GL_TRUE);
  GLFWwindow* window =
      glfwCreateWindow(1180, 760, (state.bundle.title + " - ImGui C++").c_str(), nullptr, nullptr);
  if (window == nullptr) {
    glfwTerminate();
    throw std::runtime_error("create GLFW window");
  }
  glfwMakeContextCurrent(window);
  glfwSwapInterval(1);

  IMGUI_CHECKVERSION();
  ImGui::CreateContext();
  ImGuiIO& io = ImGui::GetIO();
  io.IniFilename = nullptr;
  ImFontConfig baseConfig;
  baseConfig.SizePixels = 17.0F;
  io.Fonts->AddFontDefault(&baseConfig);
  ImFontConfig sectionConfig;
  sectionConfig.SizePixels = 21.0F;
  Fonts fonts{io.Fonts->AddFontDefault(&sectionConfig)};

  ImGui::StyleColorsLight();
  ImGui_ImplGlfw_InitForOpenGL(window, true);
  ImGui_ImplOpenGL3_Init(glslVersion);

  while (!glfwWindowShouldClose(window)) {
    glfwPollEvents();
    ImGui_ImplOpenGL3_NewFrame();
    ImGui_ImplGlfw_NewFrame();
    ImGui::NewFrame();
    renderRoot(state, fonts);
    ImGui::Render();
    int width = 0;
    int height = 0;
    glfwGetFramebufferSize(window, &width, &height);
    glViewport(0, 0, width, height);
    glClearColor(0.94F, 0.95F, 0.97F, 1.0F);
    glClear(GL_COLOR_BUFFER_BIT);
    ImGui_ImplOpenGL3_RenderDrawData(ImGui::GetDrawData());
    glfwSwapBuffers(window);
  }

  ImGui_ImplOpenGL3_Shutdown();
  ImGui_ImplGlfw_Shutdown();
  ImGui::DestroyContext();
  glfwDestroyWindow(window);
  glfwTerminate();
}
