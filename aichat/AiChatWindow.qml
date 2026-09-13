pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.aichat
import qs.services

// 面板形态：贴左侧 bar，打开时从左边滑出（宽度 0 → 内容宽度）。
// 注意：**保持"小窗口 + 横向宽度动画"**——曾经试过改成 CA drawers 那种"全屏 + mask"，
// 结果出现方向不对的入场动画，已改回。
PanelWindow {
	id: root

	readonly property real contentWidth: content.item?.implicitWidth ?? 480

	// 面板右移到左侧 bar 的右侧
	readonly property real barOffset: {
		const comp = ShellState.componentsForActive();
		return comp?.bar?.implicitWidth ?? 72;
	}

	WlrLayershell.namespace: "caelestia-aichat"
	WlrLayershell.layer: WlrLayer.Top
	// 打开面板就要能直接打字，不能要求先点一下输入框：
	// OnDemand = "由合成器决定"（Hyprland 下表现为点一下才给键盘焦点）；Exclusive 是协议级独占键盘焦点。
	// 注意别退回 HyprlandFocusGrab：它每次按键都重新抓一次焦点，会打断 fcitx5 的预编辑（2026-09-10 定位的根因）。
	WlrLayershell.keyboardFocus: AiChatState.active ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
	WlrLayershell.exclusionMode: ExclusionMode.Ignore

	anchors.top: true
	anchors.bottom: true
	anchors.left: true
	margins.left: root.barOffset

	implicitWidth: AiChatState.active ? root.contentWidth : 0
	visible: AiChatState.active || width > 0

	Behavior on implicitWidth {
		NumberAnimation {
			duration: 110
			easing.type: Easing.OutCubic
		}
	}

	color: "transparent"

	// ESC 关闭：窗口级 Shortcut，不抢焦点
	Shortcut {
		sequence: "Escape"
		context: Qt.WindowShortcut
		onActivated: AiChatState.active = false
	}

	// 关闭方式：ESC / 右上角 ✕ / `qs -c caelestia ipc call aichat close`。
	//
	// 不用 HyprlandFocusGrab：它会在每次按键/焦点变动时重新抓一次键盘焦点，
	// 把 fcitx5 的预编辑状态打断（症状：候选框闪烁、字最终以英文进框）。
	// "点窗口外面关闭"这个需求不做（2026-09-10 用户确认取消）：FocusGrab 会打断输入法；
	// 换成"监听 Hyprland 焦点事件"的替代方案试过一版、效果不好，已清理。
	// （PanelWindow 没有 focus/active 变更信号，Quickshell 只提供 focusable。）

	Loader {
		id: content

		anchors.top: parent.top
		anchors.bottom: parent.bottom
		anchors.left: parent.left

		active: true
		width: content.item?.implicitWidth ?? 0
		clip: true

		sourceComponent: AiChatPanel {
			visible: true
		}
	}

	onVisibleChanged: {
		if (visible)
			AiChatTheme.reload();
	}
}
