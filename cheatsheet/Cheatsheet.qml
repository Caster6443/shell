pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.cheatsheet

// 模块入口：快捷键速查弹窗（同 caelestia 实例）。
// 用法：qs -c caelestia ipc call cheatsheet toggle
Item {
	id: root

	CheatsheetWindow {}

	IpcHandler {
		target: "cheatsheet"

		function toggle(): void {
			CheatsheetState.active = !CheatsheetState.active;
			if (CheatsheetState.active) {
				CheatsheetTheme.reload();
				KeybindsData.reload();
			}
		}

		function open(): void {
			CheatsheetState.active = true;
			CheatsheetTheme.reload();
			KeybindsData.reload();
		}

		function close(): void {
			CheatsheetState.active = false;
		}

		function setVisible(visible: bool): void {
			CheatsheetState.active = visible;
			if (visible) {
				CheatsheetTheme.reload();
				KeybindsData.reload();
			}
		}
	}
}
