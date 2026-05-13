import QtQuick
import QtQuick.Controls

Button {
    id: root
    required property var action
    property var rowValues: ({})
    property var sectionValues: ({})
    property string suffix: ""
    property var fieldSnapshot: appController.fieldValues

    text: action.title || action.id
    visible: fieldSnapshot && appController.actionIsVisible(action, rowValues, sectionValues)
    enabled: appController.disabledReason(action, rowValues, sectionValues).length === 0
    Accessible.name: text
    Accessible.description: appController.commandPreview(action, rowValues, sectionValues)

    ToolTip.visible: hovered && (!enabled || action.tooltip)
    ToolTip.text: enabled ? (action.tooltip || appController.commandPreview(action, rowValues, sectionValues))
                      : appController.disabledReason(action, rowValues, sectionValues)

    contentItem: Label {
        text: root.text
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        color: root.action.role === "destructive" ? "#b00020" : root.palette.buttonText
    }

    onClicked: appController.requestAction(action, rowValues, suffix, sectionValues)
}
