pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.aichat

// AI 对话外挂入口：在 shell.qml 里实例化一次。
// 自带一个贴左侧 bar 的面板窗口（放在退役侧栏 overview 的位置），并暴露 IPC：
//   qs -c caelestia ipc call aichat toggle
Item {
	id: root

	AiChatWindow {}
	AiChatHotCorner {}

	IpcHandler {
		target: "aichat"

		function toggle(): void {
			AiChatState.active = !AiChatState.active;
		}

		function open(): void {
			AiChatState.active = true;
		}

		function close(): void {
			AiChatState.active = false;
		}

		function setVisible(visible: bool): void {
			AiChatState.active = visible;
		}

		// 可选：让外部把一段文本直接发进去（例如选区文字、报错日志）
		function ask(text: string): void {
			AiChatState.active = true;
			AiChatService.send(text);
		}
	}
}
