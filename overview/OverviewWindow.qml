pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.services
import qs.overview

// 参考原版设计：贴着左侧 bar 的面板，打开时从左面滑出（宽度 0 -> 内容宽度）。
// 只占左侧一列，不拦截其余屏幕区域；关闭时收回到 0 宽。
PanelWindow {
	id: root

	readonly property real contentWidth: content.item?.implicitWidth ?? 460

	// 面板右移到左侧 bar 的右侧：优先取实际 bar 宽度，失败时按 Tokens 计算
	readonly property real barOffset: {
		const comp = ShellState.componentsForActive();
		return comp?.bar?.implicitWidth ?? 72;
	}

	WlrLayershell.namespace: "caelestia-overview"
	WlrLayershell.layer: WlrLayer.Overlay
	WlrLayershell.keyboardFocus: OverviewState.active ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
	WlrLayershell.exclusionMode: ExclusionMode.Ignore

	anchors.top: true
	anchors.bottom: true
	anchors.left: true
	margins.left: root.barOffset

	implicitWidth: OverviewState.active ? root.contentWidth : 0
	visible: OverviewState.active || width > 0

	Behavior on implicitWidth {
		NumberAnimation {
			duration: 140
			easing.type: Easing.OutCubic
		}
	}

	color: "transparent"

	HyprlandFocusGrab {
		active: OverviewState.active
		windows: [root]
		onCleared: OverviewState.active = false
	}

	Item {
		id: keyCatcher

		anchors.fill: parent
		focus: true

		Keys.onPressed: event => {
			if (event.key === Qt.Key_Escape) {
				OverviewState.active = false;
				event.accepted = true;
			} else if (content.item) {
				content.item.handleKey(event);
			}
		}
	}

	Loader {
		id: content

		anchors.top: parent.top
		anchors.bottom: parent.bottom
		anchors.left: parent.left

		// 预加载：内容常驻，窗口宽度为 0 时不显示，打开时只做滑动动画
		active: true
		width: content.item?.implicitWidth ?? 0

		sourceComponent: OverviewContent {
			visible: true
		}
	}

	onVisibleChanged: {
		if (visible)
			keyCatcher.forceActiveFocus();
	}
}
