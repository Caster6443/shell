pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Wayland
import Quickshell.Hyprland
import Qt5Compat.GraphicalEffects
import qs.components
import qs.services

Item {
    id: root

    property int wsId: 1

    readonly property var winData: {
        const arr = [];
        const monW = Hyprland.focusedMonitor?.width || 1920;
        const monH = Hyprland.focusedMonitor?.height || 1080;
        const monX = Hyprland.focusedMonitor?.x || 0;
        const monY = Hyprland.focusedMonitor?.y || 0;
        const sc = Math.min((root.implicitWidth - 20) / monW, (root.implicitHeight - 20) / monH);
        for (let tl of Hyprland.toplevels.values) {
            if (tl.workspace?.id !== root.wsId) continue;
            const ipc = tl.lastIpcObject;
            // find matching ToplevelManager entry
            let capture = null;
            const addr = (tl.address ?? "").toLowerCase();
            for (let t of ToplevelManager.toplevels.values) {
                if ((t.HyprlandToplevel?.address ?? "").toLowerCase() === addr) {
                    capture = t;
                    break;
                }
            }
            arr.push({
                x: ((ipc?.at?.[0] ?? 0) - monX) * sc,
                y: ((ipc?.at?.[1] ?? 0) - monY) * sc,
                w: Math.max(16, (ipc?.size?.[0] ?? monW / 2) * sc),
                h: Math.max(12, (ipc?.size?.[1] ?? monH / 2) * sc),
                title: tl.title ?? "",
                capture: capture
            });
        }
        return arr;
    }

    implicitWidth: 260
    implicitHeight: 160

    Rectangle {
        anchors.fill: parent
        radius: 12
        color: Colours.palette.m3surfaceContainer
        border.color: Colours.palette.m3outlineVariant
        border.width: 1
        clip: true

        Text {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.margins: 8
            text: root.wsId
            color: Colours.palette.m3onSurfaceVariant
            font.pixelSize: 11
            font.bold: true
            z: 2
        }

        Item {
            id: canvas
            anchors.fill: parent
            anchors.margins: 10

            Repeater {
                model: root.winData

                delegate: Rectangle {
                    required property var modelData
                    x: modelData.x
                    y: modelData.y
                    width: modelData.w
                    height: modelData.h
                    radius: 3
                    color: Colours.palette.m3surfaceContainerHigh
                    border.color: Colours.palette.m3outline
                    border.width: 0.5
                    clip: true

                    ScreencopyView {
                        id: scv
                        anchors.fill: parent
                        live: true
                        captureSource: modelData.capture
                        visible: modelData.capture !== null

                        layer.enabled: true
                        layer.effect: OpacityMask {
                            maskSource: Rectangle {
                                width: scv.width
                                height: scv.height
                                radius: 3
                            }
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        width: parent.width - 4
                        text: modelData.title
                        color: Colours.palette.m3onSurfaceVariant
                        font.pixelSize: 8
                        elide: Text.ElideRight
                        horizontalAlignment: Text.AlignHCenter
                        visible: !scv.visible || parent.width < 40
                    }
                }
            }
        }
    }
}
