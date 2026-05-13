import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Frame {
    id: root
    padding: 12
    Accessible.name: appController.bundle.displayName || "GUI for CLI"

    RowLayout {
        anchors.fill: parent
        spacing: 12

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            RowLayout {
                Label {
                    text: appController.bundle.displayName || "GUI for CLI"
                    font.pixelSize: 22
                    font.bold: true
                }
                ToolButton {
                    text: "ⓘ"
                    Accessible.name: qsTr("Bundle summary")
                    ToolTip.visible: hovered
                    ToolTip.text: appController.bundle.summary || ""
                }
            }
            Label {
                text: appController.bundle.summary || ""
                color: palette.mid
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
        }

        Button {
            text: qsTr("Workspace")
            Accessible.name: qsTr("Open bundle workspace")
            onClicked: appController.openWorkspace()
        }

        Button {
            id: setupButton
            text: qsTr("Setup")
            Accessible.name: qsTr("Run setup step")
            onClicked: setupMenu.open()
            Menu {
                id: setupMenu
                y: setupButton.height
                Repeater {
                    model: (appController.bundle.setup && appController.bundle.setup.steps) || []
                    MenuItem {
                        text: (modelData.label || modelData.id || qsTr("Setup step"))
                        onTriggered: appController.runSetupStep(index)
                    }
                }
            }
        }
    }
}
