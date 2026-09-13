pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// 剪贴板历史（cliphist）：数据源是 `cliphist list`（每行 "id\t预览"），
// 复制/删除都走 `cliphist decode|delete` 管道（`cliphist delete` 从 stdin 读条目行）。
Singleton {
	id: root

	// [{ raw, id, preview, isImage }]
	property var entries: []
	property bool busy: false
	readonly property int maxResults: 300

	// 图片条目的缩略图缓存：id -> 解码后的临时文件路径（顺序解码，一次一个进程）
	property var thumbs: ({})
	property var thumbQueue: []
	property string thumbBusyId: ""
	readonly property string thumbDir: `${Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"}/spotlight-clip`

	function refresh(): void {
		if (listProc.running)
			return;
		root.busy = true;
		listProc.running = true;
	}

	function query(text: string): var {
		const q = String(text ?? "").trim().toLowerCase();
		if (q === "")
			return root.entries.slice(0, root.maxResults);
		const out = [];
		for (const e of root.entries) {
			if (e.preview.toLowerCase().includes(q)) {
				out.push(e);
				if (out.length >= root.maxResults)
					break;
			}
		}
		return out;
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
		const kept = root.entries.filter(e => e.raw !== entry.raw);
		root.entries = kept;
		Quickshell.execDetached(["bash", "-c", `printf '%s' ${root.shq(entry.raw)} | cliphist delete`]);
		refreshTimer.restart();
	}

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
		const path = `${root.thumbDir}/${next.id}.png`;
		thumbProc.pendingId = next.id;
		thumbProc.pendingPath = path;
		thumbProc.command = [
			"bash", "-c",
			`mkdir -p ${root.shq(root.thumbDir)} && printf '%s' ${root.shq(next.raw)} | cliphist decode > ${root.shq(path)}`
		];
		thumbProc.running = true;
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
					out.push({
						raw: line,
						id: tab >= 0 ? line.slice(0, tab) : "",
						preview: preview,
						info: m ? `${m[2].toUpperCase()} ${m[3]}×${m[4]} · ${m[1]}` : "",
						isImage: /\[\[.*binary data.*\d+x\d+.*\]\]/.test(preview)
					});
				}
				root.entries = out;
				root.busy = false;
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
}
