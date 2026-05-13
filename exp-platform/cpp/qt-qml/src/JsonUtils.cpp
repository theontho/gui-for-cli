#include "JsonUtils.hpp"

#include <QFile>
#include <QJsonDocument>
#include <QJsonParseError>
#include <QRegularExpression>
#include <stdexcept>

QJsonObject readJsonObject(const QString& path) {
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        throw std::runtime_error(QString("read %1: %2").arg(path, file.errorString()).toStdString());
    }
    QJsonParseError parseError;
    const QJsonDocument document = QJsonDocument::fromJson(file.readAll(), &parseError);
    if (parseError.error != QJsonParseError::NoError || !document.isObject()) {
        throw std::runtime_error(QString("parse %1: %2").arg(path, parseError.errorString()).toStdString());
    }
    return document.object();
}

QJsonArray toArray(const QJsonValue& value) {
    return value.isArray() ? value.toArray() : QJsonArray{};
}

QString valueToString(const QJsonValue& value) {
    if (value.isString()) {
        return value.toString();
    }
    if (value.isBool()) {
        return value.toBool() ? "true" : "false";
    }
    if (value.isDouble()) {
        return QString::number(value.toDouble(), 'g', 16);
    }
    if (value.isNull() || value.isUndefined()) {
        return {};
    }
    if (value.isArray()) {
        return QString::fromUtf8(QJsonDocument(value.toArray()).toJson(QJsonDocument::Compact));
    }
    return QString::fromUtf8(QJsonDocument(value.toObject()).toJson(QJsonDocument::Compact));
}

QMap<QString, QString> readTomlStrings(const QString& path) {
    QMap<QString, QString> strings;
    QFile file(path);
    if (!file.exists() || !file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        return strings;
    }
    const QRegularExpression linePattern(R"(^\s*\"([^\"]+)\"\s*=\s*\"((?:[^\"\\]|\\.)*)\")");
    while (!file.atEnd()) {
        const QString line = QString::fromUtf8(file.readLine());
        const auto match = linePattern.match(line);
        if (!match.hasMatch()) {
            continue;
        }
        QString value = match.captured(2);
        value.replace(R"(\n)", "\n");
        value.replace(R"(\")", "\"");
        value.replace(R"(\\)", "\\");
        strings.insert(match.captured(1), value);
    }
    return strings;
}

void mergeTomlStrings(QMap<QString, QString>& target, const QString& path) {
    const auto values = readTomlStrings(path);
    for (auto iterator = values.constBegin(); iterator != values.constEnd(); ++iterator) {
        target.insert(iterator.key(), iterator.value());
    }
}

QString localizedString(const QJsonValue& value, const QMap<QString, QString>& strings, const QString& fallback) {
    if (!value.isString()) {
        return fallback;
    }
    const QString key = value.toString();
    return strings.value(key, fallback);
}

QString interpolateBuiltins(QString value, const QString& bundleRoot, const QString& workspaceRoot, const QString& homePath) {
    value.replace("{{bundleRoot}}", bundleRoot);
    value.replace("{{bundleWorkspace}}", workspaceRoot);
    value.replace("{{home}}", homePath);
    return value;
}

QStringList stringListFromJson(const QJsonValue& value) {
    QStringList result;
    for (const auto item : toArray(value)) {
        result.push_back(valueToString(item));
    }
    return result;
}

QVariant jsonToVariant(const QJsonValue& value) {
    return value.toVariant();
}
