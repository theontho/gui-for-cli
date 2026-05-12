#include "PathPicker.hpp"

#include "Utils.hpp"

#include <array>
#include <cstdio>
#include <filesystem>

namespace {

std::filesystem::path startingDirectory(const std::string& currentValue) {
  std::filesystem::path current(currentValue);
  if (!current.empty() && std::filesystem::exists(current)) {
    return std::filesystem::is_directory(current) ? current : current.parent_path();
  }
  if (!current.empty() && current.has_parent_path() && std::filesystem::exists(current.parent_path())) {
    return current.parent_path();
  }
  return std::filesystem::current_path();
}

std::string appleScriptQuote(const std::string& value) {
  return "\"" + replaceAll(value, "\"", "\\\"") + "\"";
}

#ifdef __APPLE__
std::optional<std::string> runPickerCommand(const std::string& command) {
  std::array<char, 4096> buffer{};
  std::string output;
  FILE* pipe = popen(command.c_str(), "r");
  if (pipe == nullptr) {
    return std::nullopt;
  }
  while (fgets(buffer.data(), static_cast<int>(buffer.size()), pipe) != nullptr) {
    output += buffer.data();
  }
  int status = pclose(pipe);
  if (status != 0 || output.empty()) {
    return std::nullopt;
  }
  while (!output.empty() && (output.back() == '\n' || output.back() == '\r')) {
    output.pop_back();
  }
  return output.empty() ? std::nullopt : std::optional<std::string>{output};
}
#endif

}  // namespace

std::optional<std::string> choosePath(const std::string& currentValue, bool directory) {
#ifdef __APPLE__
  auto start = startingDirectory(currentValue).string();
  auto script = std::string("POSIX path of (choose ") + (directory ? "folder" : "file") +
                " default location POSIX file " + appleScriptQuote(start) + ")";
  return runPickerCommand("/usr/bin/osascript -e " + shellQuote(script));
#else
  (void)currentValue;
  (void)directory;
  return std::nullopt;
#endif
}
