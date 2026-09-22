pragma Singleton

import Quickshell

Singleton {
	property bool active: false
	// 外部（IPC / 快捷键）要求 launcher 打开时落在哪个标签页（"" = 用默认）；
	// 由 SpotlightPanel 打开/创建时消费一次并清空。
	property string requestedMode: ""
	// 面板当前实际所处的标签页（由 SpotlightPanel 回写），供 IPC 判断「同一标签再按一次 = 收回」
	property string currentMode: "apps"
}
