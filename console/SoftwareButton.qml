pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import qs.overview

Button {
    id: root
    property bool accent: false
    property bool danger: false
    implicitHeight: 36
    hoverEnabled: true
    leftPadding: 16
    rightPadding: 16
    contentItem: ConsoleText {
        text: root.text
        textRole: "caption"
        strong: root.accent
        color: root.enabled ? (root.accent ? ConsoleMaterialStyle.onAccent : ConsoleMaterialStyle.selectedText) : Qt.alpha(M3Palette.m3onSurface, 0.35)
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }
    background: RaisedButtonSurface {
        pressed: root.down
        hovered: root.hovered
        interactive: root.enabled
        radius: height / 2
        color: Qt.tint(root.accent ? ConsoleMaterialStyle.accent : ConsoleMaterialStyle.selection, Qt.alpha(root.accent ? ConsoleMaterialStyle.onAccent : ConsoleMaterialStyle.selectedText, root.down ? 0.12 : root.hovered ? 0.08 : 0))
        Behavior on color { ColorAnimation { duration: 140 } }
        border.width: root.danger ? 1 : 0
        border.color: Qt.alpha(M3Palette.m3onSurface, 0.3)
        opacity: root.enabled ? 1 : 0.5
    }
}
