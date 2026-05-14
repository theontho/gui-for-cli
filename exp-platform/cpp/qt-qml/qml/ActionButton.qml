import QtQuick
import QtQuick.Controls

Button {
    id: root
    required property var actionSpec
    property var rowValues: ({})
    property var sectionValues: ({})
    property string suffix: ""
    property var fieldSnapshot: appController.fieldValues

    text: actionSpec.title || actionSpec.id
    visible: fieldSnapshot && appController.actionIsVisible(actionSpec, rowValues, sectionValues)
    enabled: appController.disabledReason(actionSpec, rowValues, sectionValues).length === 0
    Accessible.name: text
    Accessible.description: appController.commandPreview(actionSpec, rowValues, sectionValues)

    ToolTip.visible: hovered && ToolTip.text.length > 0
    ToolTip.text: enabled ? (actionSpec.tooltip || appController.commandPreview(actionSpec, rowValues, sectionValues))
                      : appController.disabledReason(actionSpec, rowValues, sectionValues)

    contentItem: Label {
        text: root.text
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        color: root.actionSpec.role === "destructive" ? "#b00020" : root.palette.buttonText
    }

    onClicked: appController.requestAction(actionSpec, rowValues, suffix, sectionValues)
}
