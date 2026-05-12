#include "Utils.hpp"

#include <cctype>
#include <cstdlib>
#include <fstream>
#include <sstream>
#include <stdexcept>

std::string readTextFile(const std::filesystem::path& path) {
  std::ifstream stream(path);
  if (!stream) {
    throw std::runtime_error("read " + path.string());
  }
  std::ostringstream buffer;
  buffer << stream.rdbuf();
  return buffer.str();
}

std::map<std::string, std::string> readTomlStrings(const std::filesystem::path& path) {
  std::map<std::string, std::string> strings;
  if (!std::filesystem::exists(path)) {
    return strings;
  }

  std::istringstream input(readTextFile(path));
  std::string line;
  while (std::getline(input, line)) {
    auto comment = line.find('#');
    if (comment != std::string::npos) {
      line = line.substr(0, comment);
    }
    auto equals = line.find('=');
    if (equals == std::string::npos) {
      continue;
    }
    auto keyStart = line.find('"');
    auto keyEnd = line.find('"', keyStart + 1);
    auto valueStart = line.find('"', equals);
    if (keyStart == std::string::npos || keyEnd == std::string::npos ||
        valueStart == std::string::npos) {
      continue;
    }
    std::string value;
    bool escaped = false;
    for (std::size_t index = valueStart + 1; index < line.size(); ++index) {
      char ch = line[index];
      if (escaped) {
        value.push_back(ch == 'n' ? '\n' : ch);
        escaped = false;
      } else if (ch == '\\') {
        escaped = true;
      } else if (ch == '"') {
        strings[line.substr(keyStart + 1, keyEnd - keyStart - 1)] = value;
        break;
      } else {
        value.push_back(ch);
      }
    }
  }
  return strings;
}

void mergeTomlStrings(
    std::map<std::string, std::string>& target,
    const std::filesystem::path& path
) {
  for (auto&& [key, value] : readTomlStrings(path)) {
    target[key] = value;
  }
}

std::string localize(
    const std::string& value,
    const std::map<std::string, std::string>& strings
) {
  auto found = strings.find(value);
  return found == strings.end() ? value : found->second;
}

std::string valueToString(const nlohmann::json& value) {
  if (value.is_string()) {
    return value.get<std::string>();
  }
  if (value.is_boolean()) {
    return value.get<bool>() ? "true" : "false";
  }
  if (value.is_number()) {
    return value.dump();
  }
  return value.is_null() ? "" : value.dump();
}

std::string replaceAll(std::string value, const std::string& from, const std::string& to) {
  std::size_t offset = 0;
  while ((offset = value.find(from, offset)) != std::string::npos) {
    value.replace(offset, from.size(), to);
    offset += to.size();
  }
  return value;
}

std::string interpolateBuiltins(
    std::string value,
    const std::filesystem::path& bundleRoot
) {
  const char* home = std::getenv("HOME");
  if (home == nullptr) {
    home = std::getenv("USERPROFILE");
  }
  value = replaceAll(value, "{{bundleRoot}}", bundleRoot.string());
  value = replaceAll(value, "{{bundleWorkspace}}", bundleRoot.string());
  return replaceAll(value, "{{home}}", home == nullptr ? "" : home);
}

std::string join(const std::vector<std::string>& values, const std::string& separator) {
  std::string result;
  for (std::size_t index = 0; index < values.size(); ++index) {
    if (index > 0) {
      result += separator;
    }
    result += values[index];
  }
  return result;
}

std::string shellQuote(const std::string& value) {
  if (value.empty()) {
    return "''";
  }
  bool simple = true;
  for (char ch : value) {
    if (!(std::isalnum(static_cast<unsigned char>(ch)) || ch == '_' || ch == '-' ||
          ch == '.' || ch == '/' || ch == ':' || ch == '=')) {
      simple = false;
      break;
    }
  }
  if (simple) {
    return value;
  }
  return "'" + replaceAll(value, "'", "'\\''") + "'";
}
