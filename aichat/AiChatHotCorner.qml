pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.aichat

// 左上角热区：鼠标停 150ms 打开 AI 面板（沿用退役侧栏 overview 的 HotCorner 做法）。
// 只占 2×2、Overlay 层，不影响其它区域输入。
PanelWindow {
	id: hotCorner

	anchors.top: true
	anchors.left: true

	implicitWidth: 2
	implicitHeight: 2
	color: "transparent"

	WlrLayershell.namespace: "caelestia-aichat-hotcorner"
	WlrLayershell.layer: WlrLayer.Overlay
	WlrLayershell.exclusionMode: ExclusionMode.Ignore
	// 热区只是个 2×2 的触发区，绝不要键盘焦点：否则它会把面板/输入法的焦点抢走
	// （症状：切到中文输入法后焦点抖一下、拼音进不去 —— 第一版没热区时是正常的）
	WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

	Timer {
		id: triggerTimer

		interval: 150
		repeat: false
		onTriggered: {
			if (!AiChatState.active)
				AiChatState.active = true;
		}
	}

	HoverHandler {
		onHoveredChanged: {
			if (hovered)
				triggerTimer.restart();
			else
				triggerTimer.stop();
		}
	}
}
