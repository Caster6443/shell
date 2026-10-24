import QtQuick
import QtQuick.Effects
import qs.services

// Flat small-button surface with a restrained hover cue; input stays with its owner.
Rectangle {
    id: surface
    property bool pressed: false
    property bool hovered: false
    property bool interactive: true
    radius: 8
    RectangularShadow {
        anchors.fill: parent
        z: -1
        radius: surface.radius
        blur: 5
        offset.y: 1
        color: Qt.rgba(0, 0, 0, Colours.light ? 0.10 : 0.20)
        opacity: surface.interactive && surface.hovered && !surface.pressed ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 120 } }
    }
}
