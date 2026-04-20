pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "../../services" as Services
import qs.config
import qs.components
import qs.services
import QtQml

Item {
    id: root
    function closeOverview() {
        if (visibilities) {
            visibilities.overview = false;
        }
    }

    property var visibilities: Visibilities.getForActive()

    implicitWidth: mainContainer.implicitWidth
    implicitHeight: mainContainer.implicitHeight

    function handleKey(event) {
        if (event.key === Qt.Key_Escape) {
            visibilities.overview = false;
            event.accepted = true;
        } else if (event.key === Qt.Key_Up || event.key === Qt.Key_Down) {
            const step = flickable.cardHeight + flickable.cardSpacing;
            const delta = event.key === Qt.Key_Up ? -step : step;
            flickable.contentY = Math.max(0, Math.min(flickable.contentY + delta, flickable.contentHeight - flickable.height));
            event.accepted = true;
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            const idx = Math.round(flickable.contentY / (flickable.cardHeight + flickable.cardSpacing));
            Hyprland.dispatch(`workspace ${idx + 1}`);
            visibilities.overview = false;
            event.accepted = true;
        }
    }

    property string currentWallpaperPath: ""
    property var wsLayers: ({})
    property string hoveredWindowAddress: ""
    readonly property var windowModelRef: windowModel
    readonly property var specialWindowModelRef: specialWindowModel

    Services.HyprlandData {
        id: localHyprData
    }

    ListModel {
        id: windowModel
    }

    ListModel {
        id: specialWindowModel
    }

    function syncWindows(rawList) {
        if (!rawList)
            return;

        const normalMap = new Map();
        const specialMap = new Map();

        for (const w of rawList) {
            if (!w || !w.address)
                continue;
            const cls = (w.class || "").toLowerCase();
            const title = (w.title || "");
            if (cls.includes("quickshell") || title.includes("quickshell_pure_overview"))
                continue;
            const wsId = w.workspace?.id ?? 0;
            if (wsId === 0)
                continue;
            if (wsId > 0)
                normalMap.set(w.address, w);
            else
                specialMap.set(w.address, w);
        }

        // sync normal windows
        for (let i = windowModel.count - 1; i >= 0; --i) {
            if (!normalMap.has(windowModel.get(i).m_address))
                windowModel.remove(i);
        }
        const normalIdx = {};
        for (let i = 0; i < windowModel.count; ++i)
            normalIdx[windowModel.get(i).m_address] = i;
        for (const [addr, w] of normalMap) {
            const data = {
                m_address: addr,
                m_wsId: w.workspace?.id ?? 0,
                m_atX: w.at?.[0] ?? 0,
                m_atY: w.at?.[1] ?? 0,
                m_sizeW: w.size?.[0] ?? 0,
                m_sizeH: w.size?.[1] ?? 0,
                m_floating: !!w.floating,
                m_class: w.class ?? "",
                m_title: w.title ?? "",
                m_linearX: 20
            };
            const idx = normalIdx[addr];
            if (idx === undefined) {
                windowModel.append(data);
            } else {
                for (const k in data)
                    if (windowModel.get(idx)[k] !== data[k])
                        windowModel.setProperty(idx, k, data[k]);
            }
        }

        // sync special windows
        for (let i = specialWindowModel.count - 1; i >= 0; --i) {
            if (!specialMap.has(specialWindowModel.get(i).m_address))
                specialWindowModel.remove(i);
        }
        const specialIdx = {};
        for (let i = 0; i < specialWindowModel.count; ++i)
            specialIdx[specialWindowModel.get(i).m_address] = i;
        for (const [addr, w] of specialMap) {
            const data = {
                m_address: addr,
                m_wsId: w.workspace?.id ?? 0,
                m_wsName: w.workspace?.name ?? "",
                m_atX: w.at?.[0] ?? 0,
                m_atY: w.at?.[1] ?? 0,
                m_sizeW: w.size?.[0] ?? 0,
                m_sizeH: w.size?.[1] ?? 0,
                m_floating: !!w.floating,
                m_class: w.class ?? "",
                m_title: w.title ?? "",
                m_linearX: 20
            };
            const idx = specialIdx[addr];
            if (idx === undefined) {
                specialWindowModel.append(data);
            } else {
                for (const k in data)
                    if (specialWindowModel.get(idx)[k] !== data[k])
                        specialWindowModel.setProperty(idx, k, data[k]);
            }
        }

        root.recomputeAllLinearX();
    }

    function registerWorkspace(wsId, layerItem) {
        const nextLayers = Object.assign({}, root.wsLayers);
        nextLayers[wsId] = layerItem;
        root.wsLayers = nextLayers;
    }

    function recomputeLinearXForWs(wsId) {
        const arr = [];
        for (let i = 0; i < windowModel.count; ++i) {
            const it = windowModel.get(i);
            if (it.m_wsId !== wsId)
                continue;
            arr.push({
                idx: i,
                atX: it.m_atX,
                w: it.m_sizeW
            });
        }
        arr.sort((a, b) => a.atX - b.atX);

        const monW = Hyprland.focusedMonitor?.width || 1920;
        const gap = 40;
        let totalW = 0;
        for (let j = 0; j < arr.length; ++j) {
            const w = arr[j].w > 0 ? arr[j].w : monW / 2;
            totalW += w;
        }
        if (arr.length > 0) {
            totalW += (arr.length - 1) * gap;
        }
        let xOffset = (Math.max(monW, totalW + gap * 2) - totalW) / 2;
        for (let j = 0; j < arr.length; ++j) {
            windowModel.setProperty(arr[j].idx, "m_linearX", xOffset);
            const w = arr[j].w > 0 ? arr[j].w : monW / 2;
            xOffset += w + gap;
        }
    }

    Process {
        id: hyprBatch
        running: false
    }

    function wsAddressesSortedByX(wsId) {
        const arr = [];
        for (let i = 0; i < windowModel.count; ++i) {
            const it = windowModel.get(i);
            if (it.m_wsId !== wsId)
                continue;
            arr.push({
                addr: it.m_address,
                atX: it.m_atX
            });
        }
        arr.sort((a, b) => a.atX - b.atX);
        return arr.map(e => e.addr);
    }

    function targetIndexForDrop(wsId, address, dropAtX) {
        const items = [];
        for (let i = 0; i < windowModel.count; ++i) {
            const it = windowModel.get(i);
            if (it.m_wsId !== wsId || it.m_address === address)
                continue;
            const w = it.m_sizeW > 0 ? it.m_sizeW : (Hyprland.focusedMonitor?.width || 1920) / 2;
            items.push({
                center: it.m_atX + w / 2
            });
        }
        items.sort((a, b) => a.center - b.center);
        let idx = 0;
        while (idx < items.length && dropAtX > items[idx].center)
            idx++;
        return idx;
    }

    function dispatchBatch(commands) {
        if (!commands || commands.length === 0)
            return;
        const batch = commands.join("; ");
        if (hyprBatch.running)
            hyprBatch.running = false;
        hyprBatch.command = ["hyprctl", "--batch", batch];
        hyprBatch.running = true;
    }

    function recomputeAllLinearX() {
        const seen = {};
        for (let i = 0; i < windowModel.count; ++i) {
            const wsId = windowModel.get(i).m_wsId;
            if (seen[wsId])
                continue;
            seen[wsId] = true;
            root.recomputeLinearXForWs(wsId);
        }
        for (let i = 0; i < specialWindowModel.count; ++i) {
            const wsId = specialWindowModel.get(i).m_wsId;
            if (seen[wsId])
                continue;
            seen[wsId] = true;
            root.recomputeLinearXForWsInModel(wsId, specialWindowModel);
        }
    }

    function recomputeLinearXForWsInModel(wsId, model) {
        const arr = [];
        for (let i = 0; i < model.count; ++i) {
            const it = model.get(i);
            if (it.m_wsId !== wsId)
                continue;
            arr.push({
                idx: i,
                atX: it.m_atX,
                w: it.m_sizeW
            });
        }
        arr.sort((a, b) => a.atX - b.atX);
        const monW = Hyprland.focusedMonitor?.width || 1920;
        const gap = 40;
        let totalW = 0;
        for (let j = 0; j < arr.length; ++j)
            totalW += arr[j].w > 0 ? arr[j].w : monW / 2;
        if (arr.length > 0)
            totalW += (arr.length - 1) * gap;
        let xOffset = (Math.max(monW, totalW + gap * 2) - totalW) / 2;
        for (let j = 0; j < arr.length; ++j) {
            model.setProperty(arr[j].idx, "m_linearX", xOffset);
            xOffset += (arr[j].w > 0 ? arr[j].w : monW / 2) + gap;
        }
    }

    function anyWorkspaceLayer() {
        if (!root.wsLayers)
            return null;
        for (const k in root.wsLayers) {
            const layer = root.wsLayers[k];
            if (layer)
                return layer;
        }
        return null;
    }

    function restartSyncTimer() {
        syncTimer.restart();
    }

    Connections {
        target: localHyprData
        function onWindowListChanged() {
            root.syncWindows(localHyprData.windowList);
        }
    }

    Timer {
        id: syncTimer
        interval: 150
        onTriggered: localHyprData.updateAll()
    }

    Process {
        id: awwwQueryProc
        command: ["/usr/bin/awww", "query"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                const match = this.text.match(/image:\s*([^\n\r]+)/);
                if (match && match[1])
                    root.currentWallpaperPath = "file://" + match[1].trim();
            }
        }
    }

    Timer {
        id: wallpaperTimer
        interval: 1000
        repeat: true
        running: root.visibilities.overview

        onTriggered: {
            awwwQueryProc.running = false;
            awwwQueryProc.running = true;
        }
    }

    // --- 新增：等待排版和数据彻底稳定后的跳转定时器 ---
    Timer {
        id: jumpSettleTimer
        interval: 80  // 黄金延迟：给特殊工作区加载和 QML 排版留出充足时间
        onTriggered: {
            if (!root.visible)
                return;

            // 禁用动画直接跳，避免闪烁
            scrollAnim.enabled = false;

            const activeId = Hyprland.focusedMonitor?.activeWorkspace?.id ?? 1;
            const step = flickable.cardHeight + flickable.cardSpacing;
            const normalTop = flickable.specialSectionHeight;

            // 精确计算居中 Y 坐标
            const targetY = normalTop + (activeId - 1) * step - (flickable.visibleHeight - flickable.cardHeight) / 2;

            // 限制滚动边界
            const maxScroll = Math.max(0, flickable.contentHeight - flickable.height);
            flickable.contentY = Math.max(normalTop, Math.min(targetY, maxScroll));

            // 下一帧再恢复动画
            Qt.callLater(() => {
                scrollAnim.enabled = true;
            });
        }
    }

    onVisibleChanged: {
        if (visible) {
            localHyprData.updateAll();
            root.syncWindows(localHyprData.windowList);
            awwwQueryProc.running = true;

            // 触发！但不立刻跳，等 80ms 画面彻底排布好再跳
            jumpSettleTimer.restart();
        } else {
            awwwQueryProc.running = false;
            jumpSettleTimer.stop();
        }
    }

    Rectangle {
        id: mainContainer
        color: "#CC11111b"
        radius: 24
        implicitWidth: flickable.contentWidth + 60
        implicitHeight: flickable.visibleHeight + 60
        border.color: "#313244"
        border.width: 2
        anchors {
            top: parent.top
            bottom: parent.bottom
            topMargin: 0
            bottomMargin: 0
        }

        Item {
            id: orphanLayer
            anchors.fill: parent
            //visible: false
            visible: true
            z: -100
        }

        Flickable {
            id: flickable

            readonly property real cardHeight: 260
            readonly property real cardSpacing: 25
            readonly property real visibleCards: 5
            readonly property real visibleHeight: visibleCards * cardHeight + (visibleCards - 1) * cardSpacing
            readonly property real separatorHeight: 40
            readonly property real specialSectionHeight: specialColumn.implicitHeight > 0 ? specialColumn.implicitHeight + cardSpacing * 2 + separatorHeight : 0

            anchors.centerIn: parent
            width: contentWidth
            height: visibleHeight
            contentWidth: mainColumn.implicitWidth
            contentHeight: mainColumn.implicitHeight
            clip: true
            flickableDirection: Flickable.VerticalFlick

            Behavior on contentY {
                id: scrollAnim
                NumberAnimation {
                    duration: 300
                    easing.type: Easing.OutCubic
                }
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.NoButton
                onWheel: wheel => {
                    const step = flickable.cardHeight + flickable.cardSpacing;
                    const newY = flickable.contentY - wheel.angleDelta.y / 120 * step;
                    flickable.contentY = Math.max(0, Math.min(newY, flickable.contentHeight - flickable.height));
                }
            }

            Column {
                id: mainColumn
                spacing: 0

                // special workspaces section — hidden above normal area, revealed by scrolling up
                Item {
                    id: specialBg
                    width: specialColumn.implicitWidth || 400
                    height: specialColumn.implicitHeight + flickable.cardSpacing * 2
                    visible: specialColumn.implicitHeight > 0
                    z: 10

                    // area border — subtle glow to define the region without a solid background
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: -12
                        radius: 20
                        color: "transparent"
                        border.width: 1
                        border.color: Qt.alpha(Colours.palette.m3onSurface, 0.15)
                    }

                    Column {
                        id: specialColumn
                        spacing: flickable.cardSpacing
                        anchors.centerIn: parent
                        z: 10

                        Repeater {
                            model: {
                                const ids = [];
                                const seen = {};
                                for (let i = 0; i < specialWindowModel.count; ++i) {
                                    const id = specialWindowModel.get(i).m_wsId;
                                    if (!seen[id]) {
                                        seen[id] = true;
                                        ids.push(id);
                                    }
                                }
                                return ids;
                            }
                            delegate: WorkspaceCard {
                                required property var modelData
                                overviewRoot: root
                                windowModel: specialWindowModel
                                specialWsId: modelData
                                isSpecial: true
                            }
                        }
                    }
                }

                // gap between special and normal sections
                Item {
                    width: 1
                    height: specialColumn.implicitHeight > 0 ? flickable.separatorHeight : 0
                    visible: specialColumn.implicitHeight > 0
                }

                // normal workspaces
                Column {
                    id: normalColumn
                    spacing: flickable.cardSpacing

                    Repeater {
                        model: 10
                        delegate: WorkspaceCard {
                            overviewRoot: root
                            windowModel: windowModel
                            isSpecial: false
                        }
                    }
                }
            }
        }
    }

    Instantiator {
        model: windowModel
        delegate: WindowPreview {
            overviewRoot: root
            orphanLayer: orphanLayer
        }
    }

    Instantiator {
        model: specialWindowModel
        delegate: WindowPreview {
            overviewRoot: root
            orphanLayer: orphanLayer
        }
    }
}
