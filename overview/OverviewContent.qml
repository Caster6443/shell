pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.overview
import qs.services

Item {
	id: root

	// surface 抽象：侧栏 overview 用 OverviewState；嵌入其他窗口（如 spotlight）时可注入独立状态。
	property var surfaceState: OverviewState
	property int visibleCards: 5
	property real cardWidth: 400
	property real cardHeight: 260
	property string filterText: ""
	property var launchOnWorkspace: null
	property bool settleTopAlign: false
	property bool showPanel: true
	onFilterTextChanged: Qt.callLater(() => root.syncWindows(localHyprData.windowList))

	function closeOverview() {
		root.surfaceState.active = false;
	}

	implicitWidth: mainContainer.implicitWidth
	implicitHeight: mainContainer.implicitHeight

	function handleKey(event) {
		if (event.key === Qt.Key_Escape) {
			root.surfaceState.active = false;
			event.accepted = true;
		} else if (event.key === Qt.Key_Up || event.key === Qt.Key_Down) {
			const step = flickable.cardHeight + flickable.cardSpacing;
			const delta = event.key === Qt.Key_Up ? -step : step;
			flickable.contentY = Math.max(0, Math.min(flickable.contentY + delta, flickable.contentHeight - flickable.height));
			event.accepted = true;
		} else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
			const idx = Math.round(flickable.contentY / (flickable.cardHeight + flickable.cardSpacing));
			HyprDispatch.call(`workspace ${idx + 1}`, `hl.dsp.focus({ workspace = "${idx + 1}" })`);
			root.surfaceState.active = false;
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
	const flt = root.filterText.trim().toLowerCase();
	if (flt && !`${cls} ${title.toLowerCase()} ws${wsId}`.includes(flt))
		continue;
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

	// 命中测试：给定 overview 内容区内的坐标（相对本组件根），返回所在工作区 id；
	// 未命中返回 -1。供外部 surface（spotlight）做“拖应用图标落到工作区”的判定。
	function workspaceAt(pos: var): int {
		if (!root.wsLayers)
			return -1;
		for (const k in root.wsLayers) {
			const layer = root.wsLayers[k];
			if (!layer || !layer.visible)
				continue;
			const local = root.mapToItem(layer, pos.x, pos.y);
			if (local.x >= 0 && local.y >= 0 && local.x <= layer.width && local.y <= layer.height)
				return Number(k);
		}
		return -1;
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

	// 供外部 surface（spotlight）在窗口显示时主动刷新数据与定位到当前工作区。
	function refresh(): void {
		localHyprData.updateAll();
	}

	function settleToActive(): void {
		jumpSettleTimer.restart();
	}

	// ---- 预览状态登记（供解锁踢脚判断“是否已有画面”） ----
	property var previewState: ({})
	property int previewTotal: 0
	property int previewReady: 0

	function registerPreview(address: string): void {
		if (!(address in root.previewState)) {
			root.previewState[address] = false;
			root.recomputePreviewCounts();
		}
		root.kickIfNeeded();
	}

	function unregisterPreview(address: string): void {
		if (address in root.previewState) {
			delete root.previewState[address];
			root.recomputePreviewCounts();
		}
	}

	function setPreviewHasContent(address: string, has: bool): void {
		if (!(address in root.previewState))
			return;
		if (root.previewState[address] === has)
			return;
		root.previewState[address] = has;
		root.recomputePreviewCounts();
	}

	function recomputePreviewCounts(): void {
		root.previewTotal = 0;
		root.previewReady = 0;
		for (const k in root.previewState) {
			root.previewTotal++;
			if (root.previewState[k])
				root.previewReady++;
		}
		if (root.previewReady > 0)
			kickRetryTimer.stop();
	}

	// ---- Hyprland toplevel-export 解锁踢脚（有界） ----
	// 实测（2026-09-01~03）：新实例/新捕获上下文的窗口捕获会静默悬挂（无帧无报错），
	// 一次 monitor 截图（wlr-screencopy）可恢复合成器侧状态，随后常驻 live 流正常出帧。
	// 这里只在「有预览且一个画面都没有」时踢，任一预览出帧即停，最多 3 次/次打开。
	signal captureKickDone()
	property bool kickPending: false
	property int kickAttempts: 0

	function unlockCaptureSequence(): void {
		root.kickAttempts = 0;
		root.kickPending = false;
		root.kickIfNeeded();
	}

	function kickIfNeeded(): void {
		if (root.kickPending || root.kickAttempts >= 3)
			return;
		if (root.previewTotal === 0 || root.previewReady > 0)
			return;
		const mon = Hyprland.focusedMonitor?.name ?? "";
		if (!mon) {
			console.info("[overview-kick] skip: no focused monitor");
			return;
		}
		root.kickPending = true;
		console.info(`[overview-kick] unlock kick ${root.kickAttempts + 1}/3: grim -o ${mon} /dev/null`);
		kickProc.exec(["grim", "-o", mon, "/dev/null"]);
	}

	Process {
		id: kickProc
		onExited: (code, status) => {
			root.kickPending = false;
			root.kickAttempts++;
			console.info(`[overview-kick] grim exited code=${code}`);
			if (root.previewReady === 0 && root.previewTotal > 0 && root.kickAttempts < 3)
				kickRetryTimer.start();
			// 无论成功与否都通知预览：仍无首帧的窗口重建一次捕获
			// （解锁后新发出的捕获请求通常即恢复送帧）。
			root.captureKickDone();
		}
	}

	Timer {
		id: kickRetryTimer
		interval: 700
		onTriggered: root.kickIfNeeded()
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

	// caelestia wallpaper 写 path.txt 可能是原子替换，FileView 监听会丢事件；
	// 直接跟随 Wallpapers.actualCurrent 属性，切换瞬间即刷新 overview 背景。
	Connections {
		target: Wallpapers
		function onActualCurrentChanged() {
			if (Wallpapers.actualCurrent)
				root.currentWallpaperPath = "file://" + Wallpapers.actualCurrent;
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

		const targetY = normalTop + (activeId - 1) * step - (root.settleTopAlign ? 0 : (flickable.visibleHeight - flickable.cardHeight) / 2);

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
		color: root.showPanel ? "#CC11111b" : "transparent"
		radius: 24
		implicitWidth: flickable.contentWidth + (root.showPanel ? 60 : 0)
		implicitHeight: flickable.visibleHeight + (root.showPanel ? 60 : 0)
		border.color: root.showPanel ? "#313244" : "transparent"
		border.width: root.showPanel ? 2 : 0
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

			readonly property real cardHeight: root.cardHeight
			readonly property real cardSpacing: 25
			readonly property real visibleCards: root.visibleCards
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
								cardW: root.cardWidth
								cardH: root.cardHeight
								filterActive: root.filterText.trim() !== ""
								launchOnWorkspace: root.launchOnWorkspace
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
						cardW: root.cardWidth
						cardH: root.cardHeight
						filterActive: root.filterText.trim() !== ""
						launchOnWorkspace: root.launchOnWorkspace
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
