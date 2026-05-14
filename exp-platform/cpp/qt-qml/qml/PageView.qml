import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ScrollView {
    id: root
    required property var page
    clip: true
    Accessible.name: page.title || qsTr("Page")

    ColumnLayout {
        x: 18
        y: 18
        width: Math.max(0, root.availableWidth - 36)
        spacing: 14

        Label {
            text: page.title || qsTr("Untitled page")
            font.pixelSize: 26
            font.bold: true
            Layout.fillWidth: true
        }
        Label {
            text: page.summary || ""
            visible: text.length > 0
            wrapMode: Text.WordWrap
            color: palette.mid
            Layout.fillWidth: true
        }

        Repeater {
            model: page.sections || []
            SectionView {
                required property var modelData
                section: modelData
                Layout.fillWidth: true
            }
        }
    }
}
