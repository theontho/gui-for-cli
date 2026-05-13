#include "CommandRunner.hpp"

#include <QDir>
#include <QRegularExpression>
#include <QVariantList>
#include <algorithm>

namespace {
QString shellQuote(const QString& value) {
    if (value.isEmpty()) {
        return "''";
    }
    static const QRegularExpression simple(R"(^[A-Za-z0-9_./:=+-]+$)");
    if (simple.match(value).hasMatch()) {
        return value;
    }
    QString escaped = value;
    escaped.replace("'", "'\\''");
    return "'" + escaped + "'";
}

QString envSuffix(QString key) {
    QString suffix;
    for (const QChar ch : key) {
        suffix += ch.isLetterOrNumber() ? ch.toUpper() : QChar('_');
    }
    return suffix;
}

QStringList variantStringList(const QVariant& value) {
    QStringList result;
    for (const QVariant& item : value.toList()) {
        result.push_back(item.toString());
    }
    return result;
}

bool hasMissingPlaceholder(const QStringList& values, const QVariantMap& context) {
    static const QRegularExpression pattern(R"(\{\{\s*([^}]+?)\s*\}\})");
    for (const QString& value : values) {
        auto matchIterator = pattern.globalMatch(value);
        while (matchIterator.hasNext()) {
            const auto match = matchIterator.next();
            if (resolvePlaceholder(match.captured(1).trimmed(), context).isEmpty()) {
                return true;
            }
        }
    }
    return false;
}

bool numericConstraintsMatch(const QVariantMap& condition, const QString& value) {
    const QStringList numericKeys{"lessThan", "lessThanOrEqual", "greaterThan", "greaterThanOrEqual"};
    bool hasNumericConstraint = false;
    for (const QString& key : numericKeys) {
        hasNumericConstraint = hasNumericConstraint || condition.contains(key);
    }
    if (!hasNumericConstraint) {
        return true;
    }

    bool valueOk = false;
    const double number = value.toDouble(&valueOk);
    if (!valueOk) {
        return false;
    }

    auto threshold = [&condition](const QString& key, double& output) {
        bool ok = false;
        output = condition.value(key).toDouble(&ok);
        return ok;
    };

    double limit = 0;
    if (condition.contains("lessThan") && (!threshold("lessThan", limit) || !(number < limit))) return false;
    if (condition.contains("lessThanOrEqual") && (!threshold("lessThanOrEqual", limit) || !(number <= limit))) return false;
    if (condition.contains("greaterThan") && (!threshold("greaterThan", limit) || !(number > limit))) return false;
    if (condition.contains("greaterThanOrEqual") && (!threshold("greaterThanOrEqual", limit) || !(number >= limit))) return false;
    return true;
}

void addEnvironment(QProcessEnvironment& env, const QVariantMap& raw, const QVariantMap& context) {
    for (auto iterator = raw.constBegin(); iterator != raw.constEnd(); ++iterator) {
        env.insert(iterator.key(), interpolate(iterator.value().toString(), context));
    }
}

RenderedCommand finalizeCommand(QString executable, QStringList arguments, QString cwd, QVariantMap rawEnvironment, const QVariantMap& context, const QString& bundleRoot) {
    RenderedCommand rendered;
    rendered.executable = interpolate(executable, context);
    for (const QString& argument : arguments) {
        rendered.arguments.push_back(interpolate(argument, context));
    }
    rendered.workingDirectory = cwd.isEmpty() ? bundleRoot : interpolate(cwd, context);
    rendered.environment = QProcessEnvironment::systemEnvironment();
    rendered.environment.insert("GUI_FOR_CLI_BUNDLE_ROOT", bundleRoot);
    rendered.environment.insert("GUI_FOR_CLI_BUNDLE_WORKSPACE", context.value("bundleWorkspace").toString());
    addEnvironment(rendered.environment, rawEnvironment, context);
    for (auto iterator = context.constBegin(); iterator != context.constEnd(); ++iterator) {
        if (!iterator.value().toMap().isEmpty() || !iterator.value().toList().isEmpty()) {
            continue;
        }
        rendered.environment.insert("GUI_FOR_CLI_FIELD_" + envSuffix(iterator.key()), iterator.value().toString());
    }
    QStringList previewParts{shellQuote(rendered.executable)};
    for (const QString& argument : rendered.arguments) {
        previewParts.push_back(shellQuote(argument));
    }
    rendered.preview = previewParts.join(' ');
    return rendered;
}
}

QVariantMap commandContext(const QVariantMap& fieldValues, const QVariantMap& configValues, const QVariantMap& rowValues, const QVariantMap& sectionValues, const QString& bundleRoot, const QString& workspaceRoot) {
    QVariantMap context;
    context.insert("bundleRoot", bundleRoot);
    context.insert("bundleWorkspace", workspaceRoot);
    context.insert("home", QDir::homePath());
    for (auto iterator = fieldValues.constBegin(); iterator != fieldValues.constEnd(); ++iterator) {
        context.insert(iterator.key(), iterator.value());
    }
    for (auto iterator = configValues.constBegin(); iterator != configValues.constEnd(); ++iterator) {
        context.insert("config." + iterator.key(), iterator.value());
    }
    for (auto iterator = rowValues.constBegin(); iterator != rowValues.constEnd(); ++iterator) {
        context.insert("row." + iterator.key(), iterator.value());
    }
    for (auto iterator = sectionValues.constBegin(); iterator != sectionValues.constEnd(); ++iterator) {
        context.insert("section." + iterator.key(), iterator.value());
    }
    return context;
}

QString resolvePlaceholder(const QString& key, const QVariantMap& context) {
    const QVariant direct = context.value(key);
    if (direct.isValid()) {
        return direct.toString();
    }
    return {};
}

QString interpolate(QString value, const QVariantMap& context) {
    static const QRegularExpression pattern(R"(\{\{\s*([^}]+?)\s*\}\})");
    auto matchIterator = pattern.globalMatch(value);
    QString result;
    qsizetype offset = 0;
    while (matchIterator.hasNext()) {
        const auto match = matchIterator.next();
        result += value.mid(offset, match.capturedStart() - offset);
        result += resolvePlaceholder(match.captured(1).trimmed(), context);
        offset = match.capturedEnd();
    }
    result += value.mid(offset);
    return result;
}

bool conditionMatches(const QVariantMap& condition, const QVariantMap& context) {
    const QString value = resolvePlaceholder(condition.value("placeholder").toString(), context);
    if (condition.contains("exists") && condition.value("exists").toBool() != !value.isEmpty()) {
        return false;
    }
    if (condition.contains("equals") && value != condition.value("equals").toString()) {
        return false;
    }
    if (condition.contains("notEquals") && value == condition.value("notEquals").toString()) {
        return false;
    }
    const QStringList inValues = variantStringList(condition.value("in"));
    if (!inValues.isEmpty() && !inValues.contains(value)) {
        return false;
    }
    const QStringList notInValues = variantStringList(condition.value("notIn"));
    if (!notInValues.isEmpty() && notInValues.contains(value)) {
        return false;
    }
    if (!numericConstraintsMatch(condition, value)) return false;
    return true;
}

bool actionVisible(const QVariantMap& action, const QVariantMap& context) {
    for (const QVariant& raw : action.value("visibleWhen").toList()) {
        if (!conditionMatches(raw.toMap(), context)) {
            return false;
        }
    }
    return true;
}

QString actionDisabledReason(const QVariantMap& action, const QVariantMap& context) {
    for (const QVariant& raw : action.value("disabledWhen").toList()) {
        if (conditionMatches(raw.toMap(), context)) {
            return interpolate(action.value("disabledTooltip", "This action is not available.").toString(), context);
        }
    }
    QVariantMap command = action.value("command").toMap();
    QStringList required = variantStringList(command.value("arguments"));
    required.push_back(command.value("executable").toString());
    return hasMissingPlaceholder(required, context) ? "Fill required values before running." : QString{};
}

RenderedCommand renderActionCommand(const QVariantMap& action, const QVariantMap& context, const QString& bundleRoot) {
    const QVariantMap command = action.value("command").toMap();
    QStringList arguments = variantStringList(command.value("arguments"));
    for (const QVariant& rawGroup : command.value("optionalArguments").toList()) {
        const QStringList group = variantStringList(rawGroup);
        if (!hasMissingPlaceholder(group, context)) {
            arguments.append(group);
        }
    }
    return finalizeCommand(command.value("executable").toString(), arguments, command.value("workingDirectory").toString(), command.value("environment").toMap(), context, bundleRoot);
}

RenderedCommand renderSetupCommand(const QVariantMap& step, const QString& bundleRoot) {
    const QString kind = step.value("kind").toString();
    QString executable = step.value("value").toString();
    QStringList arguments = variantStringList(step.value("arguments"));
    if (kind == "pathTool") {
#ifdef Q_OS_WIN
        executable = "where";
#else
        executable = "which";
#endif
        arguments = {step.value("value").toString()};
    } else if (kind == "setupScript" || kind == "bundledScript") {
        executable = "sh";
        arguments.push_front(step.value("value").toString());
    } else if (kind == "pixiInstall") {
        executable = "pixi";
        arguments = {"install"};
    } else if (kind == "pixiRun") {
        executable = "pixi";
        arguments.push_front("run");
    } else if (kind == "homebrewPackage") {
        executable = "brew";
        arguments = {"list", step.value("value").toString()};
    }
    QVariantMap context = commandContext({}, {}, {}, {}, bundleRoot, bundleRoot);
    return finalizeCommand(executable, arguments, step.value("workingDirectory").toString(), step.value("environment").toMap(), context, bundleRoot);
}

RenderedCommand renderDataSourceCommand(const QVariantMap& dataSource, const QVariantMap& context, const QString& bundleRoot) {
    return finalizeCommand(dataSource.value("path").toString(), variantStringList(dataSource.value("arguments")), dataSource.value("workingDirectory").toString(), dataSource.value("environment").toMap(), context, bundleRoot);
}
