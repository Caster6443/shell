pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// 键位数据：解析 hyprland lua 配置（keybinds.lua + variables.lua）→ JSON
Singleton {
	id: root

	property var data: []

	function reload() {
		fetcher.running = false;
		fetcher.running = true;
	}

	Process {
		id: fetcher

		command: ["python3", Quickshell.shellPath("cheatsheet/fetch_keybinds.py")]
		running: false

		stdout: StdioCollector {
			onStreamFinished: {
				try {
					root.data = JSON.parse(this.text);
				} catch (e) {
					console.warn("Cheatsheet: 键位解析失败", e);
				}
			}
		}
	}

	Component.onCompleted: root.reload()
}
