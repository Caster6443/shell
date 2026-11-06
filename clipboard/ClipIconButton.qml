import QtQuick
import QtQuick.Controls
import qs.components
import qs.services
import qs.console
ToolButton {
    id: root
    property string symbol
    property string label
    property bool destructive: false
    property bool emphasized: false
    implicitWidth: 34
    implicitHeight: 34
    opacity: enabled ? 1 : 0.35
    Accessible.name: label
    contentItem: MaterialIcon {
        text: root.symbol
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        color: root.destructive ? Colours.palette.m3error : root.emphasized ? Colours.palette.m3primary : Colours.palette.m3onSurface
    }
    background: RaisedButtonSurface {
        pressed: root.down
        hovered: root.hovered
        interactive: root.enabled
        radius: 8
        color: Qt.tint(ConsoleMaterialStyle.content, Qt.alpha(root.destructive ? Colours.palette.m3error : Colours.palette.m3onSurface, root.down ? 0.16 : root.hovered ? 0.09 : 0.035))
        border.width: 1
        border.color: Qt.alpha(Colours.palette.m3onSurface, root.activeFocus ? 0.5 : 0.12)
    }
    ToolTip.visible: hovered
    ToolTip.delay: 500
    ToolTip.text: label
}
