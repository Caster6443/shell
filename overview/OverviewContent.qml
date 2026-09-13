pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
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

	// 拖拽中的缩略图要盖在所有卡片之上：同列靠卡片自身 z=100 抬升，跨列（拖去/拖出特殊工作区
	// 卡片区）还要把所在的列整体抬到另一列之上，否则缩略图会被对方列的工作区卡片盖住。
	property bool dragFromSpecialSection: false
	// 滚轮灵敏度：1.0 = 标准滚轮一格（angleDelta.y = 120）滚动一整张卡片的高度。
	property real wheelSensitivity: 1.0
	// 新插槽入场动画用的名字；动画结束后清空，避免卡片重建时重复播放
	property string lastAddedSpecialName: ""

	// ---- 特殊工作区插槽（卡片区最上面的「+」新增）----
	// 特殊工作区只有有窗口时才在 Hyprland 里存在，所以空插槽由 overview 自己记（顺序 = 显示顺序，新的在最前）。
	property var extraSpecialNames: []
	// 默认特殊工作区（SUPER+S / 四指上滑那个）：永远排在卡片区最后，回收插槽时也保留它
	readonly property string defaultSpecialName: "special:special"
	readonly property string specialSlotPrefPath: `${root.stateDir}/caelestia/overview-special-slots.json`
	// 特殊窗口模型变化时重算卡片列表（窗口在不同特殊工作区之间移动时名字集合会变）
	property int specialNamesRevision: 0

	// 卡片区要显示的特殊工作区：用户新增的插槽在前 → 有窗口的特殊工作区 → 默认的 S 永远在最后（按名字去重）。
	function specialSectionNames(): var {
		const rev = root.specialNamesRevision;
		void rev;
		const names = [];
		for (const n of root.extraSpecialNames)
			if (n && n !== root.defaultSpecialName && !names.includes(n))
				names.push(n);
		for (let i = 0; i < specialWindowModel.count; ++i) {
			const n = specialWindowModel.get(i).m_wsName;
			if (n && n !== root.defaultSpecialName && !names.includes(n))
				names.push(n);
		}
		names.push(root.defaultSpecialName);
		return names;
	}

	// 该名字对应的特殊工作区 id（还没有窗口时返回 -1，卡片按名字匹配窗口，不依赖 id）。
	function specialWsIdForName(name: string): int {
		for (let i = 0; i < specialWindowModel.count; ++i) {
			const row = specialWindowModel.get(i);
			if (row.m_wsName === name)
				return row.m_wsId;
		}
		return -1;
	}

	function addSpecialSlot(): void {
		const taken = {};
		for (const n of root.extraSpecialNames)
			taken[n] = true;
		for (let i = 0; i < specialWindowModel.count; ++i)
			taken[specialWindowModel.get(i).m_wsName] = true;
		let n = 1;
		while (taken[`special:slot${n}`])
			n++;
		const name = `special:slot${n}`;
		root.extraSpecialNames = [name].concat(root.extraSpecialNames);
		specialSlotsFile.setText(JSON.stringify(root.extraSpecialNames));
		root.lastAddedSpecialName = name;
		clearLastAddedTimer.restart();
		console.info(`[overview-special] 新增特殊工作区插槽 ${name}`);
	}

	// 启动器关闭时回收没有被使用的插槽（里面没有窗口）。默认的 S 不参与回收，永远在卡片区。
	function recycleSpecialSlots(): void {
		const used = {};
		for (let i = 0; i < specialWindowModel.count; ++i)
			used[specialWindowModel.get(i).m_wsName] = true;

		const kept = root.extraSpecialNames.filter(n => used[n]);

		const changed = kept.length !== root.extraSpecialNames.length
			|| kept.some((n, i) => n !== root.extraSpecialNames[i]);
		if (!changed)
			return;

		root.extraSpecialNames = kept;
		specialSlotsFile.setText(JSON.stringify(kept));
		console.info(`[overview-special] 回收空插槽，保留 ${JSON.stringify(kept)}`);
	}

	// 滚轮只负责按卡片步长滚动列表（曾经有过"向上滚呼出特殊工作区"的手势，用户要求下已整体移除）。
	function wheelScrolled(deltaY: real): void {
		if (deltaY === 0)
			return;
		const step = (flickable.cardHeight + flickable.cardSpacing) * root.wheelSensitivity;
		const newY = flickable.contentY - deltaY / 120 * step;
		flickable.contentY = Math.max(0, Math.min(newY, flickable.contentHeight - flickable.height));
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
		// 面板常驻后本组件在关闭期间也活着：隐藏时关闭事件驱动的全量刷新
		// （每次 = 3 个 hyprctl 进程），打开时由 refresh()/onVisibleChanged 各补一次。
		liveUpdates: root.visible
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
				// 普通工作区也带上名字：WindowPreview 把 m_wsName 声明成 required（角色必须存在）
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

	// 命中测试：给定 overview 内容区内的坐标（相对本组件根），返回所在工作区的登记键
	// （普通工作区 "1".."10"，特殊工作区 "special:xxx"）；未命中返回空串。
	// 供外部 surface（spotlight）做“拖应用图标落到工作区”的判定。
	function workspaceAt(pos: var): string {
		if (!root.wsLayers)
			return "";
		for (const k in root.wsLayers) {
			const layer = root.wsLayers[k];
			if (!layer || !layer.visible)
				continue;
			const local = root.mapToItem(layer, pos.x, pos.y);
			if (local.x >= 0 && local.y >= 0 && local.x <= layer.width && local.y <= layer.height)
				return k;
		}
		return "";
	}

	function isSpecialWorkspaceKey(key: var): bool {
		return String(key).startsWith("special:");
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

	// 最初版（2026-04 独立浮窗原型）的隐藏机关：overview 背后挂一条常驻 live 的
	// monitor 捕获流。Hyprland 的窗口导出帧要等“下一次输出提交”才拷贝，而这条
	// monitor 流每次出帧都会触发本窗口重绘/提交，形成自持节拍，窗口预览跟着一起流动。
	// 仅面板可见且有窗口预览时运行（visible 才绘制 = live 才喂帧），关闭即零开销。
	readonly property var monitorScreen: {
		const mon = Hyprland.focusedMonitor;
		for (const s of Screens.screens)
			if (s.name === mon?.name)
				return s;
		return Screens.screens[0] ?? null;
	}

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

	// 特殊工作区名字集合 = 卡片列表的来源，模型行数变化时重算（窗口跨特殊工作区移动时名字会变）
	Connections {
		target: specialWindowModel
		function onCountChanged() {
			root.specialNamesRevision++;
		}
	}

	Timer {
		id: syncTimer
		interval: 150
		onTriggered: localHyprData.updateAll()
	}

	// 新插槽入场动画播完就忘掉它，卡片重建时不重复播放
	Timer {
		id: clearLastAddedTimer
		interval: 600
		onTriggered: root.lastAddedSpecialName = ""
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

	// 「+」新增的特殊工作区插槽：空插槽在 Hyprland 里不存在，所以由 overview 自己持久化。
	FileView {
		id: specialSlotsFile

		printErrors: false
		// 面板关闭后本组件会被 launcher 的 Loader 销毁，异步写盘会丢 → 小文件直接同步写
		blockWrites: true
		path: root.specialSlotPrefPath

		onLoaded: {
			try {
				const arr = JSON.parse(text());
				if (Array.isArray(arr))
					root.extraSpecialNames = arr.filter(n => typeof n === "string" && n.startsWith("special:"));
			} catch (e) {
				console.warn("overview: 特殊工作区插槽文件解析失败，按空处理");
			}
		}
		onLoadFailed: err => {
			if (err === FileViewError.FileNotFound)
				Qt.callLater(() => setText("[]"));
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
			// 关闭时回收没用上的插槽：必须**同步**做——launcher 的 Loader 在关闭后会销毁本组件，
			// Qt.callLater / 异步写盘都会落在销毁之后（实测报 "function in an invalid context"），
			// 所以这里直接调用，且插槽文件用 blockWrites 同步写。
			root.recycleSpecialSlots();
		}
	}

	// 旧版同款 monitor 实时流（衬在内容后面当“节拍源”，低透明度避免干扰视觉）。
	ScreencopyView {
		id: liveMonitorFeed

		anchors.fill: parent
		visible: root.visible && root.previewReady > 0
		live: true
		opacity: 0.22
		captureSource: root.monitorScreen
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
				// 连续跟随目标：滚轮连发时不会每格重启一次缓动（那种「一格一停」的顿感），
				// 单格从静止起步约 385px / 3600px·s⁻¹ ≈ 110ms，与原来的 160ms 短动画接近。
				SmoothedAnimation {
					velocity: 3600
				}
			}

			// 滚轮事件沿父链冒泡到这里（工作区卡片自己不处理滚轮），
			// 所以鼠标停在卡片上滚动同样生效。
			MouseArea {
				anchors.fill: parent
				acceptedButtons: Qt.NoButton
				onWheel: wheel => {
					wheel.accepted = true;
					const dy = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : wheel.pixelDelta.y;
					root.wheelScrolled(dy);
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
					z: root.dragFromSpecialSection ? 30 : 10

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

						// 卡片区最上面的「+」：新增一个特殊工作区插槽，新插槽排在它下面、原有卡片上面
						Rectangle {
							id: addSpecialButton
							width: root.cardWidth
							height: 40
							radius: 14
							color: addSpecialArea.containsMouse ? Qt.alpha(M3Palette.m3primary, 0.22) : Qt.alpha(M3Palette.m3onSurface, 0.06)
							border.width: 1
							border.color: Qt.alpha(M3Palette.m3primary, addSpecialArea.containsMouse ? 0.7 : 0.35)
							scale: 1

							// 点击时轻微回弹，表示"又长出一个插槽"
							SequentialAnimation {
								id: addButtonPop
								NumberAnimation {
									target: addSpecialButton
									property: "scale"
									to: 0.94
									duration: 90
									easing.type: Easing.OutQuad
								}
								NumberAnimation {
									target: addSpecialButton
									property: "scale"
									to: 1.0
									duration: 200
									easing.type: Easing.OutBack
								}
							}

							Text {
								anchors.centerIn: parent
								text: "＋ 新增特殊工作区"
								color: addSpecialArea.containsMouse ? M3Palette.m3primary : Qt.alpha(M3Palette.m3onSurface, 0.75)
								font.pixelSize: 13
							}

							MouseArea {
								id: addSpecialArea
								anchors.fill: parent
								hoverEnabled: true
								onClicked: {
									addButtonPop.restart();
									root.addSpecialSlot();
								}
							}
						}

						Repeater {
							model: root.specialSectionNames()
							delegate: WorkspaceCard {
								id: slotCard
								required property string modelData
								overviewRoot: root
								windowModel: specialWindowModel
								isSpecial: true
								specialWsName: modelData
								specialWsId: root.specialWsIdForName(modelData)
								cardW: root.cardWidth
								cardH: root.cardHeight
								filterActive: root.filterText.trim() !== ""
								launchOnWorkspace: root.launchOnWorkspace

								// 新插槽入场：从「+」按钮下方滑入 + 淡入（整卡尺寸不变，只做位移，避免内容被压扁）
								appearProgress: modelData === root.lastAddedSpecialName ? 0 : 1
								transform: Translate {
									y: (1 - slotCard.appearProgress) * -90
								}
								Behavior on appearProgress {
									NumberAnimation {
										duration: 260
										easing.type: Easing.OutCubic
									}
								}
								Component.onCompleted: {
									if (modelData === root.lastAddedSpecialName)
										slotCard.appearProgress = 1;
								}
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
					// 普通列默认在特殊区之下（原行为）；从普通列拖拽时整体抬到特殊区之上。
					z: root.dragFromSpecialSection ? 0 : 20

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
