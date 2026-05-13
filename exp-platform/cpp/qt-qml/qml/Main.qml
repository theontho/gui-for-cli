import QtQuick
import QtQuick.Controls
import GUIForCLIQtQML

ApplicationWindow {
    id: window
    width: 1344
    height: 864
    visible: true
    title: (appController.bundle.displayName || "GUI for CLI") + " · Qt QML"

    AppShell {
        anchors.fill: parent
    }

    Component.onCompleted: appController.componentReady()
}
