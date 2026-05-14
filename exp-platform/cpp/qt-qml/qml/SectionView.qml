import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Frame {
    id: root
    required property var section
    padding: 14
    Accessible.name: section.title || section.id

    ColumnLayout {
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 10

        Label {
            text: section.title || section.id
            font.pixelSize: 18
            font.bold: true
            Layout.fillWidth: true
        }
        Label {
            text: section.subtitle || section.summary || ""
            visible: text.length > 0
            wrapMode: Text.WordWrap
            color: palette.mid
            Layout.fillWidth: true
        }

        Repeater {
            model: section.controls || []
            ControlField {
                control: modelData
                sectionValues: appController.dataValues(section, "section")
                Layout.fillWidth: true
            }
        }

        Flow {
            Layout.fillWidth: true
            spacing: 8
            Repeater {
                model: section.actions || []
                ActionButton { actionSpec: modelData; sectionValues: appController.dataValues(section, "section") }
            }
        }
    }
}
