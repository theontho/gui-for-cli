import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Frame {
    id: root
    padding: 8
    property bool expanded: true
    Accessible.name: qsTr("Terminal output")

    ColumnLayout {
        anchors.fill: parent
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            Label { text: qsTr("Terminal"); font.bold: true }
            TabBar {
                Layout.fillWidth: true
                currentIndex: appController.selectedTerminalIndex
                onCurrentIndexChanged: appController.selectTerminal(currentIndex)
                Repeater {
                    model: appController.terminals
                    TabButton {
                        text: (modelData.status === "running" ? "⟳ " : "") + modelData.title
                        Accessible.name: text + " " + modelData.status
                    }
                }
            }
            ToolButton {
                text: "✕"
                enabled: appController.selectedTerminalIndex > 0
                Accessible.name: qsTr("Close or cancel terminal tab")
                onClicked: appController.closeOrCancelTerminal(appController.selectedTerminalIndex)
            }
            ToolButton {
                text: root.expanded ? "⌄" : "⌃"
                Accessible.name: root.expanded ? qsTr("Hide terminal") : qsTr("Show terminal")
                onClicked: root.expanded = !root.expanded
            }
        }

        TextArea {
            id: output
            visible: root.expanded
            readOnly: true
            wrapMode: TextEdit.NoWrap
            textFormat: TextEdit.PlainText
            text: {
                var tab = appController.terminals[appController.selectedTerminalIndex]
                return tab ? tab.output : ""
            }
            Layout.fillWidth: true
            Layout.fillHeight: true
            LayoutMirroring.enabled: appController.terminalTextDirection === "rtl"
            horizontalAlignment: appController.terminalTextDirection === "rtl" ? Text.AlignRight : Text.AlignLeft
            Accessible.name: qsTr("Terminal log")
            onTextChanged: cursorPosition = length
            font.family: Qt.platform.os === "windows" ? "Consolas" : "Menlo"
        }
    }
}
