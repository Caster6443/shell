pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Caelestia.Config
import Caelestia.Multimedia
import qs.services
import Quickshell
import Quickshell.Hyprland
import qs.overview

Item {
	id: workspaceContainer

	required property int index
	required property var overviewRoot
	required property ListModel windowModel
	property bool isSpecial: false
	property int specialWsId: -1
	// 特殊工作区的完整名字（"special:slot1"）；空插槽在 Hyprland 里还没有 id，卡片一律按名字匹配窗口
	property string specialWsName: ""
	property real cardW: 400
	property real cardH: 260
	property bool filterActive: false
	property var launchOnWorkspace: null

	property int wsId: isSpecial ? specialWsId : index + 1
	// 预览登记键（WindowPreview 按同一规则找卡片）：普通工作区用 id，特殊工作区用名字
	readonly property string layerKey: isSpecial ? specialWsName : String(wsId)
	// dispatch 里用的特殊工作区名：去掉 "special:" 前缀（与 caelestia CLI `toggle specialws` 一致）
	readonly property string specialDispatchName: specialWsName.startsWith("special:") ? specialWsName.slice(8) : (specialWsName || "special")
	readonly property string cardLabel: isSpecial ? (specialDispatchName === "special" ? "S" : specialDispatchName) : String(wsId)
	property bool hasActiveDrag: false
	// 新增特殊工作区插槽的入场状态
	property real appearProgress: 1
	property bool isEntering: false
	property bool animatePosition: false

	readonly property real workspaceW: cardW
	readonly property real workspaceH: cardH

	function rowMatches(row): bool {
		return isSpecial ? row.m_wsName === specialWsName : row.m_wsId === wsId;
	}

	readonly property int matchingCount: {
		let n = 0;
		for (let i = 0; i < windowModel.count; ++i) {
			if (rowMatches(windowModel.get(i)))
				n++;
		}
		return n;
	}

	visible: !(filterActive && matchingCount === 0)

	property real contentMaxWidth: {
		let monW = Hyprland.focusedMonitor?.width || 1920;
		let totalW = 0;
		let count = 0;
		for (let i = 0; i < windowModel.count; ++i) {
			const it = windowModel.get(i);
			if (!rowMatches(it))
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

	// Fit the actual window group into the area below the workspace label.
	readonly property var spatialBounds: {
		let left = Infinity, top = Infinity, right = -Infinity, bottom = -Infinity;
		for (let i = 0; i < windowModel.count; ++i) {
			const row = windowModel.get(i);
			if (!rowMatches(row)) continue;
			const w = row.m_sizeW > 0 ? row.m_sizeW : (Hyprland.focusedMonitor?.width || 1920) / 2;
			const h = row.m_sizeH > 0 ? row.m_sizeH : (Hyprland.focusedMonitor?.height || 1080);
			left = Math.min(left, row.m_atX); top = Math.min(top, row.m_atY);
			right = Math.max(right, row.m_atX + w);
			bottom = Math.max(bottom, row.m_atY + h);
		}
		return Number.isFinite(left) ? { x: left, y: top, width: right - left, height: bottom - top }
			: { x: 0, y: 0, width: 1, height: 1 };
	}
    readonly property real contentTop: 12
    readonly property var linearLayout: {
        const rows = [];
        const monW = Hyprland.focusedMonitor?.width || 1920;
        const monH = Hyprland.focusedMonitor?.height || 1080;
        for (let i = 0; i < windowModel.count; ++i) {
            const row = windowModel.get(i);
            if (!rowMatches(row)) continue;
            rows.push({address: row.m_address || String(i), x: row.m_atX,
                       w: row.m_sizeW > 0 ? row.m_sizeW : monW / 2,
                       h: row.m_sizeH > 0 ? row.m_sizeH : monH});
        }
        rows.sort((a, b) => a.x - b.x || a.address.localeCompare(b.address));
        if (!rows.length) return {scale: 1, slots: {}};
        const reserve = rows.length === 1 ? 1.08 : 1.20;
        const halfExtra = (reserve - 1) / 2;
        const gap = 4;
        const sumW = rows.reduce((total, row) => total + row.w, 0);
        const maxH = Math.max(...rows.map(row => row.h));
        const first = rows[0].w, last = rows[rows.length - 1].w;
        // Only one preview is enlarged at a time: reserve the larger half-growth
        // at each seam, rather than adding both neighbours' hover envelopes.
        let seamW = 0;
        for (let i = 0; i + 1 < rows.length; ++i)
            seamW += halfExtra * Math.max(rows[i].w, rows[i + 1].w);
        const visibleW = sumW + seamW;
        const fitW = visibleW + 2 * halfExtra * Math.max(first, last);
        const scale = Math.max(0.0001, Math.min(
            Math.max(1, workspaceW - 24 - gap * (rows.length - 1)) / fitW,
            Math.max(1, workspaceH - contentTop - 12) / (maxH * reserve)));
        const groupW = visibleW * scale + gap * (rows.length - 1);
        let x = (workspaceW - groupW) / 2;
        const slots = {};
        for (let i = 0; i < rows.length; ++i) {
            const row = rows[i];
            slots[row.address] = {x: x, y: contentTop + (workspaceH - contentTop - 12 - row.h * scale) / 2};
            if (i + 1 < rows.length) x += row.w * scale + gap + halfExtra * Math.max(row.w, rows[i + 1].w) * scale;
        }
        return {scale: scale, slots: slots};
    }
    readonly property real singleWindowRatio: linearLayout.scale

	readonly property real scaleRatio: overviewRoot.spatialWindows
		? Math.min(Math.max(1, workspaceW - 24) / spatialBounds.width, Math.max(1, workspaceH - contentTop - 12) / spatialBounds.height) / (matchingCount <= 1 ? 1.08 : 1.20)
		: singleWindowRatio
	readonly property real spatialOffsetX: (workspaceW - spatialBounds.width * scaleRatio) / 2
	readonly property real spatialOffsetY: contentTop + (Math.max(1, workspaceH - contentTop - 12) - spatialBounds.height * scaleRatio) / 2

	width: workspaceW
	height: workspaceH
	opacity: appearProgress
	z: hasActiveDrag ? 100 : (isEntering ? 5 : 0)

	Behavior on y {
		enabled: animatePosition
		NumberAnimation {
			duration: 320
			easing.type: Easing.OutCubic
		}
	}

	Rectangle {
		id: cardFrame
		anchors.fill: parent
		radius: 14
		clip: true

        readonly property bool current: !isSpecial && Hyprland.focusedMonitor?.activeWorkspace?.id === wsId
        color: Colours.palette.m3surfaceContainer
        border.width: current ? 2 : 1
        border.color: current ? M3Palette.m3primary : Qt.alpha(M3Palette.m3onSurface, 0.25)
        Visual {
            id: wallpaper
            x: 6; y: 6
            width: parent.width - 12
            height: parent.height - 12
            source: isSpecial ? "" : overviewRoot.currentWallpaperPath
            // Decode a poster once; do not play one video per workspace card.
            playing: false
            animate: false
            fillMode: Image.PreserveAspectCrop
            opacity: workspaceContainer.matchingCount > 0 ? 0.6 : 1
            layer.enabled: true
            layer.effect: MultiEffect { maskEnabled: true; maskSource: wallpaperMask; maskThresholdMin: 0.5; maskSpreadAtMin: 1 }
        }
        Rectangle {
            id: wallpaperMask
            width: wallpaper.width; height: wallpaper.height
            radius: 9
            visible: false
            layer.enabled: true
            color: "white"
        }

		MouseArea {
			anchors.fill: parent
			onClicked: {
				if (isSpecial)
					HyprDispatch.call(`togglespecialworkspace ${specialDispatchName}`, `hl.dsp.workspace.toggle_special("${specialDispatchName}")`);
				else
					HyprDispatch.call(`workspace ${wsId}`, `hl.dsp.focus({ workspace = "${wsId}" })`);
				overviewRoot.closeOverview();
			}
		}


		DropArea {
			anchors.fill: parent
			keys: ["window", "app"]
			onDropped: drop => {
				if (drop.source && drop.source.appEntry) {
					if (workspaceContainer.launchOnWorkspace)
						// 工作区选择符：普通工作区是 "3" 这种 id 字符串，特殊工作区是 "special:slot1" 全名
						workspaceContainer.launchOnWorkspace(drop.source.appEntry, isSpecial ? specialWsName : String(wsId), isSpecial);
					drop.accepted = true;
					drop.action = Qt.MoveAction;
				} else if (drop.source && drop.source.windowAddress) {
					if (drop.source.currentWsId !== wsId) {
						const addr = HyprDispatch.addressArg(drop.source.windowAddress);
						if (isSpecial) {
							HyprDispatch.call(
								`movetoworkspacesilent ${specialWsName},address:${drop.source.windowAddress}`,
								`hl.dsp.window.move({ window = "address:${addr}", workspace = "${specialWsName}", follow = false })`
							);
						} else {
							HyprDispatch.call(
								`movetoworkspacesilent ${wsId},address:${drop.source.windowAddress}`,
								`hl.dsp.window.move({ window = "address:${addr}", workspace = "${wsId}", follow = false })`
							);
						}
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
        anchors.fill: parent
        z: 40
        // Overlay identity without reserving a separate header row.
        Text {
            x: 12; y: 12
            text: cardLabel
            color: cardFrame.current ? M3Palette.m3primary : M3Palette.m3onSurface
            font: Tokens.font.label.builders.medium.weight(Font.DemiBold).build()
            renderType: Text.NativeRendering
        }

    }

	Item {
		id: windowLayer
		anchors.fill: parent
		z: 5
		Component.onCompleted: {
			overviewRoot.registerWorkspace(layerKey, windowLayer);
			// 特殊卡片同时按 id 登记一份别名：名字角色万一拿不到时，缩略图还能靠 id 找到卡片
			if (isSpecial && wsId !== 0)
				overviewRoot.registerWorkspace(String(wsId), windowLayer);
		}
	}
}
