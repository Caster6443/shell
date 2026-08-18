pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// 动态配色：跟随 caelestia 的 scheme.json（壁纸/配色切换时实时更新）。
// 与旧版一致：cat 读取 + 可手动 reload（每次打开 cheatsheet 时刷新），
// 另加 FileView 监听保证写入即更新。
Singleton {
	id: root

	readonly property string stateDir: Quickshell.env("XDG_STATE_HOME") || `${Quickshell.env("HOME")}/.local/state`
	property var themeColours: ({})

	function colour(name: string, fallback: string): color {
		const hex = root.themeColours?.[name];
		return hex ? `#${hex}` : fallback;
	}

	function reload() {
		fetcher.running = false;
		fetcher.running = true;
	}

	readonly property color background: colour("crust", colour("surfaceContainerLow", "#0b0d11"))
	readonly property color surface: colour("surface", "#11111b")
	readonly property color textColor: colour("onSurface", colour("text", "#cdd6f4"))
	readonly property color primary: colour("primary", "#89b4fa")

	Process {
		id: fetcher

		command: ["cat", root.stateDir + "/caelestia/scheme.json"]
		running: false

		stdout: StdioCollector {
			onStreamFinished: {
				try {
					root.themeColours = JSON.parse(this.text).colours ?? {};
				} catch (e) {
					console.warn("Cheatsheet theme: scheme.json 解析失败");
				}
			}
		}
	}

	FileView {
		id: watcher

		path: root.stateDir + "/caelestia/scheme.json"
		watchChanges: true

		onLoaded: {
			try {
				root.themeColours = JSON.parse(text()).colours ?? {};
			} catch (e) {
				console.warn("Cheatsheet theme: scheme.json 解析失败");
			}
		}
	}

	Component.onCompleted: reload()
}
