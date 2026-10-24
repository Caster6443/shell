pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.services

Column {
    id: root
    required property var popouts
    function closeIfEmpty(): void {
        if (Devices.devices.length === 0 && root.popouts.currentName === "removable") {
            root.popouts.hasCurrent = false;
            root.popouts.currentName = "";
        }
    }
    Component.onCompleted: closeIfEmpty()
    Connections {
        target: Devices
        function onDevicesChanged(): void { root.closeIfEmpty(); }
    }
    Connections {
        target: root.popouts
        function onHasCurrentChanged(): void { root.closeIfEmpty(); }
        function onCurrentNameChanged(): void { root.closeIfEmpty(); }
    }
    width: 280
    spacing: 4
    Repeater {
        model: Devices.devices
        delegate: RowLayout {
            id: row
            required property var modelData
            width: root.width
            height: 44
            spacing: 10
            StyledText {
                Layout.fillWidth: true
                text: row.modelData.name
                elide: Text.ElideRight
                font: Tokens.font.body.medium
                color: Colours.palette.m3onSurface
            }
            StyledText {
                text: Devices.sizeText(row.modelData.size)
                font: Tokens.font.body.small
                color: Colours.palette.m3onSurfaceVariant
            }
            Rectangle {
                implicitWidth: 34
                implicitHeight: 34
                radius: 17
                color: Qt.alpha(Colours.palette.m3primary, 0.10)
                MaterialIcon {
                    anchors.centerIn: parent
                    text: Devices.busyPath === row.modelData.path ? "hourglass_top" : "eject"
                    fontStyle: Tokens.font.icon.small
                    color: Colours.palette.m3primary
                }
                StateLayer {
                    id: ejectButton
                    radius: parent.radius
                    disabled: Devices.busy
                    onClicked: Devices.remove(row.modelData)
                    ToolTip.visible: containsMouse
                    ToolTip.delay: 600
                    ToolTip.text: Devices.busyPath === row.modelData.path ? "正在弹出…" : "安全弹出"
                }
            }
        }
    }
    StyledText {
        width: root.width
        visible: !!Devices.error
        text: Devices.error
        wrapMode: Text.Wrap
        font: Tokens.font.body.small
        color: Colours.palette.m3error
    }
}
