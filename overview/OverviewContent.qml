pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.overview

Item {
	id: root

	function closeOverview() {
		OverviewState.active = false;
	}

	implicitWidth: mainContainer.implicitWidth
	implicitHeight: mainContainer.implicitHeight

	function handleKey(event) {
		if (event.key === Qt.Key_Escape) {
			OverviewState.active = false;
			event.accepted = true;
		} else if (event.key === Qt.Key_Up || event.key === Qt.Key_Down) {
			const step = flickable.cardHeight + flickable.cardSpacing;
			const delta = event.key === Qt.Key_Up ? -step : step;
			flickable.contentY = Math.max(0, Math.min(flickable.contentY + delta, flickable.contentHeight - flickable.height));
			event.accepted = true;
		} else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
			const idx = Math.round(flickable.contentY / (flickable.cardHeight + flickable.cardSpacing));
			HyprDispatch.call(`workspace ${idx + 1}`, `hl.dsp.focus({ workspace = "${idx + 1}" })`);
			OverviewState.active = false;
			event.accepted = true;
		}
	}

	property string currentWallpaperPath: ""
	readonly property string stateDir: Quickshell.env("XDG_STATE_HOME") || `${Quickshell.env("HOME")}/.local/state`
	property var wsLayers: ({})
	property string hoveredWindowAddress: ""
	readonly property var windowModelRef: windowModel
	readonly property var specialWindowModelRef: specialWindowModel

	HyprlandData {
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
		for (const cmd of commands)
			HyprDispatch.call(cmd.legacy, cmd.lua);
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

	// ---- Hyprland 窗口捕获静默悬挂自动踢脚 ----
	// toplevel-export 帧只在输出提交时拷贝；窗口捕获整体卡住（多次重建无首帧）时，
	// 跑一次 monitor 截图（wlr-screencopy）可驱动输出提交解卡（grim 实测有效，2026-09-03）。
	property bool kickPending: false
	signal captureKickDone()

	function requestCaptureKick() {
		if (root.kickPending)
			return;
		root.kickPending = true;
		kickDebounce.restart();
	}

	Timer {
		id: kickDebounce
		interval: 1500
		repeat: false
		onTriggered: {
			root.kickPending = false;
			const mon = Hyprland.focusedMonitor?.name ?? "";
			if (!mon) {
				console.info("[overview-kick] skip: no focused monitor");
				return;
			}
			console.info(`[overview-kick] monitor screencopy kick: grim -o ${mon} /dev/null`);
			kickProc.exec(["grim", "-o", mon, "/dev/null"]);
		}
	}

	Process {
		id: kickProc
		onExited: (code, status) => {
			console.info(`[overview-kick] grim exited code=${code}`);
			// 踢脚完成：通知各窗口立刻重建捕获（Hyprland 通常在随后的
			// 新捕获请求里把此前悬挂的窗口帧送出来）。
			root.captureKickDone();
		}
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

	FileView {
		id: wallpaperFile

		path: `${root.stateDir}/caelestia/wallpaper/path.txt`
		watchChanges: true

		onLoaded: {
			const p = text().trim();
			if (p)
				root.currentWallpaperPath = "file://" + p;
		}
	}

	Timer {
		id: jumpSettleTimer
		interval: 80
		onTriggered: {
			if (!root.visible)
				return;

			scrollAnim.enabled = false;

			const activeId = Hyprland.focusedMonitor?.activeWorkspace?.id ?? 1;
			const step = flickable.cardHeight + flickable.cardSpacing;
			const normalTop = flickable.specialSectionHeight;

			const targetY = normalTop + (activeId - 1) * step - (flickable.visibleHeight - flickable.cardHeight) / 2;

			const maxScroll = Math.max(0, flickable.contentHeight - flickable.height);
			flickable.contentY = Math.max(normalTop, Math.min(targetY, maxScroll));

			Qt.callLater(() => {
				scrollAnim.enabled = true;
			});
		}
	}

	onVisibleChanged: {
		if (visible) {
			localHyprData.updateAll();
			root.syncWindows(localHyprData.windowList);
			jumpSettleTimer.restart();
		} else {
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
					duration: 160
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

				Item {
					id: specialBg
					width: specialColumn.implicitWidth || 400
					height: specialColumn.implicitHeight + flickable.cardSpacing * 2
					visible: specialColumn.implicitHeight > 0
					z: 10

					Rectangle {
						anchors.fill: parent
						anchors.margins: -12
						radius: 20
						color: "transparent"
						border.width: 1
						border.color: Qt.alpha(M3Palette.m3onSurface, 0.15)
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

				Item {
					width: 1
					height: specialColumn.implicitHeight > 0 ? flickable.separatorHeight : 0
					visible: specialColumn.implicitHeight > 0
				}

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
