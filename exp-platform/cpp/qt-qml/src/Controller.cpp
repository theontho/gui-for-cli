#include "Controller.hpp"

#include <QCoreApplication>
#include <QDesktopServices>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>
#include <QTimer>
#include <QUrl>
#include <algorithm>
#include <iostream>
#include <memory>
#ifndef Q_OS_WIN
#include <signal.h>
#include <unistd.h>
#endif

namespace {
void terminateProcessTree(QProcess* process) {
    if (process == nullptr) return;
#ifndef Q_OS_WIN
    const qint64 pid = process->processId();
    if (pid > 0) {
        ::kill(-static_cast<pid_t>(pid), SIGTERM);
        return;
    }
#endif
    process->kill();
}

bool markProcessHandled(QProcess* process) {
    if (process->property("guiForCliHandled").toBool()) {
        return false;
    }
    process->setProperty("guiForCliHandled", true);
    return true;
}
}

Controller::Controller(LoadedBundle bundle, Args args, QElapsedTimer bootTimer, QObject* parent)
    : QObject(parent), loadedBundle_(std::move(bundle)), args_(std::move(args)), bootTimer_(bootTimer) {
    bundleMap_ = bundleSummaryMap(loadedBundle_);
    stateStore_ = std::make_unique<StateStore>(loadedBundle_.workspaceRoot);
    const QVariantMap saved = stateStore_->loadState();
    fieldValues_ = saved.value("fieldValues").toMap();
    selectedPageIndex_ = saved.value("selectedPageIndex", 0).toInt();
    initializeFields();
    terminalTabs_.append({nextTerminalId_++, "General", "Qt/QML renderer ready.\n", "ready", false, nullptr});
}

Controller::~Controller() {
    for (auto& tab : terminalTabs_) {
        if (tab.process != nullptr) {
            terminateProcessTree(tab.process);
            tab.process->deleteLater();
        }
    }
}

QVariantMap Controller::bundle() const { return bundleMap_; }
QVariantMap Controller::currentPage() const { return currentPageObject(); }
QVariantMap Controller::fieldValues() const { return fieldValues_; }
int Controller::selectedPageIndex() const { return selectedPageIndex_; }
int Controller::selectedTerminalIndex() const { return selectedTerminalIndex_; }
bool Controller::rtl() const { return loadedBundle_.rtl; }
QString Controller::terminalTextDirection() const { return loadedBundle_.terminalTextDirection; }

QVariantList Controller::terminals() const {
    QVariantList result;
    for (const auto& tab : terminalTabs_) {
        result.push_back(QVariantMap{{"id", tab.id}, {"title", tab.title}, {"output", tab.output}, {"status", tab.status}, {"closable", tab.closable}});
    }
    return result;
}

void Controller::componentReady() {
    if (printedReadyMetric_) return;
    printedReadyMetric_ = true;
    std::cout << "metric ui_ready_ms=" << bootTimer_.elapsed() << std::endl;
    QTimer::singleShot(0, this, [this] {
        refreshDataSources();
        if (args_.benchmarkFull) {
            std::cout << "metric full_feature_warm_ms=" << bootTimer_.elapsed() << std::endl;
        }
        if (args_.benchmark) {
            QTimer::singleShot(250, qApp, &QCoreApplication::quit);
        }
    });
}

void Controller::selectPage(int index) {
    const int count = pages().size();
    if (index < 0 || index >= count || index == selectedPageIndex_) return;
    selectedPageIndex_ = index;
    persistState();
    Q_EMIT currentPageChanged();
    refreshDataSources();
}

void Controller::selectTerminal(int index) {
    if (index < 0 || index >= terminalTabs_.size()) return;
    selectedTerminalIndex_ = index;
    Q_EMIT terminalsChanged();
}

void Controller::updateField(const QVariantMap& control, const QVariant& value) {
    const QString id = control.value("id").toString();
    if (id.isEmpty()) return;
    fieldValues_.insert(id, value);
    if (!control.value("configKey").toString().isEmpty()) {
        const QString key = control.value("configKey").toString();
        configValues_.insert(key, value);
        stateStore_->saveConfigValue(control.value("configFilePath").toString(), key, value.toString());
    }
    persistState();
    Q_EMIT fieldValuesChanged();
    refreshDataSources();
}

QVariant Controller::controlValue(const QVariantMap& control) const {
    const QString id = control.value("id").toString();
    if (fieldValues_.contains(id)) return fieldValues_.value(id);
    return control.value("value");
}

QString Controller::dataSourceKey(const QVariantMap& owner, const QString& prefix) const {
    return prefix + ":" + owner.value("id").toString();
}

QVariantList Controller::dataRows(const QVariantMap& owner, const QString& prefix) const {
    const QVariantMap payload = dataPayloads_.value(dataSourceKey(owner, prefix)).toMap();
    QVariant rows = payload.value("rows");
    if (!rows.isValid()) rows = payload.value("items");
    if (!rows.isValid()) rows = owner.value("items");
    return rows.toList();
}

QVariantMap Controller::dataValues(const QVariantMap& owner, const QString& prefix) const {
    return dataPayloads_.value(dataSourceKey(owner, prefix)).toMap().value("values").toMap();
}

QString Controller::dataError(const QVariantMap& owner, const QString& prefix) const {
    return dataErrors_.value(dataSourceKey(owner, prefix)).toString();
}

bool Controller::actionIsVisible(const QVariantMap& action, const QVariantMap& row, const QVariantMap& section) const {
    return actionVisible(action, contextFor(row, section));
}

QString Controller::disabledReason(const QVariantMap& action, const QVariantMap& row, const QVariantMap& section) const {
    return actionDisabledReason(action, contextFor(row, section));
}

QString Controller::commandPreview(const QVariantMap& action, const QVariantMap& row, const QVariantMap& section) const {
    return renderActionCommand(action, contextFor(row, section), loadedBundle_.bundleRoot).preview;
}

void Controller::requestAction(const QVariantMap& action, const QVariantMap& row, const QString& suffix, const QVariantMap& section) {
    PendingAction pending{action, row, section, suffix};
    const QVariantMap confirm = action.value("confirm").toMap();
    if (!confirm.isEmpty()) {
        pendingAction_ = pending;
        QVariantMap payload = confirm;
        payload.insert("actionTitle", action.value("title"));
        Q_EMIT confirmationRequested(payload);
        return;
    }
    runPendingAction(pending);
}

void Controller::confirmPendingAction(const QString& typedText) {
    if (!pendingAction_) return;
    const QVariantMap confirm = pendingAction_->action.value("confirm").toMap();
    const QString required = confirm.value("requiredText").toString();
    if (!required.isEmpty() && typedText != required) return;
    const PendingAction pending = *pendingAction_;
    pendingAction_.reset();
    runPendingAction(pending);
}

void Controller::cancelPendingAction() { pendingAction_.reset(); }

void Controller::runSetupStep(int index) {
    const QVariantList steps = bundleMap_.value("setup").toMap().value("steps").toList();
    if (index < 0 || index >= steps.size()) return;
    const QVariantMap step = steps.at(index).toMap();
    const RenderedCommand command = renderSetupCommand(step, loadedBundle_.bundleRoot);
    const int terminal = addTerminal("Setup: " + step.value("label").toString(), command.preview, true);
    startRenderedCommand({{"title", step.value("label")}}, command, terminal);
}

void Controller::refreshDataSources() {
    const QVariantMap page = currentPageObject();
    for (const QVariant& sectionValue : page.value("sections").toList()) {
        const QVariantMap section = sectionValue.toMap();
        auto refreshControls = [this, section] {
            const QVariantMap sectionValues = dataValues(section, "section");
            for (const QVariant& controlValue : section.value("controls").toList()) {
                const QVariantMap control = controlValue.toMap();
                if (control.contains("dataSource")) {
                    loadDataSource(dataSourceKey(control, "control"), control.value("dataSource").toMap(), sectionValues);
                }
            }
        };
        if (section.contains("dataSource")) {
            loadDataSource(dataSourceKey(section, "section"), section.value("dataSource").toMap(), {}, refreshControls);
        } else {
            refreshControls();
        }
    }
    Q_EMIT dataSourcesChanged();
}

void Controller::closeOrCancelTerminal(int index) {
    if (index <= 0 || index >= terminalTabs_.size()) return;
    auto& tab = terminalTabs_[index];
    if (tab.process != nullptr && tab.status == "running") {
        terminateProcessTree(tab.process);
        tab.status = "cancelled";
    } else {
        if (tab.process != nullptr) tab.process->deleteLater();
        terminalTabs_.removeAt(index);
        selectedTerminalIndex_ = std::min(selectedTerminalIndex_, static_cast<int>(terminalTabs_.size()) - 1);
    }
    Q_EMIT terminalsChanged();
}

void Controller::openWorkspace() const {
    QDesktopServices::openUrl(QUrl::fromLocalFile(loadedBundle_.workspaceRoot));
}

QVariantMap Controller::contextFor(const QVariantMap& row, const QVariantMap& section) const {
    return commandContext(fieldValues_, configValues_, row, section, loadedBundle_.bundleRoot, loadedBundle_.workspaceRoot);
}

QVariantList Controller::pages() const { return bundleMap_.value("pages").toList(); }

QVariantMap Controller::currentPageObject() const {
    const QVariantList allPages = pages();
    if (allPages.isEmpty()) return {};
    const int index = std::clamp(selectedPageIndex_, 0, static_cast<int>(allPages.size()) - 1);
    return allPages.at(index).toMap();
}

void Controller::initializeFields() {
    for (const QVariant& pageValue : pages()) {
        for (const QVariant& sectionValue : pageValue.toMap().value("sections").toList()) {
            for (const QVariant& controlValue : sectionValue.toMap().value("controls").toList()) {
                const QVariantMap control = controlValue.toMap();
                const QString id = control.value("id").toString();
                if (!id.isEmpty() && !fieldValues_.contains(id)) fieldValues_.insert(id, control.value("value"));
                for (const QVariant& settingValue : control.value("settings").toList()) {
                    const QVariantMap setting = settingValue.toMap();
                    const QString settingId = setting.value("id").toString();
                    if (!settingId.isEmpty() && !fieldValues_.contains(settingId)) fieldValues_.insert(settingId, setting.value("value"));
                }
            }
        }
    }
}

void Controller::persistState() const {
    stateStore_->saveState({{"fieldValues", fieldValues_}, {"selectedPageIndex", selectedPageIndex_}});
}

int Controller::addTerminal(const QString& title, const QString& preview, bool closable) {
    const int id = nextTerminalId_++;
    terminalTabs_.append({id, title, "$ " + preview + "\n", "running", closable, nullptr});
    selectedTerminalIndex_ = terminalTabs_.size() - 1;
    Q_EMIT terminalsChanged();
    return id;
}

void Controller::appendTerminalOutput(int terminalId, const QString& text) {
    for (auto& tab : terminalTabs_) {
        if (tab.id == terminalId) {
            tab.output += text;
            break;
        }
    }
    Q_EMIT terminalsChanged();
}

void Controller::startRenderedCommand(const QVariantMap& action, const RenderedCommand& command, int terminalId) {
    QProcess* process = new QProcess(this);
    process->setWorkingDirectory(command.workingDirectory);
#ifndef Q_OS_WIN
    process->setChildProcessModifier([] { ::setpgid(0, 0); });
#endif
    process->setProcessEnvironment(command.environment);
    process->setProcessChannelMode(QProcess::MergedChannels);
    process->setProperty("guiForCliHandled", false);
    for (auto& tab : terminalTabs_) if (tab.id == terminalId) tab.process = process;
    connect(process, &QProcess::readyReadStandardOutput, this, [this, process, terminalId] {
        appendTerminalOutput(terminalId, QString::fromLocal8Bit(process->readAllStandardOutput()));
    });
    connect(process, &QProcess::finished, this, [this, process, terminalId](int exitCode, QProcess::ExitStatus status) {
        if (!markProcessHandled(process)) return;
        finishTerminal(terminalId, exitCode, status);
        process->deleteLater();
    });
    connect(process, &QProcess::errorOccurred, this, [this, process, terminalId](QProcess::ProcessError error) {
        if (error != QProcess::FailedToStart || !markProcessHandled(process)) return;
        appendTerminalOutput(terminalId, "error: failed to start process: " + process->errorString() + "\n");
        finishTerminal(terminalId, 127, QProcess::CrashExit);
        process->deleteLater();
    });
    process->start(command.executable, command.arguments);
    Q_UNUSED(action);
}

void Controller::finishTerminal(int terminalId, int exitCode, QProcess::ExitStatus status) {
    for (auto& tab : terminalTabs_) {
        if (tab.id != terminalId) continue;
        tab.status = status == QProcess::CrashExit ? "failed" : (exitCode == 0 ? "succeeded" : "failed");
        tab.output += QString("\n[exit %1]\n").arg(exitCode);
        tab.process = nullptr;
    }
    refreshDataSources();
    Q_EMIT terminalsChanged();
}

void Controller::runPendingAction(const PendingAction& pending) {
    const QVariantMap context = contextFor(pending.row, pending.section);
    const QString reason = actionDisabledReason(pending.action, context);
    if (!reason.isEmpty()) {
        appendTerminalOutput(terminalTabs_.first().id, "Blocked action: " + reason + "\n");
        return;
    }
    const RenderedCommand command = renderActionCommand(pending.action, context, loadedBundle_.bundleRoot);
    const QString title = pending.action.value("title").toString() + (pending.suffix.isEmpty() ? QString{} : " — " + pending.suffix);
    startRenderedCommand(pending.action, command, addTerminal(title, command.preview, true));
}

void Controller::loadDataSource(const QString& key, const QVariantMap& dataSource, const QVariantMap& sectionValues, std::function<void()> completion) {
    const RenderedCommand command = renderDataSourceCommand(dataSource, contextFor({}, sectionValues), loadedBundle_.bundleRoot);
    if (QProcess* active = dataSourceProcesses_.take(key); active != nullptr) {
        disconnect(active, nullptr, this, nullptr);
        terminateProcessTree(active);
        active->deleteLater();
    }
    QProcess* process = new QProcess(this);
    auto output = std::make_shared<QByteArray>();
    const int generation = nextDataSourceGeneration_++;
    dataSourceGenerations_.insert(key, generation);
    dataSourceProcesses_.insert(key, process);

    process->setWorkingDirectory(command.workingDirectory);
    process->setProcessEnvironment(command.environment);
    process->setProcessChannelMode(QProcess::MergedChannels);
    process->setProperty("guiForCliHandled", false);
    connect(process, &QProcess::readyReadStandardOutput, this, [process, output] {
        output->append(process->readAllStandardOutput());
    });
    connect(process, &QProcess::finished, this, [this, process, output, key, generation, completion = std::move(completion)](int exitCode, QProcess::ExitStatus status) {
        if (!markProcessHandled(process)) return;
        output->append(process->readAllStandardOutput());
        if (dataSourceGenerations_.value(key) == generation) {
            dataSourceGenerations_.remove(key);
            if (dataSourceProcesses_.value(key) == process) dataSourceProcesses_.remove(key);
            if (status != QProcess::NormalExit || exitCode != 0) {
                const QString message = QString::fromLocal8Bit(*output).trimmed();
                dataErrors_.insert(key, message.isEmpty() ? process->errorString() : message);
                dataPayloads_.remove(key);
            } else {
                QJsonParseError parseError;
                const QJsonDocument document = QJsonDocument::fromJson(*output, &parseError);
                if (parseError.error != QJsonParseError::NoError || !document.isObject()) {
                    dataErrors_.insert(key, "Data source did not return a JSON object.");
                    dataPayloads_.remove(key);
                } else {
                    dataErrors_.remove(key);
                    dataPayloads_.insert(key, document.object().toVariantMap());
                    if (completion) completion();
                }
            }
            Q_EMIT dataSourcesChanged();
        }
        process->deleteLater();
    });
    connect(process, &QProcess::errorOccurred, this, [this, process, key, generation](QProcess::ProcessError error) {
        if (error != QProcess::FailedToStart || !markProcessHandled(process)) return;
        if (dataSourceGenerations_.value(key) == generation) {
            dataSourceGenerations_.remove(key);
            if (dataSourceProcesses_.value(key) == process) dataSourceProcesses_.remove(key);
            dataErrors_.insert(key, "Data source failed to start: " + process->errorString());
            dataPayloads_.remove(key);
            Q_EMIT dataSourcesChanged();
        }
        process->deleteLater();
    });
    process->start(command.executable, command.arguments);
}
