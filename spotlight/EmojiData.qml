pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Emoji 数据：每行 "<emoji> <关键词…>"，关键词用于模糊搜索（子串匹配，忽略大小写）。
// 数据文件 data/emoji.tsv 来自 end-4/dots-hyprland（GPL-3.0）的 fuzzel-emoji.sh 内嵌 DATA 段。
Singleton {
	id: root

	// [{ emoji, keywords }]
	property var items: []
	property bool loaded: false
	readonly property int maxResults: 400

	function query(text: string): var {
		const q = String(text ?? "").trim().toLowerCase();
		if (q === "")
			return root.items;
		const out = [];
		for (const it of root.items) {
			if (it.keywords.includes(q) || it.emoji === q) {
				out.push(it);
				if (out.length >= root.maxResults)
					break;
			}
		}
		return out;
	}

	function copy(item: var): void {
		if (!item)
			return;
		Quickshell.clipboardText = item.emoji;
	}

	// 数据只在 singleton 首次创建时读一次（约 1900 行 / 60KB）
	FileView {
		id: dataFile

		// 用 shellDir 拼绝对路径：singleton 里的 Qt.resolvedUrl 基准不可靠（实测加载不到）
		path: `${Quickshell.shellDir}/spotlight/data/emoji.tsv`
		watchChanges: false
		printErrors: true

		onLoaded: {
			const out = [];
			for (const line of String(text()).split("\n")) {
				if (line === "" || line.startsWith("#"))
					continue;
				const sp = line.indexOf(" ");
				if (sp <= 0)
					continue;
				out.push({
					emoji: line.slice(0, sp),
					keywords: line.slice(sp + 1).toLowerCase()
				});
			}
			root.items = out;
			root.loaded = true;
		}
		onLoadFailed: err => console.warn(`[spotlight-emoji] 数据文件加载失败 err=${err} path=${dataFile.path}`)
	}
}
