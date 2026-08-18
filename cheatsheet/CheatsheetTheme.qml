pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
	id: root

	readonly property string stateDir: Quickshell.env("XDG_STATE_HOME") || `${Quickshell.env("HOME")}/.local/state`
	property var scheme: ({})

	function colour(name: string, fallback: string): color {
		const hex = root.scheme?.colours?.[name];
		return hex ? `#${hex}` : fallback;
	}

	readonly property color background: colour("surfaceContainerLow", "#1e1e2e")
	readonly property color surface: colour("surface", "#11111b")
	readonly property color onSurface: colour("onSurface", "#cdd6f4")
	readonly property color onSurfaceVariant: colour("onSurfaceVariant", "#a6adc8")
	readonly property color primary: colour("primary", "#89b4fa")
	readonly property color outline: colour("outline", "#6c7086")

	FileView {
		id: schemeFile

		path: `${root.stateDir}/caelestia/scheme.json`
		watchChanges: true

		onLoaded: {
			try {
				root.scheme = JSON.parse(text());
			} catch (e) {
				console.warn("Cheatsheet theme: scheme.json 解析失败");
			}
		}
	}
}
