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
	readonly property var categories: ["全部", "表情", "人物", "动物", "食物", "出行", "活动", "物品", "符号", "旗帜", "其他"]

	function query(text: string, category: string): var {
		category = category || "全部";
		const q = String(text ?? "").trim().toLowerCase();
		if (q === "" && category === "全部")
			return root.items;
		const out = [];
		for (const it of root.items) {
			if ((category === "全部" || it.category === category) && (q === "" || it.keywords.includes(q) || it.emoji === q)) {
				out.push(it);
				if (q !== "" && out.length >= root.maxResults)
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
		path: `${Quickshell.shellDir}/console/data/emoji.tsv`
		watchChanges: false
		printErrors: true

		onLoaded: {
			const out = [];
			for (const line of String(text()).split("\n")) {
				if (line === "" || line.startsWith("#"))
					continue;
				const fields = line.split("\t");
                if (fields.length !== 3) continue;
                out.push({ emoji: fields[0], category: fields[1], keywords: fields[2].toLowerCase() });
			}
			root.items = out;
			root.loaded = true;
		}
		onLoadFailed: err => console.warn(`[console-emoji] 数据文件加载失败 err=${err} path=${dataFile.path}`)
	}
}
