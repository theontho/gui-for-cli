#pragma once

#include <QJsonObject>
#include <QString>
#include <QVariantMap>

class StateStore {
public:
    explicit StateStore(QString workspaceRoot);

    QVariantMap loadState() const;
    void saveState(const QVariantMap& state) const;
    QVariantMap loadConfig(const QString& path) const;
    void saveConfigValue(const QString& path, const QString& key, const QString& value) const;
    QString statePath() const;

private:
    QString workspaceRoot_;
};
