pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Caelestia.Config
import qs.modules.launcher.services
import qs.overview
import qs.services
import qs.spotlight

// Spotlight 内容面板：左 overview 工作区列 + 右应用列表；壁纸模式双视图。
// 由 launcher 弹出面板实例化（原浮动窗已退役）。
Item {
	id: root

	signal closeRequested()

	implicitWidth: Math.round(Screen.width * 0.4)
	implicitHeight: Math.round(Screen.height * 0.6)

	property var pendingLaunch: null
	property var launchWatch: null
	property bool ghostVisible: false
	property string ghostIcon: ""
	property string mode: "apps"
	// 把当前标签页回写给 SpotlightState：IPC（如 Super+V）据此判断「同一标签再按一次 = 收回」
	onModeChanged: {
		SpotlightState.currentMode = root.mode;
		root.hideAppTip();
		root.closeAppMenu();
		Qt.callLater(root.primeWallStrip);
		// 切到应用标签时，让当前分类的胶囊处在可视区
		if (root.mode === "apps")
			Qt.callLater(root.ensureAppCategoryVisible);
	}
	// 顶部标签顺序（胶囊按索引滑动，cycleMode 也用这个顺序）
	readonly property var modeOrder: ["apps", "wallpaper", "clipboard", "emoji"]
	readonly property int modeIndex: Math.max(0, root.modeOrder.indexOf(root.mode))

	function modeLabel(m: string): string {
		if (m === "apps")
			return "应用";
		if (m === "wallpaper")
			return "壁纸";
		if (m === "clipboard")
			return "剪贴板";
		return "Emoji";
	}

	function modePlaceholder(m: string): string {
		if (m === "wallpaper")
			return "搜索壁纸…";
		if (m === "clipboard")
			return "搜索剪贴板历史…";
		if (m === "emoji")
			return "搜索 Emoji（英文关键词）…";
		return "搜索应用…";
	}

	// 应用外部请求的标签页（IPC / 快捷键写入 SpotlightState.requestedMode），用后清空。
	// 返回是否真的切换了；不在 modeOrder 里的值一律忽略。
	function applyRequestedMode(): bool {
		const requested = SpotlightState.requestedMode;
		if (requested === "" || root.modeOrder.indexOf(requested) < 0)
			return false;
		root.mode = requested;
		SpotlightState.requestedMode = "";
		console.info(`[spotlight] 按外部请求切到 ${requested} 标签`);
		return true;
	}
	// 壁纸模式视图：carousel（竖排，2026-09-04 起）/ grid（网格）/ strip（横向胶片条，2026-09-14 新增，
	// 对齐 Denial 壁纸选择器外观）。默认定在新增的 strip 上方便直接评估，
	// 想回到旧手感把这里改回 "carousel" 即可。
	property string wallView: "strip"
	// 壁纸胶片条外观（2026-09-15 按参考图重做）：所有卡片同向倾斜、同高同基线，
	// 当前居中卡通过真实宽度展开并推动相邻卡片；不是左右镜像的扇形，也没有上下错落。
	// stripSlant 设 0 可退回普通矩形；展开倍率刻意明显，接近参考图里“窄卡 → 横向大画幅”的变化。
	property real stripSlant: -17
	property real stripCenterStretch: 2.8
	property real stripCenterGrow: 1.1
	property int stripMotionDuration: 400
	// 视图切换后把新视图的选中项重新对准“正在用的壁纸”（各视图的 currentIndex 是各自维护的）
	onWallViewChanged: {
		Qt.callLater(root.resetWallSelection);
		Qt.callLater(root.primeWallStrip);
	}
	// 在给定底色上取对比色。M3Palette 没暴露 onPrimary/onTertiary，用相对亮度判断即可
	// （0.299/0.587/0.114 是 Rec.601 亮度权重；阈值 0.55 偏保守，宁可给白字）。
	function contrastOn(base: color): color {
		return (0.299 * base.r + 0.587 * base.g + 0.114 * base.b) > 0.55 ? "#101010" : "#FFFFFF";
	}
	// 无本地结果时回车回退到浏览器搜索（?q= 后由 openWebSearch 自动拼接查询词）
	readonly property string webSearchBase: "https://www.bing.com/search?q="
	property real maxHeight: 900
	// 剪贴板 tab：二次确认状态（"" | "delete" | "clearUnpinned" | "clearAll"）
	property string clipConfirm: ""

	// ---------------- 壁纸结果缓存（三个视图共用一份） ----------------
	// 2026-09-14 用户反馈"壁纸动不动就要加载画面"的根因：三个视图原来各自绑定 wallpaperResults(input.text)，
	// 查询串一变（包括每次打开面板把搜索框清空）就产生**新数组实例**，ListView/GridView 视为换模型 →
	// 全部委托重建 → 缩略图整批重新解码。现在改成：查询串没变就复用同一个数组实例，
	// 只有壁纸目录本身增删文件才强制重查（应用壁纸只改 actualCurrent，不该重建列表）。
	property var wallResults: []
	property string wallResultsKey: "\u0000"

	function syncWallResults(force: bool): void {
		const key = (input.text || "").trim();
		if (!force && key === root.wallResultsKey)
			return;
		root.wallResultsKey = key;
		root.wallResults = Wallpapers.query(key).filter(a => !!a);
	}

	// 输入防抖：连续敲字只在停顿后查一次，避免每个字符都重建列表、重新解码
	Timer {
		id: wallQueryDebounce

		interval: 130
		repeat: false
		onTriggered: root.syncWallResults(false)
	}

	Connections {
		target: Wallpapers

		// 壁纸目录增删文件时才需要重查
		function onListChanged(): void {
			root.syncWallResults(true);
		}
	}

	Connections {
		target: Apps

		// 应用数据库加载/刷新时补一次查询（原来只靠输入变化触发，数据库晚到就会一直是空列表）
		function onListChanged(): void {
			root.syncAppResults(true);
		}
	}

	Connections {
		target: AppCategories

		// .desktop 分类/双语字段异步扫描、收藏、归类或排序变化后，显式重算当前网格。
		function onRevisionChanged(): void {
			Qt.callLater(root.refreshAppResults);
		}
	}

	// ---------------- 胶片条一次性渲染（2026-09-14 用户要求） ----------------
	// 「点开壁纸选项卡后把缩略图一次全部渲染出来」：进入标签后把 strip 的 cacheBuffer 放大到远超列表总长，
	// ListView 就会把**全部**委托一次性实例化并解码；之后滚动不会再触发新的解码。
	// 原来 cacheBuffer 只有 1400px，滚到没有缓存的位置就要现场解码（表现就是"动不动加载"）。
	// 刻意用"进入标签才置位"而不是一开始就置位：面板预热时常驻在内存里，提前渲染会拖慢启动器打开。
	property bool wallStripPrimed: false

	function primeWallStrip(): void {
		if (root.wallStripPrimed || root.mode !== "wallpaper" || root.wallView !== "strip" || !root.visible)
			return;
		root.wallStripPrimed = true;
		console.info(`[spotlight] 胶片条预热：一次性渲染 ${root.wallResults.length} 张缩略图`);
	}

	// ---------------- 应用标签：分类视图 + 结果缓存 + 悬浮提示 + 右键归类菜单 ----------------
	// 2026-09-14 第二轮改版（用户要求）：删掉原来的"列表 / 网格"两个视图，改成**分类视图**——
	// 顶部一排分类胶囊（定义与自动归类规则在 AppCategories.qml），下面按当前分类渲染图标网格；
	// 右键图标 = 归类菜单（「添加到常用」/「归类到 X」/「恢复自动归类」）。
	// 启动器默认落在「常用」分类。用户 2026-09-15 要求：每次打开都先看常用
	property string appCategory: "favorite"
	property string appResultsKey: "\u0000"
	property var appFilteredApps: []
	property var appPendingResults: []
	// 右键菜单状态
	property bool appMenuVisible: false
	property var appMenuEntry: null
	property real appMenuX: 0
	property real appMenuY: 0
	property string appTipText: ""
	property real appTipX: 0
	property real appTipY: 0
	property bool appTipVisible: false
	property int appTipIndex: -1
	property string appTipPending: ""

	function syncAppResults(force: bool): void {
		const key = (input.text || "").trim();
		root.appResultsKey = key;
		// 分类视图只在应用数据库刷新或首次初始化时取一次完整应用表；敲搜索词时只过滤当前分类，
		// 不再重复调用 Apps.search(key) 生成跨分类结果。
		if (force || AppCategories.allApps.length === 0)
			AppCategories.allApps = Apps.search("").filter(a => !!a);
		root.refreshAppResults();
	}

	// 显式重算候选结果；真正的 GridView model 在下一事件循环提交。
	// TextField.onTextChanged 的信号栈里直接替换 JS 数组时，过滤日志虽已变化，GridView 却可能继续保留旧模型，
	// 直到切分类造成下一次更新。拆成“计算 → Timer 提交”可稳定触发 model changed。
	function refreshAppResults(): void {
		const key = (input.text || "").trim();
		const source = AppCategories.buckets[root.appCategory] ?? [];
		root.appResultsKey = key;
		root.appPendingResults = AppCategories.searchIn(source, key);
		appResultsCommitTimer.restart();
		console.info(`[spotlight-search] calculate query="${key}" category=${root.appCategory} source=${source.length} matched=${root.appPendingResults.length}`);
	}

	Timer {
		id: appResultsCommitTimer

		interval: 1
		repeat: false
		onTriggered: {
			// 先置空，再在下一事件循环提交全新数组，强制 GridView 丢弃旧的 JS 数组模型。
			const committed = root.appPendingResults.slice();
			root.appFilteredApps = [];
			Qt.callLater(() => {
				root.appFilteredApps = committed;
				console.info(`[spotlight-search] commit query="${root.appResultsKey}" category=${root.appCategory} model=${root.appFilteredApps.length}`);
				if (root.mode === "apps")
					root.resetAppSelection();
			});
		}
	}

	function setAppCategory(id: string): void {
		if (root.appCategory === id)
			return;
		root.closeAppMenu();
		root.hideAppTip();
		root.appCategory = id;
		root.refreshAppResults();
		Qt.callLater(root.resetAppSelection);
		// 滚轮切分类时让胶囊列表跟着动（不然只有高亮换了、列表还停在原地）
		Qt.callLater(root.ensureAppCategoryVisible);
	}

	// 把当前分类的胶囊滚到可视区中间；Repeater.itemAt 拿到胶囊项，算它相对条的位置
	function ensureAppCategoryVisible(): void {
		const list = AppCategories.categories;
		let idx = 0;
		for (let i = 0; i < list.length; ++i) {
			if (list[i].id === root.appCategory)
				idx = i;
		}
		const item = catRepeater.itemAt(idx);
		if (!item)
			return;
		const maxX = Math.max(0, appCatBar.contentWidth - appCatBar.width);
		const target = item.x + item.width / 2 - appCatBar.width / 2;
		appCatBar.contentX = Math.max(0, Math.min(target, maxX));
	}

	// 滚轮到分类胶囊上：上 = 下一个分类、下 = 上一个（与顶部标签同一套手势方向）
	function cycleAppCategory(deltaY: real): void {
		const list = AppCategories.categories;
		if (list.length === 0 || deltaY === 0)
			return;
		let idx = 0;
		for (let i = 0; i < list.length; ++i) {
			if (list[i].id === root.appCategory)
				idx = i;
		}
		const step = deltaY < 0 ? 1 : -1;
		root.setAppCategory(list[(idx + step + list.length) % list.length].id);
	}

	// ---------------- 右键菜单：归类 / 常用 ----------------
	function openAppMenu(cell: var, pos: point): void {
		root.appMenuEntry = cell?.modelData ?? null;
		if (!root.appMenuEntry)
			return;
		root.hideAppTip();
		root.appMenuX = pos.x;
		root.appMenuY = pos.y;
		root.appMenuVisible = true;
	}

	function closeAppMenu(): void {
		root.appMenuVisible = false;
		root.appMenuEntry = null;
	}

	function toggleAppFavorite(): void {
		if (!root.appMenuEntry)
			return;
		const entry = root.appMenuEntry;
		const added = AppCategories.toggleFavorite(entry);
		console.info(`[spotlight-apps] ${added ? "加入" : "移出"}常用: ${entry.id ?? ""}`);
		// 2026-09-14 用户更正：加常用**不要**跳转（原来加完会切到「常用」标签，很烦）；
		// 原地只给图标加 ★ 角标就行，视图不动；菜单点完即关。
		root.closeAppMenu();
	}

	// id 传 "" 或 "auto" = 恢复自动归类
	function assignAppCategory(id: string): void {
		if (!root.appMenuEntry)
			return;
		const entry = root.appMenuEntry;
		AppCategories.assign(entry, id);
		console.info(`[spotlight-apps] 归类 ${entry.id ?? ""} -> ${id}`);
		// 同理：不在"全部"下时跟着应用一起换标签（"恢复自动归类"则跟到自动判断出来的那个分类）
		if (root.appCategory !== "all")
			Qt.callLater(() => root.setAppCategory(id === "" || id === "auto" ? AppCategories.categoryFor(entry) : id));
		root.closeAppMenu();
	}

	// 悬停判定：整块网格上一个 HoverHandler + GridView.indexAt 算命中的格子。
	// 原来靠每个委托自己的 onEntered/onExited —— 委托被回收/重建时那些事件会漏，表现就是"有时不显示应用名"。
	function updateAppTipFromHover(handler: var): void {
		if (!handler.hovered) {
			root.hideAppTip();
			return;
		}
		const p = handler.point.position;
		const idx = appGrid.indexAt(p.x + appGrid.contentX, p.y + appGrid.contentY);
		if (idx < 0 || idx >= appGrid.count) {
			root.hideAppTip();
			return;
		}
		if (idx === root.appTipIndex && (root.appTipVisible || appTipTimer.running))
			return;
		const entry = appGrid.model?.[idx] ?? null;
		if (!entry) {
			root.hideAppTip();
			return;
		}
		appGrid.currentIndex = idx;
		root.appTipIndex = idx;
		root.appTipPending = entry.name ?? "";
		appTipTimer.restart();
	}

	function hideAppTip(): void {
		appTipTimer.stop();
		root.appTipVisible = false;
		root.appTipIndex = -1;
		root.appTipPending = "";
	}

	Timer {
		id: appTipTimer

		interval: 600
		repeat: false
		onTriggered: {
			const idx = root.appTipIndex;
			if (idx < 0 || idx >= appGrid.count || root.appTipPending === "")
				return;
			const cols = Math.max(1, Math.floor(appGrid.width / appGrid.cellWidth));
			const cx = (idx % cols) * appGrid.cellWidth - appGrid.contentX;
			const cy = Math.floor(idx / cols) * appGrid.cellHeight - appGrid.contentY;
			// 完全滚出视口就不弹
			if (cy + appGrid.cellHeight < 0 || cy > appGrid.height)
				return;
			const p = appGrid.mapToItem(shell, cx + appGrid.cellWidth / 2, cy);
			root.appTipText = root.appTipPending;
			root.appTipX = p.x;
			root.appTipY = p.y;
			root.appTipVisible = true;
		}
	}

	// 应用委托的点击/拖放共用逻辑：
	//   网格内拖动松手 = 调整该分类的顺序（写进 sidecar 的 order）；
	//   拖到网格外（左侧 overview 卡片）= 在指定工作区启动（原有行为）。
	property int appDragFromIndex: -1
	property int appDragToIndex: -1

	// 指针落在网格的哪个格子上（用 indexAt，不依赖委托对象）；不在网格内返回 -1
	function appGridIndexAt(area: var, mouse: var): int {
		const p = area.mapToItem(appGrid, mouse.x, mouse.y);
		if (p.x < 0 || p.y < 0 || p.x > appGrid.width || p.y > appGrid.height)
			return -1;
		return appGrid.indexAt(p.x + appGrid.contentX, p.y + appGrid.contentY);
	}

	// 把第 fromIndex 个图标插到 toIndex 那个格子的位置，并把结果顺序落盘
	function reorderApp(fromIndex: int, toIndex: int): void {
		const list = appZone.visibleApps;
		if (fromIndex < 0 || fromIndex >= list.length || toIndex < 0 || toIndex >= list.length)
			return;
		const ids = list.map(e => e?.id ?? "");
		const moved = ids.splice(fromIndex, 1)[0];
		ids.splice(toIndex > fromIndex ? toIndex - 1 : toIndex, 0, moved);
		AppCategories.setCategoryOrder(root.appCategory, ids);
		console.info(`[spotlight-apps] 排序 ${root.appCategory}: ${fromIndex} → ${toIndex}`);
	}

	function appDragPressed(area: var, mouse: var, index: int): void {
		area.pressMightDrag = true;
		area.pressPos = Qt.point(mouse.x, mouse.y);
		root.appDragFromIndex = index;
		root.appDragToIndex = -1;
	}

	function appDragMoved(area: var, target: var, mouse: var, entry: var): void {
		if (area.pressMightDrag && !target.Drag.active
				&& (Math.abs(mouse.x - area.pressPos.x) > 8 || Math.abs(mouse.y - area.pressPos.y) > 8)) {
			target.Drag.active = true;
			target.opacity = 0.45;
			root.ghostIcon = Quickshell.iconPath(entry.icon ?? "", "image-missing");
			root.ghostVisible = true;
			root.hideAppTip();
				}
		if (target.Drag.active) {
			const p = area.mapToItem(shell, mouse.x, mouse.y);
			dragGhost.x = p.x - 28;
			dragGhost.y = p.y - 28;
			// 网格内排序：记录落点格子；搜索状态下不排序（结果集是临时的，顺序没意义）
			const inGrid = root.appGridIndexAt(area, mouse);
			root.appDragToIndex = root.appResultsKey === "" ? inGrid : -1;
			// 拖到网格上下边缘时自动滚动，方便跨屏排序
			if (inGrid >= 0) {
				const g = area.mapToItem(appGrid, mouse.x, mouse.y);
				const maxY = Math.max(0, appGrid.contentHeight - appGrid.height);
				if (g.y < 28)
					appGrid.contentY = Math.max(0, appGrid.contentY - 16);
				else if (g.y > appGrid.height - 28)
					appGrid.contentY = Math.min(maxY, appGrid.contentY + 16);
			}
		}
	}

	function appDragReleased(area: var, target: var, mouse: var, entry: var): void {
		const wasDrag = target.Drag.active;
		const dropIndex = root.appDragToIndex;
		const fromIndex = root.appDragFromIndex;
		if (wasDrag) {
			if (dropIndex >= 0 && fromIndex >= 0 && dropIndex !== fromIndex) {
				// 在网格里松手 → 只排序，不启动应用
				root.reorderApp(fromIndex, dropIndex);
			} else {
				const p = area.mapToItem(ov, mouse.x, mouse.y);
				const hitWs = ov.workspaceAt(p);
				console.info(`[spotlight-drag] release ${entry.name ?? ""} ws=${hitWs}`);
				if (hitWs !== "")
					root.launchOnWorkspace(entry, hitWs, ov.isSpecialWorkspaceKey(hitWs));
			}
		}
		target.Drag.active = false;
		target.opacity = 1;
		root.ghostVisible = false;
		area.pressMightDrag = false;
		root.appDragFromIndex = -1;
		root.appDragToIndex = -1;
		if (!wasDrag) {
			console.info(`[spotlight-click] launch ${entry.name ?? ""}`);
			Apps.launch(entry);
			launchRefreshTimer.restart();
			root.closeRequested();
		}
	}

	// ---------------- 生命周期 ----------------
	// 面板内容现在常驻（launcher Wrapper 的本地补丁：首次打开后不再销毁重建），
	// 所以这里同时负责「每次打开」和「完全关闭后」的重置工作。
	Component.onCompleted: Qt.callLater(() => {
		root.applyRequestedMode();
		root.syncWallResults(false);
		root.syncAppResults(false);
		if (root.mode === "apps")
			root.resetAppSelection();
		// 预热（隐藏状态创建）时不要抢焦点，只在真正可见时补焦点。
		if (root.visible)
			input.forceActiveFocus();
	})

	// 打开流程里唯一会起外部进程的重活（cliphist list）：推迟到面板已经上屏之后再跑，
	// 不和入场动画抢主线程与 CPU。
	Timer {
		id: clipboardRefreshTimer
		interval: 250
		repeat: false
		onTriggered: ClipboardData.refresh()
	}

	onVisibleChanged: {
		if (visible) {
			hoverCloseTimer.stop();
			input.text = "";
			// 搜索框清空后结果要立刻回到全量（查询串没变时这里什么都不做）
			root.syncWallResults(false);
			root.syncAppResults(false);
			// 打开面板时若停在壁纸标签，也补一次一次性渲染
			Qt.callLater(root.primeWallStrip);
			// 用户要求：每次打开启动器都回到「常用」分类，并把胶囊条对齐过去
			root.appCategory = "favorite";
			root.refreshAppResults();
			Qt.callLater(root.ensureAppCategoryVisible);
			root.launchWatch = null;
			root.ghostVisible = false;
			SpotlightState.active = true;
			// IPC / 快捷键指定的标签页（如 Super+V → clipboard）：打开时消费一次
			root.applyRequestedMode();
			// 剪贴板历史每次打开刷新一次（一个 cliphist list 进程，很便宜）
			clipboardRefreshTimer.restart();
			ov.refresh();
			ov.unlockCaptureSequence();
			Qt.callLater(() => ov.settleToActive());
			input.forceActiveFocus();
			Qt.callLater(root.resetAppSelection);
		} else {
			SpotlightState.active = false;
			clipboardRefreshTimer.stop();
			root.hideAppTip();
			root.closeAppMenu();
			// 面板常驻后不再随关闭销毁重建，这里显式回到默认标签页，
			// 保持与之前「每次打开都停在应用标签」一致的手感。
			root.mode = "apps";
		}
	}

	// 外部请求切标签：面板已打开时就地切换，未打开时先记下、等面板可见再消费
	Connections {
		target: SpotlightState

		function onRequestedModeChanged(): void {
			root.applyRequestedMode();
		}
	}

	// 鼠标离开面板即自动关闭；给 150ms 宽限，避免贴着边缘/拖动时被误关。
	HoverHandler {
		onHoveredChanged: {
			if (hovered)
				hoverCloseTimer.stop();
			else if (root.visible)
				hoverCloseTimer.restart();
		}
	}

	Timer {
		id: hoverCloseTimer

		interval: 150
		repeat: false
		onTriggered: {
			if (root.visible)
				root.closeRequested();
		}
	}

	Component.onDestruction: SpotlightState.active = false

	// overview 内点击工作区卡/窗口缩略图会经 closeOverview() 把 SpotlightState 置 false，
	// 此时启动器面板仍可见 → 视为“已选定目标”，自动关闭启动器
	Connections {
		target: SpotlightState

		function onActiveChanged() {
			if (!SpotlightState.active && root.visible)
				root.closeRequested();
		}
	}

	// ---------------- 应用 → 指定工作区启动 ----------------
	function shq(s: string): string {
		return "'" + String(s).replace(/'/g, "'\\''") + "'";
	}

	function buildLaunchArgv(entry: var): var {
		if (entry?.runInTerminal)
			return [...GlobalConfig.general.apps.terminal, `${Quickshell.shellDir}/assets/wrap_term_launch.sh`, ...(entry.command ?? [])];
		return entry?.command ?? [];
	}

	// 模式标签切换：滚轮向上 = 下一个标签，向下 = 上一个标签（按 modeOrder 循环；方向按用户实测反馈定）
	function cycleMode(deltaY: real): void {
		if (deltaY === 0)
			return;
		const order = root.modeOrder;
		const idx = order.indexOf(root.mode);
		const step = deltaY < 0 ? 1 : -1;
		const next = order[(idx + step + order.length) % order.length];
		if (next !== root.mode)
			root.mode = next;
	}

	// 壁纸视图（竖排 / 网格）切换：方向与标签一致
	function cycleWallView(deltaY: real): void {
		if (deltaY === 0)
			return;
		const order = ["carousel", "grid", "strip"];
		const idx = Math.max(0, order.indexOf(root.wallView));
		const step = deltaY < 0 ? 1 : -1;
		root.wallView = order[(idx + step + order.length) % order.length];
	}

	// ws 是工作区选择符字符串：普通工作区 "3"，特殊工作区 "special:slot1"
	function launchOnWorkspace(entry: var, ws: var, isSpecial: bool): void {
		launchRefreshTimer.restart();
		if (isSpecial) {
			root.pendingLaunch = { entry: entry, ws: ws, special: true };
			clientsProc.running = true;
			return;
		}
		const argv = root.buildLaunchArgv(entry);
		const cmdline = argv.map(root.shq).join(" ");
		const luaCmd = String(cmdline).replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\n/g, "\\n");
		const expr = `hl.dispatch(hl.dsp.exec_cmd("${luaCmd}", { workspace = "${ws} silent" }))`;
		console.info(`[spotlight-launch] eval ws=${ws}: ${cmdline.slice(0, 120)}`);
		Quickshell.execDetached(["hyprctl", "eval", expr]);
	}

	Timer {
		id: launchRefreshTimer

		interval: 1000
		repeat: false
		onTriggered: ov.refresh()
	}

	// wsId 这里其实是工作区选择符（普通 "3" / 特殊 "special:slot1"），用 var 接收
	function beginWatch(snapshot: var, entry: var, wsId: var, isSpecial: bool): void {
		const expected = new Set();
		for (const c of [entry?.startupClass, entry?.command?.[0]]) {
			if (!c)
				continue;
			expected.add(String(c).toLowerCase().split("/").pop().replace(/\..*$/, ""));
		}
		root.launchWatch = {
			expected: expected,
			ws: wsId,
			special: isSpecial,
			snapshot: new Set(snapshot),
			tries: 0
		};
		console.info(`[spotlight-launch] watch ws=${wsId} special=${isSpecial} expected=[${[...expected].join(",")}]`);
		Apps.launch(entry);
		root.pollLaunch();
	}

	function pollLaunch(): void {
		if (!root.launchWatch)
			return;
		if (root.launchWatch.tries++ >= 40) {
			console.info("[spotlight-launch] timeout: 未发现可移动的新窗口");
			root.launchWatch = null;
			return;
		}
		pollProc.running = true;
	}

	Timer {
		id: pollRetryTimer

		interval: 300
		repeat: false
		onTriggered: root.pollLaunch()
	}

	Process {
		id: pollProc

		command: ["hyprctl", "clients", "-j"]
		running: false

		stdout: StdioCollector {
			onStreamFinished: {
				const watch = root.launchWatch;
				if (!watch) {
					root.launchWatch = null;
					return;
				}
				try {
					const raw = JSON.parse(this.text);
					let moved = false;
					for (const c of raw) {
						if (!c.address || watch.snapshot.has(c.address))
							continue;
						const cls = (c.class || "").toLowerCase();
						const matched = watch.expected.size === 0 || watch.expected.has(cls);
						if (!matched)
							continue;
						const ws = String(watch.ws);
						console.info(`[spotlight-launch] move ${c.class ?? ""} ${c.address} -> ws ${ws}`);
						HyprDispatch.call(
							`movetoworkspacesilent ${ws},address:${HyprDispatch.addressArg(c.address)}`,
							`hl.dsp.window.move({ window = "address:${HyprDispatch.addressArg(c.address)}", workspace = "${ws}", follow = false })`
						);
						watch.snapshot.add(c.address);
						moved = true;
					}
					if (moved) {
						root.launchWatch = null;
						return;
					}
				} catch (e) {
					console.warn("Spotlight: 轮询新窗口失败", e);
				}
				pollRetryTimer.restart();
			}
		}
	}

	Process {
		id: clientsProc

		command: ["hyprctl", "clients", "-j"]
		running: false

		stdout: StdioCollector {
			onStreamFinished: {
				try {
					const raw = JSON.parse(this.text);
					const arr = [];
					for (const c of raw) {
						if (!c.address || !c.mapped)
							continue;
						arr.push(c.address);
					}
					const pending = root.pendingLaunch;
					root.pendingLaunch = null;
					if (pending)
						root.beginWatch(arr, pending.entry, pending.ws, pending.special);
				} catch (e) {
					console.warn("Spotlight: 解析 hyprctl clients 失败", e);
					root.pendingLaunch = null;
				}
			}
		}
	}

	// ---------------- UI ----------------
	Rectangle {
		id: shell

		anchors.fill: parent
		anchors.margins: 1
		radius: 20
		// 跟随全局透明度设置（Wallpaper & style → Transparency），不写死
		color: Colours.tPalette.m3surfaceContainerHigh
		border.color: Qt.alpha(M3Palette.m3onSurface, 0.12)
		border.width: 1
		clip: true

		Column {
			anchors.fill: parent
			anchors.margins: 12
			spacing: 10

			TextField {
				id: input

				objectName: "spotlightSearch"
				width: parent.width
				height: 40
				leftPadding: 40
				rightPadding: 14

				placeholderText: root.modePlaceholder(root.mode)
				placeholderTextColor: Qt.alpha(M3Palette.m3onSurface, 0.45)
				color: M3Palette.m3onSurface
				font: Tokens.font.body.large

				IconImage {
					asynchronous: true
					implicitSize: 18
					source: Quickshell.iconPath("system-search", "image-missing")
					anchors.left: parent.left
					anchors.verticalCenter: parent.verticalCenter
					anchors.leftMargin: 12
				}

				background: Rectangle {
					radius: 12
					color: Qt.alpha(M3Palette.m3surface, 0.5)
					border.color: input.activeFocus
						? M3Palette.m3tertiary
						: Qt.alpha(M3Palette.m3onSurface, 0.2)
					border.width: input.activeFocus ? 1.5 : 1
				}

				Keys.onEscapePressed: event => {
					root.closeRequested();
					event.accepted = true;
				}
				Keys.onDownPressed: event => {
					if (root.mode === "apps") {
						root.moveAppSelection(0, 1);
						event.accepted = true;
					} else if (root.mode === "wallpaper") {
						root.moveWallSelection(0, 1);
						event.accepted = true;
					} else if (root.mode === "clipboard") {
						root.moveClipSelection(1, 0);
						event.accepted = true;
					} else if (root.mode === "emoji") {
						root.moveEmojiSelection(0, 1);
						event.accepted = true;
					}
				}
				Keys.onUpPressed: event => {
					if (root.mode === "apps") {
						root.moveAppSelection(0, -1);
						event.accepted = true;
					} else if (root.mode === "wallpaper") {
						root.moveWallSelection(0, -1);
						event.accepted = true;
					} else if (root.mode === "clipboard") {
						root.moveClipSelection(-1, 0);
						event.accepted = true;
					} else if (root.mode === "emoji") {
						root.moveEmojiSelection(0, -1);
						event.accepted = true;
					}
				}
				Keys.onLeftPressed: event => {
					// 网格与胶片条都用左右键（胶片条的方向键主用左右）
					if (root.mode === "apps") {
						root.moveAppSelection(-1, 0);
						event.accepted = true;
					} else if (root.mode === "wallpaper" && (root.wallView === "grid" || root.wallView === "strip")) {
						root.moveWallSelection(-1, 0);
						event.accepted = true;
					} else if (root.mode === "emoji") {
						root.moveEmojiSelection(-1, 0);
						event.accepted = true;
					}
				}
				Keys.onRightPressed: event => {
					if (root.mode === "apps") {
						root.moveAppSelection(1, 0);
						event.accepted = true;
					} else if (root.mode === "wallpaper" && (root.wallView === "grid" || root.wallView === "strip")) {
						root.moveWallSelection(1, 0);
						event.accepted = true;
					} else if (root.mode === "emoji") {
						root.moveEmojiSelection(1, 0);
						event.accepted = true;
					}
				}
				// 剪贴板 tab 的额外快捷键：Ctrl+P 置顶开关、Ctrl+D 删除（走确认框）。
				// 用 Ctrl 组合而不是 Del/Backspace，避免抢走搜索框本身的编辑键。
				Keys.onPressed: event => {
					if (root.mode !== "clipboard" || !(event.modifiers & Qt.ControlModifier))
						return;
					if (event.key === Qt.Key_P) {
						root.toggleSelectedClipPin();
						event.accepted = true;
					} else if (event.key === Qt.Key_D) {
						root.requestClipConfirm("delete");
						event.accepted = true;
					}
				}
				onTextChanged: {
					// 壁纸结果走防抖，其余标签仍是即时反应
					// 注意：wallQueryDebounce 是 root 的直接子对象（靠 id 在组件内可见），
					// 不是 root 的属性——写成 root.wallQueryDebounce.restart() 会取到 undefined，
					// 导致防抖永不触发、壁纸搜索不随输入刷新（2026-09-23 修复）。
					wallQueryDebounce.restart();
					// 应用结果与改造前一样即时刷新（多了一层"查询串没变就复用"的保护）
					root.syncAppResults(false);
					// 结果集变了，右键菜单里的归类状态可能已失效
					root.closeAppMenu();
					if (root.mode === "apps")
						Qt.callLater(root.resetAppSelection);
					else if (root.mode === "wallpaper")
						Qt.callLater(root.resetWallSelection);
					else if (root.mode === "clipboard")
						Qt.callLater(root.resetClipSelection);
					else if (root.mode === "emoji")
						Qt.callLater(root.resetEmojiSelection);
				}
				// TextInput.textEdited 专门在用户实际编辑时发出。当前环境中键入字符没有稳定进入
				// onTextChanged，但分类切换能读到新 text；这里为应用搜索建立明确的用户输入入口。
				onTextEdited: {
					if (root.mode === "apps")
						root.syncAppResults(false);
				}
				onAccepted: {
					if (root.mode === "apps") {
						// 两个视图都可能显示结果，用当前视图的条目数判断
						if (appZone.appCount > 0)
							root.launchSelectedApp();
						else if (input.text.trim())
							root.openWebSearch(input.text);
					} else if (root.mode === "wallpaper") {
						root.applySelectedWallpaper();
					} else if (root.mode === "clipboard") {
						root.copySelectedClip();
					} else if (root.mode === "emoji") {
						root.copySelectedEmoji();
					}
				}
			}

			// 顶部：模式切换（应用 / 壁纸 / 剪贴板 / Emoji）
			Rectangle {
				id: modeHeader

				width: 300
				height: 30
				radius: 15
				// 轨道底色加深：0.55 在浅色/低饱和配色方案下和面板糊在一起（2026-09-14 用户反馈"配色太淡"）
				color: Qt.alpha(M3Palette.m3surface, 0.9)
				border.color: Qt.alpha(M3Palette.m3onSurface, 0.18)
				border.width: 1
				// 格子宽度统一由总宽推算，滑块不会超出轨道（原来最后一个标签的滑块会压出 2px）
				readonly property int cellWidth: Math.floor(width / root.modeOrder.length)
				clip: true

				// 滑块胶囊：单一元素在标签之间滑过去（按 modeIndex 定位）
				Rectangle {
					id: modePill

					y: 2
					width: modeHeader.cellWidth - 4
					height: modeHeader.height - 4
					radius: 13
					// m3tertiary 在暖色/浅色方案下是奶白色，配白字直接看不见（用户截图）；primary 更稳
					color: M3Palette.m3primary
					x: 2 + root.modeIndex * modeHeader.cellWidth

					Behavior on x {
						NumberAnimation {
							duration: 190
							easing.type: Easing.OutCubic
						}
					}
				}

				Row {
					anchors.fill: parent

					Repeater {
						model: root.modeOrder

						delegate: Item {
							id: modeTab
							required property string modelData

							width: modeHeader.cellWidth
							height: modeHeader.height

							Text {
								anchors.centerIn: parent
								text: root.modeLabel(modeTab.modelData)
								color: root.mode === modeTab.modelData
									? root.contrastOn(M3Palette.m3primary)
									: Qt.alpha(M3Palette.m3onSurfaceVariant, 0.85)
								font.pixelSize: 11
								font.bold: root.mode === modeTab.modelData
							}

							MouseArea {
								anchors.fill: parent
								hoverEnabled: true
								// 悬停在选项卡上滚轮也能切换模式
								onWheel: wheel => {
									wheel.accepted = true;
									root.cycleMode(wheel.angleDelta.y);
								}
								onClicked: {
									root.mode = modeTab.modelData;
									if (modeTab.modelData === "clipboard")
										ClipboardData.refresh();
								}
							}
						}
					}
				}
			}

			// ---------------- 应用模式 ----------------
			Item {
				id: appsBody

				visible: root.mode === "apps"
				width: parent.width
				height: parent.height - input.height - modeHeader.height - parent.spacing * 2

				Row {
					anchors.fill: parent
					spacing: 10

					Item {
						id: leftZone

						width: 566
						height: parent.height

						OverviewContent {
							id: ov

							anchors.fill: parent
							surfaceState: SpotlightState
							visibleCards: 2
							cardWidth: 560
							cardHeight: 360
							showPanel: false
							settleTopAlign: true
							launchOnWorkspace: root.launchOnWorkspace
						}
					}

					Rectangle {
						width: 1
						height: parent.height
						color: Qt.alpha(M3Palette.m3onSurface, 0.1)
					}

					Item {
						id: appZone

						width: parent.width - leftZone.width - 11
						height: parent.height
						// 由 refreshAppResults() 显式更新，不依赖 QML 对 JS 函数内部属性的隐式依赖追踪。
						readonly property var visibleApps: root.appFilteredApps
						readonly property int appCount: appGrid.count

						Text {
							id: appTitle

							text: input.text.trim()
								? `${AppCategories.labelFor(root.appCategory)}内匹配 · ${appZone.visibleApps.length}`
								: `${AppCategories.labelFor(root.appCategory)} · ${appZone.visibleApps.length}`
							color: Qt.alpha(M3Palette.m3onSurface, 0.55)
							font.pixelSize: 11
							font.bold: true
						}

						// 分类胶囊：横向可滚动；滚轮 = 切换分类（与顶部标签同一套手势方向）
						Flickable {
							id: appCatBar

							anchors.top: appTitle.bottom
							anchors.topMargin: 8
							anchors.left: parent.left
							anchors.right: parent.right
							height: 22
							clip: true
							contentWidth: appCatRow.width
							contentHeight: height
							interactive: true
							boundsBehavior: Flickable.StopAtBounds

							// 切分类时整条胶囊滑过去（配合 ensureAppCategoryVisible）
							Behavior on contentX {
								NumberAnimation {
									duration: 220
									easing.type: Easing.InOutCubic
								}
							}

							Row {
								id: appCatRow

								height: appCatBar.height
								spacing: 6

								Repeater {
									id: catRepeater

									model: AppCategories.categories

									delegate: Rectangle {
										id: catPill

										required property var modelData

										// 同样直接读 buckets 以保证依赖可追踪（数量只用于"空分类压暗"）
										readonly property int catCount: AppCategories.buckets[catPill.modelData.id] ? AppCategories.buckets[catPill.modelData.id].length : 0
										readonly property bool selected: root.appCategory === catPill.modelData.id

										width: catLabel.implicitWidth + 18
										height: appCatRow.height
										radius: height / 2
										// 选中 = 实心 tertiary 胶囊；未选中 = 只有细边框的幽灵胶囊；都不显示数量
										color: catPill.selected ? M3Palette.m3tertiary : "transparent"
										border.color: catPill.selected ? "transparent" : Qt.alpha(M3Palette.m3onSurface, 0.22)
										border.width: 1
										// 空分类压暗（数量仍参与判断，只是不显示）
										opacity: (catPill.catCount === 0 && !catPill.selected) ? 0.45 : 1

										Text {
											id: catLabel

											anchors.centerIn: parent
											text: catPill.modelData.label
											color: catPill.selected ? root.contrastOn(M3Palette.m3tertiary) : Qt.alpha(M3Palette.m3onSurface, 0.8)
											font.pixelSize: 11
											font.bold: catPill.selected
										}

										MouseArea {
											anchors.fill: parent
											hoverEnabled: true
											onWheel: wheel => {
												wheel.accepted = true;
												root.cycleAppCategory(wheel.angleDelta.y);
											}
											onClicked: root.setAppCategory(catPill.modelData.id)
										}
									}
								}
							}
						}

						// 搜索无命中：回车走浏览器搜索
						Text {
							id: webSearchHint

							anchors.top: appCatBar.bottom
							anchors.left: parent.left
							anchors.right: parent.right
							anchors.topMargin: 10
							visible: root.appResultsKey !== "" && appZone.visibleApps.length === 0
							text: "没有匹配的应用 — 回车用浏览器搜索"
							color: Qt.alpha(M3Palette.m3onSurface, 0.45)
							font.pixelSize: 12
						}

						// 空分类提示：告诉用户右键能归类 / 加常用
						Text {
							id: emptyCatHint

							anchors.top: appCatBar.bottom
							anchors.left: parent.left
							anchors.right: parent.right
							anchors.topMargin: 10
							visible: root.appResultsKey === "" && appZone.visibleApps.length === 0
							text: root.appCategory === "favorite"
								? "「常用」还是空的 — 右键任意应用图标 →「添加到常用」"
								: "这个分类下没有应用 — 右键任意应用图标 →「归类到…」"
							color: Qt.alpha(M3Palette.m3onSurface, 0.45)
							font.pixelSize: 12
						}

						GridView {
							id: appGrid

							anchors.top: appCatBar.bottom
							anchors.topMargin: 8
							anchors.left: parent.left
							anchors.right: parent.right
							anchors.bottom: parent.bottom
							clip: true
							// 按可用宽度决定列数（每格目标 92px、至少 3 列），正方形格子
							cellWidth: Math.max(78, Math.floor(width / Math.max(3, Math.floor(width / 92))))
							cellHeight: cellWidth
							model: appZone.visibleApps
							currentIndex: -1
							cacheBuffer: 900

							onCountChanged: {
								if (root.mode === "apps")
									Qt.callLater(root.resetAppSelection);
							}
							// 滚起来就收起提示，免得提示粘在屏幕上跟着乱飘
							onContentYChanged: {
								if (root.appTipVisible)
									root.hideAppTip();
							}

							// 悬停命中判定：整块网格一个 HoverHandler + indexAt（不依赖每个委托的进入/离开事件）
							HoverHandler {
								id: appGridHover

								onPointChanged: root.updateAppTipFromHover(appGridHover)
								onHoveredChanged: root.updateAppTipFromHover(appGridHover)
							}

							delegate: Item {
								id: appCell

								required property var modelData
								required property int index

								width: appGrid.cellWidth
								height: appGrid.cellHeight

								Drag.keys: ["app"]
								Drag.source: appCell
								// 拖拽排序时的落点高亮（appDragToIndex 由 appDragMoved 里的 indexAt 算出）
								readonly property bool isDropTarget: root.appDragFromIndex >= 0
									&& root.appDragToIndex === appCell.index
									&& root.appDragToIndex !== root.appDragFromIndex

								Rectangle {
									id: appCellBg

									anchors.centerIn: parent
									width: Math.min(parent.width, parent.height) - 14
									height: width
									radius: 16
									color: appCell.isDropTarget
										? Qt.alpha(M3Palette.m3tertiary, 0.35)
										: (appCell.GridView.isCurrentItem
											? Qt.alpha(M3Palette.m3tertiary, 0.28)
											: (cellMouse.containsMouse ? Qt.alpha(M3Palette.m3onSurface, 0.1) : "transparent"))
									border.color: (appCell.isDropTarget || appCell.GridView.isCurrentItem)
										? Qt.alpha(M3Palette.m3tertiary, 0.8)
										: "transparent"
									border.width: appCell.isDropTarget ? 2 : 1

									IconImage {
										anchors.centerIn: parent
										asynchronous: true
										implicitSize: Math.round(parent.width * 0.62)
										source: Quickshell.iconPath(modelData.icon ?? "", "image-missing")
									}

									// 「常用」角标：提醒"这个应用已在常用里"——在「常用」标签页里显示它没有意义，所以那里不显示
									Text {
										anchors.top: parent.top
										anchors.right: parent.right
										anchors.margins: 6
										visible: {
											if (root.appCategory === "favorite")
												return false;
											const rev = AppCategories.revision;
											return AppCategories.isFavorite(appCell.modelData);
										}
										text: "★"
										color: M3Palette.m3tertiary
										font.pixelSize: 12
									}
								}

								MouseArea {
									id: cellMouse

									anchors.fill: parent
									hoverEnabled: true
									acceptedButtons: Qt.LeftButton | Qt.RightButton
									preventStealing: true

									property bool pressMightDrag: false
									property point pressPos

									// 悬停选中 + 0.6s 弹应用名：统一由 appGrid 上的 HoverHandler 处理（见下）
									onPressed: mouse => {
										if (mouse.button === Qt.LeftButton)
											root.appDragPressed(cellMouse, mouse, appCell.index);
									}
									onPositionChanged: mouse => root.appDragMoved(cellMouse, appCell, mouse, appCell.modelData)
									onReleased: mouse => {
										if (mouse.button === Qt.LeftButton)
											root.appDragReleased(cellMouse, appCell, mouse, appCell.modelData);
									}
									onClicked: mouse => {
										if (mouse.button === Qt.RightButton) {
											// 右键：在指针处弹分类菜单（归类 / 加到常用）
											const p = cellMouse.mapToItem(shell, mouse.x, mouse.y);
											root.openAppMenu(appCell, p);
											return;
										}
										root.hideAppTip();
									}
								}
							}
						}
					}
				}
			}

			// ---------------- 壁纸模式（竖排 / 网格） ----------------
			Item {
				id: wallBody

				visible: root.mode === "wallpaper"
				width: parent.width
				height: parent.height - input.height - modeHeader.height - parent.spacing * 2

				Row {
					id: wallToolbar

					anchors.top: parent.top
					anchors.right: parent.right
					height: 28
					spacing: 8

					// 随机 Booru 壁纸（只取 rating:safe）：抓一张随机图下载到缓存再应用
					Rectangle {
						id: booruButton

						width: booruLabel.implicitWidth + 20
						height: parent.height
						radius: 9
						color: BooruWallpaper.busy
							? Qt.alpha(M3Palette.m3tertiary, 0.5)
							: (booruArea.containsMouse ? Qt.alpha(M3Palette.m3tertiary, 0.35) : Qt.alpha(M3Palette.m3surface, 0.6))

						Text {
							id: booruLabel

							anchors.centerIn: parent
							text: BooruWallpaper.busy ? "抓取中…" : "🎲 随机壁纸"
							color: BooruWallpaper.busy ? "#FFFFFF" : M3Palette.m3onSurface
							font.pixelSize: 12
						}

						MouseArea {
							id: booruArea

							anchors.fill: parent
							hoverEnabled: true
							onClicked: BooruWallpaper.randomize()
						}
					}

					Text {
						anchors.verticalCenter: parent.verticalCenter
						visible: BooruWallpaper.status !== ""
						text: BooruWallpaper.status
						color: Qt.alpha(M3Palette.m3onSurface, 0.55)
						font.pixelSize: 11
					}

					// 竖排 / 网格 / 胶片条 切换：单一滑块 + 滚轮切换（与顶部标签同一套手势方向）
					Rectangle {
						id: wallViewSwitch

						width: 156
						height: parent.height
						radius: 9
						// 底色加深 + 描边：0.6 透明度在浅色配色方案下几乎糊在面板上（2026-09-14 用户反馈"配色是淡的"）
						color: Qt.alpha(M3Palette.m3surface, 0.9)
						border.color: Qt.alpha(M3Palette.m3onSurface, 0.16)
						border.width: 1
						// 格子宽度统一由总宽推算，滑块绝不可能超出轨道
						readonly property int cellWidth: Math.floor(width / 3)
						readonly property int viewIndex: Math.max(0, ["carousel", "grid", "strip"].indexOf(root.wallView))
						clip: true

						Rectangle {
							id: wallViewPill

							y: 2
							width: wallViewSwitch.cellWidth - 4
							height: wallViewSwitch.height - 4
							radius: 7
							// primary 比 tertiary 更稳，浅色/深色方案下都压得住
							color: M3Palette.m3primary
							x: 2 + wallViewSwitch.viewIndex * wallViewSwitch.cellWidth

							Behavior on x {
								NumberAnimation {
									duration: 160
									easing.type: Easing.OutCubic
								}
							}
						}

						Row {
							anchors.fill: parent

							Item {
								width: wallViewSwitch.cellWidth
								height: wallViewSwitch.height

								Text {
									anchors.centerIn: parent
									text: "≡"
									color: root.wallView === "carousel"
										? root.contrastOn(M3Palette.m3primary)
										: Qt.alpha(M3Palette.m3onSurfaceVariant, 0.85)
									font.pixelSize: 16
									font.bold: root.wallView === "carousel"
								}

								MouseArea {
									anchors.fill: parent
									hoverEnabled: true
									onWheel: wheel => {
										wheel.accepted = true;
										root.cycleWallView(wheel.angleDelta.y);
									}
									onClicked: root.wallView = "carousel"
								}
							}

							Item {
								width: wallViewSwitch.cellWidth
								height: wallViewSwitch.height

								Text {
									anchors.centerIn: parent
									text: "▦"
									color: root.wallView === "grid"
										? root.contrastOn(M3Palette.m3primary)
										: Qt.alpha(M3Palette.m3onSurfaceVariant, 0.85)
									font.pixelSize: 15
									font.bold: root.wallView === "grid"
								}

								MouseArea {
									anchors.fill: parent
									hoverEnabled: true
									onWheel: wheel => {
										wheel.accepted = true;
										root.cycleWallView(wheel.angleDelta.y);
									}
									onClicked: root.wallView = "grid"
								}
							}

							// 胶片条（strip）：2026-09-14 新增的第三个视图
							Item {
								width: wallViewSwitch.cellWidth
								height: wallViewSwitch.height

								Text {
									anchors.centerIn: parent
									text: "▤"
									color: root.wallView === "strip"
										? root.contrastOn(M3Palette.m3primary)
										: Qt.alpha(M3Palette.m3onSurfaceVariant, 0.85)
									font.pixelSize: 14
									font.bold: root.wallView === "strip"
								}

								MouseArea {
									anchors.fill: parent
									hoverEnabled: true
									onWheel: wheel => {
										wheel.accepted = true;
										root.cycleWallView(wheel.angleDelta.y);
									}
									onClicked: root.wallView = "strip"
								}
							}
						}
					}
				}

				Item {
					id: wallViewport

					anchors.top: wallToolbar.bottom
					anchors.bottom: parent.bottom
					anchors.left: parent.left
					anchors.right: parent.right
					anchors.topMargin: 6
					clip: true

					ListView {
						id: wallList

						anchors.fill: parent
						orientation: ListView.Vertical
						interactive: false
						spacing: 12
						boundsBehavior: Flickable.StopAtBounds
						model: root.wallResults
						// 缓存视口外的委托：滚回来不用重新解码缩略图
						cacheBuffer: 800
						clip: true
						visible: root.wallView === "carousel"
						currentIndex: 0

						Behavior on contentY {
							NumberAnimation {
								// 带加速段的缓动（慢起 → 加速 → 收尾），比纯减速的 OutCubic 更有"滚起来"的手感
								duration: 300
								easing.type: Easing.InOutCubic
							}
						}

						onCountChanged: {
							for (let i = 0; i < wallList.count; ++i) {
								if (wallList.model?.[i]?.path === Wallpapers.actualCurrent) {
									wallList.currentIndex = i;
									wallList.positionViewAtIndex(i, ListView.Center);
									return;
								}
							}
							wallList.currentIndex = 0;
						}

						delegate: Item {
							id: wallCard

							required property var modelData

							width: wallList.width
							height: Math.round(wallList.height * 0.46)

							readonly property bool isCurrent: modelData?.path === Wallpapers.actualCurrent
							readonly property bool isSelected: ListView.isCurrentItem

							// 外层只负责“选中放大”的基准缩放，点击回弹动画放到内层 wallFrame，互不干扰
							scale: wallCard.isSelected ? 1 : 0.94
							opacity: wallCard.isSelected ? 1 : 0.78

							Behavior on scale {
								NumberAnimation {
									duration: 180
									easing.type: Easing.OutCubic
								}
							}
							Behavior on opacity {
								NumberAnimation {
									duration: 180
									easing.type: Easing.OutCubic
								}
							}

							Rectangle {
								id: wallFrame

								width: parent.width
								height: Math.min(parent.height, Math.round(parent.width / 16 * 9))
								anchors.centerIn: parent
								radius: 16
								clip: true
								color: Qt.alpha(M3Palette.m3surface, 0.35)
								border.color: (wallHover.containsMouse || wallCard.isSelected || wallCard.isCurrent)
									? M3Palette.m3tertiary
									: Qt.alpha(M3Palette.m3onSurface, 0.12)
								border.width: (wallHover.containsMouse || wallCard.isSelected || wallCard.isCurrent) ? 2 : 1

								// 点击反馈：轻微缩小再快速回位。pressScale 由单一 SequentialAnimation 控制，
								// 不设 Behavior（避免 Behavior 与显式动画在同一属性上叠加打架）
								property real pressScale: 1
								scale: wallFrame.pressScale

								Image {
									id: wallImage

									anchors.top: parent.top
									anchors.left: parent.left
									anchors.right: parent.right
									height: parent.height
									source: modelData?.path ? "file://" + modelData.path : ""
									fillMode: Image.PreserveAspectCrop
									asynchronous: true
									sourceSize: Qt.size(
										Math.max(640, Math.round(width * 2)),
										Math.max(360, Math.round(height * 2))
									)
								}

								// 当前壁纸：右上角对勾（不用文字）
								Rectangle {
									visible: wallCard.isCurrent
									width: 24
									height: 24
									radius: 12
									color: M3Palette.m3tertiary
									anchors.top: parent.top
									anchors.right: parent.right
									anchors.margins: 8
									z: 5

									Text {
										anchors.centerIn: parent
										text: "✓"
										color: "#FFFFFF"
										font.pixelSize: 14
										font.bold: true
									}
								}
							}

							MouseArea {
								id: wallHover

								anchors.fill: parent
								hoverEnabled: true
								onClicked: {
									if (modelData?.path) {
										wallPressAnim.restart();
										Wallpapers.setWallpaper(modelData.path);
									}
								}
							}

							// 点击反馈单一动画源：快速收缩 → 带回弹回位
							SequentialAnimation {
								id: wallPressAnim

								running: false
								NumberAnimation {
									target: wallFrame
									property: "pressScale"
									to: 0.9
									duration: 60
								}
								NumberAnimation {
									target: wallFrame
									property: "pressScale"
									to: 1
									duration: 170
									easing.type: Easing.OutBack
								}
							}
						}
					}

					// 滚轮翻页（竖排模式）
					MouseArea {
						visible: root.wallView === "carousel"
						anchors.fill: parent
						acceptedButtons: Qt.NoButton
						onWheel: wheel => {
							const delta = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : wheel.angleDelta.x;
							let idx = wallList.currentIndex + (delta < 0 ? 1 : -1);
							idx = Math.max(0, Math.min(idx, wallList.count - 1));
							wallList.currentIndex = idx;
							wallList.positionViewAtIndex(idx, ListView.Center);
						}
					}

					// 网格视图
					GridView {
						id: wallGrid

						visible: root.wallView === "grid"
						anchors.fill: parent
						clip: true
						cellWidth: parent.width >= 900
							? Math.round((parent.width - 24) / 4)
							: Math.round((parent.width - 16) / 3)
						cellHeight: Math.round(cellWidth / 16 * 9 + 10)
						model: root.wallResults
						cacheBuffer: 900
						currentIndex: 0

						onCountChanged: {
							for (let i = 0; i < wallGrid.count; ++i) {
								if (wallGrid.model?.[i]?.path === Wallpapers.actualCurrent) {
									wallGrid.currentIndex = i;
									wallGrid.positionViewAtIndex(i, GridView.Center);
									return;
								}
							}
							wallGrid.currentIndex = 0;
						}

						delegate: Item {
							id: gridCard

							required property var modelData

							width: wallGrid.cellWidth
							height: wallGrid.cellHeight

							readonly property bool isCurrent: modelData?.path === Wallpapers.actualCurrent

							Rectangle {
								id: gridFrame

								anchors.fill: parent
								anchors.margins: 4
								radius: 12
								clip: true
								color: Qt.alpha(M3Palette.m3surface, 0.35)
								border.color: (gridHover.containsMouse || gridCard.isCurrent)
									? M3Palette.m3tertiary
									: Qt.alpha(M3Palette.m3onSurface, 0.12)
								border.width: (gridHover.containsMouse || gridCard.isCurrent) ? 2 : 1

								// 点击反馈：轻微缩小再快速回位。pressScale 由单一 SequentialAnimation 控制，
								// 不设 Behavior（避免 Behavior 与显式动画在同一属性上叠加打架）
								property real pressScale: 1
								scale: gridFrame.pressScale

								Image {
									anchors.fill: parent
									source: modelData?.path ? "file://" + modelData.path : ""
									fillMode: Image.PreserveAspectCrop
									asynchronous: true
									sourceSize: Qt.size(
										Math.max(480, Math.round(width * 2)),
										Math.max(270, Math.round(height * 2))
									)
								}

								Rectangle {
									visible: gridCard.isCurrent
									width: 22
									height: 22
									radius: 11
									color: M3Palette.m3tertiary
									anchors.top: parent.top
									anchors.right: parent.right
									anchors.margins: 6
									z: 5

									Text {
										anchors.centerIn: parent
										text: "✓"
										color: "#FFFFFF"
										font.pixelSize: 13
										font.bold: true
									}
								}
							}

							// 点击反馈单一动画源：快速收缩 → 带回弹回位
							SequentialAnimation {
								id: gridPressAnim

								running: false
								NumberAnimation {
									target: gridFrame
									property: "pressScale"
									to: 0.9
									duration: 60
								}
								NumberAnimation {
									target: gridFrame
									property: "pressScale"
									to: 1
									duration: 170
									easing.type: Easing.OutBack
								}
							}

							MouseArea {
								id: gridHover

								anchors.fill: parent
								hoverEnabled: true
								onClicked: {
									if (modelData?.path) {
										gridPressAnim.restart();
										Wallpapers.setWallpaper(modelData.path);
									}
								}
							}
						}
					}
				}

					// ---------------- 胶片条视图（2026-09-14 新增） ----------------
					// 对齐 Denial 壁纸选择器的外观：横向一条竖版海报卡片（胶片条）+ 选中项铺底当氛围底图 +
					// 底部胶囊信息条。旧 carousel / grid 视图原样保留，供对比评估后再决定取舍。
					Item {
						id: wallStripView

						visible: root.wallView === "strip"
						// ⚠ 这个 Item 在文本层级上是 wallBody 的直接子级（wallViewport 那段闭合括号的缩进错了一级，
						// 见开发日志 2026-09-14 记录），所以必须显式锚到工具栏下方，和 wallViewport 占同一块区域。
						// 早期写成 anchors.fill: parent 会连工具栏一起盖住 → 工具栏与其上的视图切换按钮看起来"发淡"。
						anchors.top: wallToolbar.bottom
						anchors.topMargin: 6
						anchors.left: parent.left
						anchors.right: parent.right
						anchors.bottom: parent.bottom
						clip: true
						// 面板每次打开也刷一次氛围底图（选中项没变化时不会有 targetPathChanged 信号）
						onVisibleChanged: {
							if (visible)
								stripAmbientTimer.restart();
						}

						// 氛围底图：跟随选中项，压暗后垫在胶片条下面（复刻 Denial 选择器"壁纸铺满、缩略图浮在上面"的观感）。
						// 只按 512×288 解码，不为一张背景图付全尺寸解码成本。
						Image {
							id: stripAmbient

							// 目标路径跟着选中项走，但延迟 140ms 才真正换图：快速滑动时不会每张都解码一遍
							property string targetPath: wallStrip.focusPath
							onTargetPathChanged: stripAmbientTimer.restart()
							anchors.fill: parent
							asynchronous: true
							cache: true
							// 换图期间保留上一帧，避免异步解码那一下闪空白
							retainWhileLoading: true
							fillMode: Image.PreserveAspectCrop
							opacity: 0.3
							source: ""
							sourceSize: Qt.size(512, 288)
						}

						Timer {
							id: stripAmbientTimer

							interval: 140
							repeat: false
							onTriggered: stripAmbient.source = stripAmbient.targetPath !== "" ? "file://" + stripAmbient.targetPath : ""
						}

						Rectangle {
							anchors.fill: parent
							color: Qt.alpha(Colours.tPalette.m3surfaceContainerHigh, 0.78)
						}

						Text {
							anchors.centerIn: parent
							visible: wallStrip.count === 0
							text: "没有匹配的壁纸"
							color: Qt.alpha(M3Palette.m3onSurface, 0.5)
							font.pixelSize: 15
						}

						ListView {
							id: wallStrip

							anchors.top: parent.top
							anchors.left: parent.left
							anchors.right: parent.right
							anchors.bottom: stripCaption.top
							anchors.bottomMargin: 10
							spacing: 6
							clip: true
							orientation: ListView.Horizontal
							interactive: false
							boundsBehavior: Flickable.StopAtBounds
							// 参考 serpantinum WallpaperPicker：固定目标区域，让 ListView 独占滚动动画。
							preferredHighlightBegin: (width - cardBaseWidth * root.stripCenterStretch) / 2
							preferredHighlightEnd: (width + cardBaseWidth * root.stripCenterStretch) / 2
							highlightMoveDuration: root.stripMotionDuration
							highlightMoveVelocity: -1
							highlightRangeMode: ListView.StrictlyEnforceRange
							model: root.wallResults
						// 横向一屏约 4~5 张，缓冲放大一些，左右滑回来不会重新解码
						// 进入壁纸标签后 wallStripPrimed 置位 → 缓冲放大到远超列表长度，等于把整条列表一次性实例化
						// （列表特别大时不做全量渲染，留个安全阀，避免一次性吃掉太多显存）
							readonly property bool stripEager: root.wallStripPrimed && root.wallResults.length <= 400
							cacheBuffer: stripEager ? 200000 : 1400
							currentIndex: 0
							// 所有缩略图统一按“中心卡最大尺寸”解码。这个值只依赖视口尺寸，不依赖 currentIndex：
							// 若 sourceSize 跟 delegate 动画中的 width/height 走，换中心项时旧图与新图会每帧重新解码，
							// 表现为两三张卡先黑一下再出现。
							readonly property int cardBaseHeight: Math.round(height * 0.78)
							readonly property int cardBaseWidth: Math.round(cardBaseHeight * 0.4)
							readonly property size cardDecodeSize: Qt.size(
								Math.max(240, Math.round(cardBaseWidth * root.stripCenterStretch * 1.15)),
								Math.max(360, Math.round(cardBaseHeight * root.stripCenterGrow * 1.15))
							)

							// 选中项路径：氛围底图与底部信息条都读它（用 model + index 取值，不绑 currentItem 防抖动）
							readonly property string focusPath: {
								const m = wallStrip.model;
								const i = wallStrip.currentIndex;
								if (!m || i < 0)
									return "";
								return m[i]?.path ?? "";
							}

						// 不给 contentX 再套 Behavior：宽度重排时叠加缓动会造成两侧反向推挤。

							onCountChanged: {
								for (let i = 0; i < wallStrip.count; ++i) {
									if (wallStrip.model?.[i]?.path === Wallpapers.actualCurrent) {
										wallStrip.currentIndex = i;
										wallStrip.positionViewAtIndex(i, ListView.Center);
										return;
									}
								}
								wallStrip.currentIndex = 0;
								wallStrip.positionViewAtIndex(0, ListView.Center);
							}

							delegate: Item {
								id: stripCard

								required property var modelData
								required property int index

								// 参考图的普通项是窄长卡，选中项不是盖住邻居，而是自身槽位一起变宽、
								// 把左右邻居推开。这样滚动切换时旧卡收窄、新卡展开，才是图里的手风琴效果。
								readonly property int cardHeight: wallStrip.cardBaseHeight
								readonly property int cardWidth: wallStrip.cardBaseWidth
								readonly property int dist: index - wallStrip.currentIndex
								readonly property bool isCenter: dist === 0
								width: Math.round(cardWidth * (isCenter ? root.stripCenterStretch : 1))
								height: wallStrip.height
								z: isCenter ? 2 : 1

								readonly property bool isCurrent: modelData?.path === Wallpapers.actualCurrent
								readonly property bool isSelected: ListView.isCurrentItem
								property string pendingApplyPath: ""

								function confirmApply(): void {
									const path = modelData?.path ?? "";
									if (path === "" || stripApplyAnim.running)
										return;
									pendingApplyPath = path;
									stripApplyTimer.restart();
									stripApplyAnim.restart();
								}

								// 参考图里非中心项只是略暗，不再整体缩放（否则上下基线又会散掉）。
								opacity: stripCard.isSelected ? 1 : 0.82

								Behavior on width {
									NumberAnimation {
										duration: root.stripMotionDuration
										easing.type: Easing.OutCubic
									}
								}
								Behavior on opacity {
									NumberAnimation {
										duration: root.stripMotionDuration
										easing.type: Easing.OutCubic
									}
								}

								Rectangle {
									id: stripFrame

									// 帧填满可变宽槽位；图片仍用 PreserveAspectCrop，所以横向展开显示更多画面，
									// 不会把人物本身拉宽变形。
									x: 0
									width: stripCard.width
									height: Math.round(stripCard.cardHeight * (stripCard.isCenter ? root.stripCenterGrow : 1))
									// 所有卡片共用同一条垂直中心线；中心项只略微向上下同时长高。
									y: Math.round((stripCard.height - height) / 2)
									radius: 8
									clip: true
									// 参考图中每一张卡的两条斜边方向、角度都一致；不再按左右位置镜像或逐级加大。
									transform: Shear {
										origin.x: stripFrame.width / 2
										origin.y: stripFrame.height / 2
										xAngle: root.stripSlant
									}
									Behavior on height {
										NumberAnimation {
											duration: root.stripMotionDuration
											easing.type: Easing.OutCubic
										}
									}
									Behavior on y {
										NumberAnimation {
											duration: root.stripMotionDuration
											easing.type: Easing.OutCubic
										}
									}
									color: Qt.alpha(M3Palette.m3surface, 0.35)
									border.color: (stripHover.containsMouse || stripCard.isSelected || stripCard.isCurrent)
										? M3Palette.m3tertiary
										: Qt.alpha(M3Palette.m3onSurface, 0.12)
									border.width: (stripHover.containsMouse || stripCard.isSelected || stripCard.isCurrent) ? 2 : 1

									// 确认反馈独立于滚动几何动画：小幅压下、柔和描边脉冲，再平滑回位。
									property real pressScale: 1
									property real applyPulse: 0
									scale: stripFrame.pressScale

										Image {
											anchors.fill: parent
											source: modelData?.path ? "file://" + modelData.path : ""
											fillMode: Image.PreserveAspectCrop
											asynchronous: true
											cache: true
											// 固定为中心卡最大解码尺寸，滚动/展开时不触发重新解码；即便视口尺寸真的变化，
											// retainWhileLoading 也会保留上一帧，避免短暂露出黑色帧背景。
											retainWhileLoading: true
											sourceSize: wallStrip.cardDecodeSize
										}

									// 当前壁纸：右上角对勾
									Rectangle {
										visible: stripCard.isCurrent
										width: 22
										height: 22
										radius: 11
										color: M3Palette.m3tertiary
										anchors.top: parent.top
										anchors.right: parent.right
										anchors.margins: 8
										z: 5

										Text {
											anchors.centerIn: parent
											text: "✓"
											color: "#FFFFFF"
											font.pixelSize: 13
											font.bold: true
										}
									}

									// 描边脉冲比大幅缩放更明确，也不会让斜切卡片产生突兀的弹跳。
									Rectangle {
										anchors.fill: parent
										radius: parent.radius
										color: Qt.alpha(M3Palette.m3tertiary, 0.13)
										border.color: Qt.alpha(M3Palette.m3tertiary, 0.85)
										border.width: 2
										opacity: stripFrame.applyPulse
										z: 4
									}
								}

								MouseArea {
									id: stripHover

									// 只覆盖卡片本身：卡片外的空白既不触发 hover 也不响应点击
									anchors.fill: stripFrame
									hoverEnabled: true
									onClicked: {
										stripCard.confirmApply();
									}
								}

								Timer {
									id: stripApplyTimer

									interval: 75
									repeat: false
									onTriggered: {
										if (stripCard.pendingApplyPath !== "") {
											console.info(`[spotlight-wallpaper] set ${stripCard.pendingApplyPath}`);
											Wallpapers.setWallpaper(stripCard.pendingApplyPath);
										}
									}
								}

								ParallelAnimation {
									id: stripApplyAnim

									running: false
									onFinished: stripCard.pendingApplyPath = ""

									SequentialAnimation {
										NumberAnimation {
											target: stripFrame
											property: "pressScale"
											from: 1
											to: 0.975
											duration: 90
											easing.type: Easing.OutCubic
										}
										NumberAnimation {
											target: stripFrame
											property: "pressScale"
											from: 0.975
											to: 1
											duration: 210
											easing.type: Easing.OutQuart
										}
									}

									SequentialAnimation {
										NumberAnimation {
											target: stripFrame
											property: "applyPulse"
											from: 0
											to: 0.72
											duration: 95
											easing.type: Easing.OutCubic
										}
										NumberAnimation {
											target: stripFrame
											property: "applyPulse"
											from: 0.72
											to: 0
											duration: 235
											easing.type: Easing.OutQuart
										}
									}
								}
							}
						}

						// 滚轮：水平滚轮优先（触控板横滑），否则用垂直滚轮，一格一张。
						// 用户实测确认：负向（滚轮向下/横向向左）= 下一张。
						MouseArea {
							visible: root.wallView === "strip"
							anchors.fill: parent
							acceptedButtons: Qt.NoButton
							onWheel: wheel => {
								const delta = wheel.angleDelta.x !== 0 ? wheel.angleDelta.x : wheel.angleDelta.y;
								let idx = wallStrip.currentIndex + (delta < 0 ? 1 : -1);
								idx = Math.max(0, Math.min(idx, wallStrip.count - 1));
								wallStrip.currentIndex = idx;
							}
						}

						// 底部胶囊信息条（对应 Denial 选择器底部控制条的位置）：序号 + 文件名 + 操作提示
						Rectangle {
							id: stripCaption

							anchors.bottom: parent.bottom
							anchors.horizontalCenter: parent.horizontalCenter
							width: Math.min(parent.width - 16, 560)
							height: 40
							radius: 20
							color: Qt.alpha(M3Palette.m3surface, 0.85)
							border.color: Qt.alpha(M3Palette.m3onSurface, 0.14)
							border.width: 1
							clip: true

							// 用路径末段当显示名，不依赖模型条目是否带 name 字段
							readonly property string focusedName: wallStrip.focusPath !== ""
								? wallStrip.focusPath.split("/").pop()
								: ""
							readonly property bool focusedIsCurrent: wallStrip.focusPath !== ""
								&& wallStrip.focusPath === Wallpapers.actualCurrent

							Text {
								id: stripCaptionHint

								anchors.right: parent.right
								anchors.rightMargin: 18
								anchors.verticalCenter: parent.verticalCenter
								text: "← → 选择 · ⏎ 应用"
								color: Qt.alpha(M3Palette.m3onSurface, 0.5)
								font.pixelSize: 12
							}

							Text {
								anchors.left: parent.left
								anchors.leftMargin: 18
								anchors.verticalCenter: parent.verticalCenter
								width: Math.max(80, stripCaption.width - stripCaptionHint.width - 54)
								text: wallStrip.count > 0
									? `${wallStrip.currentIndex + 1}/${wallStrip.count} · ${stripCaption.focusedName}`
									: "没有匹配的壁纸"
								color: stripCaption.focusedIsCurrent ? M3Palette.m3tertiary : M3Palette.m3onSurface
								font.pixelSize: 13
								elide: Text.ElideMiddle
							}
						}
					}
			}

			// ---------------- 剪贴板历史（cliphist） ----------------
			// 2026-09-14 重构（对齐 noctalia 面板的交互，数据源仍是 cliphist）：
			//   左列 = 清空工具条 + 紧凑列表（图片行内 40×40 缩略图、置顶项显示 📌），
			//   右侧 = 预览栏（完整文本 / 大图 + 元信息 + 置顶/复制/删除），
			//   删除与清空走二次确认；中键删除保持即时（沿用旧习惯），右键 = 置顶开关。
			// 字号（2026-09-14 用户反馈"有点小"后统一上调）：列表行 16、预览正文 15、
			// 标题/元信息 13–15、按钮 13–14 —— 要整体再调，改这一段里的 font.pixelSize 即可。
			Item {
				id: clipboardBody

				visible: root.mode === "clipboard"
				width: parent.width
				height: parent.height - input.height - modeHeader.height - parent.spacing * 2

				// 切走或关面板时清掉未决确认框，避免下次打开还挂着旧弹窗
				onVisibleChanged: {
					if (!visible)
						root.clipConfirm = "";
				}

				Text {
					anchors.centerIn: parent
					visible: clipList.count === 0
					text: ClipboardData.busy
						? "读取剪贴板历史…"
						: (ClipboardData.entries.length === 0
							? "剪贴板历史为空（需要 cliphist + wl-paste --watch cliphist store）"
							: "没有匹配的条目")
					color: Qt.alpha(M3Palette.m3onSurface, 0.5)
					font.pixelSize: 15
				}

				Row {
					id: clipColumns

					visible: clipList.count > 0
					anchors.fill: parent
					spacing: 12

					// ---- 左：清空工具条 + 列表 ----
					Item {
						id: clipListPane

						width: Math.round((clipColumns.width - clipColumns.spacing) * 0.56)
						height: clipColumns.height

						Row {
							id: clipToolbar

							width: parent.width
							height: 26
							spacing: 8

							Repeater {
								model: [
									{ kind: "clearUnpinned", label: "清空未置顶" },
									{ kind: "clearAll", label: "清空全部" }
								]

								Rectangle {
									id: clipClearButton

									required property var modelData

									width: clipClearText.implicitWidth + 22
									height: clipToolbar.height
									radius: 8
									color: clipClearArea.containsMouse
										? Qt.alpha(M3Palette.m3error, 0.35)
										: Qt.alpha(M3Palette.m3surface, 0.5)

									Text {
										id: clipClearText

										anchors.centerIn: parent
										text: clipClearButton.modelData.label
										color: M3Palette.m3onSurface
										font.pixelSize: 13
									}

									MouseArea {
										id: clipClearArea

										anchors.fill: parent
										hoverEnabled: true
										onClicked: root.requestClipConfirm(clipClearButton.modelData.kind)
									}
								}
							}

							Text {
								id: clipCountLabel

								anchors.verticalCenter: parent.verticalCenter
								text: `共 ${clipList.count} 条`
								color: Qt.alpha(M3Palette.m3onSurface, 0.5)
								font.pixelSize: 12
							}
						}

						ListView {
							id: clipList

							anchors.top: clipToolbar.bottom
							anchors.topMargin: 6
							anchors.left: parent.left
							anchors.right: parent.right
							anchors.bottom: parent.bottom
							clip: true
							spacing: 4
							model: ClipboardData.query(input.text)
							currentIndex: -1

							onCountChanged: {
								if (currentIndex < 0 && count > 0)
									currentIndex = 0;
								Qt.callLater(() => ClipboardData.ensurePreview(root.selectedClipEntry()));
							}

							// 选中项变了就按需解码预览（图片解大图、文本解完整内容）；解码请求不在绑定里发
							onCurrentIndexChanged: Qt.callLater(() => ClipboardData.ensurePreview(root.selectedClipEntry()))

							delegate: Rectangle {
								id: clipRow
								required property var modelData
								required property int index

								width: clipList.width
								height: 56
								radius: 10
								color: (clipList.currentIndex === clipRow.index || clipRowMouse.containsMouse)
									? Qt.alpha(M3Palette.m3tertiary, 0.22)
									: Qt.alpha(M3Palette.m3surface, 0.3)

								Text {
									id: clipIcon

									anchors.left: parent.left
									anchors.leftMargin: 12
									anchors.verticalCenter: parent.verticalCenter
									visible: !clipRow.modelData.isImage
									text: "📄"
									font.pixelSize: 18
								}

								// 图片条目：40×40 缩略图（大图看右侧预览栏；解码缓存见 ClipboardData.thumbs）
								Image {
									id: clipThumb

									anchors.left: parent.left
									anchors.leftMargin: 8
									anchors.verticalCenter: parent.verticalCenter
									visible: clipRow.modelData.isImage
									width: 40
									height: 40
									source: clipRow.modelData.isImage ? ClipboardData.thumbFor(clipRow.modelData.id) : ""
									sourceSize: Qt.size(128, 128)
									fillMode: Image.PreserveAspectCrop
									asynchronous: true
									cache: false

									Component.onCompleted: {
										if (clipRow.modelData.isImage)
											ClipboardData.requestThumb(clipRow.modelData);
									}
								}

								Text {
									id: clipRowLabel

									anchors.left: clipRow.modelData.isImage ? clipThumb.right : clipIcon.right
									anchors.leftMargin: 10
									anchors.right: clipPinnedMark.visible ? clipPinnedMark.left : parent.right
									anchors.rightMargin: 8
									anchors.verticalCenter: parent.verticalCenter
									text: clipRow.modelData.isImage ? clipRow.modelData.info : clipRow.modelData.preview
									textFormat: Text.PlainText
									elide: Text.ElideRight
									maximumLineCount: 1
									color: M3Palette.m3onSurface
									font.pixelSize: 16
								}

								Text {
									id: clipPinnedMark

									anchors.right: parent.right
									anchors.rightMargin: 10
									anchors.verticalCenter: parent.verticalCenter
									visible: ClipboardData.isPinned(clipRow.modelData)
									text: "📌"
									font.pixelSize: 14
								}

								MouseArea {
									id: clipRowMouse

									anchors.fill: parent
									hoverEnabled: true
									acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
									onEntered: clipList.currentIndex = clipRow.index
									onClicked: mouse => {
										clipList.currentIndex = clipRow.index;
										if (mouse.button === Qt.MiddleButton) {
											// 旧习惯保留：中键即时删除（不弹确认框）
											ClipboardData.remove(clipRow.modelData);
											return;
										}
										if (mouse.button === Qt.RightButton) {
											root.toggleSelectedClipPin();
											return;
										}
										root.copyClipEntry(clipRow.modelData);
									}
								}
							}
						}
					}

					// ---- 右：预览栏（内容 + 元信息 + 操作；布局对齐 noctalia 面板） ----
					Rectangle {
						id: clipPreviewPane

						property var entry: root.selectedClipEntry()
						property bool loading: !!entry
							&& (entry.isImage
								? (ClipboardData.previewBusyId === entry.id && ClipboardData.previewFor(entry.id) === "")
								: (ClipboardData.textBusyId === entry.id && ClipboardData.textFor(entry) === ""))

						width: clipColumns.width - clipListPane.width - clipColumns.spacing
						height: clipColumns.height
						radius: 12
						color: Qt.alpha(M3Palette.m3surface, 0.35)
						border.color: Qt.alpha(M3Palette.m3onSurface, 0.12)
						border.width: 1

						Column {
							id: clipPreviewColumn

							anchors.fill: parent
							anchors.margins: 12
							spacing: 8

							Text {
								id: clipPreviewTitle

								width: parent.width
								height: 20
								text: clipPreviewPane.entry
									? (clipPreviewPane.entry.isImage ? "图片" : "文本")
										+ (ClipboardData.isPinned(clipPreviewPane.entry) ? " · 已置顶 📌" : "")
									: "未选择条目"
								color: Qt.alpha(M3Palette.m3onSurface, 0.75)
								font.pixelSize: 15
								elide: Text.ElideRight
								verticalAlignment: Text.AlignVCenter
							}

							Item {
								id: clipPreviewBody

								width: parent.width
								height: Math.max(0, clipPreviewPane.height - 118)

								Image {
									id: clipPreviewImage

									anchors.fill: parent
									visible: !!clipPreviewPane.entry && clipPreviewPane.entry.isImage
									source: clipPreviewPane.entry && clipPreviewPane.entry.isImage
										? ClipboardData.previewFor(clipPreviewPane.entry.id)
										: ""
									sourceSize: Qt.size(1024, 1024)
									fillMode: Image.PreserveAspectFit
									asynchronous: true
									cache: false
								}

								ScrollView {
									id: clipPreviewScroll

									anchors.fill: parent
									visible: !!clipPreviewPane.entry && !clipPreviewPane.entry.isImage
									clip: true

									Text {
										width: clipPreviewScroll.availableWidth
										text: clipPreviewPane.entry ? ClipboardData.textFor(clipPreviewPane.entry) : ""
										textFormat: Text.PlainText
										wrapMode: Text.WrapAnywhere
										color: M3Palette.m3onSurface
										font.pixelSize: 15
									}
								}

								Text {
									anchors.centerIn: parent
									visible: clipPreviewPane.loading
									text: "解码中…"
									color: Qt.alpha(M3Palette.m3onSurface, 0.45)
									font.pixelSize: 13
								}
							}

							Text {
								id: clipPreviewMeta

								width: parent.width
								height: 18
								text: clipPreviewPane.entry
									? (clipPreviewPane.entry.isImage
										? clipPreviewPane.entry.info
										: `文本 · ${ClipboardData.textFor(clipPreviewPane.entry).length} 字符`)
									: ""
								color: Qt.alpha(M3Palette.m3onSurface, 0.55)
								font.pixelSize: 13
								elide: Text.ElideRight
								verticalAlignment: Text.AlignVCenter
							}

							Row {
								id: clipActionRow

								width: parent.width
								height: 32
								spacing: 8

								Repeater {
									model: ["pin", "copy", "delete"]

									Rectangle {
										id: clipActionButton

										required property string modelData

										width: Math.round((clipActionRow.width - 16) / 3)
										height: clipActionRow.height
										radius: 9
										color: clipActionArea.containsMouse
											? Qt.alpha(M3Palette.m3tertiary, 0.3)
											: Qt.alpha(M3Palette.m3surface, 0.55)

										Text {
											anchors.centerIn: parent
											text: {
												if (clipActionButton.modelData === "pin")
													return ClipboardData.isPinned(clipPreviewPane.entry) ? "取消置顶" : "置顶";
												if (clipActionButton.modelData === "copy")
													return "复制";
												return "删除";
											}
											color: M3Palette.m3onSurface
											font.pixelSize: 14
										}

										MouseArea {
											id: clipActionArea

											anchors.fill: parent
											hoverEnabled: true
											onClicked: {
												const kind = clipActionButton.modelData;
												if (kind === "pin")
													root.toggleSelectedClipPin();
												else if (kind === "copy")
													root.copySelectedClip();
												else
													root.requestClipConfirm("delete");
											}
										}
									}
								}
							}
						}
					}
				}

				// ---- 二次确认浮层（删除单条 / 清空未置顶 / 清空全部） ----
				Rectangle {
					id: clipConfirmCard

					visible: root.clipConfirm !== ""
					anchors.centerIn: parent
					width: Math.min(parent.width - 40, 380)
					height: 116
					radius: 14
					color: Qt.alpha(M3Palette.m3surface, 0.97)
					border.color: Qt.alpha(M3Palette.m3onSurface, 0.2)
					border.width: 1
					z: 10

					Text {
						id: clipConfirmLabel

						anchors.horizontalCenter: parent.horizontalCenter
						anchors.top: parent.top
						anchors.topMargin: 18
						width: parent.width - 32
						horizontalAlignment: Text.AlignHCenter
						wrapMode: Text.WordWrap
						text: {
							if (root.clipConfirm === "delete")
								return "删除这条记录？";
							if (root.clipConfirm === "clearUnpinned")
								return `清空 ${ClipboardData.unpinnedCount()} 条未置顶记录？（置顶的会保留）`;
							if (root.clipConfirm === "clearAll")
								return `清空全部 ${ClipboardData.entries.length} 条记录（含置顶）？`;
							return "";
						}
						color: M3Palette.m3onSurface
						font.pixelSize: 15
					}

					Row {
						id: clipConfirmButtons

						anchors.horizontalCenter: parent.horizontalCenter
						anchors.bottom: parent.bottom
						anchors.bottomMargin: 14
						spacing: 10

						Rectangle {
							id: clipConfirmCancel

							width: 92
							height: 30
							radius: 9
							color: clipCancelArea.containsMouse
								? Qt.alpha(M3Palette.m3onSurface, 0.18)
								: Qt.alpha(M3Palette.m3surface, 0.6)

							Text {
								anchors.centerIn: parent
								text: "取消"
								color: M3Palette.m3onSurface
								font.pixelSize: 14
							}

							MouseArea {
								id: clipCancelArea

								anchors.fill: parent
								hoverEnabled: true
								onClicked: root.clipConfirm = ""
							}
						}

						Rectangle {
							id: clipConfirmOk

							width: 92
							height: 30
							radius: 9
							color: clipOkArea.containsMouse
								? Qt.alpha(M3Palette.m3error, 0.55)
								: Qt.alpha(M3Palette.m3error, 0.35)

							Text {
								anchors.centerIn: parent
								text: "确认"
								color: "#FFFFFF"
								font.pixelSize: 14
							}

							MouseArea {
								id: clipOkArea

								anchors.fill: parent
								hoverEnabled: true
								onClicked: root.confirmClipAction()
							}
						}
					}
				}
			}

			// ---------------- Emoji 选择器 ----------------
			Item {
				id: emojiBody

				visible: root.mode === "emoji"
				width: parent.width
				height: parent.height - input.height - modeHeader.height - parent.spacing * 2

				Text {
					anchors.centerIn: parent
					visible: emojiGrid.count === 0
					text: EmojiData.loaded ? "没有匹配的 Emoji" : "正在载入 Emoji 数据…"
					color: Qt.alpha(M3Palette.m3onSurface, 0.5)
					font.pixelSize: 12
				}

				GridView {
					id: emojiGrid

					anchors.fill: parent
					clip: true
					cellWidth: 58
					cellHeight: 58
					model: EmojiData.query(input.text)
					currentIndex: -1

					onCountChanged: {
						if (currentIndex < 0 && count > 0)
							currentIndex = 0;
					}

					delegate: Rectangle {
						id: emojiCell
						required property var modelData
						required property int index

						width: emojiGrid.cellWidth - 4
						height: emojiGrid.cellHeight - 4
						radius: 10
						color: (emojiGrid.currentIndex === emojiCell.index || emojiCellMouse.containsMouse)
							? Qt.alpha(M3Palette.m3tertiary, 0.25)
							: "transparent"

						Text {
							anchors.centerIn: parent
							text: emojiCell.modelData.emoji
							font.pixelSize: 32
						}

						MouseArea {
							id: emojiCellMouse

							anchors.fill: parent
							hoverEnabled: true
							onEntered: emojiGrid.currentIndex = emojiCell.index
							onClicked: root.copyEmojiEntry(emojiCell.modelData)
						}
					}
				}
			}

		}
			// 拖拽幽灵
		Item {
			id: dragGhost

			width: 56
			height: 56
			visible: root.ghostVisible
			z: 1000

			Rectangle {
				anchors.fill: parent
				radius: 14
				color: Qt.alpha(M3Palette.m3surfaceContainerHigh, 0.96)
				border.color: M3Palette.m3tertiary
				border.width: 1

				IconImage {
					anchors.centerIn: parent
					implicitSize: 34
					source: root.ghostIcon
				}
			}
		}

		// 应用网格的悬浮提示：停 0.6s 后出现在图标上方（位置由 appTipTimer 换算，做左右/上边界夹取）
		Rectangle {
		id: appTip

			visible: root.appTipVisible
			z: 900
			width: Math.min(appTipLabel.implicitWidth + 18, 260)
			height: 26
			radius: 9
			color: Qt.alpha(M3Palette.m3surfaceContainerHigh, 0.97)
			border.color: Qt.alpha(M3Palette.m3onSurface, 0.18)
			border.width: 1
			x: Math.max(6, Math.min(root.appTipX - width / 2, shell.width - width - 6))
			y: Math.max(6, root.appTipY - height - 8)

			Text {
				id: appTipLabel

				anchors.centerIn: parent
				width: parent.width - 12
				text: root.appTipText
				color: M3Palette.m3onSurface
				font.pixelSize: 12
				elide: Text.ElideRight
				horizontalAlignment: Text.AlignHCenter
			}
		}

	// 应用归类菜单（右键图标弹出）：常用开关 + 归类到某分类 + 恢复自动归类
		Rectangle {
			id: appMenu

			visible: root.appMenuVisible
			z: 970
			width: 210
			height: appMenuCol.implicitHeight + 16
			radius: 12
			color: Qt.alpha(M3Palette.m3surfaceContainerHigh, 0.98)
			border.color: Qt.alpha(M3Palette.m3onSurface, 0.18)
			border.width: 1
			x: Math.max(6, Math.min(root.appMenuX, shell.width - width - 6))
			y: Math.max(6, Math.min(root.appMenuY, shell.height - height - 6))

			readonly property var entry: root.appMenuEntry
			readonly property bool isFav: {
				const rev = AppCategories.revision;
				return appMenu.entry ? AppCategories.isFavorite(appMenu.entry) : false;
			}
			readonly property string currentCat: {
				const rev = AppCategories.revision;
				return appMenu.entry ? AppCategories.categoryFor(appMenu.entry) : "";
			}
			readonly property bool hasManual: {
				const rev = AppCategories.revision;
				return appMenu.entry ? AppCategories.assignmentFor(appMenu.entry) !== "" : false;
			}

			Column {
				id: appMenuCol

				anchors.top: parent.top
				anchors.left: parent.left
				anchors.right: parent.right
				anchors.topMargin: 8
				anchors.leftMargin: 8
				anchors.rightMargin: 8
				spacing: 2

				Text {
					width: parent.width
					text: appMenu.entry?.name ?? ""
					color: M3Palette.m3onSurface
					font.pixelSize: 13
					font.bold: true
					elide: Text.ElideRight
				}

				// 「添加到常用」/「从常用移除」
				Rectangle {
					width: parent.width
					height: 30
					radius: 8
					color: favArea.containsMouse ? Qt.alpha(M3Palette.m3primary, 0.28) : "transparent"

					Text {
						anchors.left: parent.left
						anchors.leftMargin: 8
						anchors.verticalCenter: parent.verticalCenter
						text: appMenu.isFav ? "★  从「常用」移除" : "☆  添加到「常用」"
						color: M3Palette.m3onSurface
						font.pixelSize: 12
					}

					MouseArea {
						id: favArea

						anchors.fill: parent
						hoverEnabled: true
						onClicked: root.toggleAppFavorite()
					}
				}

				Rectangle {
					width: parent.width
					height: 1
					color: Qt.alpha(M3Palette.m3onSurface, 0.14)
				}

				Text {
					width: parent.width
					text: "归类到"
					color: Qt.alpha(M3Palette.m3onSurface, 0.55)
					font.pixelSize: 11
				}

				Repeater {
					model: AppCategories.assignableCategories

					delegate: Rectangle {
						id: catRow

						required property var modelData

						width: appMenuCol.width
						height: 28
						radius: 8
						color: catArea.containsMouse ? Qt.alpha(M3Palette.m3primary, 0.22) : "transparent"

						Text {
							anchors.left: parent.left
							anchors.leftMargin: 8
							anchors.verticalCenter: parent.verticalCenter
							text: `${catRow.modelData.label}${appMenu.currentCat === catRow.modelData.id ? "  ✓" : ""}`
							color: appMenu.currentCat === catRow.modelData.id ? M3Palette.m3tertiary : M3Palette.m3onSurface
							font.pixelSize: 12
							font.bold: appMenu.currentCat === catRow.modelData.id
						}

						MouseArea {
							id: catArea

							anchors.fill: parent
							hoverEnabled: true
							onClicked: root.assignAppCategory(catRow.modelData.id)
						}
					}
				}

				// 只有手动归类过才出现
				Rectangle {
					visible: appMenu.hasManual
					width: parent.width
					height: 28
					radius: 8
					color: autoArea.containsMouse ? Qt.alpha(M3Palette.m3primary, 0.22) : "transparent"

					Text {
						anchors.left: parent.left
						anchors.leftMargin: 8
						anchors.verticalCenter: parent.verticalCenter
						text: "↺  恢复自动归类"
						color: Qt.alpha(M3Palette.m3onSurface, 0.85)
						font.pixelSize: 12
					}

					MouseArea {
						id: autoArea

						anchors.fill: parent
						hoverEnabled: true
						onClicked: root.assignAppCategory("")
					}
				}
			}
		}

		// 点菜单以外的地方关闭菜单（放在菜单下层，所以不会吃掉菜单自身的点击）
		MouseArea {
			anchors.fill: parent
			visible: root.appMenuVisible
			z: 960
			onClicked: root.closeAppMenu()
		}
	}

	// ---------------- 数据 ----------------
	// 壁纸选中（carousel 竖排 / grid 网格 / strip 胶片条）当前项定位到“正在用的壁纸”
	function resetWallSelection(): void {
		if (root.wallView === "grid") {
			if (wallGrid.count > 0) {
				for (let i = 0; i < wallGrid.count; ++i) {
					if (wallGrid.model?.[i]?.path === Wallpapers.actualCurrent) {
						wallGrid.currentIndex = i;
						wallGrid.positionViewAtIndex(i, GridView.Center);
						return;
					}
				}
				wallGrid.currentIndex = 0;
			}
		} else if (root.wallView === "strip") {
			if (wallStrip.count > 0) {
				let target = 0;
				for (let i = 0; i < wallStrip.count; ++i) {
					if (wallStrip.model?.[i]?.path === Wallpapers.actualCurrent) {
						target = i;
						break;
					}
				}
				wallStrip.currentIndex = target;
				wallStrip.positionViewAtIndex(target, ListView.Center);
			}
		} else {
			if (wallList.count > 0) {
				for (let i = 0; i < wallList.count; ++i) {
					if (wallList.model?.[i]?.path === Wallpapers.actualCurrent) {
						wallList.currentIndex = i;
						wallList.positionViewAtIndex(i, ListView.Center);
						return;
					}
				}
				wallList.currentIndex = 0;
			}
		}
	}

	// 方向键移动壁纸选中：carousel 只用 dy（上下），grid 用 dx+dy（四向），strip 用 dx（左右，dy 兼容）
	function moveWallSelection(dx: int, dy: int): void {
		if (root.wallView === "grid") {
			const cols = Math.max(1, Math.floor(wallGrid.width / wallGrid.cellWidth));
			const total = wallGrid.count;
			if (total === 0)
				return;
			let idx = wallGrid.currentIndex;
			if (dx !== 0) {
				const row = Math.floor(idx / cols);
				idx += dx;
				idx = Math.max(row * cols, Math.min(idx, Math.min((row + 1) * cols - 1, total - 1)));
			}
			if (dy !== 0) {
				idx += dy * cols;
				idx = Math.max(0, Math.min(idx, total - 1));
			}
			if (idx !== wallGrid.currentIndex) {
				wallGrid.currentIndex = idx;
				wallGrid.positionViewAtIndex(idx, GridView.Contain);
			}
		} else if (root.wallView === "strip") {
			const total = wallStrip.count;
			const step = dx !== 0 ? dx : dy;
			if (total === 0 || step === 0)
				return;
			const next = Math.max(0, Math.min(total - 1, wallStrip.currentIndex + step));
			if (next !== wallStrip.currentIndex) {
				wallStrip.currentIndex = next;
			}
		} else {
			const total = wallList.count;
			if (total === 0)
				return;
			const next = Math.max(0, Math.min(total - 1, wallList.currentIndex + dy));
			if (next !== wallList.currentIndex) {
				wallList.currentIndex = next;
				// Center：保持"中间完整、上下各露半张"的居中 carousel 视图（与滚轮一致）
				wallList.positionViewAtIndex(next, ListView.Center);
			}
		}
	}

	// 回车/确认应用当前选中的壁纸（三种视图各自取当前项）
	function applySelectedWallpaper(): void {
		let entry = null;
		if (root.wallView === "grid") {
			if (wallGrid.count > 0)
				entry = wallGrid.currentItem?.modelData ?? wallGrid.model?.[wallGrid.currentIndex];
		} else if (root.wallView === "strip") {
			if (wallStrip.currentItem?.confirmApply) {
				wallStrip.currentItem.confirmApply();
				return;
			}
			if (wallStrip.count > 0)
				entry = wallStrip.currentItem?.modelData ?? wallStrip.model?.[wallStrip.currentIndex];
		} else if (wallList.count > 0) {
			entry = wallList.currentItem?.modelData ?? wallList.model?.[wallList.currentIndex];
		}
		if (!entry?.path)
			return;
		console.info(`[spotlight-key] wallpaper set ${entry.path}`);
		Wallpapers.setWallpaper(entry.path);
	}

	// ---------------- 剪贴板历史（cliphist） ----------------
	function resetClipSelection(): void {
		if (clipList.count > 0) {
			clipList.currentIndex = 0;
			clipList.positionViewAtIndex(0, ListView.Beginning);
		} else {
			clipList.currentIndex = -1;
		}
	}

	function moveClipSelection(delta: int): void {
		if (clipList.count === 0)
			return;
		if (clipList.currentIndex < 0) {
			clipList.currentIndex = 0;
			return;
		}
		const idx = Math.max(0, Math.min(clipList.currentIndex + delta, clipList.count - 1));
		clipList.currentIndex = idx;
		clipList.positionViewAtIndex(idx, ListView.Contain);
	}

	function copyClipEntry(entry: var): void {
		if (!entry)
			return;
		ClipboardData.copy(entry);
		root.closeRequested();
	}

	function copySelectedClip(): void {
		root.copyClipEntry(clipList.currentItem?.modelData ?? clipList.model?.[clipList.currentIndex]);
	}

	// ---------------- 剪贴板：置顶 / 删除 / 清空 ----------------
	// 统一取「当前选中条目」：委托被回收时 itemAtIndex 会返回 null，退回到 model 下标取数据
	function selectedClipEntry(): var {
		const idx = clipList.currentIndex;
		if (idx < 0 || idx >= clipList.count)
			return null;
		return clipList.itemAtIndex(idx)?.modelData ?? clipList.model?.[idx] ?? null;
	}

	function requestClipConfirm(kind: string): void {
		if (kind === "delete" && !root.selectedClipEntry())
			return;
		root.clipConfirm = kind;
	}

	function confirmClipAction(): void {
		const kind = root.clipConfirm;
		const entry = root.selectedClipEntry();
		root.clipConfirm = "";
		if (kind === "delete") {
			if (!entry)
				return;
			const id = entry.id;
			ClipboardData.remove(entry);
			// 删除后列表整体上移，尽量把相邻的那条继续选中
			Qt.callLater(() => root.selectClipById(id));
		} else if (kind === "clearUnpinned") {
			ClipboardData.clearUnpinned();
			Qt.callLater(root.resetClipSelection);
		} else if (kind === "clearAll") {
			ClipboardData.clearAll();
		}
	}

	function toggleSelectedClipPin(): void {
		const entry = root.selectedClipEntry();
		if (!entry)
			return;
		const id = entry.id;
		const pinned = ClipboardData.togglePin(entry);
		console.info(`[spotlight-clip] ${pinned ? "置顶" : "取消置顶"} id=${id}`);
		// 置顶会让列表重排（置顶块在最前），让同一条尽量保持在选中状态
		Qt.callLater(() => root.selectClipById(id));
	}

	function selectClipById(id: string): void {
		const model = clipList.model;
		if (!model || id === "")
			return;
		for (let i = 0; i < model.length; i++) {
			if (model[i] && model[i].id === id) {
				clipList.currentIndex = i;
				clipList.positionViewAtIndex(i, ListView.Contain);
				return;
			}
		}
	}

	// ---------------- Emoji ----------------
	function resetEmojiSelection(): void {
		if (emojiGrid.count > 0) {
			emojiGrid.currentIndex = 0;
			emojiGrid.positionViewAtIndex(0, GridView.Beginning);
		} else {
			emojiGrid.currentIndex = -1;
		}
	}

	function moveEmojiSelection(dx: int, dy: int): void {
		const total = emojiGrid.count;
		if (total === 0)
			return;
		const cols = Math.max(1, Math.floor(emojiGrid.width / emojiGrid.cellWidth));
		let idx = emojiGrid.currentIndex < 0 ? 0 : emojiGrid.currentIndex;
		if (dx !== 0) {
			const row = Math.floor(idx / cols);
			idx = idx + dx;
			idx = Math.max(row * cols, Math.min(idx, Math.min((row + 1) * cols - 1, total - 1)));
		}
		if (dy !== 0)
			idx = Math.max(0, Math.min(idx + dy * cols, total - 1));
		emojiGrid.currentIndex = idx;
		emojiGrid.positionViewAtIndex(idx, GridView.Contain);
	}

	function copyEmojiEntry(item: var): void {
		if (!item)
			return;
		EmojiData.copy(item);
		root.closeRequested();
	}

	function copySelectedEmoji(): void {
		root.copyEmojiEntry(emojiGrid.currentItem?.modelData ?? emojiGrid.model?.[emojiGrid.currentIndex]);
	}

	function resetAppSelection(): void {
		// 分类视图只有网格一种形态
		if (appGrid.count > 0) {
			appGrid.currentIndex = 0;
			appGrid.positionViewAtIndex(0, GridView.Beginning);
		} else {
			appGrid.currentIndex = -1;
		}
	}

	// 方向键移动应用选中：网格语义（左右换列、上下换行）
	function moveAppSelection(dx: int, dy: int): void {
		root.hideAppTip();
		const cols = Math.max(1, Math.floor(appGrid.width / appGrid.cellWidth));
		const total = appGrid.count;
		if (total === 0)
			return;
		let idx = appGrid.currentIndex < 0 ? 0 : appGrid.currentIndex;
		if (dx !== 0) {
			const row = Math.floor(idx / cols);
			idx = Math.max(row * cols, Math.min(idx + dx, Math.min((row + 1) * cols - 1, total - 1)));
		}
		if (dy !== 0)
			idx = Math.max(0, Math.min(idx + dy * cols, total - 1));
		if (idx !== appGrid.currentIndex) {
			appGrid.currentIndex = idx;
			appGrid.positionViewAtIndex(idx, GridView.Contain);
		}
	}

	function launchSelectedApp(): void {
		const entry = appGrid.count > 0
			? (appGrid.currentItem?.modelData ?? appGrid.model?.[appGrid.currentIndex])
			: null;
		if (!entry)
			return;
		console.info(`[spotlight-key] launch ${entry.name ?? ""}`);
		Apps.launch(entry);
		root.closeRequested();
	}

	function openWebSearch(query: string): void {
		const q = (query ?? "").trim();
		if (!q)
			return;
		const url = root.webSearchBase + encodeURIComponent(q);
		console.info(`[spotlight-web] open ${url}`);
		Quickshell.execDetached(["xdg-open", url]);
		root.closeRequested();
	}

	// 说明：原来这里有两个「即时查询」函数（appResults / wallpaperResults），
	// 现在应用与壁纸的结果都由 syncAppResults / syncWallResults 缓存在 root 上（查询串不变就复用同一数组实例），
	// 避免每次开面板/改输入都产生新数组 → 委托整批重建 → 缩略图与图标重新解码。故删除。
}
