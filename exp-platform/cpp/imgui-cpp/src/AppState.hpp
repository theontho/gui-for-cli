#pragma once

#include "Args.hpp"
#include "Bundle.hpp"

#include <cstddef>
#include <future>
#include <map>
#include <memory>
#include <nlohmann/json.hpp>
#include <optional>
#include <string>
#include <vector>

class RunningProcess;

enum class TerminalStatus { Ready, Running, Succeeded, Failed, Cancelled };

struct TerminalEntry {
  int id = 0;
  std::string title;
  std::string output;
  TerminalStatus status = TerminalStatus::Ready;
  bool closable = false;
};

struct DataSourceRows {
  std::vector<nlohmann::json> rows;
  std::string error;
  bool loading = false;
};

struct PendingConfirmation {
  ActionView action;
  std::map<std::string, std::string> values;
  std::string suffix;
  std::string typedText;
};

class AppState {
 public:
  AppState(BundleView bundle, Args args);

  BundleView bundle;
  Args args;
  int selectedPage = 0;
  float fontScale = 1.0F;
  bool sidebarVisible = true;
  bool terminalVisible = true;
  bool terminalAutoscroll = true;
  float terminalHeight = 190.0F;
  int selectedTerminal = 0;

  std::map<std::string, std::string> fieldValues;
  std::vector<TerminalEntry> terminals;
  std::optional<PendingConfirmation> pendingConfirmation;

  std::map<std::string, std::string> effectiveFieldValues(const PageView& page) const;
  std::vector<ActionView> visibleActions(const PageView& page) const;
  void setControlValue(const ControlView& control, std::string value);
  void requestAction(
      const ActionView& action,
      const std::map<std::string, std::string>& values,
      std::string suffix
  );
  void confirmPendingAction();
  void cancelPendingAction();
  bool isActionRunning(const std::string& actionKey) const;
  void closeOrCancelTerminal(int index);
  void startAction(const ActionView& action);
  void startAction(
      const ActionView& action,
      const std::map<std::string, std::string>& values,
      std::string actionKey = ""
  );
  void startSetupStep(const SetupStepView& step, std::string actionKey);
  void pollFinishedActions();
  DataSourceRows dataRows(const ControlView& control);
  void warmAllPages();
  std::size_t dataSourcesLoaded() const;

 private:
  struct RunningAction {
    int terminalId = 0;
    std::string actionKey;
    std::shared_ptr<RunningProcess> process;
    std::future<std::string> future;
  };

  int nextTerminalId_ = 1;
  int dataSourceGeneration_ = 0;
  std::vector<RunningAction> running_;
  std::map<std::string, DataSourceRows> dataSourceCache_;
  std::map<std::string, std::future<DataSourceRows>> dataSourceLoads_;
};
