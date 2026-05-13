#pragma once

#include "Bundle.hpp"

#include <filesystem>
#include <map>
#include <optional>
#include <string>

std::map<std::string, std::string> loadTomlScalars(const std::filesystem::path& path);
std::optional<std::string> configValueFor(const ControlView& control);
void saveConfigValue(const ControlView& control, const std::string& value);
