import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ColumnLayout {
    id: root
    required property var control
    property var sectionValues: ({})
    property var rows: appController.dataRows(control, "control")
    property string errorText: appController.dataError(control, "control")
    spacing: 6

    Connections {
        target: appController
        function onDataSourcesChanged() {
            root.rows = appController.dataRows(control, "control")
            root.errorText = appController.dataError(control, "control")
        }
    }

    Label {
        text: root.errorText
        visible: text.length > 0
        color: "#b00020"
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
    }

    Label {
        text: qsTr("No rows are available.")
        visible: rows.length === 0 && root.errorText.length === 0
        color: palette.mid
    }

    Repeater {
        model: rows
        Frame {
            id: rowFrame
            property var rowData: modelData
            Layout.fillWidth: true
            padding: 10
            Accessible.name: rowData.title || rowData.name || rowData.id || qsTr("Library row")

            ColumnLayout {
                anchors.left: parent.left
                anchors.right: parent.right
                spacing: 6

                GridLayout {
                    columns: 2
                    Layout.fillWidth: true
                    Repeater {
                        model: control.columns && control.columns.length > 0 ? control.columns : Object.keys(rowFrame.rowData).map(function(key) { return { id: key, title: key } })
                        delegate: Item {
                            Layout.fillWidth: true
                            implicitHeight: valueLabel.implicitHeight
                            RowLayout {
                                anchors.fill: parent
                                Label { text: (modelData.title || modelData.id) + ":"; font.bold: true }
                                Label {
                                    id: valueLabel
                                    text: String(rowFrame.rowData[modelData.id] || "")
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                            }
                        }
                    }
                }

                Flow {
                    spacing: 8
                    Repeater {
                        model: control.rowActions || []
                        ActionButton {
                            action: modelData
                            rowValues: rowFrame.rowData
                            sectionValues: root.sectionValues
                            suffix: rowFrame.rowData.title || rowFrame.rowData.id || ""
                        }
                    }
                }
            }
        }
    }
}
