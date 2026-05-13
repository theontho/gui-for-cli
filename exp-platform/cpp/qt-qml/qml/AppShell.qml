import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root
    LayoutMirroring.enabled: appController.rtl
    LayoutMirroring.childrenInherit: true

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        HeaderBar { Layout.fillWidth: true }

        SplitView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            orientation: Qt.Vertical

            RowLayout {
                SplitView.fillHeight: true
                SplitView.minimumHeight: 360
                spacing: 0

                Sidebar {
                    Layout.preferredWidth: 260
                    Layout.fillHeight: true
                }

                PageView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    page: appController.currentPage
                }
            }

            TerminalDrawer {
                SplitView.preferredHeight: 220
                SplitView.minimumHeight: 40
                SplitView.maximumHeight: 420
            }
        }
    }

    ConfirmationDialog { id: confirmationDialog }

    Connections {
        target: appController
        function onConfirmationRequested(payload) { confirmationDialog.openFor(payload) }
    }
}
