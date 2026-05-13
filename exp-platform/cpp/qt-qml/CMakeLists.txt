cmake_minimum_required(VERSION 3.24)

project(GUIForCLIQtQML LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

option(GUI_FOR_CLI_QT_QML_VALIDATE_ONLY "Configure source checks without requiring Qt" OFF)

set(QT_QML_CPP_FILES
  src/Args.cpp
  src/BundleLoader.cpp
  src/CommandRunner.cpp
  src/Controller.cpp
  src/JsonUtils.cpp
  src/main.cpp
  src/StateStore.cpp
)
set(QT_QML_HEADER_FILES
  src/Args.hpp
  src/BundleLoader.hpp
  src/CommandRunner.hpp
  src/Controller.hpp
  src/JsonUtils.hpp
  src/StateStore.hpp
)
set(QT_QML_QML_FILES
  qml/Main.qml
  qml/AppShell.qml
  qml/ActionButton.qml
  qml/ConfirmationDialog.qml
  qml/ControlField.qml
  qml/HeaderBar.qml
  qml/LibraryList.qml
  qml/PageView.qml
  qml/SectionView.qml
  qml/Sidebar.qml
  qml/TerminalDrawer.qml
)

if(GUI_FOR_CLI_QT_QML_VALIDATE_ONLY)
  include(cmake/ValidateSources.cmake)
  add_custom_target(gui-for-cli-qt-qml-validate ALL
    COMMAND ${CMAKE_COMMAND} -E echo "Qt QML source manifest validated"
  )
  return()
endif()

find_package(Qt6 6.5 REQUIRED COMPONENTS Core Gui Qml Quick QuickControls2)
qt_standard_project_setup(REQUIRES 6.5)

qt_add_executable(gui-for-cli-qt-qml
  ${QT_QML_CPP_FILES}
  ${QT_QML_HEADER_FILES}
)

target_compile_definitions(gui-for-cli-qt-qml PRIVATE
  QT_NO_KEYWORDS
  QT_QML_DEBUG_NO_WARNING
)

target_link_libraries(gui-for-cli-qt-qml PRIVATE
  Qt6::Core
  Qt6::Gui
  Qt6::Qml
  Qt6::Quick
  Qt6::QuickControls2
)

qt_add_qml_module(gui-for-cli-qt-qml
  URI GUIForCLIQtQML
  VERSION 1.0
  QML_FILES ${QT_QML_QML_FILES}
)
