pragma Singleton
import QtQuick
import qs.services

// Wallpaper-derived tonal surfaces shared by the two standalone panels.
QtObject {
    id: root
    readonly property var palette: Colours.palette
    function blend(base: color, tint: color, amount: real): color {
        return Qt.rgba(base.r * (1 - amount) + tint.r * amount,
                       base.g * (1 - amount) + tint.g * amount,
                       base.b * (1 - amount) + tint.b * amount, 1);
    }
    readonly property color background: blend(palette.m3surfaceContainerHigh, palette.m3primary, Colours.light ? 0.025 : 0.10)
    readonly property color content: blend(palette.m3surfaceContainerLow, palette.m3primary, Colours.light ? 0.015 : 0.045)
    readonly property color selection: Colours.light ? palette.m3primary : palette.m3primaryContainer
    readonly property color selectedText: Colours.light ? palette.m3onPrimary : palette.m3onPrimaryContainer
    readonly property color outline: Qt.alpha(palette.m3onSurface, Colours.light ? 0.12 : 0.10)
}
