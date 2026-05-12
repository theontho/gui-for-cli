#pragma once

#include "Bundle.hpp"

#include <filesystem>
#include <map>
#include <nlohmann/json.hpp>
#include <string>
#include <vector>

std::string interpolateFields(
    const std::string& value,
    const std::map<std::string, std::string>& fieldValues
);
std::vector<std::string> actionArguments(
    const ActionView& action,
    const std::map<std::string, std::string>& fieldValues
);
std::string commandPreview(
    const ActionView& action,
    const std::map<std::string, std::string>& fieldValues
);
bool isActionVisible(
    const ActionView& action,
    const std::map<std::string, std::string>& fieldValues
);
std::string actionUnavailableReason(
    const ActionView& action,
    const std::map<std::string, std::string>& fieldValues
);
std::string runActionCommand(
    const ActionView& action,
    const std::map<std::string, std::string>& fieldValues,
    const std::filesystem::path& bundleRoot
);
std::string setupCommandPreview(const SetupStepView& step, const std::filesystem::path& bundleRoot);
std::string runSetupCommand(const SetupStepView& step, const std::filesystem::path& bundleRoot);
nlohmann::json runDataSource(
    const DataSourceView& dataSource,
    const std::map<std::string, std::string>& fieldValues,
    const std::filesystem::path& bundleRoot
);
