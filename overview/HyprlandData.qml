pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

Item {
	id: root

	property var windowList: []
	property var workspaces: []
	property var activeWorkspace: null

	function updateAll() {
		getClients.running = true;
		getWorkspaces.running = true;
		getActiveWorkspace.running = true;
	}

	Component.onCompleted: updateAll()

	Connections {
		target: Hyprland
		function onRawEvent(event) {
			if (["openlayer", "closelayer", "screencast", "activemon"].includes(event.name))
				return;
			updateAll();
		}
	}

	Process {
		id: getClients
		command: ["hyprctl", "clients", "-j"]
		running: false
		stdout: StdioCollector {
			onStreamFinished: {
				try {
					root.windowList = JSON.parse(this.text);
				} catch (e) {
					console.warn("HyprlandData: Failed to parse clients JSON");
				}
			}
		}
	}

	Process {
		id: getWorkspaces
		command: ["hyprctl", "workspaces", "-j"]
		running: false
		stdout: StdioCollector {
			onStreamFinished: {
				try {
					var raw = JSON.parse(this.text);
					root.workspaces = raw.filter(function(ws) { return ws.id >= 1 && ws.id <= 100; });
				} catch (e) {
					console.warn("HyprlandData: Failed to parse workspaces JSON");
				}
			}
		}
	}

	Process {
		id: getActiveWorkspace
		command: ["hyprctl", "activeworkspace", "-j"]
		running: false
		stdout: StdioCollector {
			onStreamFinished: {
				try {
					root.activeWorkspace = JSON.parse(this.text);
				} catch (e) {
					console.warn("HyprlandData: Failed to parse activeWorkspace JSON");
				}
			}
		}
	}
}
