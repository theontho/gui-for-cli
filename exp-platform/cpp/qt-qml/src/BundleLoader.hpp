#pragma once

#include <QJsonObject>
#include <QMap>
#include <QString>
#include <QVariantMap>

struct BundleLoadOptions {
    QString bundleRoot;
    QString repoRoot;
    QString locale;
};

struct LoadedBundle {
    QJsonObject manifest;
    QMap<QString, QString> strings;
    QString bundleRoot;
    QString workspaceRoot;
    QString locale;
    QString terminalTextDirection = "ltr";
    bool rtl = false;
    int controlCount = 0;
    int actionCount = 0;
    int dataSourceCount = 0;
};

LoadedBundle loadBundle(const BundleLoadOptions& options);
QVariantMap bundleSummaryMap(const LoadedBundle& bundle);
