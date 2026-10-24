pragma Singleton
import QtQuick
import qs.services
import qs.overview

// Stable neutral surfaces; wallpaper colours are reserved for selection and focus.
// Shared by Console and the standalone clipboard; global shell palette is unchanged.
QtObject {
    readonly property color background: Colours.light ? "#f2f3f5" : "#222428"
    readonly property color content: Colours.light ? "#fafafa" : "#2b2d31"
    readonly property color field: Colours.light ? "#e7e9ed" : "#36383d"
    readonly property color selection: Colours.palette.m3secondaryContainer
    readonly property color selectedText: Colours.palette.m3onSecondaryContainer
    readonly property color outline: Colours.light ? "#24000000" : "#28ffffff"
    readonly property color chipOutline: Colours.light ? "#35000000" : "#35ffffff"
}
