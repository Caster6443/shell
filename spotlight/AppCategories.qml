pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// 应用分类数据层（2026-09-14 随 spotlight 应用标签改版新增）
//
// 分类来源三层，优先级从高到低：
//   1) 手动归类：右键图标「归类到 X」写入 sidecar JSON，覆盖自动判断；
//   2) 常用：右键图标「添加到常用」手动收藏（刻意不把 caelestia 的启动频次混进来，避免列表自己变）；
//   3) 自动：读 .desktop 的 Categories（freedesktop 主分类 + 附加分类），按 autoRules 的顺序命中第一个。
//
// 存储：`<XDG_STATE_HOME>/caelestia/app-categories.json`，形如
//   { "favorites": ["kitty.desktop"], "assign": { "code.desktop": "development" } }
// 与剪贴板置顶（clip-pins.json）同一套做法：FileView + blockWrites + chmod 600。
Singleton {
	id: root

	// ---------------- 分类定义（胶囊按这个顺序排） ----------------
	readonly property var categories: [
		{
			"id": "all",
			"label": "全部"
		},
		{
			"id": "favorite",
			"label": "常用"
		},
		{
			"id": "development",
			"label": "开发"
		},
		{
			"id": "graphics",
			"label": "图形"
		},
		{
			"id": "media",
			"label": "影音"
		},
		{
			"id": "game",
			"label": "游戏"
		},
		{
			"id": "office",
			"label": "办公"
		},
		{
			"id": "internet",
			"label": "网络"
		},
		{
			"id": "system",
			"label": "系统"
		},
		{
			"id": "settings",
			"label": "设置"
		},
		{
			"id": "tools",
			"label": "工具"
		},
		{
			"id": "other",
			"label": "其他"
		}
	]

	// 可手动归类的分类（"全部"与"常用"不参与归类）
	readonly property var assignableCategories: root.categories.filter(c => c.id !== "all" && c.id !== "favorite")

	// 自动归类规则：顺序即优先级（靠前的先命中）；keys 是 .desktop 里的分类名。
	// 2026-09-14 按用户实际安装的 168 个可见条目调过一轮：原来的 system 规则把 Utility/Settings 全兜进去
	// （73 个应用挤一个标签），所以拆成 系统 / 设置 / 工具 三个；同时把 Emulator 从游戏规则里去掉，
	// 免得 Boxes / virt-manager 这类虚拟机工具被划进游戏。
	readonly property var autoRules: [
		{
			"id": "game",
			"keys": ["Game", "ActionGame", "AdventureGame", "ArcadeGame", "BoardGame", "BlocksGame", "CardGame", "KidsGame", "LogicGame", "RolePlaying", "Shooter", "Simulation", "SportsGame", "StrategyGame"]
		},
		{
			"id": "settings",
			"keys": ["Settings", "DesktopSettings", "HardwareSettings", "LoginManager", "X-GNOME-PersonalSettings", "X-XFCE-SettingsDialog", "X-XFCE-PersonalSettings", "X-GNOME-SettingsDialog"]
		},
		{
			"id": "office",
			"keys": ["Office", "WordProcessor", "Spreadsheet", "Presentation", "Calculator", "Finance", "FlowChart", "ProjectManagement", "Calendar", "ContactManagement", "Dictionary", "Chart"]
		},
		{
			"id": "development",
			"keys": ["Development", "IDE", "Debugger", "Profiling", "RevisionControl", "Building", "GUIDesigner", "Translation", "TextEditor", "WebDevelopment", "Database"]
		},
		{
			"id": "graphics",
			"keys": ["Graphics", "2DGraphics", "3DGraphics", "VectorGraphics", "RasterGraphics", "Photography", "Scanning", "Publishing", "Viewer"]
		},
		{
			"id": "media",
			"keys": ["AudioVideo", "Audio", "Video", "Music", "Player", "Recorder", "Midi", "TV", "AudioVideoEditing"]
		},
		{
			"id": "internet",
			"keys": ["Network", "WebBrowser", "Email", "InstantMessaging", "Chat", "IRCClient", "FileTransfer", "P2P", "Feed", "VideoConference", "Telephony", "RemoteAccess"]
		},
		{
			"id": "tools",
			"keys": ["Utility", "TerminalEmulator", "FileManager", "FileTools", "X-GNOME-Utilities", "Archiving", "Compression", "Filesystem", "ConsoleOnly", "Emulator"]
		},
		{
			"id": "system",
			"keys": ["System", "Monitor", "Security", "PackageManager", "Accessibility", "Printing", "Clock"]
		}
	]

	// ---------------- 存储 ----------------
	readonly property string stateDir: `${Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") || "") + "/.local/state"}/caelestia`
	readonly property string storePath: `${root.stateDir}/app-categories.json`
	property var favorites: []
	property var assignments: ({})
	// 每个分类的手动顺序：categoryId -> [entryId]（拖动排序写入；没记录的项排在后面）
	property var order: ({})
	// 每次改动 +1：QML 无法追踪 JS 函数内部的属性读取，面板侧把 revision 当显式依赖
	property int revision: 0

	// 由面板塞进来的完整应用列表（DesktopEntry 数组）
	property var allApps: []

	// id → .desktop 的 Categories（自己扫文件得到；见 scan-app-categories.sh 顶部注释说明为什么不用对象属性）
	property var scannedCategories: ({})
	// id → .desktop 的中英文本搜索字段（默认值 + 所有 Name[locale]/GenericName/Keywords/Comment）
	property var scannedSearchText: ({})

	function shq(s: string): string {
		return `'${String(s).replace(/'/g, "'\\''")}'`;
	}

	function entryId(entry: var): string {
		return entry?.id ?? "";
	}

	function isFavorite(entry: var): bool {
		const id = root.entryId(entry);
		return id !== "" && root.favorites.indexOf(id) >= 0;
	}

	// 返回切换后的状态（true = 现在在常用里）
	function toggleFavorite(entry: var): bool {
		const id = root.entryId(entry);
		if (id === "")
			return false;
		const next = root.favorites.slice();
		const at = next.indexOf(id);
		if (at >= 0)
			next.splice(at, 1);
		else
			next.unshift(id);
		root.favorites = next;
		root.save();
		root.revision++;
		return at < 0;
	}

	// 按记录的顺序重排；没记录的项保持原有相对顺序、排在最后
	function applyOrder(list: var, ids: var): var {
		const pos = ({});
		for (let i = 0; i < ids.length; ++i)
			pos[ids[i]] = i;
		return list.slice().sort((a, b) => {
			const pa = pos[a?.id ?? ""] ?? Number.MAX_SAFE_INTEGER;
			const pb = pos[b?.id ?? ""] ?? Number.MAX_SAFE_INTEGER;
			return pa - pb;
		});
	}

	// 拖动排序：存某一分类的完整 id 顺序（存全量，便于以后增删应用时行为可预测）
	function setCategoryOrder(categoryId: string, ids: var): void {
		const next = Object.assign({}, root.order);
		next[categoryId] = ids.slice();
		root.order = next;
		root.save();
		root.revision++;
	}

	function assignmentFor(entry: var): string {
		return root.assignments[root.entryId(entry)] ?? "";
	}

	// categoryId 传 "" 或 "auto" = 清除手动归类，回到自动判断
	function assign(entry: var, categoryId: string): void {
		const id = root.entryId(entry);
		if (id === "")
			return;
		const next = Object.assign({}, root.assignments);
		if (categoryId === "" || categoryId === "auto")
			delete next[id];
		else
			next[id] = categoryId;
		root.assignments = next;
		root.save();
		root.revision++;
	}

	// 取一个应用的 Categories；统一成字符串数组。
	// 优先用自己扫出来的结果（运行时读 entry.categories 实测为空 → 所有应用都会落进「其他」），
	// 扫不到时再退回对象属性。
	function categoryTokens(entry: var): var {
		const scanned = root.scannedCategories[root.entryId(entry)] ?? "";
		if (scanned !== "")
			return String(scanned).split(";").filter(s => s !== "");
		const raw = entry?.categories;
		if (raw === undefined || raw === null)
			return [];
		if (Array.isArray(raw))
			return raw.map(x => String(x));
		return String(raw).split(";").filter(s => s !== "");
	}

	// 扫 .desktop 的结果解析成 map（首行胜出，与脚本输出顺序一致）
	function applyScan(text: string): void {
		const categoryMap = ({});
		const searchMap = ({});
		for (const line of String(text ?? "").split("\n")) {
			if (line === "")
				continue;
			const firstTab = line.indexOf("\t");
			if (firstTab <= 0)
				continue;
			const secondTab = line.indexOf("\t", firstTab + 1);
			const id = line.slice(0, firstTab);
			if (categoryMap[id] !== undefined)
				continue;
			categoryMap[id] = secondTab < 0 ? line.slice(firstTab + 1) : line.slice(firstTab + 1, secondTab);
			searchMap[id] = secondTab < 0 ? "" : line.slice(secondTab + 1);
		}
		root.scannedCategories = categoryMap;
		root.scannedSearchText = searchMap;
		root.revision++;
		console.info(`[spotlight-apps] 已扫描 ${Object.keys(categoryMap).length} 个 .desktop 的分类与中英搜索字段`);
	}

	function searchableText(entry: var): string {
		const id = root.entryId(entry);
		const fields = [
			id,
			entry?.name,
			entry?.genericName,
			entry?.comment,
			entry?.keywords,
			entry?.startupClass,
			entry?.execString,
			root.scannedSearchText[id]
		];
		return fields.filter(v => v !== undefined && v !== null).map(v => String(v)).join(" ").toLocaleLowerCase();
	}

	// 只过滤传入的分类列表；空格分隔的多个词必须全部命中，但可以落在不同字段中。
	function searchIn(list: var, query: string): var {
		const words = String(query ?? "").trim().toLocaleLowerCase().split(/\s+/).filter(w => w !== "");
		if (words.length === 0)
			return list;
		return list.filter(entry => {
			const haystack = root.searchableText(entry);
			return words.every(word => haystack.indexOf(word) >= 0);
		});
	}

	// 分类结果快照日志：只在内容变化时打一行，方便排查"某分类是空的"
	property string lastBucketLog: ""
	function logBuckets(map: var): void {
		const parts = [];
		for (const c of root.categories)
			parts.push(`${c.label}:${map[c.id] ? map[c.id].length : 0}`);
		const line = parts.join(" ");
		if (line !== root.lastBucketLog) {
			root.lastBucketLog = line;
			console.info(`[spotlight-apps] 分类结果：${line}`);
		}
	}

	function autoCategory(entry: var): string {
		const tokens = root.categoryTokens(entry);
		for (const rule of root.autoRules) {
			for (const k of rule.keys) {
				if (tokens.indexOf(k) >= 0)
					return rule.id;
			}
		}
		return "other";
	}

	function categoryFor(entry: var): string {
		const manual = root.assignmentFor(entry);
		return manual !== "" ? manual : root.autoCategory(entry);
	}

	function labelFor(categoryId: string): string {
		for (const c of root.categories) {
			if (c.id === categoryId)
				return c.label;
		}
		return "其他";
	}

	// 分类 → 应用数组。读取 revision 作显式依赖，收藏/归类一变整张表重算。
	readonly property var buckets: {
		const rev = root.revision;
		const map = ({});
		for (const c of root.categories)
			map[c.id] = [];
		for (const e of root.allApps) {
			map.all.push(e);
			if (root.isFavorite(e))
				map.favorite.push(e);
			const cat = root.categoryFor(e);
			if (map[cat])
				map[cat].push(e);
		}
		// 套用各分类的手动顺序
		for (const c of root.categories) {
			const ord = root.order[c.id];
			if (ord && ord.length > 0)
				map[c.id] = root.applyOrder(map[c.id], ord);
		}
		root.logBuckets(map);
		return map;
	}

	function appsIn(categoryId: string): var {
		return root.buckets[categoryId] ?? [];
	}

	function countIn(categoryId: string): int {
		return root.buckets[categoryId]?.length ?? 0;
	}

	function save(): void {
		try {
			storeFile.setText(JSON.stringify({
				"favorites": root.favorites,
				"assign": root.assignments,
				"order": root.order
			}, null, "\t"));
		} catch (e) {
			console.warn(`[spotlight-apps] 写入分类存储失败: ${e}`);
		}
		Quickshell.execDetached(["bash", "-c", `mkdir -p ${root.shq(root.stateDir)} && chmod 600 ${root.shq(root.storePath)} 2>/dev/null || true`]);
	}

	FileView {
		id: storeFile

		path: root.storePath
		blockWrites: true
		printErrors: false

		onLoaded: {
			try {
				const data = JSON.parse(storeFile.text());
				if (data && typeof data === "object") {
					if (Array.isArray(data.favorites))
						root.favorites = data.favorites.map(x => String(x));
					if (data.assign && typeof data.assign === "object" && !Array.isArray(data.assign))
						root.assignments = data.assign;
					if (data.order && typeof data.order === "object" && !Array.isArray(data.order))
						root.order = data.order;
					root.revision++;
					console.info(`[spotlight-apps] 分类存储已加载：常用 ${root.favorites.length} 条，手动归类 ${Object.keys(root.assignments).length} 条`);
				}
			} catch (e) {
				console.warn("[spotlight-apps] 分类存储解析失败，按空处理");
			}
		}
	}

	// 扫 .desktop 拿 Categories（见同目录 scan-app-categories.sh）
	Process {
		id: scanProc

		command: ["bash", `${Quickshell.shellDir}/spotlight/scan-app-categories.sh`]
		stdout: StdioCollector {
			onStreamFinished: root.applyScan(text)
		}
	}

	Component.onCompleted: {
		storeFile.reload();
		scanProc.running = true;
	}
}
