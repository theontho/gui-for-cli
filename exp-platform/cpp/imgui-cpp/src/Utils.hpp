#pragma once

#include <filesystem>
#include <map>
#include <nlohmann/json.hpp>
#include <string>
#include <vector>

std::string readTextFile(const std::filesystem::path& path);
std::map<std::string, std::string> readTomlStrings(const std::filesystem::path& path);
void mergeTomlStrings(
    std::map<std::string, std::string>& target,
    const std::filesystem::path& path
);
std::string localize(
    const std::string& value,
    const std::map<std::string, std::string>& strings
);
std::string valueToString(const nlohmann::json& value);
std::string replaceAll(std::string value, const std::string& from, const std::string& to);
std::string interpolateBuiltins(
    std::string value,
    const std::filesystem::path& bundleRoot
);
std::string join(const std::vector<std::string>& values, const std::string& separator);
std::string shellQuote(const std::string& value);
