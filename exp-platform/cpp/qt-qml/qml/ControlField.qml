import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts

ColumnLayout {
    id: root
    required property var control
    property var sectionValues: ({})
    spacing: 4
    Accessible.name: control.label || control.id
    function stringValue(value) {
        return value === null || value === undefined ? "" : String(value)
    }

    Label {
        text: control.label || control.id
        font.bold: true
        visible: control.kind !== "toggle"
    }

    Loader {
        Layout.fillWidth: true
        sourceComponent: {
            if (control.kind === "dropdown") return dropdownComponent
            if (control.kind === "toggle") return toggleComponent
            if (control.kind === "checkboxGroup") return checkboxGroupComponent
            if (control.kind === "libraryList") return libraryListComponent
            if (control.kind === "infoGrid") return infoGridComponent
            if (control.kind === "configEditor") return configEditorComponent
            return textComponent
        }
    }

    Label {
        text: control.tooltip || control.helper || ""
        visible: text.length > 0
        wrapMode: Text.WordWrap
        color: palette.mid
        Layout.fillWidth: true
    }

    Component {
        id: textComponent
        RowLayout {
            TextField {
                id: input
                text: root.stringValue(appController.controlValue(control))
                placeholderText: control.placeholder || ""
                Layout.fillWidth: true
                LayoutMirroring.enabled: false
                horizontalAlignment: Text.AlignLeft
                Accessible.name: control.label || control.id
                onEditingFinished: appController.updateField(control, text)
            }
            Button {
                visible: control.kind === "path"
                text: qsTr("Browse…")
                Accessible.name: qsTr("Choose path for %1").arg(control.label || control.id)
                onClicked: fileDialog.open()
            }
            FileDialog {
                id: fileDialog
                title: qsTr("Choose path")
                onAccepted: appController.updateField(control, selectedFile.toString().replace(/^file:\/\//, ""))
            }
        }
    }

    Component {
        id: dropdownComponent
        ComboBox {
            id: combo
            model: control.options || []
            textRole: "title"
            valueRole: "id"
            currentIndex: Math.max(0, model.findIndex ? model.findIndex(function(item) { return item.id === appController.controlValue(control) }) : 0)
            Accessible.name: control.label || control.id
            onActivated: appController.updateField(control, currentValue)
        }
    }

    Component {
        id: toggleComponent
        Switch {
            text: control.label || control.id
            checked: root.stringValue(appController.controlValue(control)) === "true"
            Accessible.name: text
            onToggled: appController.updateField(control, checked ? "true" : "false")
        }
    }

    Component {
        id: checkboxGroupComponent
        Flow {
            spacing: 10
            Repeater {
                model: control.options || []
                CheckBox {
                    text: modelData.title || modelData.id
                    checked: root.stringValue(appController.controlValue(control)).split(",").indexOf(modelData.id) >= 0
                    Accessible.name: text
                    onToggled: {
                        var selected = root.stringValue(appController.controlValue(control)).split(",").filter(Boolean)
                        var pos = selected.indexOf(modelData.id)
                        if (checked && pos < 0) selected.push(modelData.id)
                        if (!checked && pos >= 0) selected.splice(pos, 1)
                        appController.updateField(control, selected.join(","))
                    }
                }
            }
        }
    }

    Component {
        id: infoGridComponent
        GridLayout {
            columns: 2
            property var values: appController.dataValues(control, "control")
            Connections { target: appController; function onDataSourcesChanged() { parent.values = appController.dataValues(control, "control") } }
            Repeater {
                model: Object.keys(values)
                delegate: Label { text: modelData + ": " + values[modelData] }
            }
        }
    }

    Component {
        id: configEditorComponent
        ColumnLayout {
            Repeater {
                model: control.settings || []
                ColumnLayout {
                    id: settingRoot
                    required property var modelData
                    property var settingControl: Object.assign({}, modelData, { configFilePath: root.control.configFile ? root.control.configFile.path : "", configKey: modelData.key || modelData.id })
                    Layout.fillWidth: true
                    Label {
                        text: modelData.label || modelData.id
                        font.bold: true
                    }
                    Loader {
                        Layout.fillWidth: true
                        sourceComponent: modelData.kind === "dropdown" ? configDropdownComponent : configTextComponent
                    }
                    Component {
                        id: configTextComponent
                        TextField {
                            text: root.stringValue(appController.controlValue(settingRoot.settingControl))
                            placeholderText: modelData.placeholder || ""
                            Layout.fillWidth: true
                            Accessible.name: modelData.label || modelData.id
                            onEditingFinished: appController.updateField(settingRoot.settingControl, text)
                        }
                    }
                    Component {
                        id: configDropdownComponent
                        ComboBox {
                            model: modelData.options || []
                            textRole: "title"
                            valueRole: "id"
                            currentIndex: model.findIndex ? model.findIndex(function(item) { return item.id === appController.controlValue(settingRoot.settingControl) }) : -1
                            Layout.fillWidth: true
                            Accessible.name: modelData.label || modelData.id
                            onActivated: appController.updateField(settingRoot.settingControl, currentValue)
                        }
                    }
                }
            }
        }
    }

    Component {
        id: libraryListComponent
        LibraryList { control: root.control; sectionValues: root.sectionValues; Layout.fillWidth: true }
    }
}
