pragma Singleton
import QtQuick
import qs.services

// Shared Material surfaces for Console and the standalone clipboard.
QtObject {
    readonly property color background: Colours.palette.m3surface
    readonly property color content: Colours.palette.m3surfaceContainerLow
    readonly property color field: Colours.palette.m3surfaceContainerHighest
    readonly property color selection: Colours.palette.m3secondaryContainer
    readonly property color selectedText: Colours.palette.m3onSecondaryContainer
    readonly property color accent: Colours.palette.m3primary
    readonly property color onAccent: Colours.palette.m3onPrimary
    readonly property color outline: Qt.alpha(Colours.palette.m3outlineVariant, 0.55)
    readonly property color chipOutline: Colours.palette.m3outlineVariant
}
