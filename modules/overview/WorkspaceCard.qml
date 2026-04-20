pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.services

Item {
    id: workspaceContainer

    required property int index
    required property var overviewRoot
    required property ListModel windowModel
    property bool isSpecial: false
    property int specialWsId: -1

    property int wsId: isSpecial ? specialWsId : index + 1
    property bool hasActiveDrag: false

    readonly property real workspaceW: 400
    readonly property real workspaceH: 260

    property real contentMaxWidth: {
        let monW = Hyprland.focusedMonitor?.width || 1920;
        let totalW = 0;
        let count = 0;
        for (let i = 0; i < windowModel.count; ++i) {
            const it = windowModel.get(i);
            if (it.m_wsId !== wsId)
                continue;
            const w = it.m_sizeW;
            totalW += (w > 0 ? w : monW / 2);
            count++;
        }
        const gap = 40;
        if (count > 0)
            totalW += (count - 1) * gap;
        totalW += gap * 2;
        return Math.max(monW, totalW);
    }

    readonly property real scaleRatio: workspaceW / contentMaxWidth

    width: workspaceW
    height: workspaceH
    z: hasActiveDrag ? 100 : 0

    Rectangle {
        anchors.fill: parent
        radius: 18
        clip: true

        color: {
            if (isSpecial)
                return Qt.darker(Colours.palette.m3surfaceContainer, 1.4);
            return Hyprland.focusedMonitor?.activeWorkspace?.id === wsId ? Colours.palette.m3surfaceContainer : Colours.palette.m3surface;
        }
        border.width: 1
        border.color: isSpecial ? Qt.alpha(Colours.palette.m3onSurface, 0.12) : (Hyprland.focusedMonitor?.activeWorkspace?.id === wsId ? Colours.palette.m3primary : Colours.palette.m3outlineVariant)

        Image {
            anchors.fill: parent
            source: isSpecial ? "" : overviewRoot.currentWallpaperPath
            fillMode: Image.PreserveAspectCrop
            opacity: 0.6
        }

        MouseArea {
            anchors.fill: parent
            onClicked: {
                if (isSpecial)
                    Hyprland.dispatch(`togglespecialworkspace ${workspaceContainer.wsId < 0 ? "special" : ""}`);
                else
                    Hyprland.dispatch(`workspace ${wsId}`);
                //overviewRoot.visibilities.overview = false;
                overviewRoot.closeOverview();
            }
        }

        Text {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.margins: 8
            text: isSpecial ? "S" : wsId
            color: isSpecial ? Colours.palette.m3onTertiaryContainer : Colours.palette.m3onSurface
            font.pixelSize: 13
            font.bold: true
            z: 10
        }

        DropArea {
            anchors.fill: parent
            keys: ["window"]
            onDropped: drop => {
                if (drop.source && drop.source.windowAddress) {
                    if (drop.source.currentWsId !== wsId) {
                        if (isSpecial)
                            Hyprland.dispatch(`movetoworkspacesilent special,address:${drop.source.windowAddress}`);
                        else
                            Hyprland.dispatch(`movetoworkspacesilent ${wsId},address:${drop.source.windowAddress}`);
                        drop.action = Qt.MoveAction;
                    } else {
                        drop.action = Qt.CopyAction;
                    }
                    drop.accepted = true;
                    overviewRoot.restartSyncTimer();
                }
            }
        }
    }

    Item {
        id: windowLayer
        anchors.fill: parent
        z: 5
        Component.onCompleted: overviewRoot.registerWorkspace(wsId, windowLayer)
    }
}
