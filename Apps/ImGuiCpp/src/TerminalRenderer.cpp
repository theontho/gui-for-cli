#include "TerminalRenderer.hpp"

#include "RenderHelpers.hpp"

#include <imgui.h>

namespace {

const char* terminalStatusLabel(TerminalStatus status) {
  switch (status) {
    case TerminalStatus::Ready:
      return "ready";
    case TerminalStatus::Running:
      return "running";
    case TerminalStatus::Succeeded:
      return "ok";
    case TerminalStatus::Failed:
      return "failed";
    case TerminalStatus::Cancelled:
      return "cancelled";
  }
  return "unknown";
}

ImVec4 terminalStatusColor(TerminalStatus status) {
  switch (status) {
    case TerminalStatus::Running:
      return ImVec4(0.16F, 0.37F, 0.72F, 1.0F);
    case TerminalStatus::Succeeded:
      return ImVec4(0.14F, 0.50F, 0.22F, 1.0F);
    case TerminalStatus::Failed:
    case TerminalStatus::Cancelled:
      return ImVec4(0.75F, 0.12F, 0.12F, 1.0F);
    case TerminalStatus::Ready:
      return ImGui::GetStyleColorVec4(ImGuiCol_Text);
  }
  return ImGui::GetStyleColorVec4(ImGuiCol_Text);
}

}  // namespace

void renderTerminal(AppState& state) {
  if (!state.terminalVisible) {
    auto show = localizedLabel(state, "app.terminal.showOutput.label");
    if (ImGui::SmallButton(show.c_str())) {
      state.terminalVisible = true;
    }
    return;
  }

  ImGui::Text("%s", localizedLabel(state, "app.terminal.commandOutput.label").c_str());
  ImGui::SameLine();
  ImGui::SetNextItemWidth(160.0F);
  ImGui::SliderFloat("##terminal-height", &state.terminalHeight, 120.0F, 420.0F);
  ImGui::SameLine();
  ImGui::Checkbox(localizedLabel(state, "app.terminal.autoscroll.label").c_str(), &state.terminalAutoscroll);

  ImGui::BeginChild("terminal", ImVec2(0, state.terminalHeight), true);
  for (int index = 0; index < static_cast<int>(state.terminals.size()); ++index) {
    auto& entry = state.terminals[index];
    auto title = std::string("[") + terminalStatusLabel(entry.status) + "] " + entry.title +
                 "##terminal-" + std::to_string(entry.id);
    ImGui::PushStyleColor(ImGuiCol_Text, terminalStatusColor(entry.status));
    if (ImGui::SmallButton(title.c_str())) {
      state.selectedTerminal = index;
    }
    ImGui::PopStyleColor();
    if (entry.closable) {
      ImGui::SameLine();
      auto closeTitle =
          std::string(entry.status == TerminalStatus::Running ? "Cancel" : "Close") +
          "##terminal-close-" + std::to_string(entry.id);
      if (ImGui::SmallButton(closeTitle.c_str())) {
        state.closeOrCancelTerminal(index);
        break;
      }
    }
    ImGui::SameLine();
  }
  auto hide = localizedLabel(state, "app.terminal.hideOutput.label");
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
