#pragma once

#include "Bundle.hpp"

#include <atomic>
#include <cstdint>
#include <filesystem>
#include <map>
#include <memory>
#include <nlohmann/json.hpp>
#include <string>
#include <vector>

struct CommandResult {
  std::string output;
  int exitCode = 0;
  bool cancelled = false;
};

class RunningProcess {
 public:
  void cancel();
  bool cancelled() const;
  void setProcessId(long processId);
  void setCancelHandle(std::uintptr_t handle);

 private:
  std::atomic<long> processId_ = -1;
  std::atomic<std::uintptr_t> cancelHandle_ = 0;
  std::atomic<bool> cancelled_ = false;
};

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
    const std::filesystem::path& bundleRoot,
    const std::shared_ptr<RunningProcess>& process
);
std::string setupCommandPreview(const SetupStepView& step, const std::filesystem::path& bundleRoot);
std::string runSetupCommand(
    const SetupStepView& step,
    const std::filesystem::path& bundleRoot,
    const std::shared_ptr<RunningProcess>& process
);
nlohmann::json runDataSource(
    const DataSourceView& dataSource,
    const std::map<std::string, std::string>& fieldValues,
    const std::filesystem::path& bundleRoot
);
