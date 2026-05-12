#pragma once

#include "Args.hpp"
#include "Bundle.hpp"

#include <chrono>
#include <future>
#include <map>
#include <nlohmann/json.hpp>
#include <optional>
#include <string>
#include <vector>

enum class TerminalStatus { Ready, Running, Succeeded, Failed };

struct TerminalEntry {
  std::string title;
  std::string output;
  TerminalStatus status = TerminalStatus::Ready;
  bool closable = false;
};

struct DataSourceRows {
  std::vector<nlohmann::json> rows;
  std::string error;
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
  void startAction(const ActionView& action);
  void startAction(
      const ActionView& action,
      const std::map<std::string, std::string>& values
  );
  void startSetupStep(const SetupStepView& step);
  void pollFinishedActions();
  DataSourceRows dataRows(const ControlView& control);
  void warmAllPages();
  std::size_t dataSourcesLoaded() const;
  double loadedMs() const;
  double readyMs() const;

 private:
  struct RunningAction {
    int terminalIndex = 0;
    std::future<std::string> future;
  };

  std::chrono::steady_clock::time_point started_;
  std::chrono::steady_clock::time_point loaded_;
  std::vector<RunningAction> running_;
  std::map<std::string, DataSourceRows> dataSourceCache_;
};
