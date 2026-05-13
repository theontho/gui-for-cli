#include "ActionRenderer.hpp"

#include "Execution.hpp"

#include <imgui.h>

void renderActionButton(
    AppState& state,
    const ActionView& action,
    const std::map<std::string, std::string>& values,
    const std::string& suffix
) {
  auto unavailable = actionUnavailableReason(action, values);
  bool running = state.isActionRunning(suffix);
  auto title = (running ? std::string("Running... ") : std::string()) + action.title + "##" + suffix;
  bool enabled = unavailable.empty() && !running;
  bool destructive = action.role == "destructive";
  if (!enabled) {
    ImGui::BeginDisabled();
  }
  if (destructive) {
    ImGui::PushStyleColor(ImGuiCol_Button, ImVec4(0.70F, 0.12F, 0.12F, 1.0F));
    ImGui::PushStyleColor(ImGuiCol_ButtonHovered, ImVec4(0.82F, 0.18F, 0.18F, 1.0F));
    ImGui::PushStyleColor(ImGuiCol_ButtonActive, ImVec4(0.58F, 0.08F, 0.08F, 1.0F));
  }
  if (ImGui::Button(title.c_str())) {
    state.requestAction(action, values, suffix);
  }
  if (destructive) {
    ImGui::PopStyleColor(3);
  }
  if (!enabled) {
    ImGui::EndDisabled();
  }
  if (ImGui::IsItemHovered()) {
    ImGui::SetTooltip("%s", (running ? "Command is already running."
                                      : (enabled ? commandPreview(action, values) : unavailable))
                                  .c_str());
  }
}
