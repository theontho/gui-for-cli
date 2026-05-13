#include "Args.hpp"
#include "BundleLoader.hpp"
#include "Controller.hpp"

#include <QCoreApplication>
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QJsonDocument>
#include <QQuickStyle>
#include <iostream>

int main(int argc, char* argv[]) {
    QElapsedTimer bootTimer;
    bootTimer.start();
    std::cout << "metric process_started_ms=0" << std::endl;

    try {
        QStringList rawArgs;
        rawArgs.reserve(argc);
        for (int index = 0; index < argc; ++index) {
            rawArgs.append(QString::fromLocal8Bit(argv[index]));
        }
        const Args args = parseArgs(rawArgs);
        if (args.version) {
            std::cout << "gui-for-cli-qt-qml experimental" << std::endl;
            return 0;
        }

        if (args.once && !args.benchmark) {
            QCoreApplication app(argc, argv);
            QCoreApplication::setApplicationName("GUI for CLI Qt QML");
            LoadedBundle bundle = loadBundle({args.bundle, args.repoRoot, args.locale});
            std::cout << "metric bundle_loaded_ms=" << bootTimer.elapsed() << std::endl;
            std::cout << QJsonDocument::fromVariant(bundleSummaryMap(bundle)).toJson(QJsonDocument::Indented).toStdString();
            return 0;
        }

        QGuiApplication app(argc, argv);
        QGuiApplication::setApplicationName("GUI for CLI Qt QML");
        QQuickStyle::setStyle("Fusion");

        LoadedBundle bundle = loadBundle({args.bundle, args.repoRoot, args.locale});
        std::cout << "metric bundle_loaded_ms=" << bootTimer.elapsed() << std::endl;

        Controller controller(std::move(bundle), args, bootTimer);
        QQmlApplicationEngine engine;
        engine.rootContext()->setContextProperty("appController", &controller);
        QObject::connect(&engine, &QQmlApplicationEngine::objectCreationFailed, &app, [] { QCoreApplication::exit(1); }, Qt::QueuedConnection);
        engine.loadFromModule("GUIForCLIQtQML", "Main");
        return app.exec();
    } catch (const std::exception& error) {
        std::cerr << error.what() << std::endl;
        return 1;
    }
}
