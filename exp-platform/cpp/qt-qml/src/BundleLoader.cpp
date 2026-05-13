#include "BundleLoader.hpp"

#include "JsonUtils.hpp"

#include <QCryptographicHash>
#include <QDir>
#include <QFileInfo>
#include <QJsonArray>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QSet>
#include <stdexcept>

namespace {
const QSet<QString> visibleKeys = {
    "displayName", "summary", "title", "subtitle", "label", "placeholder", "tooltip",
    "disabledTooltip", "message", "confirmButtonTitle", "cancelButtonTitle", "prompt", "text", "helper"
};

bool isRtlLocale(const QString& locale) {
    const QString language = locale.left(2).toLower();
    return language == "ar" || language == "he" || language == "fa" || language == "ur";
}

QString safeLocale(QString locale) {
    if (locale.isEmpty()) {
        return "en";
    }
    static const QRegularExpression localePattern(R"(^[A-Za-z]{2,3}([-_][A-Za-z0-9]{2,8})*$)");
    return localePattern.match(locale).hasMatch() ? locale : QString{"en"};
}

QString resolvePagePath(const QDir& bundleDir, const QString& pageRef) {
    if (pageRef.isEmpty() || QDir::isAbsolutePath(pageRef)) {
        throw std::runtime_error(QString("invalid page reference: %1").arg(pageRef).toStdString());
    }
    const QString cleanRef = QDir::cleanPath(pageRef);
    if (cleanRef == ".." || cleanRef.startsWith("../")) {
        throw std::runtime_error(QString("invalid page reference: %1").arg(pageRef).toStdString());
    }

    const QDir pagesDir(bundleDir.filePath("pages"));
    const QString pagesRoot = QFileInfo(pagesDir.absolutePath()).canonicalFilePath();
    if (pagesRoot.isEmpty()) {
        throw std::runtime_error(QString("bundle pages directory not found: %1").arg(pagesDir.absolutePath()).toStdString());
    }
    const QString pagePath = pagesDir.filePath(cleanRef);
    const QString canonicalPagePath = QFileInfo(pagePath).canonicalFilePath();
    const QString rootPrefix = pagesRoot + QDir::separator();
    if (canonicalPagePath.isEmpty() || (canonicalPagePath != pagesRoot && !canonicalPagePath.startsWith(rootPrefix))) {
        throw std::runtime_error(QString("page reference escapes pages directory: %1").arg(pageRef).toStdString());
    }
    return canonicalPagePath;
}

QString safeWorkspaceName(const QJsonObject& manifest, const QString& bundleRoot) {
    QString raw = manifest.value("id").toString();
    if (raw.isEmpty()) {
        raw = QFileInfo(bundleRoot).fileName();
    }
    const QByteArray digest = QCryptographicHash::hash(bundleRoot.toUtf8(), QCryptographicHash::Sha1).toHex().left(10);
    raw.replace(QRegularExpression(R"([^A-Za-z0-9_.-]+)"), "-");
    return raw + "-" + QString::fromLatin1(digest);
}

QString workspaceRootFor(const QJsonObject& manifest, const QString& bundleRoot) {
    QString base = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    if (base.isEmpty()) {
        base = QDir::home().filePath(".gui-for-cli");
    }
    QDir dir(base);
    if (!dir.mkpath("workspaces")) {
        throw std::runtime_error(QString("create workspace root %1").arg(dir.filePath("workspaces")).toStdString());
    }
    const QString workspace = dir.filePath("workspaces/" + safeWorkspaceName(manifest, bundleRoot));
    if (!QDir().mkpath(workspace)) {
        throw std::runtime_error(QString("create bundle workspace %1").arg(workspace).toStdString());
    }
    return workspace;
}

QJsonValue localizeVisibleStrings(const QJsonValue& value, const QMap<QString, QString>& strings, const QString& parentKey = {}) {
    if (value.isObject()) {
        QJsonObject result;
        const QJsonObject object = value.toObject();
        for (auto iterator = object.constBegin(); iterator != object.constEnd(); ++iterator) {
            result.insert(iterator.key(), localizeVisibleStrings(iterator.value(), strings, iterator.key()));
        }
        return result;
    }
    if (value.isArray()) {
        QJsonArray result;
        for (const auto item : value.toArray()) {
            result.push_back(localizeVisibleStrings(item, strings, parentKey));
        }
        return result;
    }
    if (value.isString() && visibleKeys.contains(parentKey)) {
        return strings.value(value.toString(), value.toString());
    }
    return value;
}

void resolveBuiltins(QJsonValue& value, const QString& bundleRoot, const QString& workspaceRoot, const QString& homePath) {
    if (value.isObject()) {
        QJsonObject object = value.toObject();
        for (auto iterator = object.begin(); iterator != object.end(); ++iterator) {
            QJsonValue child = iterator.value();
            resolveBuiltins(child, bundleRoot, workspaceRoot, homePath);
            iterator.value() = child;
        }
        value = object;
    } else if (value.isArray()) {
        QJsonArray array = value.toArray();
        for (qsizetype index = 0; index < array.size(); ++index) {
            QJsonValue item = array.at(index);
            resolveBuiltins(item, bundleRoot, workspaceRoot, homePath);
            array.replace(index, item);
        }
        value = array;
    } else if (value.isString()) {
        value = interpolateBuiltins(value.toString(), bundleRoot, workspaceRoot, homePath);
    }
}

void countPage(const QJsonObject& page, LoadedBundle& bundle) {
    for (const auto sectionValue : toArray(page.value("sections"))) {
        const QJsonObject section = sectionValue.toObject();
        if (section.contains("dataSource")) {
            bundle.dataSourceCount += 1;
        }
        for (const auto controlValue : toArray(section.value("controls"))) {
            const QJsonObject control = controlValue.toObject();
            bundle.controlCount += 1;
            if (control.contains("dataSource")) {
                bundle.dataSourceCount += 1;
            }
            bundle.actionCount += toArray(control.value("rowActions")).size();
            bundle.controlCount += toArray(control.value("settings")).size();
        }
        bundle.actionCount += toArray(section.value("actions")).size();
    }
}
}

LoadedBundle loadBundle(const BundleLoadOptions& options) {
    QDir bundleDir(options.bundleRoot);
    if (!bundleDir.exists("manifest.json")) {
        throw std::runtime_error(QString("bundle manifest not found: %1").arg(bundleDir.filePath("manifest.json")).toStdString());
    }

    const QString locale = safeLocale(options.locale);
    QJsonObject manifest = readJsonObject(bundleDir.filePath("manifest.json"));
    QMap<QString, QString> strings;
    const QString builtinRoot = QDir(options.repoRoot).filePath("platform/apple/shared/Sources/GUIForCLICore/Resources/BuiltinStrings");
    mergeTomlStrings(strings, QDir(builtinRoot).filePath("strings.en.toml"));
    if (locale != "en") {
        mergeTomlStrings(strings, QDir(builtinRoot).filePath("strings." + locale + ".toml"));
    }
    mergeTomlStrings(strings, bundleDir.filePath("strings/strings." + locale + ".toml"));

    LoadedBundle bundle;
    bundle.bundleRoot = bundleDir.absolutePath();
    bundle.locale = locale;
    bundle.workspaceRoot = workspaceRootFor(manifest, bundle.bundleRoot);
    bundle.strings = strings;
    bundle.terminalTextDirection = manifest.value("terminalTextDirection").toString("ltr").toLower() == "rtl" ? "rtl" : "ltr";
    bundle.rtl = isRtlLocale(locale);

    QJsonValue manifestValue = manifest;
    resolveBuiltins(manifestValue, bundle.bundleRoot, bundle.workspaceRoot, QDir::homePath());
    manifest = manifestValue.toObject();
    manifest = localizeVisibleStrings(manifest, strings).toObject();

    QJsonArray pages;
    for (const auto pageRef : toArray(manifest.value("pages"))) {
        QJsonObject page = pageRef.isString()
            ? readJsonObject(resolvePagePath(bundleDir, pageRef.toString()))
            : pageRef.toObject();
        QJsonValue pageValue = page;
        resolveBuiltins(pageValue, bundle.bundleRoot, bundle.workspaceRoot, QDir::homePath());
        page = localizeVisibleStrings(pageValue, strings).toObject();
        pages.push_back(page);
        countPage(page, bundle);
    }
    manifest.insert("pages", pages);
    manifest.insert("bundleRootPath", bundle.bundleRoot);
    manifest.insert("bundleWorkspacePath", bundle.workspaceRoot);
    bundle.manifest = manifest;
    return bundle;
}

QVariantMap bundleSummaryMap(const LoadedBundle& bundle) {
    QVariantMap map = bundle.manifest.toVariantMap();
    map.insert("bundleRootPath", bundle.bundleRoot);
    map.insert("bundleWorkspacePath", bundle.workspaceRoot);
    map.insert("locale", bundle.locale);
    map.insert("terminalTextDirection", bundle.terminalTextDirection);
    map.insert("rtl", bundle.rtl);
    map.insert("controlCount", bundle.controlCount);
    map.insert("actionCount", bundle.actionCount);
    map.insert("dataSourceCount", bundle.dataSourceCount);
    return map;
}
