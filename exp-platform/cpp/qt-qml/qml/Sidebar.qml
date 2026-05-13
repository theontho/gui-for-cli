import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Frame {
    id: root
    padding: 8
    Accessible.name: qsTr("Pages")

    ListView {
        anchors.fill: parent
        model: appController.bundle.pages || []
        spacing: 4
        clip: true

        delegate: ItemDelegate {
            width: ListView.view.width
            highlighted: index === appController.selectedPageIndex
            Accessible.name: modelData.title || modelData.id
            onClicked: appController.selectPage(index)

            contentItem: RowLayout {
                spacing: 8
                Label {
                    text: modelData.icon || "•"
                    horizontalAlignment: Text.AlignHCenter
                    Layout.preferredWidth: 26
                    Accessible.ignored: true
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    Label { text: modelData.title || modelData.id; font.bold: true; elide: Text.ElideRight; Layout.fillWidth: true }
                    Label { text: modelData.sidebarGroup || ""; color: palette.mid; font.pixelSize: 11; visible: text.length > 0 }
                }
            }
        }
    }
}
