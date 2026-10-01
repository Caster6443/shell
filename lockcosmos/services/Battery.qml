pragma Singleton
import QtQuick
import Quickshell.Services.UPower
QtObject {
    readonly property real percentage: UPower.displayDevice.percentage * 100
    readonly property bool charging: !UPower.onBattery
}
