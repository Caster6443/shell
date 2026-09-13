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

	// 事件驱动的全量刷新开关（每次刷新 = 3 个 hyprctl 进程）。
	// 面板现在常驻不销毁，隐藏期间由宿主把这里置 false，避免在后台跟着
	// Hyprland 事件（窗口标题 10Hz 级别的刷新）反复拉起进程。
	property bool liveUpdates: true

	function updateAll() {
		getClients.running = true;
		getWorkspaces.running = true;
		getActiveWorkspace.running = true;
	}

	Component.onCompleted: updateAll()

	Connections {
		target: Hyprland
		function onRawEvent(event) {
			if (!root.liveUpdates)
				return;
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
