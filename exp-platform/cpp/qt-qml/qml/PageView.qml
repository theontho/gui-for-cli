import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ScrollView {
    id: root
    required property var page
    clip: true
    Accessible.name: page.title || qsTr("Page")

    ColumnLayout {
        width: root.availableWidth
        spacing: 14
        padding: 18

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
            SectionView { section: modelData; Layout.fillWidth: true }
        }
    }
}
