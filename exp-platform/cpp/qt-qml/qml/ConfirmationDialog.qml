import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Dialog {
    id: root
    modal: true
    title: payload.title || payload.actionTitle || qsTr("Confirm action")
    standardButtons: Dialog.NoButton
    property var payload: ({})

    function openFor(value) {
        payload = value
        typed.text = ""
        open()
    }

    ColumnLayout {
        width: Math.min(520, parent ? parent.width : 520)
        spacing: 10
        Label {
            text: root.payload.message || root.payload.prompt || qsTr("Run this action?")
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }
        TextField {
            id: typed
            visible: (root.payload.requiredText || "").length > 0
            placeholderText: root.payload.requiredText ? qsTr("Type %1 to confirm").arg(root.payload.requiredText) : ""
            Accessible.name: qsTr("Confirmation text")
            Layout.fillWidth: true
        }
        RowLayout {
            Layout.alignment: Qt.AlignRight
            Button { text: root.payload.cancelButtonTitle || qsTr("Cancel"); onClicked: { appController.cancelPendingAction(); root.close() } }
            Button { text: root.payload.confirmButtonTitle || qsTr("Continue"); onClicked: { appController.confirmPendingAction(typed.text); root.close() } }
        }
    }
}
