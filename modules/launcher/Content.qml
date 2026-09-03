pragma ComponentBehavior: Bound

import QtQuick
import qs.spotlight

// Launcher 弹出面板内容：由 SpotlightPanel 整体接管（overview + 应用 + 壁纸）。
// 上游旧的应用菜单内容已迁移覆盖到 spotlight，模块目录保留以便未来合上游。
Item {
	id: root

	required property var screenState
	required property var panels
	required property real maxHeight

	implicitWidth: 980
	implicitHeight: Math.min(920, Math.max(480, root.maxHeight - 20))

	SpotlightPanel {
		id: panel

		anchors.fill: parent
		maxHeight: root.maxHeight

		onCloseRequested: root.screenState.launcher = false
	}
}
