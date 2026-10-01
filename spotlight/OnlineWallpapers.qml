pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

// Wallhaven 的公开 SFW 列表。只请求 JSON 元数据；预览由 Image 延迟加载，原图仅在应用/收藏时下载。
Singleton {
	id: root

	property var items: []
	property string status: ""
	property bool loading: false
	property bool downloading: false
	property string downloadingId: ""
	property bool favoritingFromCache: false
	property real downloadProgress: 0
	// 由 Spotlight 根据实际视口可容纳的卡片数配置；API 的 per_page 上限为 24。
	property int groupSize: 24
	property int page: 1
	property int lastPage: 1
	property int requestedPage: 1
	property var groupHistory: []
	property int historyIndex: -1
	readonly property bool canGoBack: !root.loading && root.historyIndex > 0
	property string queryText: ""
	property string queuedQuery: "\u0000"
	property int queuedGroupSize: -1
	property string pendingAction: ""
	property var pendingItem: null
	property var savedIds: ({})
	property var cachedIds: ({})
	readonly property string wallpaperDir: `${Quickshell.env("HOME")}/Pictures/Wallpapers`
	readonly property string cacheDir: `${Quickshell.env("XDG_CACHE_HOME") || `${Quickshell.env("HOME")}/.cache`}/caelestia/online-wallpapers`

	function shq(value: string): string {
		return "'" + String(value).replace(/'/g, "'\\''") + "'";
	}

	function isSaved(id: string): bool {
		return !!root.savedIds[id];
	}

	function refresh(searchText: string): void {
		if (root.loading) {
			root.queuedQuery = searchText.trim();
			return;
		}
		root.queryText = searchText.trim();
		root.page = 1;
		root.lastPage = 1;
		root.groupHistory = [];
		root.historyIndex = -1;
		root.fetchPage(1);
	}

	function configureGroupSize(size: int, searchText: string): void {
		const nextSize = Math.max(1, Math.min(24, size));
		if (root.loading) {
			root.queuedGroupSize = nextSize;
			root.queuedQuery = searchText.trim();
			return;
		}
		if (nextSize === root.groupSize) {
			if (root.items.length === 0)
				root.refresh(searchText);
			return;
		}
		root.groupSize = nextSize;
		root.refresh(searchText);
	}

	function nextGroup(searchText: string): void {
		if (root.loading)
			return;
		const query = searchText.trim();
		if (query !== root.queryText) {
			root.refresh(query);
			return;
		}
		if (root.historyIndex < root.groupHistory.length - 1) {
			root.showHistory(root.historyIndex + 1);
			return;
		}
		const nextPage = root.page >= root.lastPage ? 1 : root.page + 1;
		root.fetchPage(nextPage);
	}

	function previousGroup(): void {
		if (root.canGoBack)
			root.showHistory(root.historyIndex - 1);
	}

	function showHistory(index: int): void {
		if (index < 0 || index >= root.groupHistory.length)
			return;
		const entry = root.groupHistory[index];
		root.historyIndex = index;
		root.page = entry.page;
		root.lastPage = entry.lastPage;
		root.items = entry.rows;
		root.status = entry.rows.length > 0
			? `第 ${entry.page}/${entry.lastPage} 组 · ${entry.rows.length} 张`
			: "这一组没有符合条件的图片";
	}

	function fetchPage(targetPage: int): void {
		root.requestedPage = Math.max(1, targetPage);
		root.loading = true;
		root.status = "正在获取网络壁纸…";
		// 用最近一个月的社区热门排序，避免随机抓取低人气、主题不清楚的图片。
		// categories=110 限制为通用壁纸 + 动漫壁纸，不混入人物摄影分类。
		const q = root.queryText === ""
			? "sorting=toplist&topRange=1M"
			: `q=${encodeURIComponent(root.queryText)}&sorting=toplist&topRange=1M`;
		const url = `https://wallhaven.cc/api/v1/search?${q}&purity=100&categories=110&atleast=2560x1440&per_page=${root.groupSize}&page=${root.requestedPage}`;
		fetchProc.command = ["curl", "-fsSL", "--max-time", "30", "-A", "CaelestiaSpotlight/1.0", url];
		fetchProc.running = true;
	}

	function runQueuedSearch(): void {
		const nextSize = root.queuedGroupSize;
		const hasSize = nextSize >= 1;
		root.queuedGroupSize = -1;
		if (root.queuedQuery === "\u0000" && !hasSize)
			return;
		const next = root.queuedQuery === "\u0000" ? root.queryText : root.queuedQuery;
		root.queuedQuery = "\u0000";
		const sizeChanged = hasSize && nextSize !== root.groupSize;
		if (hasSize)
			root.groupSize = nextSize;
		if (sizeChanged || next !== root.queryText)
			Qt.callLater(() => root.refresh(next));
	}

	function parseResults(jsonText: string): var {
		try {
			const parsed = JSON.parse(jsonText);
			if (!Array.isArray(parsed.data))
				return null;
			// 类别、纯净度与最低分辨率由 API 查询参数筛选；这里只验证记录含有图片地址。
			const rows = parsed.data.filter(row =>
				row.purity === "sfw" && row.path && row.thumbs?.large
			).map(row => {
				const ext = (row.file_type || "image/jpeg").split("/").pop().replace(/[^a-z0-9]/gi, "").toLowerCase();
				return {
					id: String(row.id),
					preview: String(row.thumbs.large),
					url: String(row.path),
					resolution: String(row.resolution || `${row.dimension_x}×${row.dimension_y}`),
					ext: ext === "jpeg" ? "jpg" : ext,
					pageUrl: String(row.short_url || row.url || "")
				};
			}).slice(0, root.groupSize);
			return {
				rows: rows,
				lastPage: Math.max(1, Number(parsed.meta?.last_page) || 1)
			};
		} catch (e) {
			return null;
		}
	}

	function startDownload(item: var, action: string): void {
		if (root.downloading || !item || !/^[a-z0-9]+$/i.test(item.id))
			return;
		if (action === "favorite" && root.isSaved(item.id)) {
			root.status = "已收藏到壁纸目录";
			return;
		}
		root.pendingItem = item;
		root.pendingAction = action;
		root.downloading = true;
		root.downloadingId = String(item.id);
		root.favoritingFromCache = action === "favorite" && !!root.cachedIds[item.id];
		root.downloadProgress = 0;
		root.status = action === "favorite"
			? (root.favoritingFromCache ? "正在从缓存收藏…" : "正在下载原图并收藏…")
			: "正在下载并应用…";
		const ext = /^[a-z0-9]+$/i.test(item.ext) ? item.ext : "jpg";
		const targetDir = action === "favorite" ? root.wallpaperDir : root.cacheDir;
		const target = `${targetDir}/wallhaven-${item.id}.${ext}`;
		const cachedSource = `${root.cacheDir}/wallhaven-${item.id}.${ext}`;
		const partial = `${target}.part`;
		const acquire = action === "favorite"
			? `if [ -s ${root.shq(cachedSource)} ]; then cp --reflink=auto -- ${root.shq(cachedSource)} ${root.shq(partial)}; else curl -fL --progress-bar --stderr - --max-time 120 -A 'CaelestiaSpotlight/1.0' -o ${root.shq(partial)} ${root.shq(item.url)}; fi`
			: `curl -fL --progress-bar --stderr - --max-time 120 -A 'CaelestiaSpotlight/1.0' -o ${root.shq(partial)} ${root.shq(item.url)}`;
		const script = `mkdir -p ${root.shq(targetDir)} && if [ -s ${root.shq(target)} ]; then exit 0; fi && rm -f ${root.shq(partial)} && ${acquire} && test -s ${root.shq(partial)} && mv -f ${root.shq(partial)} ${root.shq(target)}`;
		downloadProc.command = ["bash", "-c", script];
		downloadProc.running = true;
	}

	function readDownloadProgress(output: string): void {
		const values = String(output).match(/\d{1,3}(?:\.\d+)?%/g);
		if (!values || values.length === 0)
			return;
		const percent = Number.parseFloat(values[values.length - 1]);
		if (Number.isFinite(percent))
			root.downloadProgress = Math.max(0, Math.min(1, percent / 100));
	}

	Component.onCompleted: {
		loadSaved();
		loadCache();
	}

	function loadSaved(): void {
		loadSavedProc.running = true;
	}

	function loadCache(): void {
		loadCacheProc.running = true;
	}

	Process {
		id: loadSavedProc
		command: ["find", root.wallpaperDir, "-maxdepth", "1", "-type", "f", "-name", "wallhaven-*", "!", "-name", "*.part", "-printf", "%f\\n"]
		stdout: StdioCollector {
			onStreamFinished: {
				const found = {};
				for (const name of String(this.text).split("\n")) {
					const match = name.match(/^wallhaven-([a-z0-9]+)\./i);
					if (match)
						found[match[1]] = true;
				}
				root.savedIds = found;
			}
		}
	}

	Process {
		id: loadCacheProc
		command: ["find", root.cacheDir, "-maxdepth", "1", "-type", "f", "-name", "wallhaven-*", "!", "-name", "*.part", "-printf", "%f\\n"]
		stdout: StdioCollector {
			onStreamFinished: {
				const found = {};
				for (const name of String(this.text).split("\n")) {
					const match = name.match(/^wallhaven-([a-z0-9]+)\./i);
					if (match)
						found[match[1]] = true;
				}
				root.cachedIds = found;
			}
		}
	}

	Process {
		id: fetchProc
		running: false
		stdout: StdioCollector { id: fetchStdout }
		stderr: StdioCollector { id: fetchStderr }
		onExited: (code, exitStatus) => {
			root.loading = false;
			if (code !== 0) {
				const detail = String(fetchStderr.text).trim().replace(/\s+/g, " ").slice(-180);
				root.status = detail ? `网络请求失败：${detail}` : `网络请求失败（curl ${code}）`;
				console.warn(`[spotlight-online-wallpaper] curl exited ${code}: ${detail || "no stderr"}`);
				root.runQueuedSearch();
				return;
			}
			const result = root.parseResults(String(fetchStdout.text));
			if (result === null) {
				root.status = "壁纸服务返回了无法识别的数据";
				console.warn(`[spotlight-online-wallpaper] invalid API response: ${String(fetchStdout.text).slice(0, 180).replace(/\s+/g, " ")}`);
				root.runQueuedSearch();
				return;
			}
			root.items = result.rows;
			root.page = root.requestedPage;
			root.lastPage = result.lastPage;
			const history = root.groupHistory.slice(0, root.historyIndex + 1);
			history.push({ page: root.page, lastPage: root.lastPage, rows: result.rows });
			root.groupHistory = history;
			root.historyIndex = history.length - 1;
			root.status = result.rows.length > 0
				? `第 ${root.page}/${root.lastPage} 组 · ${result.rows.length} 张`
				: "这一组没有符合条件的图片";
			root.runQueuedSearch();
		}
	}

	Process {
		id: downloadProc
		running: false
		stdout: SplitParser {
			splitMarker: "\r"
			onRead: data => root.readDownloadProgress(data)
		}
		onExited: (code, status) => {
			const item = root.pendingItem;
			const action = root.pendingAction;
			root.downloading = false;
			root.downloadingId = "";
			root.favoritingFromCache = false;
			if (code !== 0 || !item) {
				root.downloadProgress = 0;
				root.status = "原图下载失败";
				return;
			}
			const ext = /^[a-z0-9]+$/i.test(item.ext) ? item.ext : "jpg";
			if (action === "favorite") {
				root.savedIds = Object.assign({}, root.savedIds, { [item.id]: true });
				root.status = "已收藏到 ~/Pictures/Wallpapers";
			} else {
				const path = `${root.cacheDir}/wallhaven-${item.id}.${ext}`;
				root.cachedIds = Object.assign({}, root.cachedIds, { [item.id]: true });
				Wallpapers.setWallpaper(path);
				root.status = `已应用 ${item.resolution}`;
			}
		}
	}
}
