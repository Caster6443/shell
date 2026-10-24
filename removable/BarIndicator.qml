import QtQuick
import Caelestia.Config
import qs.components
import qs.services

Item {
    implicitWidth: Tokens.sizes.bar.innerWidth
    implicitHeight: 32
    MaterialIcon {
        anchors.centerIn: parent
        text: Devices.busy ? "hourglass_top" : "usb"
        color: Colours.palette.m3primary
        fontStyle: Tokens.font.icon.medium
    }
}
