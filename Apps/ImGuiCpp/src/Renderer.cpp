#include "Renderer.hpp"

#include "ActionRenderer.hpp"
#include "ControlRenderer.hpp"
#include "Execution.hpp"
#include "RenderHelpers.hpp"
#include "TerminalRenderer.hpp"

#include <GLFW/glfw3.h>
#include <imgui.h>
#include <imgui_impl_glfw.h>
#include <imgui_impl_opengl3.h>

#include <iostream>
#include <sstream>
#include <stdexcept>

namespace {

struct Fonts {
  ImFont* section = nullptr;
};

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
  sectionHeading(localizedLabel(state, "app.actionsColumn.title").c_str(), fonts);
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
  ImGui::SeparatorText(localizedLabel(state, "app.setup.status.title").c_str());
  for (std::size_t index = 0; index < state.bundle.setupSteps.size(); ++index) {
    const auto& step = state.bundle.setupSteps[index];
    auto actionKey = "setup-step-" + std::to_string(index);
    auto buttonTitle =
        (state.isActionRunning(actionKey) ? std::string("Running... ") : std::string()) +
        step.label + "##" + actionKey;
    if (state.isActionRunning(actionKey)) {
      ImGui::BeginDisabled();
    }
    if (ImGui::SmallButton(buttonTitle.c_str())) {
      state.startSetupStep(step, actionKey);
    }
    if (state.isActionRunning(actionKey)) {
      ImGui::EndDisabled();
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
    ImGui::SeparatorText(localizedLabel(state, "app.setup.status.title").c_str());
    for (const auto& line : state.bundle.setupLines) {
      ImGui::TextWrapped("%s", line.c_str());
    }
  }
  renderSetupSteps(state);
  ImGui::SeparatorText(localizedLabel(state, "app.standardOptions.title").c_str());
  ImGui::SliderFloat(localizedLabel(state, "app.fontSize.label").c_str(), &state.fontScale, 0.8F, 1.6F);
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
  bool rtl = state.bundle.terminalTextDirection == "rtl";
  if (!rtl) {
    renderSidebar(state);
    ImGui::SameLine();
  }
  ImGui::BeginChild("detail", ImVec2(rtl ? -270.0F : 0, 0), true);
  float terminalSpace = state.terminalVisible ? state.terminalHeight + 58.0F : 34.0F;
  ImGui::BeginChild("page", ImVec2(0, -terminalSpace), false);
  renderPage(state, fonts);
  ImGui::EndChild();
  ImGui::Separator();
  renderTerminal(state);
  renderConfirmationModal(state);
  ImGui::EndChild();
  if (rtl) {
    ImGui::SameLine();
    renderSidebar(state);
  }
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
