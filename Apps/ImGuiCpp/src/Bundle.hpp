#pragma once

#include <filesystem>
#include <map>
#include <optional>
#include <string>
#include <vector>

struct ActionCondition {
  std::string placeholder;
  std::optional<std::string> equals;
  std::optional<std::string> notEquals;
  std::vector<std::string> inValues;
  std::vector<std::string> notInValues;
  std::optional<bool> exists;
};

struct DataSourceView {
  std::string path;
  std::vector<std::string> arguments;
  std::map<std::string, std::string> environment;
  std::optional<std::string> workingDirectory;
};

struct OptionView {
  std::string id;
  std::string title;
  std::string group;
  bool selected = false;
};

struct ColumnView {
  std::string id;
  std::string title;
};

struct ActionConfirmationView {
  std::string title;
  std::string message;
  std::string confirmButtonTitle;
  std::string cancelButtonTitle;
  std::string requiredText;
  std::string prompt;
};

struct ActionView {
  std::string id;
  std::string title;
  std::string role = "primary";
  std::string executable;
  std::vector<std::string> arguments;
  std::vector<std::vector<std::string>> optionalArguments;
  std::map<std::string, std::string> environment;
  std::optional<std::string> workingDirectory;
  std::vector<ActionCondition> visibleWhen;
  std::vector<ActionCondition> disabledWhen;
  std::string disabledTooltip = "This action is not available.";
  std::optional<ActionConfirmationView> confirmation;
};

struct ControlView {
  std::string id;
  std::string label;
  std::string kind = "text";
  std::string value;
  std::string placeholder;
  std::string helper;
  std::string options;
  std::vector<OptionView> optionItems;
  std::optional<DataSourceView> dataSource;
  std::vector<ColumnView> columns;
  std::vector<ActionView> rowActions;
  std::string configFilePath;
  std::string configKey;
};

struct SetupStepView {
  std::string label;
  std::string kind;
  std::string value;
  std::vector<std::string> arguments;
  std::map<std::string, std::string> environment;
  std::optional<std::string> workingDirectory;
  bool optional = false;
};

struct PageView {
  std::string id;
  std::string title;
  std::string summary;
  std::string body;
  std::vector<ControlView> controls;
  std::vector<ActionView> actions;
};

struct BundleView {
  std::string title;
  std::string summary;
  std::map<std::string, std::string> strings;
  std::string terminalTextDirection = "ltr";
  std::vector<std::string> setupLines;
  std::vector<SetupStepView> setupSteps;
  std::vector<PageView> pages;
  int controlCount = 0;
  int actionCount = 0;
  int dataSourceCount = 0;
};

BundleView loadBundle(
    const std::filesystem::path& bundleRoot,
    const std::filesystem::path& repoRoot,
    const std::string& locale
);
