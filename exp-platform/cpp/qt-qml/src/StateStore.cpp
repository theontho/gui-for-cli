#include "StateStore.hpp"

#include "JsonUtils.hpp"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QTextStream>

namespace {
QString decodeTomlString(const QString& encoded) {
    QString decoded;
    decoded.reserve(encoded.size());
    for (int index = 0; index < encoded.size(); ++index) {
        const QChar current = encoded.at(index);
        if (current != '\\' || index + 1 >= encoded.size()) {
            decoded += current;
            continue;
        }
        const QChar escaped = encoded.at(++index);
        if (escaped == 'n') decoded += '\n';
        else if (escaped == '"') decoded += '"';
        else if (escaped == '\\') decoded += '\\';
        else decoded += escaped;
    }
    return decoded;
}
}

StateStore::StateStore(QString workspaceRoot) : workspaceRoot_(std::move(workspaceRoot)) {}

QString StateStore::statePath() const {
    return QDir(workspaceRoot_).filePath("qt-qml-state.json");
}

QVariantMap StateStore::loadState() const {
    QFile file(statePath());
    if (!file.exists() || !file.open(QIODevice::ReadOnly)) {
        return {};
    }
    const QJsonDocument document = QJsonDocument::fromJson(file.readAll());
    return document.isObject() ? document.object().toVariantMap() : QVariantMap{};
}

void StateStore::saveState(const QVariantMap& state) const {
    QDir().mkpath(workspaceRoot_);
    QFile file(statePath());
    if (file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        file.write(QJsonDocument::fromVariant(state).toJson(QJsonDocument::Indented));
    }
}

QVariantMap StateStore::loadConfig(const QString& path) const {
    QVariantMap result;
    QFile file(path);
    if (!file.exists() || !file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        return result;
    }
    while (!file.atEnd()) {
        const QString line = QString::fromUtf8(file.readLine()).trimmed();
        if (line.startsWith('#') || !line.contains('=')) {
            continue;
        }
        const int equals = line.indexOf('=');
        const QString key = line.left(equals).trimmed();
        QString value = line.mid(equals + 1).trimmed();
        if (value.startsWith('"') && value.endsWith('"') && value.size() >= 2) {
            value = decodeTomlString(value.mid(1, value.size() - 2));
        }
        result.insert(key, value);
    }
    return result;
}

void StateStore::saveConfigValue(const QString& path, const QString& key, const QString& value) const {
    QDir().mkpath(QFileInfo(path).absolutePath());
    QVariantMap config = loadConfig(path);
    config.insert(key, value);
    QFile file(path);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Text | QIODevice::Truncate)) {
        return;
    }
    QTextStream stream(&file);
    for (auto iterator = config.constBegin(); iterator != config.constEnd(); ++iterator) {
        QString escaped = iterator.value().toString();
        escaped.replace("\\", "\\\\").replace("\n", R"(\n)").replace("\"", R"(\")");
        stream << iterator.key() << " = \"" << escaped << "\"\n";
    }
}
