cmake_minimum_required(VERSION 3.24)

project(GUIForCLIRayguiC LANGUAGES C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_C_EXTENSIONS OFF)

include(FetchContent)

FetchContent_Declare(
  raylib
  GIT_REPOSITORY https://github.com/raysan5/raylib.git
  GIT_TAG c1ab645ca298a2801097931d1079b10ff7eb9df8
)
set(BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
FetchContent_MakeAvailable(raylib)

FetchContent_Declare(
  raygui
  GIT_REPOSITORY https://github.com/raysan5/raygui.git
  GIT_TAG 25c8c65a6e5f0f4d4b564a0343861898c6f2778b
)
FetchContent_MakeAvailable(raygui)

FetchContent_Declare(
  cjson
  GIT_REPOSITORY https://github.com/DaveGamble/cJSON.git
  GIT_TAG c859b25da02955fef659d658b8f324b5cde87be3
)
set(CMAKE_POLICY_VERSION_MINIMUM 3.5)
set(ENABLE_CJSON_TEST OFF CACHE BOOL "" FORCE)
set(ENABLE_CJSON_UTILS OFF CACHE BOOL "" FORCE)
set(ENABLE_CJSON_UNINSTALL OFF CACHE BOOL "" FORCE)
set(ENABLE_TARGET_EXPORT OFF CACHE BOOL "" FORCE)
FetchContent_MakeAvailable(cjson)

find_package(Threads REQUIRED)

add_executable(gui-for-cli-raygui-c
  src/app.c
  src/args.c
  src/bundle.c
  src/bundle_free.c
  src/command_runner.c
  src/data_source.c
  src/main.c
  src/raygui_backend.c
  src/setup_actions.c
  src/state.c
  src/string_map.c
  src/ui.c
  src/utils.c
)

target_include_directories(gui-for-cli-raygui-c PRIVATE
  src
  ${raygui_SOURCE_DIR}/src
  ${cjson_SOURCE_DIR}
)
target_compile_definitions(gui-for-cli-raygui-c PRIVATE
  GL_SILENCE_DEPRECATION
)
target_link_libraries(gui-for-cli-raygui-c PRIVATE
  cjson
  raylib
  Threads::Threads
)
