pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
	id: root

	readonly property string stateDir: Quickshell.env("XDG_STATE_HOME") || `${Quickshell.env("HOME")}/.local/state`
	property var scheme: ({})
	readonly property bool light: scheme.mode === "light"

	function colour(name: string, fallback: string): color {
		const hex = root.scheme?.colours?.[name];
		return hex ? `#${hex}` : fallback;
	}

	readonly property color m3surface: colour("surface", "#130c0c")
	readonly property color m3surfaceBright: colour("surfaceBright", "#372928")
	readonly property color m3surfaceContainer: colour("surfaceContainer", "#211717")
	readonly property color m3surfaceContainerHigh: colour("surfaceContainerHigh", "#281d1d")
	readonly property color m3surfaceContainerHighest: colour("surfaceContainerHighest", "#302222")
	readonly property color m3surfaceVariant: colour("surfaceVariant", "#302222")
	readonly property color m3onSurface: colour("onSurface", "#f8e0df")
	readonly property color m3onSurfaceVariant: colour("onSurfaceVariant", "#bca6a5")
	readonly property color m3outline: colour("outline", "#847170")
	readonly property color m3outlineVariant: colour("outlineVariant", "#544444")
	readonly property color m3primary: colour("primary", "#f8b6b5")
	readonly property color m3primaryContainer: colour("primaryContainer", "#764545")
	readonly property color m3onPrimaryContainer: colour("onPrimaryContainer", "#ffdbda")
	readonly property color m3secondary: colour("secondary", "#e6bdbc")
	readonly property color m3tertiary: colour("tertiary", "#ffdff4")
	readonly property color m3onTertiaryContainer: colour("onTertiaryContainer", "#67405e")

	FileView {
		id: schemeFile

		path: `${root.stateDir}/caelestia/scheme.json`
		watchChanges: true

		onLoaded: {
			try {
				root.scheme = JSON.parse(text());
			} catch (e) {
				console.warn("Overview Palette: failed to parse scheme.json");
			}
		}
	}
}
