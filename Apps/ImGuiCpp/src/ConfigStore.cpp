#include "ConfigStore.hpp"

#include "Utils.hpp"

#include <fstream>
#include <sstream>
#include <stdexcept>

namespace {

std::string trim(std::string value) {
  auto first = value.find_first_not_of(" \t\r\n");
  if (first == std::string::npos) {
    return "";
  }
  auto last = value.find_last_not_of(" \t\r\n");
  return value.substr(first, last - first + 1);
}

std::string unquote(std::string value) {
  value = trim(std::move(value));
  if (value.size() < 2 || value.front() != '"' || value.back() != '"') {
    return value;
  }
  std::string result;
  bool escaped = false;
  for (std::size_t index = 1; index + 1 < value.size(); ++index) {
    char ch = value[index];
    if (escaped) {
      result.push_back(ch == 'n' ? '\n' : ch);
      escaped = false;
    } else if (ch == '\\') {
      escaped = true;
    } else {
      result.push_back(ch);
    }
  }
  return result;
}

std::string quoteTomlString(const std::string& value) {
  std::string result = "\"";
  for (char ch : value) {
    if (ch == '\\' || ch == '"') {
      result.push_back('\\');
      result.push_back(ch);
    } else if (ch == '\n') {
      result += "\\n";
    } else {
      result.push_back(ch);
    }
  }
  result.push_back('"');
  return result;
}

std::string tomlScalar(const std::string& value, const std::string& kind) {
  return kind == "toggle" ? (value == "true" ? "true" : "false") : quoteTomlString(value);
}

}  // namespace

std::map<std::string, std::string> loadTomlScalars(const std::filesystem::path& path) {
  std::map<std::string, std::string> values;
  if (!std::filesystem::exists(path)) {
    return values;
  }
  std::istringstream input(readTextFile(path));
  std::string line;
  std::string section;
  while (std::getline(input, line)) {
    auto comment = line.find('#');
    if (comment != std::string::npos) {
      line = line.substr(0, comment);
    }
    line = trim(line);
    if (line.empty()) {
      continue;
    }
    if (line.front() == '[' && line.back() == ']') {
      section = trim(line.substr(1, line.size() - 2));
      continue;
    }
    auto equals = line.find('=');
    if (equals == std::string::npos) {
      continue;
    }
    auto key = trim(line.substr(0, equals));
    auto value = unquote(line.substr(equals + 1));
    values[section.empty() ? key : section + "." + key] = value;
  }
  return values;
}

std::optional<std::string> configValueFor(const ControlView& control) {
  if (control.configFilePath.empty() || control.configKey.empty()) {
    return std::nullopt;
  }
  auto values = loadTomlScalars(control.configFilePath);
  auto found = values.find(control.configKey);
  if (found == values.end()) {
    return std::nullopt;
  }
  return found->second;
}

void saveConfigValue(const ControlView& control, const std::string& value) {
  if (control.configFilePath.empty() || control.configKey.empty()) {
    return;
  }
  auto path = std::filesystem::path(control.configFilePath);
  auto values = loadTomlScalars(path);
  values[control.configKey] = value;
  if (path.has_parent_path()) {
    std::filesystem::create_directories(path.parent_path());
  }

  std::map<std::string, std::map<std::string, std::string>> sections;
  std::map<std::string, std::string> roots;
  for (const auto& [key, storedValue] : values) {
    if (auto dot = key.find('.'); dot != std::string::npos) {
      sections[key.substr(0, dot)][key.substr(dot + 1)] = storedValue;
    } else {
      roots[key] = storedValue;
    }
  }

  std::ofstream output(path);
  if (!output) {
    throw std::runtime_error("write " + path.string());
  }
  for (const auto& [key, storedValue] : roots) {
    output << key << " = " << tomlScalar(storedValue, key == control.configKey ? control.kind : "")
           << "\n";
  }
  for (const auto& [section, entries] : sections) {
    if (!roots.empty()) {
      output << "\n";
    }
    output << "[" << section << "]\n";
    for (const auto& [key, storedValue] : entries) {
      auto fullKey = section + "." + key;
      output << key << " = "
             << tomlScalar(storedValue, fullKey == control.configKey ? control.kind : "") << "\n";
    }
  }
}
