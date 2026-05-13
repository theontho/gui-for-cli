#pragma once

#include <QJsonObject>
#include <QProcessEnvironment>
#include <QString>
#include <QStringList>
#include <QVariantMap>

struct RenderedCommand {
    QString executable;
    QStringList arguments;
    QString workingDirectory;
    QProcessEnvironment environment;
    QString preview;
    QString missingReason;
};

QVariantMap commandContext(
    const QVariantMap& fieldValues,
    const QVariantMap& configValues,
    const QVariantMap& rowValues,
    const QVariantMap& sectionValues,
    const QString& bundleRoot,
    const QString& workspaceRoot
);
QString resolvePlaceholder(const QString& key, const QVariantMap& context);
QString interpolate(QString value, const QVariantMap& context);
bool conditionMatches(const QVariantMap& condition, const QVariantMap& context);
bool actionVisible(const QVariantMap& action, const QVariantMap& context);
QString actionDisabledReason(const QVariantMap& action, const QVariantMap& context);
RenderedCommand renderActionCommand(const QVariantMap& action, const QVariantMap& context, const QString& bundleRoot);
RenderedCommand renderSetupCommand(const QVariantMap& step, const QString& bundleRoot);
RenderedCommand renderDataSourceCommand(const QVariantMap& dataSource, const QVariantMap& context, const QString& bundleRoot);
