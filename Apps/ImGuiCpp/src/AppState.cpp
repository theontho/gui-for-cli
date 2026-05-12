#include "AppState.hpp"

#include "ConfigStore.hpp"
#include "Execution.hpp"

#include <algorithm>
#include <chrono>
#include <iterator>
#include <thread>

AppState::AppState(BundleView bundleValue, Args argsValue)
    : bundle(std::move(bundleValue)),
      args(std::move(argsValue)) {
  for (const auto& page : bundle.pages) {
    for (const auto& control : page.controls) {
      fieldValues[control.id] = configValueFor(control).value_or(control.value);
    }
  }
  terminals.push_back(TerminalEntry{
      0,
      bundle.strings.contains("app.terminal.mainTab.title")
          ? bundle.strings["app.terminal.mainTab.title"]
          : "Main",
      bundle.strings.contains("app.setup.status.ready") ? bundle.strings["app.setup.status.ready"]
                                                        : "Ready.",
      TerminalStatus::Ready,
      false,
  });
}

std::map<std::string, std::string> AppState::effectiveFieldValues(const PageView& page) const {
  std::map<std::string, std::string> values = fieldValues;
  for (const auto& control : page.controls) {
    if (!values.contains(control.id)) {
      values[control.id] = control.value;
    }
  }
  return values;
}

std::vector<ActionView> AppState::visibleActions(const PageView& page) const {
  auto values = effectiveFieldValues(page);
  std::vector<ActionView> actions;
  for (const auto& action : page.actions) {
    if (isActionVisible(action, values)) {
      actions.push_back(action);
    }
  }
  return actions;
}

void AppState::setControlValue(const ControlView& control, std::string value) {
  fieldValues[control.id] = value;
  saveConfigValue(control, value);
  dataSourceCache_.clear();
  ++dataSourceGeneration_;
}

void AppState::requestAction(
    const ActionView& action,
    const std::map<std::string, std::string>& values,
    std::string suffix
) {
  if (action.confirmation) {
    pendingConfirmation = PendingConfirmation{action, values, std::move(suffix), ""};
    return;
  }
  startAction(action, values, std::move(suffix));
}

void AppState::confirmPendingAction() {
  if (!pendingConfirmation) {
    return;
  }
  auto pending = *pendingConfirmation;
  pendingConfirmation = std::nullopt;
  startAction(pending.action, pending.values, pending.suffix);
}

void AppState::cancelPendingAction() {
  pendingConfirmation = std::nullopt;
}

void AppState::startAction(const ActionView& action) {
  startAction(action, fieldValues, action.id);
}

bool AppState::isActionRunning(const std::string& actionKey) const {
  if (actionKey.empty()) {
    return false;
  }
  return std::any_of(running_.begin(), running_.end(), [&](const auto& running) {
    return running.actionKey == actionKey;
  });
}

void AppState::closeOrCancelTerminal(int index) {
  if (index <= 0 || index >= static_cast<int>(terminals.size()) || !terminals[index].closable) {
    return;
  }
  auto terminalId = terminals[index].id;
  auto running = std::find_if(running_.begin(), running_.end(), [&](const auto& item) {
    return item.terminalId == terminalId;
  });
  if (running != running_.end()) {
    if (running->process) {
      running->process->cancel();
    }
    terminals[index].output += "\n[cancellation requested]";
    return;
  }

  terminals.erase(terminals.begin() + index);
  if (selectedTerminal >= static_cast<int>(terminals.size())) {
    selectedTerminal = static_cast<int>(terminals.size()) - 1;
  } else if (selectedTerminal >= index) {
    selectedTerminal = std::max(0, selectedTerminal - 1);
  }
}

void AppState::startAction(
    const ActionView& action,
    const std::map<std::string, std::string>& values,
    std::string actionKey
) {
  auto terminalId = nextTerminalId_++;
  auto command = commandPreview(action, values);
  terminals.push_back(TerminalEntry{
      terminalId,
      action.title,
      "$ " + command + "\n[running]",
      TerminalStatus::Running,
      true,
  });
  auto terminalIndex = static_cast<int>(terminals.size()) - 1;
  selectedTerminal = terminalIndex;
  auto bundleRoot = args.bundle;
  auto process = std::make_shared<RunningProcess>();
  running_.push_back(RunningAction{
      terminalId,
      std::move(actionKey),
      process,
      std::async(std::launch::async, [action, values, bundleRoot, process]() {
        try {
          return runActionCommand(action, values, bundleRoot, process);
        } catch (const std::exception& error) {
          return std::string("error: ") + error.what();
        }
      }),
  });
}

void AppState::startSetupStep(const SetupStepView& step, std::string actionKey) {
  auto terminalId = nextTerminalId_++;
  auto command = setupCommandPreview(step, args.bundle);
  terminals.push_back(TerminalEntry{
      terminalId,
      step.label,
      "$ " + command + "\n[running]",
      TerminalStatus::Running,
      true,
  });
  auto terminalIndex = static_cast<int>(terminals.size()) - 1;
  selectedTerminal = terminalIndex;
  auto bundleRoot = args.bundle;
  auto process = std::make_shared<RunningProcess>();
  running_.push_back(RunningAction{
      terminalId,
      std::move(actionKey),
      process,
      std::async(std::launch::async, [step, bundleRoot, process]() {
        try {
          return runSetupCommand(step, bundleRoot, process);
        } catch (const std::exception& error) {
          return std::string("error: ") + error.what();
        }
      }),
  });
}

void AppState::pollFinishedActions() {
  for (auto iterator = running_.begin(); iterator != running_.end();) {
    if (iterator->future.wait_for(std::chrono::seconds(0)) == std::future_status::ready) {
      auto output = iterator->future.get();
      auto terminal = std::find_if(terminals.begin(), terminals.end(), [&](const auto& entry) {
        return entry.id == iterator->terminalId;
      });
      if (terminal != terminals.end()) {
        terminal->output = output.empty() ? "(no output)" : output;
        if (terminal->output.find("[cancelled]") != std::string::npos) {
          terminal->status = TerminalStatus::Cancelled;
        } else if (terminal->output.starts_with("error: ") ||
                   terminal->output.find("error: command exited with status ") != std::string::npos ||
                   (terminal->output.find(" exit ") != std::string::npos &&
                    terminal->output.find(" exit 0]") == std::string::npos)) {
          terminal->status = TerminalStatus::Failed;
        } else {
          terminal->status = TerminalStatus::Succeeded;
        }
      }
      dataSourceCache_.clear();
      ++dataSourceGeneration_;
      iterator = running_.erase(iterator);
    } else {
      ++iterator;
    }
  }
}

void AppState::warmAllPages() {
  for (const auto& page : bundle.pages) {
    auto values = effectiveFieldValues(page);
    (void)visibleActions(page);
    for (const auto& control : page.controls) {
      if (control.dataSource) {
        while (dataRows(control).loading) {
          std::this_thread::sleep_for(std::chrono::milliseconds(1));
        }
      }
    }
  }
}

std::size_t AppState::dataSourcesLoaded() const {
  return dataSourceCache_.size();
}

DataSourceRows AppState::dataRows(const ControlView& control) {
  if (!control.dataSource) {
    return {};
  }
  auto key = std::to_string(dataSourceGeneration_) + ":" + control.id + ":" + control.dataSource->path;
  for (const auto& [field, value] : fieldValues) {
    key += "|" + field + "=" + value;
  }
  for (auto iterator = dataSourceLoads_.begin(); iterator != dataSourceLoads_.end();) {
    if (iterator->first != key &&
        iterator->second.wait_for(std::chrono::seconds(0)) == std::future_status::ready) {
      (void)iterator->second.get();
      iterator = dataSourceLoads_.erase(iterator);
    } else {
      ++iterator;
    }
  }
  if (auto found = dataSourceCache_.find(key); found != dataSourceCache_.end()) {
    return found->second;
  }
  if (auto pending = dataSourceLoads_.find(key); pending != dataSourceLoads_.end()) {
    if (pending->second.wait_for(std::chrono::seconds(0)) != std::future_status::ready) {
      return DataSourceRows{{}, "", true};
    }
    auto rows = pending->second.get();
    dataSourceLoads_.erase(pending);
    dataSourceCache_[key] = rows;
    return rows;
  }

  auto dataSource = *control.dataSource;
  auto values = fieldValues;
  auto bundleRoot = args.bundle;
  dataSourceLoads_[key] = std::async(std::launch::async, [dataSource, values, bundleRoot]() {
    DataSourceRows rows;
    try {
      auto payload = runDataSource(dataSource, values, bundleRoot);
      if (payload.contains("items") && payload["items"].is_array()) {
        for (const auto& item : payload["items"]) {
          rows.rows.push_back(item);
        }
      } else if (payload.contains("options") && payload["options"].is_array()) {
        for (const auto& item : payload["options"]) {
          rows.rows.push_back(item);
        }
      }
    } catch (const std::exception& error) {
      rows.error = error.what();
    }
    return rows;
  });
  return DataSourceRows{{}, "", true};
}
