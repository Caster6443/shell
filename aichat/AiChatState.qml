pragma Singleton

import Quickshell

// AI 对话面板开合状态（与 overview/cheatsheet 同一套单例模式）
Singleton {
	property bool active: false
}
