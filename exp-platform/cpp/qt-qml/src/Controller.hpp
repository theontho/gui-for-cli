#pragma once

#include "Args.hpp"
#include "BundleLoader.hpp"
#include "CommandRunner.hpp"
#include "StateStore.hpp"

#include <QElapsedTimer>
#include <QObject>
#include <QProcess>
#include <QVariantList>
#include <memory>
#include <optional>

class Controller : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantMap bundle READ bundle NOTIFY bundleChanged)
    Q_PROPERTY(QVariantMap currentPage READ currentPage NOTIFY currentPageChanged)
    Q_PROPERTY(QVariantMap fieldValues READ fieldValues NOTIFY fieldValuesChanged)
    Q_PROPERTY(QVariantList terminals READ terminals NOTIFY terminalsChanged)
    Q_PROPERTY(int selectedPageIndex READ selectedPageIndex WRITE selectPage NOTIFY currentPageChanged)
    Q_PROPERTY(int selectedTerminalIndex READ selectedTerminalIndex WRITE selectTerminal NOTIFY terminalsChanged)
    Q_PROPERTY(bool rtl READ rtl CONSTANT)
    Q_PROPERTY(QString terminalTextDirection READ terminalTextDirection CONSTANT)

public:
    Controller(LoadedBundle bundle, Args args, QElapsedTimer bootTimer, QObject* parent = nullptr);
    ~Controller() override;

    QVariantMap bundle() const;
    QVariantMap currentPage() const;
    QVariantMap fieldValues() const;
    QVariantList terminals() const;
    int selectedPageIndex() const;
    int selectedTerminalIndex() const;
    bool rtl() const;
    QString terminalTextDirection() const;

    Q_INVOKABLE void componentReady();
    Q_INVOKABLE void selectPage(int index);
    Q_INVOKABLE void selectTerminal(int index);
    Q_INVOKABLE void updateField(const QVariantMap& control, const QVariant& value);
    Q_INVOKABLE QVariant controlValue(const QVariantMap& control) const;
    Q_INVOKABLE QString dataSourceKey(const QVariantMap& owner, const QString& prefix) const;
    Q_INVOKABLE QVariantList dataRows(const QVariantMap& owner, const QString& prefix) const;
    Q_INVOKABLE QVariantMap dataValues(const QVariantMap& owner, const QString& prefix) const;
    Q_INVOKABLE QString dataError(const QVariantMap& owner, const QString& prefix) const;
    Q_INVOKABLE bool actionIsVisible(const QVariantMap& action, const QVariantMap& row = {}, const QVariantMap& section = {}) const;
    Q_INVOKABLE QString disabledReason(const QVariantMap& action, const QVariantMap& row = {}, const QVariantMap& section = {}) const;
    Q_INVOKABLE QString commandPreview(const QVariantMap& action, const QVariantMap& row = {}, const QVariantMap& section = {}) const;
    Q_INVOKABLE void requestAction(const QVariantMap& action, const QVariantMap& row = {}, const QString& suffix = {}, const QVariantMap& section = {});
    Q_INVOKABLE void confirmPendingAction(const QString& typedText);
    Q_INVOKABLE void cancelPendingAction();
    Q_INVOKABLE void runSetupStep(int index);
    Q_INVOKABLE void refreshDataSources();
    Q_INVOKABLE void closeOrCancelTerminal(int index);
    Q_INVOKABLE void openWorkspace() const;

Q_SIGNALS:
    void bundleChanged();
    void currentPageChanged();
    void fieldValuesChanged();
    void terminalsChanged();
    void dataSourcesChanged();
    void confirmationRequested(QVariantMap confirmation);
    void benchmarkComplete();

private:
    struct TerminalTab {
        int id = 0;
        QString title;
        QString output;
        QString status = "ready";
        bool closable = false;
        QProcess* process = nullptr;
    };
    struct PendingAction {
        QVariantMap action;
        QVariantMap row;
        QVariantMap section;
        QString suffix;
    };

    QVariantMap contextFor(const QVariantMap& row = {}, const QVariantMap& section = {}) const;
    QVariantMap currentPageObject() const;
    QVariantList pages() const;
    void initializeFields();
    void persistState() const;
    void appendTerminalOutput(int terminalId, const QString& text);
    int addTerminal(const QString& title, const QString& preview, bool closable);
    void startRenderedCommand(const QVariantMap& action, const RenderedCommand& command, int terminalId);
    void finishTerminal(int terminalId, int exitCode, QProcess::ExitStatus status);
    void runPendingAction(const PendingAction& pending);
    void loadDataSource(const QString& key, const QVariantMap& dataSource, const QVariantMap& sectionValues = {});

    LoadedBundle loadedBundle_;
    Args args_;
    QElapsedTimer bootTimer_;
    QVariantMap bundleMap_;
    QVariantMap fieldValues_;
    QVariantMap configValues_;
    QVariantMap dataPayloads_;
    QVariantMap dataErrors_;
    QList<TerminalTab> terminalTabs_;
    std::unique_ptr<StateStore> stateStore_;
    std::optional<PendingAction> pendingAction_;
    int selectedPageIndex_ = 0;
    int selectedTerminalIndex_ = 0;
    int nextTerminalId_ = 1;
    bool printedReadyMetric_ = false;
};
