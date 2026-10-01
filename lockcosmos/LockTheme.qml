pragma Singleton
import QtQuick
import qs.services as CaelestiaServices

QtObject {
    readonly property color ink: "#f4f2ee"
    readonly property color inkDim: "#b9b8c4"
    readonly property color inkFaint: "#777887"
    readonly property color accent: CaelestiaServices.Colours.palette.m3primary
    readonly property color accentSoft: CaelestiaServices.Colours.palette.m3primaryContainer
    readonly property color gold: CaelestiaServices.Colours.palette.m3tertiary
    readonly property color danger: "#ff786f"
    readonly property color panel: "#20212b"
    readonly property color panelHi: "#30313d"
    readonly property color line: "#ffffff"
    readonly property string display: "Adwaita Sans"
    readonly property string mono: "JetBrains Mono"
    readonly property string icons: "Material Symbols Rounded"
    readonly property color base: "#11121a"
    function alpha(c, a) { return Qt.alpha(c, a); }
    function seg(v, from, to) { return Math.max(0, Math.min(1, (v - from) / (to - from))); }
}
