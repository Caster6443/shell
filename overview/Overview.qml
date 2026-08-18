pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.overview

// Entry point of the overview addon. Instantiate this once in shell.qml.
// It creates its own overlay window and hot corner, and exposes an IPC
// target ("overview") so Hyprland can toggle it:
//   qs -c caelestia ipc call overview toggle
Item {
	id: root

	OverviewWindow {}

	HotCorner {}

	IpcHandler {
		target: "overview"

		function toggle(): void {
			OverviewState.active = !OverviewState.active;
		}

		function open(): void {
			OverviewState.active = true;
		}

		function close(): void {
			OverviewState.active = false;
		}

		function setVisible(visible: bool): void {
			OverviewState.active = visible;
		}
	}
}
