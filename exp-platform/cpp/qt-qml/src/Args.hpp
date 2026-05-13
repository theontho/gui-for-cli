#pragma once

#include <QString>

struct Args {
    QString bundle;
    QString repoRoot;
    QString locale = "en";
    bool benchmark = false;
    bool benchmarkFull = false;
    bool once = false;
    bool version = false;
};

Args parseArgs(const QStringList& rawArgs);
QString usageText();
