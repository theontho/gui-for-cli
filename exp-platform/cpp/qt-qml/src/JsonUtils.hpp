#pragma once

#include <QJsonArray>
#include <QJsonObject>
#include <QJsonValue>
#include <QMap>
#include <QString>
#include <QStringList>

QJsonObject readJsonObject(const QString& path);
QJsonArray toArray(const QJsonValue& value);
QString valueToString(const QJsonValue& value);
QMap<QString, QString> readTomlStrings(const QString& path);
void mergeTomlStrings(QMap<QString, QString>& target, const QString& path);
QString localizedString(const QJsonValue& value, const QMap<QString, QString>& strings, const QString& fallback = {});
QString interpolateBuiltins(QString value, const QString& bundleRoot, const QString& workspaceRoot, const QString& homePath);
QStringList stringListFromJson(const QJsonValue& value);
QVariant jsonToVariant(const QJsonValue& value);
