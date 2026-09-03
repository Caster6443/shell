pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.spotlight

// Spotlight 模块入口：居中悬浮的聚合启动器（试验版）。
// 用法：qs -c caelestia ipc call spotlight toggle
// 与上游 launcher（底部抽屉）互不影响，旧启动器保留可随时切回。
Item {
	id: root

	SpotlightWindow {}

	IpcHandler {
		target: "spotlight"

		function toggle(): void {
			SpotlightState.active = !SpotlightState.active;
		}

		function open(): void {
			SpotlightState.active = true;
		}

		function close(): void {
			SpotlightState.active = false;
		}

		function setVisible(visible: bool): void {
			SpotlightState.active = visible;
		}
	}
}
