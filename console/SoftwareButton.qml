pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import qs.overview

Button {
    id: root
    property bool accent: false
    property bool danger: false
    implicitHeight: 32
    leftPadding: 12
    rightPadding: 12
    contentItem: ConsoleText {
        text: root.text
        textRole: "caption"
        strong: root.accent
        color: root.enabled ? (root.accent ? ConsoleStyle.selectedText : M3Palette.m3onSurface) : Qt.alpha(M3Palette.m3onSurface, 0.35)
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }
    background: RaisedButtonSurface {
        pressed: root.down
        hovered: root.hovered
        interactive: root.enabled
        radius: 8
        color: root.accent ? ConsoleStyle.selection : Qt.tint(ConsoleStyle.content, Qt.alpha(M3Palette.m3onSurface, root.hovered ? 0.08 : 0.03))
        border.width: root.danger ? 1 : 0
        border.color: Qt.alpha(M3Palette.m3onSurface, 0.3)
        opacity: root.enabled ? 1 : 0.5
    }
}
