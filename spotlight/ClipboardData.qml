pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// 剪贴板历史（cliphist）：数据源是 `cliphist list`（每行 "id\t预览"），
// 复制/删除都走 `cliphist decode|delete` 管道（`cliphist delete` 从 stdin 读条目行）。
//
// 2026-09-14 扩展（对齐 noctalia 面板的交互，数据源保持 cliphist 不变）：
//   - 置顶 pin：cliphist 本身没有 pin 概念，用 sidecar JSON `<state>/caelestia/clip-pins.json` 记 id；
//     `query()` 把置顶项排到最前，「清空未置顶」不碰它们；
//   - 元信息：文本给「字符数/行数」，图片给「格式/尺寸/体积」；
//   - 预览：列表行用小缩略图（images）／截断预览（文本）；
//     选中项的「完整文本」与「大图」**按需解码**并缓存，避免一次性解全表（noctalia 的懒加载思路）。
Singleton {
	id: root

	// [{ raw, id, preview, info, meta, isImage }]
	property var entries: []
	property bool busy: false
	readonly property int maxResults: 300

	// ---------------- 置顶（pin） ----------------
	property var pins: ({})
	readonly property string stateDir: `${Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") || "") + "/.local/state"}/caelestia`
	readonly property string pinsPath: `${root.stateDir}/clip-pins.json`

	function isPinned(entry: var): bool {
		return !!entry && entry.id !== "" && root.pins[entry.id] === true;
	}

	function unpinnedCount(): int {
		let n = 0;
		for (const e of root.entries)
			if (!root.isPinned(e))
				n++;
		return n;
	}

	function togglePin(entry: var): bool {
		if (!entry || entry.id === "")
			return false;
		const next = Object.assign({}, root.pins);
		if (next[entry.id] === true)
			delete next[entry.id];
		else
			next[entry.id] = true;
		root.pins = next;
		root.savePins();
		// 置顶会改变排序（置顶块在最前），用一次浅拷贝触发列表重算
		root.entries = root.entries.slice();
		return next[entry.id] === true;
	}

	function savePins(): void {
		try {
			pinsFile.setText(JSON.stringify(root.pins, null, "\t"));
		} catch (e) {
			console.warn(`[spotlight-clip] 写入置顶列表失败: ${e}`);
		}
		Quickshell.execDetached(["bash", "-c", `mkdir -p ${root.shq(root.stateDir)} && chmod 600 ${root.shq(root.pinsPath)} 2>/dev/null || true`]);
	}

	FileView {
		id: pinsFile

		path: root.pinsPath
		blockWrites: true
		printErrors: false

		onLoaded: {
			try {
				const data = JSON.parse(pinsFile.text());
				if (data && typeof data === "object" && !Array.isArray(data))
					root.pins = data;
			} catch (e) {
				console.warn("[spotlight-clip] 置顶列表解析失败，按空处理");
			}
		}
	}

	Component.onCompleted: pinsFile.reload()

	// ---------------- 列表 ----------------
	function refresh(): void {
		if (listProc.running)
			return;
		root.busy = true;
		listProc.running = true;
	}

	// 过滤 + 置顶优先排序（置顶项内部、非置顶项内部各自保持 cliphist 的原始顺序）
	function query(text: string): var {
		const q = String(text ?? "").trim().toLowerCase();
		const pinned = [];
		const rest = [];
		for (const e of root.entries) {
			if (q !== "" && !e.preview.toLowerCase().includes(q))
				continue;
			(root.isPinned(e) ? pinned : rest).push(e);
		}
		return pinned.concat(rest).slice(0, root.maxResults);
	}

	function shq(s: string): string {
		return "'" + String(s).replace(/'/g, "'\\''") + "'";
	}

	function copy(entry: var): void {
		if (!entry)
			return;
		Quickshell.execDetached(["bash", "-c", `printf '%s' ${root.shq(entry.raw)} | cliphist decode | wl-copy`]);
	}

	function remove(entry: var): void {
		if (!entry)
			return;
		// 先从本地列表里摘掉，避免等下一次 cliphist list 才消失
		root.entries = root.entries.filter(e => e.raw !== entry.raw);
		if (root.pins[entry.id] === true) {
			const next = Object.assign({}, root.pins);
			delete next[entry.id];
			root.pins = next;
			root.savePins();
		}
		root.pruneCaches();
		Quickshell.execDetached(["bash", "-c", `printf '%s' ${root.shq(entry.raw)} | cliphist delete`]);
		refreshTimer.restart();
	}

	// 清空「未置顶」：把未置顶的条目行整体喂给 `cliphist delete`（它的 stdin 接受 list 的行格式）
	function clearUnpinned(): void {
		const doomed = root.entries.filter(e => !root.isPinned(e));
		if (doomed.length === 0)
			return;
		const payload = doomed.map(e => e.raw).join("\n");
		root.entries = root.entries.filter(e => root.isPinned(e));
		root.pruneCaches();
		Quickshell.execDetached(["bash", "-c", `printf '%s\\n' ${root.shq(payload)} | cliphist delete`]);
		refreshTimer.restart();
	}

	// 清空全部：连置顶一起清（确认框里会写明）
	function clearAll(): void {
		root.entries = [];
		root.pins = ({});
		root.thumbs = ({});
		root.previews = ({});
		root.texts = ({});
		root.savePins();
		Quickshell.execDetached(["cliphist", "wipe"]);
		refreshTimer.restart();
	}

	// 丢弃已经不存在的条目的缓存（列表刷新后调用，避免缓存无限增长）
	function pruneCaches(): void {
		const live = ({});
		for (const e of root.entries)
			live[e.id] = true;
		const prune = src => {
			const out = ({});
			for (const id in src)
				if (live[id])
					out[id] = src[id];
			return out;
		};
		root.thumbs = prune(root.thumbs);
		root.previews = prune(root.previews);
		root.texts = prune(root.texts);
	}

	// ---------------- 图片：列表缩略图（小） ----------------
	property var thumbs: ({})
	property var thumbQueue: []
	property string thumbBusyId: ""
	readonly property string thumbDir: `${Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"}/spotlight-clip`

	// 纯函数：命中缓存返回 file:// 路径，否则空串（解码请求由委托在生命周期事件里发，避免绑定循环）
	function thumbFor(id: var): string {
		if (id === undefined || id === "")
			return "";
		const cached = root.thumbs[id];
		if (cached)
			return `file://${cached}`;
		return "";
	}

	function requestThumb(entry: var): void {
		if (!entry || !entry.isImage || entry.id === "")
			return;
		if (root.thumbs[entry.id] || root.thumbBusyId === entry.id)
			return;
		if (root.thumbQueue.some(q => q.id === entry.id))
			return;
		root.thumbQueue = root.thumbQueue.concat([{ id: entry.id, raw: entry.raw }]);
		root.pumpThumbQueue();
	}

	function pumpThumbQueue(): void {
		if (root.thumbBusyId !== "" || root.thumbQueue.length === 0)
			return;
		const next = root.thumbQueue[0];
		root.thumbQueue = root.thumbQueue.slice(1);
		root.thumbBusyId = next.id;
		const path = `${root.thumbDir}/thumb-${next.id}.png`;
		thumbProc.pendingId = next.id;
		thumbProc.pendingPath = path;
		thumbProc.command = [
			"bash", "-c",
			`mkdir -p ${root.shq(root.thumbDir)} && printf '%s' ${root.shq(next.raw)} | cliphist decode > ${root.shq(path)}`
		];
		thumbProc.running = true;
	}

	// ---------------- 图片：右侧预览（大，仅在选中时解码） ----------------
	property var previews: ({})
	property string previewBusyId: ""

	function previewFor(id: var): string {
		if (id === undefined || id === "")
			return "";
		const cached = root.previews[id];
		if (cached)
			return `file://${cached}`;
		return "";
	}

	function requestPreview(entry: var): void {
		if (!entry || entry.isImage !== true || entry.id === "")
			return;
		if (root.previews[entry.id] || root.previewBusyId === entry.id)
			return;
		root.previewBusyId = entry.id;
		const path = `${root.thumbDir}/preview-${entry.id}.png`;
		previewProc.pendingId = entry.id;
		previewProc.pendingPath = path;
		previewProc.command = [
			"bash", "-c",
			`mkdir -p ${root.shq(root.thumbDir)} && printf '%s' ${root.shq(entry.raw)} | cliphist decode > ${root.shq(path)}`
		];
		previewProc.running = true;
	}

	// ---------------- 文本：右侧预览（完整内容，仅在选中时解码） ----------------
	// 列表里的 preview 被 cliphist 截到 100 字符（-preview-width），要完整内容得 decode 一次。
	property var texts: ({})
	property string textBusyId: ""

	function textFor(entry: var): string {
		if (!entry || entry.isImage || entry.id === "")
			return "";
		return root.texts[entry.id] ?? "";
	}

	function requestText(entry: var): void {
		if (!entry || entry.isImage || entry.id === "")
			return;
		if (root.texts[entry.id] !== undefined || root.textBusyId === entry.id)
			return;
		root.textBusyId = entry.id;
		textProc.pendingId = entry.id;
		textProc.command = ["bash", "-c", `printf '%s' ${root.shq(entry.raw)} | cliphist decode | head -c 262144`];
		textProc.running = true;
	}

	// 选中项变了就按需解码（图片走大图，文本走完整内容）
	function ensurePreview(entry: var): void {
		if (!entry)
			return;
		if (entry.isImage)
			root.requestPreview(entry);
		else
			root.requestText(entry);
	}

	Timer {
		id: refreshTimer

		interval: 250
		onTriggered: root.refresh()
	}

	Process {
		id: listProc

		command: ["cliphist", "list"]
		running: false

		stdout: StdioCollector {
			onStreamFinished: {
				const out = [];
				const lines = String(this.text).split("\n");
				for (const line of lines) {
					if (line === "")
						continue;
					const tab = line.indexOf("\t");
					const preview = tab >= 0 ? line.slice(tab + 1) : line;
					// 图片条目预览形如 "[[ binary data 974 KiB png 1741x481 ]]" → 提成 "PNG 1741×481 · 974 KiB"
					const m = /binary data\s+(.+?)\s+(\w+)\s+(\d+)x(\d+)/.exec(preview);
					const isImage = /\[\[.*binary data.*\d+x\d+.*\]\]/.test(preview);
					const info = m ? `${m[2].toUpperCase()} ${m[3]}×${m[4]} · ${m[1]}` : "";
					out.push({
						raw: line,
						id: tab >= 0 ? line.slice(0, tab) : "",
						preview: preview,
						info: info,
						isImage: isImage,
						meta: isImage ? info : `文本 · ${preview.length} 字符`,
					});
				}
				root.entries = out;
				root.busy = false;
				root.pruneCaches();
			}
		}
	}

	Process {
		id: thumbProc

		property string pendingId: ""
		property string pendingPath: ""

		running: false

		onExited: (code, status) => {
			if (code === 0 && thumbProc.pendingId !== "" && thumbProc.pendingPath !== "") {
				const next = Object.assign({}, root.thumbs);
				next[thumbProc.pendingId] = thumbProc.pendingPath;
				root.thumbs = next;
			}
			root.thumbBusyId = "";
			root.pumpThumbQueue();
		}
	}

	Process {
		id: previewProc

		property string pendingId: ""
		property string pendingPath: ""

		running: false

		onExited: (code, status) => {
			if (code === 0 && previewProc.pendingId !== "" && previewProc.pendingPath !== "") {
				const next = Object.assign({}, root.previews);
				next[previewProc.pendingId] = previewProc.pendingPath;
				root.previews = next;
			}
			root.previewBusyId = "";
		}
	}

	Process {
		id: textProc

		property string pendingId: ""
		property string pendingText: ""

		running: false

		stdout: StdioCollector {
			onStreamFinished: textProc.pendingText = String(this.text)
		}

		onExited: (code, status) => {
			if (code === 0 && textProc.pendingId !== "") {
				const next = Object.assign({}, root.texts);
				next[textProc.pendingId] = textProc.pendingText;
				root.texts = next;
			}
			root.textBusyId = "";
		}
	}
}
