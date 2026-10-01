import QtQuick
import qs.lockcosmos

Text {
    property bool filled: false
    property int weight: 500
    font.family: LockTheme.icons
    font.variableAxes: ({ "FILL": filled ? 1 : 0, "wght": weight })
    color: LockTheme.ink
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
}
