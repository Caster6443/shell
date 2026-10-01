import QtQuick
import qs.lockcosmos

Item {
    required property var ctx
    property bool shown: true
    property bool still: false
    property real minScale: 0.7
    property url shot
    anchors.fill: parent
    CosmosLockScreen {
        anchors.fill: parent
        lock: ctx.lock
        pam: ctx.pam
    }
}
