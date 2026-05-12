cmake_minimum_required(VERSION 3.24)

project(GUIForCLIImGuiCpp LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

include(FetchContent)

FetchContent_Declare(
  glfw
  GIT_REPOSITORY https://github.com/glfw/glfw.git
  GIT_TAG 3.4
)
set(GLFW_BUILD_DOCS OFF CACHE BOOL "" FORCE)
set(GLFW_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(GLFW_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(GLFW_INSTALL OFF CACHE BOOL "" FORCE)
FetchContent_MakeAvailable(glfw)

FetchContent_Declare(
  imgui
  GIT_REPOSITORY https://github.com/ocornut/imgui.git
  GIT_TAG v1.92.4
)
FetchContent_MakeAvailable(imgui)

FetchContent_Declare(
  nlohmann_json
  URL https://github.com/nlohmann/json/releases/download/v3.12.0/json.tar.xz
)
FetchContent_MakeAvailable(nlohmann_json)

find_package(OpenGL REQUIRED)

add_library(gui_for_cli_imgui_cpp_backend STATIC
  ${imgui_SOURCE_DIR}/imgui.cpp
  ${imgui_SOURCE_DIR}/imgui_draw.cpp
  ${imgui_SOURCE_DIR}/imgui_tables.cpp
  ${imgui_SOURCE_DIR}/imgui_widgets.cpp
  ${imgui_SOURCE_DIR}/backends/imgui_impl_glfw.cpp
  ${imgui_SOURCE_DIR}/backends/imgui_impl_opengl3.cpp
)
target_include_directories(gui_for_cli_imgui_cpp_backend PUBLIC
  ${imgui_SOURCE_DIR}
  ${imgui_SOURCE_DIR}/backends
)
target_compile_definitions(gui_for_cli_imgui_cpp_backend PUBLIC
  GL_SILENCE_DEPRECATION
  IMGUI_DISABLE_DEMO_WINDOWS
  IMGUI_DISABLE_DEBUG_TOOLS
)
target_link_libraries(gui_for_cli_imgui_cpp_backend PUBLIC glfw OpenGL::GL)

add_executable(gui-for-cli-imgui-cpp
  src/AppState.cpp
  src/Args.cpp
  src/ActionRenderer.cpp
  src/Bundle.cpp
  src/ConfigStore.cpp
  src/ControlRenderer.cpp
  src/Execution.cpp
  src/PathPicker.cpp
  src/Renderer.cpp
  src/TerminalRenderer.cpp
  src/Utils.cpp
  src/main.cpp
)
target_include_directories(gui-for-cli-imgui-cpp PRIVATE src)
target_compile_definitions(gui-for-cli-imgui-cpp PRIVATE
  IMGUI_DISABLE_DEMO_WINDOWS
  IMGUI_DISABLE_DEBUG_TOOLS
)
target_link_libraries(gui-for-cli-imgui-cpp PRIVATE
  gui_for_cli_imgui_cpp_backend
  nlohmann_json::nlohmann_json
)
