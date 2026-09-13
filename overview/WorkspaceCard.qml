pragma ComponentBehavior: Bound

import QtQuick
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
	// 入场动画进度（0 = 还没出现，1 = 完全出现）：「+」新增的插槽从 0 撑开 + 淡入，普通卡片恒为 1
	property real appearProgress: 1

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

	readonly property real scaleRatio: workspaceW / contentMaxWidth

	width: workspaceW
	height: workspaceH
	opacity: Math.min(1, appearProgress * 1.6)
	z: hasActiveDrag ? 100 : 0

	Rectangle {
		anchors.fill: parent
		radius: 18
		clip: true

		color: {
			if (isSpecial)
				return Qt.darker(M3Palette.m3surfaceContainer, 1.4);
			return Hyprland.focusedMonitor?.activeWorkspace?.id === wsId ? M3Palette.m3surfaceContainer : M3Palette.m3surface;
		}
		border.width: 1
		border.color: isSpecial ? Qt.alpha(M3Palette.m3onSurface, 0.12) : (Hyprland.focusedMonitor?.activeWorkspace?.id === wsId ? M3Palette.m3primary : M3Palette.m3outlineVariant)

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
					HyprDispatch.call(`togglespecialworkspace ${specialDispatchName}`, `hl.dsp.workspace.toggle_special("${specialDispatchName}")`);
				else
					HyprDispatch.call(`workspace ${wsId}`, `hl.dsp.focus({ workspace = "${wsId}" })`);
				overviewRoot.closeOverview();
			}
		}

		Text {
			anchors.top: parent.top
			anchors.left: parent.left
			anchors.margins: 8
			text: cardLabel
			elide: Text.ElideRight
			width: parent.width - 16
			color: isSpecial ? M3Palette.m3onTertiaryContainer : M3Palette.m3onSurface
			font.pixelSize: 13
			font.bold: true
			z: 10
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
