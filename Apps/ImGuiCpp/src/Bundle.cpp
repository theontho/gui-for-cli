#include "Bundle.hpp"

#include "Utils.hpp"

#include <algorithm>
#include <cctype>
#include <nlohmann/json.hpp>
#include <stdexcept>

using nlohmann::json;

namespace {

json readJson(const std::filesystem::path& path) {
  try {
    return json::parse(readTextFile(path));
  } catch (const std::exception& error) {
    throw std::runtime_error("parse " + path.string() + ": " + error.what());
  }
}

std::string localized(
    const json& value,
    const std::map<std::string, std::string>& strings,
    const std::string& fallback
) {
  if (!value.is_string()) {
    return fallback;
  }
  return localize(value.get<std::string>(), strings);
}

std::vector<std::string> stringsFrom(const json& value) {
  std::vector<std::string> result;
  if (!value.is_array()) {
    return result;
  }
  for (const auto& item : value) {
    result.push_back(valueToString(item));
  }
  return result;
}

std::map<std::string, std::string> stringMapFrom(
    const json& value,
    const std::filesystem::path& bundleRoot
) {
  std::map<std::string, std::string> result;
  if (!value.is_object()) {
    return result;
  }
  for (auto iterator = value.begin(); iterator != value.end(); ++iterator) {
    result[iterator.key()] = interpolateBuiltins(valueToString(iterator.value()), bundleRoot);
  }
  return result;
}

std::vector<ActionCondition> conditionsFrom(const json& value) {
  std::vector<ActionCondition> conditions;
  if (!value.is_array()) {
    return conditions;
  }
  for (const auto& item : value) {
    if (!item.is_object()) {
      continue;
    }
    ActionCondition condition;
    condition.placeholder = item.value("placeholder", "");
    if (item.contains("equals")) {
      condition.equals = valueToString(item["equals"]);
    }
    if (item.contains("notEquals")) {
      condition.notEquals = valueToString(item["notEquals"]);
    }
    if (item.contains("in") && item["in"].is_array()) {
      condition.inValues = stringsFrom(item["in"]);
    }
    if (item.contains("notIn") && item["notIn"].is_array()) {
      condition.notInValues = stringsFrom(item["notIn"]);
    }
    if (item.contains("exists") && item["exists"].is_boolean()) {
      condition.exists = item["exists"].get<bool>();
    }
    conditions.push_back(std::move(condition));
  }
  return conditions;
}

std::vector<OptionView> optionViews(
    const json& options,
    const std::map<std::string, std::string>& strings
) {
  std::vector<OptionView> result;
  if (!options.is_array()) {
    return result;
  }
  for (const auto& option : options) {
    OptionView view;
    view.id = option.value("id", "");
    view.title = localized(option.value("title", json()), strings, view.id);
    view.group = option.value("group", "");
    view.selected = option.value("selected", false);
    result.push_back(std::move(view));
  }
  return result;
}

std::string optionTitles(const std::vector<OptionView>& options) {
  std::vector<std::string> titles;
  for (const auto& option : options) {
    titles.push_back(option.title);
  }
  return join(titles, ", ");
}

std::string selectedOptionIds(const std::vector<OptionView>& options) {
  std::vector<std::string> ids;
  for (const auto& option : options) {
    if (option.selected) {
      ids.push_back(option.id);
    }
  }
  return join(ids, ",");
}

std::vector<ColumnView> columnViews(
    const json& columns,
    const std::map<std::string, std::string>& strings
) {
  std::vector<ColumnView> result;
  if (!columns.is_array()) {
    return result;
  }
  for (const auto& column : columns) {
    ColumnView view;
    view.id = column.value("id", "");
    view.title = localized(column.value("title", json()), strings, view.id);
    result.push_back(std::move(view));
  }
  return result;
}

DataSourceView dataSourceView(const json& dataSource, const std::filesystem::path& bundleRoot) {
  DataSourceView view;
  view.path = interpolateBuiltins(dataSource.value("path", ""), bundleRoot);
  for (const auto& argument : stringsFrom(dataSource.value("arguments", json::array()))) {
    view.arguments.push_back(interpolateBuiltins(argument, bundleRoot));
  }
  view.environment = stringMapFrom(dataSource.value("environment", json::object()), bundleRoot);
  if (dataSource.contains("workingDirectory")) {
    view.workingDirectory =
        interpolateBuiltins(dataSource.value("workingDirectory", ""), bundleRoot);
  }
  return view;
}

std::vector<std::vector<std::string>> optionalArguments(
    const json& command,
    const std::filesystem::path& bundleRoot
) {
  std::vector<std::vector<std::string>> result;
  auto groups = command.value("optionalArguments", json::array());
  if (!groups.is_array()) {
    return result;
  }
  for (const auto& group : groups) {
    std::vector<std::string> rendered;
    for (const auto& argument : stringsFrom(group)) {
      rendered.push_back(interpolateBuiltins(argument, bundleRoot));
    }
    result.push_back(std::move(rendered));
  }
  return result;
}

std::optional<ActionView> actionView(
    const json& action,
    const std::map<std::string, std::string>& strings,
    const std::filesystem::path& bundleRoot
) {
  if (!action.contains("command")) {
    return std::nullopt;
  }
  const auto& command = action["command"];
  ActionView view;
  view.id = action.value("id", "");
  view.title = localized(action.value("title", json()), strings, view.id);
  view.role = action.value("role", "primary");
  view.executable = interpolateBuiltins(command.value("executable", ""), bundleRoot);
  for (const auto& argument : stringsFrom(command.value("arguments", json::array()))) {
    view.arguments.push_back(interpolateBuiltins(argument, bundleRoot));
  }
  view.optionalArguments = optionalArguments(command, bundleRoot);
  view.environment = stringMapFrom(command.value("environment", json::object()), bundleRoot);
  if (command.contains("workingDirectory")) {
    view.workingDirectory = interpolateBuiltins(command.value("workingDirectory", ""), bundleRoot);
  }
  view.visibleWhen = conditionsFrom(action.value("visibleWhen", json::array()));
  view.disabledWhen = conditionsFrom(action.value("disabledWhen", json::array()));
  view.disabledTooltip = localized(
      action.value("disabledTooltip", json("This action is not available.")),
      strings,
      "This action is not available."
  );
  if (action.contains("confirm")) {
    const auto& confirm = action["confirm"];
    view.confirmation = ActionConfirmationView{
        localized(confirm.value("title", json()), strings, ""),
        localized(confirm.value("message", json()), strings, ""),
        localized(confirm.value("confirmButtonTitle", json("Continue")), strings, "Continue"),
        localized(confirm.value("cancelButtonTitle", json("Cancel")), strings, "Cancel"),
        confirm.value("requiredText", ""),
        localized(confirm.value("prompt", json()), strings, ""),
    };
  }
  return view;
}

bool isEditableControl(const std::string& kind) {
  return kind == "text" || kind == "path" || kind == "dropdown" || kind == "toggle" ||
         kind == "checkboxGroup" || kind == "infoGrid" || kind == "libraryList";
}

std::string renderActionText(
    const json& action,
    const std::map<std::string, std::string>& strings,
    const std::string& prefix
) {
  auto title = localized(action.value("title", json()), strings, action.value("id", ""));
  auto role = action.value("role", "primary");
  std::vector<std::string> lines{prefix + "> " + title + " (" + role + ")"};
  if (action.contains("tooltip")) {
    lines.push_back("  " + localized(action["tooltip"], strings, ""));
  }
  if (action.contains("command")) {
    const auto& command = action["command"];
    auto parts = stringsFrom(command.value("arguments", json::array()));
    parts.insert(parts.begin(), command.value("executable", ""));
    lines.push_back("  command: " + join(parts, " "));
  }
  return join(lines, "\n");
}

void appendControl(
    const json& control,
    const std::map<std::string, std::string>& strings,
    const std::filesystem::path& bundleRoot,
    std::vector<std::string>& body,
    std::vector<ControlView>& controls
) {
  auto label = localized(control.value("label", json()), strings, control.value("id", ""));
  auto kind = control.value("kind", "text");
  auto options = optionViews(control.value("options", json::array()), strings);
  auto dataSource = control.contains("dataSource")
      ? std::optional<DataSourceView>{dataSourceView(control["dataSource"], bundleRoot)}
      : std::nullopt;
  auto columns = columnViews(control.value("columns", json::array()), strings);
  std::vector<ActionView> rowActions;
  for (const auto& action : control.value("rowActions", json::array())) {
    if (auto view = actionView(action, strings, bundleRoot)) {
      rowActions.push_back(*view);
    }
  }

  std::vector<std::string> lines{"- " + label + " (" + kind + ")"};
  auto value = control.contains("value") ? valueToString(control["value"]) : "";
  if (isEditableControl(kind)) {
    ControlView view;
    view.id = control.value("id", "");
    view.label = label;
    view.kind = kind;
    view.value = kind == "checkboxGroup" && value.empty() ? selectedOptionIds(options) : value;
    view.placeholder = localized(control.value("placeholder", json()), strings, "");
    view.helper = localized(control.value("tooltip", json()), strings, "");
    view.options = optionTitles(options);
    view.optionItems = options;
    view.dataSource = dataSource;
    view.columns = columns;
    view.rowActions = rowActions;
    controls.push_back(std::move(view));
  }
  if (!value.empty()) {
    lines.push_back("  default: " + value);
  }
  if (dataSource) {
    lines.push_back("  data source: " + dataSource->path + " " + join(dataSource->arguments, " "));
  }
  if (!options.empty()) {
    lines.push_back("  options: " + optionTitles(options));
  }
  auto configFilePath = control.contains("configFile")
      ? interpolateBuiltins(control["configFile"].value("path", ""), bundleRoot)
      : "";
  for (const auto& setting : control.value("settings", json::array())) {
    auto settingLabel =
        localized(setting.value("label", json()), strings, setting.value("id", ""));
    auto settingKind = setting.value("kind", "text");
    auto settingOptions = optionViews(setting.value("options", json::array()), strings);
    auto settingValue = setting.contains("value") ? valueToString(setting["value"]) : "";
    if (isEditableControl(settingKind)) {
      ControlView view;
      view.id = setting.value("id", "");
      view.label = settingLabel;
      view.kind = settingKind;
      view.value = settingValue;
      view.placeholder = localized(setting.value("placeholder", json()), strings, "");
      view.helper = localized(setting.value("tooltip", json()), strings, "");
      view.options = optionTitles(settingOptions);
      view.optionItems = settingOptions;
      if (setting.contains("dataSource")) {
        view.dataSource = dataSourceView(setting["dataSource"], bundleRoot);
      }
      view.configFilePath = configFilePath;
      view.configKey = setting.value("key", view.id);
      controls.push_back(std::move(view));
    }
    lines.push_back("  setting: " + settingLabel + " (" + settingKind + ") " + settingValue);
  }
  for (const auto& action : control.value("rowActions", json::array())) {
    lines.push_back(renderActionText(action, strings, "  row action: "));
  }
  body.push_back(join(lines, "\n"));
}

PageView renderPage(
    const json& page,
    const std::map<std::string, std::string>& strings,
    const std::filesystem::path& bundleRoot
) {
  PageView view;
  view.id = page.value("id", "");
  view.title = localized(page.value("title", json()), strings, view.id);
  view.summary = localized(page.value("summary", json()), strings, "");
  std::vector<std::string> body;
  for (const auto& section : page.value("sections", json::array())) {
    auto title = localized(section.value("title", json()), strings, section.value("id", ""));
    body.push_back("## " + title);
    if (section.contains("subtitle")) {
      body.push_back(localized(section["subtitle"], strings, ""));
    }
    if (section.contains("dataSource")) {
      ControlView control;
      control.id = "section-data-source-" + section.value("id", "");
      control.label = title + " status";
      control.kind = "infoGrid";
      control.dataSource = dataSourceView(section["dataSource"], bundleRoot);
      view.controls.push_back(std::move(control));
    }
    for (const auto& control : section.value("controls", json::array())) {
      appendControl(control, strings, bundleRoot, body, view.controls);
    }
    for (const auto& action : section.value("actions", json::array())) {
      body.push_back(renderActionText(action, strings, ""));
      if (auto actionViewValue = actionView(action, strings, bundleRoot)) {
        view.actions.push_back(*actionViewValue);
      }
    }
    body.push_back("");
  }
  view.body = join(body, "\n");
  return view;
}

std::vector<std::string> renderSetup(
    const json& setup,
    const std::map<std::string, std::string>& strings
) {
  std::vector<std::string> lines;
  for (const auto& step : setup.value("steps", json::array())) {
    auto label = localized(step.value("label", json()), strings, step.value("id", ""));
    auto kind = step.value("kind", "step");
    auto optional = step.value("optional", false) ? " optional" : "";
    lines.push_back("- " + label + " (" + kind + optional + ") " + step.value("value", ""));
  }
  return lines;
}

std::vector<SetupStepView> setupSteps(
    const json& setup,
    const std::map<std::string, std::string>& strings,
    const std::filesystem::path& bundleRoot
) {
  std::vector<SetupStepView> result;
  for (const auto& step : setup.value("steps", json::array())) {
    SetupStepView view;
    view.label = localized(step.value("label", json()), strings, step.value("id", ""));
    view.kind = step.value("kind", "step");
    view.value = interpolateBuiltins(step.value("value", ""), bundleRoot);
    for (const auto& argument : stringsFrom(step.value("arguments", json::array()))) {
      view.arguments.push_back(interpolateBuiltins(argument, bundleRoot));
    }
    view.environment = stringMapFrom(step.value("environment", json::object()), bundleRoot);
    if (step.contains("workingDirectory")) {
      view.workingDirectory = interpolateBuiltins(step.value("workingDirectory", ""), bundleRoot);
    }
    view.optional = step.value("optional", false);
    result.push_back(std::move(view));
  }
  return result;
}

}  // namespace

BundleView loadBundle(
    const std::filesystem::path& bundleRoot,
    const std::filesystem::path& repoRoot,
    const std::string& locale
) {
  auto manifest = readJson(bundleRoot / "manifest.json");
  std::map<std::string, std::string> strings;
  auto builtinRoot = repoRoot / "Sources" / "GUIForCLICore" / "Resources" / "BuiltinStrings";
  mergeTomlStrings(strings, builtinRoot / "strings.en.toml");
  if (locale != "en") {
    mergeTomlStrings(strings, builtinRoot / ("strings." + locale + ".toml"));
  }
  mergeTomlStrings(strings, bundleRoot / "strings" / ("strings." + locale + ".toml"));

  BundleView bundle;
  bundle.strings = strings;
  bundle.title = localized(manifest.value("displayName", json()), strings, manifest.value("id", ""));
  bundle.summary = localized(manifest.value("summary", json()), strings, "");
  auto direction = manifest.value("terminalTextDirection", "ltr");
  std::transform(direction.begin(), direction.end(), direction.begin(), [](unsigned char ch) {
    return static_cast<char>(std::tolower(ch));
  });
  bundle.terminalTextDirection = direction == "rtl" ? "rtl" : "ltr";
  bundle.setupLines = renderSetup(manifest.value("setup", json::object()), strings);
  bundle.setupSteps = setupSteps(manifest.value("setup", json::object()), strings, bundleRoot);

  for (const auto& pageRef : manifest.value("pages", json::array())) {
    auto page = pageRef.is_string() ? readJson(bundleRoot / "pages" / pageRef.get<std::string>())
                                    : pageRef;
    bundle.pages.push_back(renderPage(page, strings, bundleRoot));
  }
  for (const auto& page : bundle.pages) {
    bundle.controlCount += static_cast<int>(page.controls.size());
    bundle.actionCount += static_cast<int>(page.actions.size());
    for (const auto& control : page.controls) {
      if (control.dataSource) {
        bundle.dataSourceCount += 1;
      }
    }
  }
  return bundle;
}
