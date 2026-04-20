pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Qt5Compat.GraphicalEffects
import qs.services
import qs.components

Rectangle {
    id: windowItem

    required property string m_address
    required property int m_wsId
    required property real m_atX
    required property real m_atY
    required property real m_sizeW
    required property real m_sizeH
    required property real m_linearX
    required property bool m_floating
    required property string m_title

    required property var overviewRoot
    required property Item orphanLayer

    property string windowAddress: m_address
    property int currentWsId: m_wsId

    // hover magnification + push effect
    readonly property bool isHovered: overviewRoot.hoveredWindowAddress === m_address

    readonly property int wsWindowCount: {
        let n = 0;
        for (let i = 0; i < overviewRoot.windowModelRef.count; ++i)
            if (overviewRoot.windowModelRef.get(i).m_wsId === m_wsId)
                n++;
        return n;
    }

    readonly property real hoverScale: wsWindowCount <= 1 ? 1.06 : 1.18

    readonly property real pushOffset: {
        const hAddr = overviewRoot.hoveredWindowAddress;
        if (!hAddr || hAddr === m_address)
            return 0;
        for (let i = 0; i < overviewRoot.windowModelRef.count; ++i) {
            const it = overviewRoot.windowModelRef.get(i);
            if (it.m_address !== hAddr || it.m_wsId !== m_wsId)
                continue;
            const hovX = it.m_linearX * scaleRatio;
            const myX = m_linearX * scaleRatio;
            const dist = myX - hovX;
            if (Math.abs(dist) > width * 2)
                return 0;
            const push = 28 * Math.exp(-Math.abs(dist) / (width * 0.8));
            return dist > 0 ? push : -push;
        }
        return 0;
    }

    parent: (overviewRoot.wsLayers && overviewRoot.wsLayers[m_wsId]) ? overviewRoot.wsLayers[m_wsId] : (overviewRoot.anyWorkspaceLayer() ? overviewRoot.anyWorkspaceLayer() : orphanLayer)
    visible: parent !== orphanLayer
    z: isHovered ? 30 : 20
    scale: isHovered ? hoverScale : 1.0
    opacity: mouseArea.drag.active ? 0.9 : 1.0

    Behavior on x {
        enabled: !mouseArea.drag.active
        Anim {
            type: Anim.DefaultSpatial  // <- 接入全局阻尼动画
        }
    }
    Behavior on y {
        enabled: !mouseArea.drag.active
        Anim {
            type: Anim.DefaultSpatial  // <- 接入全局阻尼动画
        }
    }

    Behavior on width {
        NumberAnimation {
            duration: 160
            easing.type: Easing.OutCubic
        }
    }
    Behavior on height {
        NumberAnimation {
            duration: 160
            easing.type: Easing.OutCubic
        }
    }
    Behavior on scale {
        NumberAnimation {
            duration: 200
            easing.type: Easing.OutBack
            easing.overshoot: 0.5
        }
    }
    Behavior on opacity {
        NumberAnimation {
            duration: 120
            easing.type: Easing.OutCubic
        }
    }

    readonly property real scaleRatio: {
        const layer = parent;
        const container = layer ? layer.parent : null;
        return container && container.scaleRatio !== undefined ? container.scaleRatio : 1.0;
    }

    property real targetX: m_linearX * scaleRatio + pushOffset

    property real targetY: {
        const ph = parent ? parent.height : 260;
        const h = (m_sizeH > 0 ? m_sizeH : (Hyprland.focusedMonitor?.height || 1080)) * scaleRatio;
        return Math.max(0, (ph - h) / 2);
    }

    readonly property real clampedX: {
        if (isNaN(targetX))
            return 0;
        const pw = parent ? parent.width : 0;
        if (!pw || isNaN(width))
            return targetX;
        // clamp center point, not edge — so scaled window stays visually within card
        const half = width / 2;
        return Math.max(half, Math.min(targetX + half, pw - half)) - half;
    }
    readonly property real clampedY: {
        const ph = parent ? parent.height : 0;
        if (!ph || isNaN(targetY) || isNaN(height))
            return targetY;
        return Math.max(0, Math.min(targetY, ph - height));
    }

    Binding on x {
        value: windowItem.clampedX
        when: !mouseArea.drag.active
    }
    Binding on y {
        value: windowItem.clampedY
        when: !mouseArea.drag.active
    }

    width: (m_sizeW > 0 ? m_sizeW : (Hyprland.focusedMonitor?.width || 1920) / 2) * scaleRatio
    height: (m_sizeH > 0 ? m_sizeH : (Hyprland.focusedMonitor?.height || 1080)) * scaleRatio

    radius: 6
    color: Colours.palette.m3surfaceContainerHigh
    border.color: mouseArea.containsMouse ? Colours.palette.m3tertiary : Colours.palette.m3primaryContainer
    border.width: 1

    Rectangle {
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: titleText.implicitHeight + 6
        radius: 5
        color: Qt.alpha(Colours.palette.m3surface, 0.85)
        visible: mouseArea.containsMouse && m_title !== ""
        z: 10

        Text {
            id: titleText
            anchors.centerIn: parent
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 6
            text: m_title
            color: Colours.palette.m3onSurface
            font.pixelSize: 11
            elide: Text.ElideRight
        }
    }

    ScreencopyView {
        id: screenView
        anchors.fill: parent
        anchors.margins: 1
        live: overviewRoot.visibilities.overview

        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: Rectangle {
                width: screenView.width
                height: screenView.height
                radius: 5
            }
        }

        captureSource: {
            const addr = windowAddress.toLowerCase();
            for (let tl of ToplevelManager.toplevels.values) {
                if (`0x${tl.HyprlandToplevel?.address}`.toLowerCase() === addr)
                    return tl;
            }
            return null;
        }
    }

    Drag.keys: ["window"]
    Drag.active: mouseArea.drag.active
    Drag.source: windowItem
    Drag.hotSpot.x: width / 2
    Drag.hotSpot.y: height / 2

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        drag.target: windowItem
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton

        onEntered: overviewRoot.hoveredWindowAddress = m_address
        onExited: overviewRoot.hoveredWindowAddress = ""

        onPressed: mouse => {
            if (mouse.button === Qt.MiddleButton) {
                mouse.accepted = true;
                Hyprland.dispatch(`closewindow address:${windowAddress}`);
                overviewRoot.restartSyncTimer();
                return;
            }
            windowItem.z = 100;
            const layer = windowItem.parent;
            const container = layer ? layer.parent : null;
            if (container)
                container.hasActiveDrag = true;
        }

        onReleased: mouse => {
            if (mouse.button === Qt.MiddleButton)
                return;
            windowItem.z = 1;
            const layer = windowItem.parent;
            const container = layer ? layer.parent : null;
            if (container)
                container.hasActiveDrag = false;

            const dropResult = windowItem.Drag.drop();
            // if drop was accepted by a WorkspaceCard (cross-workspace move), skip reorder
            if (dropResult === Qt.MoveAction)
                return;

            const activeWs = Hyprland.focusedMonitor?.activeWorkspace?.id ?? -999;
            const monX = Hyprland.focusedMonitor?.x || 0;
            const monY = Hyprland.focusedMonitor?.y || 0;
            const realX = Math.round(windowItem.x / scaleRatio + monX);
            const realY = Math.round(windowItem.y / scaleRatio + monY);

            if (currentWsId === activeWs) {
                if (m_floating) {
                    Hyprland.dispatch(`movewindowpixel exact ${realX} ${realY},address:${windowAddress}`);
                } else {
                    const beforeOrder = overviewRoot.wsAddressesSortedByX(currentWsId);
                    const curIndex = beforeOrder.indexOf(windowAddress);
                    const targetIndex = overviewRoot.targetIndexForDrop(currentWsId, windowAddress, realX);
                    const delta = (curIndex !== -1) ? (targetIndex - curIndex) : 0;
                    if (delta !== 0) {
                        const dir = delta > 0 ? "r" : "l";
                        const cmds = [`dispatch focuswindow address:${windowAddress}`];
                        for (let step = 0; step < Math.abs(delta); ++step)
                            cmds.push(`dispatch layoutmsg swapcol ${dir}`);
                        overviewRoot.dispatchBatch(cmds);
                    }
                }
                overviewRoot.restartSyncTimer();
            }
        }

        onClicked: mouse => {
            if (mouse.button !== Qt.LeftButton)
                return;
            Hyprland.dispatch(`focuswindow address:${windowAddress}`);
            //overviewRoot.visibilities.overview = false;
            overviewRoot.closeOverview();
        }
    }
}
