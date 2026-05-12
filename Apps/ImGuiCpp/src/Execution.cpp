#include "Execution.hpp"

#include "Utils.hpp"

#include <algorithm>
#include <array>
#include <cstdio>
#include <stdexcept>
#include <utility>

namespace {

bool missingPlaceholders(
    const std::vector<std::string>& values,
    const std::map<std::string, std::string>& fieldValues
) {
  for (const auto& value : values) {
    std::size_t offset = 0;
    while ((offset = value.find("{{", offset)) != std::string::npos) {
      auto end = value.find("}}", offset + 2);
      if (end == std::string::npos) {
        break;
      }
      auto key = value.substr(offset + 2, end - offset - 2);
      key.erase(0, key.find_first_not_of(" \t"));
      key.erase(key.find_last_not_of(" \t") + 1);
      auto found = fieldValues.find(key);
      if (found == fieldValues.end() || found->second.empty()) {
        return true;
      }
      offset = end + 2;
    }
  }
  return false;
}

bool conditionMatches(
    const ActionCondition& condition,
    const std::map<std::string, std::string>& fieldValues
) {
  auto found = fieldValues.find(condition.placeholder);
  auto value = found == fieldValues.end() ? "" : found->second;
  if (condition.exists && (*condition.exists != !value.empty())) {
    return false;
  }
  if (condition.equals && value != *condition.equals) {
    return false;
  }
  if (condition.notEquals && value == *condition.notEquals) {
    return false;
  }
  if (!condition.inValues.empty() &&
      std::find(condition.inValues.begin(), condition.inValues.end(), value) ==
          condition.inValues.end()) {
    return false;
  }
  if (!condition.notInValues.empty() &&
      std::find(condition.notInValues.begin(), condition.notInValues.end(), value) !=
          condition.notInValues.end()) {
    return false;
  }
  return true;
}

std::string runShellCommand(const std::string& command) {
  std::array<char, 4096> buffer{};
  std::string output;
#ifdef _WIN32
  FILE* pipe = _popen(command.c_str(), "r");
#else
  FILE* pipe = popen(command.c_str(), "r");
#endif
  if (pipe == nullptr) {
    throw std::runtime_error("start command failed");
  }
  while (fgets(buffer.data(), static_cast<int>(buffer.size()), pipe) != nullptr) {
    output += buffer.data();
  }
#ifdef _WIN32
  int status = _pclose(pipe);
#else
  int status = pclose(pipe);
#endif
  if (status != 0) {
    output += "\n(exit status " + std::to_string(status) + ")";
  }
  return output;
}

#ifdef _WIN32
std::string cmdQuote(const std::string& value) {
  return "\"" + replaceAll(value, "\"", "\\\"") + "\"";
}
#endif

std::string shellCommand(
    const std::string& executable,
    const std::vector<std::string>& arguments,
    const std::filesystem::path& cwd,
    const std::map<std::string, std::string>& environment
) {
  std::vector<std::string> parts;
#ifdef _WIN32
  parts.push_back("cd /D " + cmdQuote(cwd.string()) + " &&");
  for (const auto& [key, value] : environment) {
    parts.push_back("set \"" + key + "=" + value + "\" &&");
  }
  parts.push_back(cmdQuote(executable));
  for (const auto& argument : arguments) {
    parts.push_back(cmdQuote(argument));
  }
#else
  parts.push_back("cd " + shellQuote(cwd.string()) + " &&");
  for (const auto& [key, value] : environment) {
    parts.push_back(key + "=" + shellQuote(value));
  }
  parts.push_back(shellQuote(executable));
  for (const auto& argument : arguments) {
    parts.push_back(shellQuote(argument));
  }
#endif
  parts.push_back("2>&1");
  return join(parts, " ");
}

std::pair<std::string, std::vector<std::string>> setupExecutableAndArguments(
    const SetupStepView& step,
    const std::filesystem::path& bundleRoot
) {
  auto value = step.value;
  if (step.kind == "pathTool") {
#ifdef _WIN32
    return {"where", {value}};
#else
    return {"which", {value}};
#endif
  }
  if (step.kind == "setupScript" || step.kind == "bundledScript") {
    auto script = std::filesystem::path(value);
    if (script.is_relative()) {
      script = bundleRoot / script;
    }
    std::vector<std::string> arguments{script.string()};
    arguments.insert(arguments.end(), step.arguments.begin(), step.arguments.end());
    return {"sh", arguments};
  }
  if (step.kind == "pixiInstall") {
    return {"pixi", {"install"}};
  }
  if (step.kind == "pixiRun") {
    std::vector<std::string> arguments{"run"};
    if (!value.empty()) {
      arguments.push_back(value);
    }
    arguments.insert(arguments.end(), step.arguments.begin(), step.arguments.end());
    return {"pixi", arguments};
  }
  if (step.kind == "homebrewPackage") {
    return {"brew", {"list", value}};
  }
  std::vector<std::string> arguments = step.arguments;
  return {value, arguments};
}

}  // namespace

std::string interpolateFields(
    const std::string& value,
    const std::map<std::string, std::string>& fieldValues
) {
  std::string rendered;
  std::size_t offset = 0;
  while (true) {
    auto start = value.find("{{", offset);
    if (start == std::string::npos) {
      rendered += value.substr(offset);
      break;
    }
    rendered += value.substr(offset, start - offset);
    auto end = value.find("}}", start + 2);
    if (end == std::string::npos) {
      rendered += value.substr(start);
      break;
    }
    auto key = value.substr(start + 2, end - start - 2);
    key.erase(0, key.find_first_not_of(" \t"));
    key.erase(key.find_last_not_of(" \t") + 1);
    auto found = fieldValues.find(key);
    if (found != fieldValues.end()) {
      rendered += found->second;
    }
    offset = end + 2;
  }
  return rendered;
}

std::vector<std::string> actionArguments(
    const ActionView& action,
    const std::map<std::string, std::string>& fieldValues
) {
  std::vector<std::string> arguments;
  for (const auto& argument : action.arguments) {
    arguments.push_back(interpolateFields(argument, fieldValues));
  }
  for (const auto& group : action.optionalArguments) {
    if (!missingPlaceholders(group, fieldValues)) {
      for (const auto& argument : group) {
        arguments.push_back(interpolateFields(argument, fieldValues));
      }
    }
  }
  return arguments;
}

std::string commandPreview(
    const ActionView& action,
    const std::map<std::string, std::string>& fieldValues
) {
  auto arguments = actionArguments(action, fieldValues);
  std::vector<std::string> parts{shellQuote(interpolateFields(action.executable, fieldValues))};
  for (const auto& argument : arguments) {
    parts.push_back(shellQuote(argument));
  }
  return join(parts, " ");
}

bool isActionVisible(
    const ActionView& action,
    const std::map<std::string, std::string>& fieldValues
) {
  return std::all_of(action.visibleWhen.begin(), action.visibleWhen.end(), [&](const auto& item) {
    return conditionMatches(item, fieldValues);
  });
}

std::string actionUnavailableReason(
    const ActionView& action,
    const std::map<std::string, std::string>& fieldValues
) {
  for (const auto& condition : action.disabledWhen) {
    if (conditionMatches(condition, fieldValues)) {
      return action.disabledTooltip.empty() ? "This action is not available."
                                           : interpolateFields(action.disabledTooltip, fieldValues);
    }
  }
  std::vector<std::string> values = action.arguments;
  values.push_back(action.executable);
  return missingPlaceholders(values, fieldValues) ? "Fill required values before running." : "";
}

std::string runActionCommand(
    const ActionView& action,
    const std::map<std::string, std::string>& fieldValues,
    const std::filesystem::path& bundleRoot
) {
  auto executable = interpolateFields(action.executable, fieldValues);
  auto arguments = actionArguments(action, fieldValues);
  auto cwd = action.workingDirectory ? std::filesystem::path(*action.workingDirectory) : bundleRoot;
  auto env = action.environment;
  env["GUI_FOR_CLI_BUNDLE_ROOT"] = bundleRoot.string();
  for (const auto& [key, value] : fieldValues) {
    env["GUI_FOR_CLI_FIELD_" + key] = value;
  }
  return runShellCommand(shellCommand(executable, arguments, cwd, env));
}

std::string setupCommandPreview(const SetupStepView& step, const std::filesystem::path& bundleRoot) {
  auto [executable, arguments] = setupExecutableAndArguments(step, bundleRoot);
  std::vector<std::string> parts{shellQuote(executable)};
  for (const auto& argument : arguments) {
    parts.push_back(shellQuote(argument));
  }
  return join(parts, " ");
}

std::string runSetupCommand(const SetupStepView& step, const std::filesystem::path& bundleRoot) {
  auto [executable, arguments] = setupExecutableAndArguments(step, bundleRoot);
  auto cwd = step.workingDirectory ? std::filesystem::path(*step.workingDirectory) : bundleRoot;
  auto env = step.environment;
  env["GUI_FOR_CLI_BUNDLE_ROOT"] = bundleRoot.string();
  env["GUI_FOR_CLI_SETUP_STEP_KIND"] = step.kind;
  return runShellCommand(shellCommand(executable, arguments, cwd, env));
}

nlohmann::json runDataSource(
    const DataSourceView& dataSource,
    const std::map<std::string, std::string>& fieldValues,
    const std::filesystem::path& bundleRoot
) {
  auto cwd =
      dataSource.workingDirectory ? std::filesystem::path(*dataSource.workingDirectory) : bundleRoot;
  auto env = dataSource.environment;
  env["GUI_FOR_CLI_DATA_SOURCE"] = "1";
  env["GUI_FOR_CLI_BUNDLE_ROOT"] = bundleRoot.string();
  for (const auto& [key, value] : fieldValues) {
    env["GUI_FOR_CLI_FIELD_" + key] = value;
  }
  std::vector<std::string> arguments;
  for (const auto& argument : dataSource.arguments) {
    arguments.push_back(interpolateFields(argument, fieldValues));
  }
  auto output = runShellCommand(shellCommand(dataSource.path, arguments, cwd, env));
  return nlohmann::json::parse(output);
}
