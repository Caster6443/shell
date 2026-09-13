pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// 跟随 caelestia scheme.json 的动态配色（与 cheatsheet 外挂同款做法）
Singleton {
	id: root

	readonly property string stateDir: Quickshell.env("XDG_STATE_HOME") || `${Quickshell.env("HOME")}/.local/state`
	property var themeColours: ({})

	function colour(name: string, fallback: string): color {
		const hex = root.themeColours?.[name];
		return hex ? `#${hex}` : fallback;
	}

	function reload(): void {
		fetcher.running = false;
		fetcher.running = true;
	}

	readonly property color background: colour("surfaceContainerLow", "#11111b")
	readonly property color surface: colour("surfaceContainerHigh", "#1e1e2e")
	readonly property color textColor: colour("onSurface", "#cdd6f4")
	readonly property color muted: Qt.alpha(textColor, 0.55)
	readonly property color primary: colour("primary", "#89b4fa")
	readonly property color onPrimary: colour("onPrimary", "#11111b")
	readonly property color error: colour("error", "#f38ba8")

	// 面板字号统一缩放。原始设计偏小（用户反馈 2026-09-10），面板里所有 font.pixelSize
	// 都写成 `AiChatTheme.fs(原始值)`，实际大小 = 原始值 × fontScale。
	// 想再调：改 ~/.config/caelestia/aichat.json 里的 "fontScale"（重启 shell 生效）。
	readonly property real fontScale: AiChatService.fontScale

	function fs(base: real): real {
		return Math.round(base * root.fontScale);
	}

	Process {
		id: fetcher

		command: ["cat", `${root.stateDir}/caelestia/scheme.json`]
		running: false

		stdout: StdioCollector {
			onStreamFinished: {
				try {
					root.themeColours = JSON.parse(this.text).colours ?? {};
				} catch (e) {
					// 读不到就继续用默认色
				}
			}
		}
	}
}
