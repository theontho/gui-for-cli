#include "AppState.hpp"

#include "ConfigStore.hpp"
#include "Execution.hpp"

#include <algorithm>

AppState::AppState(BundleView bundleValue, Args argsValue)
    : bundle(std::move(bundleValue)),
      args(std::move(argsValue)),
      started_(std::chrono::steady_clock::now()),
  loaded_(started_) {
  for (const auto& page : bundle.pages) {
    for (const auto& control : page.controls) {
      fieldValues[control.id] = configValueFor(control).value_or(control.value);
    }
  }
  terminals.push_back(TerminalEntry{
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
  startAction(action, values);
}

void AppState::confirmPendingAction() {
  if (!pendingConfirmation) {
    return;
  }
  auto pending = *pendingConfirmation;
  pendingConfirmation = std::nullopt;
  startAction(pending.action, pending.values);
}

void AppState::cancelPendingAction() {
  pendingConfirmation = std::nullopt;
}

void AppState::startAction(const ActionView& action) {
  startAction(action, fieldValues);
}

void AppState::startAction(
    const ActionView& action,
    const std::map<std::string, std::string>& values
) {
  auto terminalIndex = static_cast<int>(terminals.size());
  terminals.push_back(TerminalEntry{action.title, commandPreview(action, values), TerminalStatus::Running, true});
  selectedTerminal = terminalIndex;
  auto bundleRoot = args.bundle;
  running_.push_back(RunningAction{
      terminalIndex,
      std::async(std::launch::async, [action, values, bundleRoot]() {
        try {
          return runActionCommand(action, values, bundleRoot);
        } catch (const std::exception& error) {
          return std::string("error: ") + error.what();
        }
      }),
  });
}

void AppState::startSetupStep(const SetupStepView& step) {
  auto terminalIndex = static_cast<int>(terminals.size());
  terminals.push_back(
      TerminalEntry{step.label, setupCommandPreview(step, args.bundle), TerminalStatus::Running, true}
  );
  selectedTerminal = terminalIndex;
  auto bundleRoot = args.bundle;
  running_.push_back(RunningAction{
      terminalIndex,
      std::async(std::launch::async, [step, bundleRoot]() {
        try {
          return runSetupCommand(step, bundleRoot);
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
      auto& terminal = terminals[iterator->terminalIndex];
      terminal.output = output.empty() ? "(no output)" : output;
      terminal.status = output.starts_with("error: ") ? TerminalStatus::Failed : TerminalStatus::Succeeded;
      dataSourceCache_.clear();
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
        (void)dataRows(control);
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
  auto key = control.id + ":" + control.dataSource->path;
  for (const auto& [field, value] : fieldValues) {
    key += "|" + field + "=" + value;
  }
  if (auto found = dataSourceCache_.find(key); found != dataSourceCache_.end()) {
    return found->second;
  }

  DataSourceRows rows;
  try {
    auto payload = runDataSource(*control.dataSource, fieldValues, args.bundle);
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
  dataSourceCache_[key] = rows;
  return rows;
}

double AppState::loadedMs() const {
  return std::chrono::duration<double, std::milli>(loaded_ - started_).count();
}

double AppState::readyMs() const {
  return std::chrono::duration<double, std::milli>(
             std::chrono::steady_clock::now() - started_
  )
      .count();
}
