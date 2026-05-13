#include "Args.hpp"

#include <QCoreApplication>
#include <QDir>
#include <QFileInfo>
#include <QStringList>
#include <stdexcept>

namespace {
QString findRepoRoot(QString start) {
    QDir current(QFileInfo(start).absoluteFilePath());
    while (true) {
        if (QFileInfo::exists(current.filePath("platform/apple/Package.swift")) &&
            QFileInfo::exists(current.filePath("examples"))) {
            return current.absolutePath();
        }
        if (!current.cdUp()) {
            return QDir::currentPath();
        }
    }
}

QString nextValue(const QStringList& args, int& index, const QString& flag) {
    if (index + 1 >= args.size() || args.at(index + 1).startsWith('-')) {
        throw std::runtime_error(QString("%1 requires a value").arg(flag).toStdString());
    }
    index += 1;
    return args.at(index);
}
}

Args parseArgs(const QStringList& rawArgs) {
    Args args;
    args.repoRoot = findRepoRoot(QDir::currentPath());
    args.bundle = QDir(args.repoRoot).filePath("examples/WGSExtract");
    bool bundleProvided = false;

    for (int index = 1; index < rawArgs.size(); ++index) {
        const QString argument = rawArgs.at(index);
        if (argument == "--bundle") {
            bundleProvided = true;
            args.bundle = nextValue(rawArgs, index, argument);
        } else if (argument == "--repo-root") {
            args.repoRoot = nextValue(rawArgs, index, argument);
            if (!bundleProvided) {
                args.bundle = QDir(args.repoRoot).filePath("examples/WGSExtract");
            }
        } else if (argument == "--locale") {
            args.locale = nextValue(rawArgs, index, argument);
        } else if (argument == "--benchmark") {
            args.benchmark = true;
        } else if (argument == "--benchmark-full") {
            args.benchmarkFull = true;
        } else if (argument == "--once") {
            args.once = true;
        } else if (argument == "--version") {
            args.version = true;
        } else if (argument == "--help" || argument == "-h") {
            throw std::runtime_error(usageText().toStdString());
        } else {
            throw std::runtime_error(QString("unknown argument: %1\n%2").arg(argument, usageText()).toStdString());
        }
    }

    QFileInfo bundleInfo(args.bundle);
    if (bundleInfo.isRelative()) {
        args.bundle = QDir::current().absoluteFilePath(args.bundle);
    }
    QFileInfo repoInfo(args.repoRoot);
    if (repoInfo.isRelative()) {
        args.repoRoot = QDir::current().absoluteFilePath(args.repoRoot);
    }
    return args;
}

QString usageText() {
    return "Usage: gui-for-cli-qt-qml [--bundle PATH] [--repo-root PATH] [--locale CODE] "
           "[--benchmark] [--benchmark-full] [--once] [--version]";
}
