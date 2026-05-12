#include "ControlRenderer.hpp"

#include "ActionRenderer.hpp"
#include "Execution.hpp"
#include "PathPicker.hpp"
#include "RenderHelpers.hpp"
#include "Utils.hpp"

#include <imgui.h>
#include <nlohmann/json.hpp>

#include <algorithm>
#include <array>
#include <cstdio>
#include <set>
#include <sstream>

namespace {

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
                       localizedLabel(state, "app.dataSource.error.title").c_str(), rows.error.c_str());
    return;
  }
  if (rows.rows.empty()) {
    ImGui::TextDisabled("%s", localizedLabel(state, "app.library.empty").c_str());
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
    ImGui::TableSetupColumn(localizedLabel(state, "app.actionsColumn.title").c_str());
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
                       localizedLabel(state, "app.dataSource.error.title").c_str(), rows.error.c_str());
    return false;
  }

  std::vector<OptionView> options;
  for (std::size_t index = 0; index < rows.rows.size(); ++index) {
    options.push_back(OptionView{optionId(rows.rows[index], index), rowLabel(rows.rows[index], index)});
  }
  if (options.empty()) {
    ImGui::TextDisabled("%s", localizedLabel(state, "app.library.empty").c_str());
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

}  // namespace

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
  } else if (control.kind == "path") {
    std::array<char, 4096> buffer{};
    std::snprintf(buffer.data(), buffer.size(), "%s", value.c_str());
    edited = ImGui::InputTextWithHint(
        ("##" + control.id).c_str(),
        control.placeholder.c_str(),
        buffer.data(),
        buffer.size()
    );
    value = buffer.data();
    ImGui::SameLine();
    if (ImGui::SmallButton(("File##pick-file-" + control.id).c_str())) {
      if (auto chosen = choosePath(value, false)) {
        value = *chosen;
        edited = true;
      }
    }
    ImGui::SameLine();
    if (ImGui::SmallButton(("Folder##pick-folder-" + control.id).c_str())) {
      if (auto chosen = choosePath(value, true)) {
        value = *chosen;
        edited = true;
      }
    }
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
