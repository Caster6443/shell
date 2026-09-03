pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.overview

Rectangle {
	id: windowItem

	required property string m_address
	required property int m_wsId
	required property real m_atX
	required property real m_atY
	required property real m_sizeW
	required property real m_sizeH
	required property real m_linearX
	required property bool m_floating
	required property string m_title

	required property var overviewRoot
	required property Item orphanLayer

	property string windowAddress: m_address
	property int currentWsId: m_wsId

	readonly property bool isHovered: overviewRoot.hoveredWindowAddress === m_address

	readonly property int wsWindowCount: {
		let n = 0;
		for (let i = 0; i < overviewRoot.windowModelRef.count; ++i)
			if (overviewRoot.windowModelRef.get(i).m_wsId === m_wsId)
				n++;
		return n;
	}

	readonly property real hoverScale: wsWindowCount <= 1 ? 1.06 : 1.18

	readonly property real pushOffset: {
		const hAddr = overviewRoot.hoveredWindowAddress;
		if (!hAddr || hAddr === m_address)
			return 0;
		for (let i = 0; i < overviewRoot.windowModelRef.count; ++i) {
			const it = overviewRoot.windowModelRef.get(i);
			if (it.m_address !== hAddr || it.m_wsId !== m_wsId)
				continue;
			const hovX = it.m_linearX * scaleRatio;
			const myX = m_linearX * scaleRatio;
			const dist = myX - hovX;
			if (Math.abs(dist) > width * 2)
				return 0;
			const push = 28 * Math.exp(-Math.abs(dist) / (width * 0.8));
			return dist > 0 ? push : -push;
		}
		return 0;
	}

	parent: (overviewRoot.wsLayers && overviewRoot.wsLayers[m_wsId]) ? overviewRoot.wsLayers[m_wsId] : (overviewRoot.anyWorkspaceLayer() ? overviewRoot.anyWorkspaceLayer() : orphanLayer)
	visible: parent !== orphanLayer
	z: isHovered ? 30 : 20
	scale: isHovered ? hoverScale : 1.0
	opacity: mouseArea.drag.active ? 0.9 : 1.0

	Behavior on x {
		enabled: !mouseArea.drag.active
		NumberAnimation {
			duration: 220
			easing.type: Easing.OutCubic
		}
	}
	Behavior on y {
		enabled: !mouseArea.drag.active
		NumberAnimation {
			duration: 220
			easing.type: Easing.OutCubic
		}
	}

	Behavior on width {
		NumberAnimation {
			duration: 160
			easing.type: Easing.OutCubic
		}
	}
	Behavior on height {
		NumberAnimation {
			duration: 160
			easing.type: Easing.OutCubic
		}
	}
	Behavior on scale {
		NumberAnimation {
			duration: 200
			easing.type: Easing.OutBack
		}
	}
	Behavior on opacity {
		NumberAnimation {
			duration: 120
			easing.type: Easing.OutCubic
		}
	}

	readonly property real scaleRatio: {
		const layer = parent;
		const container = layer ? layer.parent : null;
		return container && container.scaleRatio !== undefined ? container.scaleRatio : 1.0;
	}

	property real targetX: m_linearX * scaleRatio + pushOffset

	property real targetY: {
		const ph = parent ? parent.height : 260;
		const h = (m_sizeH > 0 ? m_sizeH : (Hyprland.focusedMonitor?.height || 1080)) * scaleRatio;
		return Math.max(0, (ph - h) / 2);
	}

	readonly property real clampedX: {
		if (isNaN(targetX))
			return 0;
		const pw = parent ? parent.width : 0;
		if (!pw || isNaN(width))
			return targetX;
		const half = width / 2;
		return Math.max(half, Math.min(targetX + half, pw - half)) - half;
	}
	readonly property real clampedY: {
		const ph = parent ? parent.height : 0;
		if (!ph || isNaN(targetY) || isNaN(height))
			return targetY;
		return Math.max(0, Math.min(targetY, ph - height));
	}

	Binding on x {
		value: windowItem.clampedX
		when: !mouseArea.drag.active
	}
	Binding on y {
		value: windowItem.clampedY
		when: !mouseArea.drag.active
	}

	width: (m_sizeW > 0 ? m_sizeW : (Hyprland.focusedMonitor?.width || 1920) / 2) * scaleRatio
	height: (m_sizeH > 0 ? m_sizeH : (Hyprland.focusedMonitor?.height || 1080)) * scaleRatio

	radius: 6
	color: M3Palette.m3surfaceContainerHigh
	border.color: mouseArea.containsMouse ? M3Palette.m3tertiary : M3Palette.m3primaryContainer
	border.width: 1
	clip: true

	Rectangle {
		anchors.bottom: parent.bottom
		anchors.left: parent.left
		anchors.right: parent.right
		height: titleText.implicitHeight + 6
		radius: 5
		color: Qt.alpha(M3Palette.m3surface, 0.85)
		visible: mouseArea.containsMouse && m_title !== ""
		z: 10

		Text {
			id: titleText
			anchors.centerIn: parent
			anchors.left: parent.left
			anchors.right: parent.right
			anchors.margins: 6
			text: m_title
			color: M3Palette.m3onSurface
			font.pixelSize: 11
			elide: Text.ElideRight
		}
	}

	ScreencopyView {
		id: screenView
		anchors.fill: parent
		anchors.margins: 1
		live: OverviewState.active

		// HyprlandToplevel 按 address 复用，指针稳定；wayland 句柄到位后绑定自动更新。
		readonly property var myToplevel: {
			const addr = windowAddress.toLowerCase();
			for (const tl of Hyprland.toplevels.values) {
				if (`0x${tl.address}`.toLowerCase() === addr)
					return tl;
			}
			return null;
		}

		// 置 true 时 captureSource 走 null 分支，用于销毁旧捕获上下文后强制重建。
		property bool forceBlank: false
		// 静默卡死保护：Hyprland 有时收到捕获请求后既不回帧也不报错
		// （无 ready/failed，ScreencopyView 不会触发 stopped），缩略图会永久纯色。
		// 这里用递增退避定时重建捕获上下文，覆盖数秒到一分钟级的卡死；
		// 连续重建仍无首帧时请求共享 monitor 截图踢脚（见 OverviewContent.requestCaptureKick）。
		property int retryIdx: -1
		readonly property var retryDelays: [1000, 2500, 5000, 10000, 20000, 40000]

		captureSource: forceBlank ? null : (myToplevel?.wayland ?? null)

		onHasContentChanged: {
			if (screenView.hasContent) {
				screenView.retryIdx = -1;
				console.info(`[overview] ${windowAddress} capture ok`);
			}
		}

		// 合成器终止画面流（如离屏窗口首帧失败、混合显卡拷贝失败）后，
		// ScreencopyView 不会自愈：同指针 setCaptureSource 直接返回，
		// live=true 也只在已有上下文时捕获。这里重试重建捕获。
		onStopped: {
			screenView.scheduleRetry();
		}

		function scheduleRetry() {
			if (!OverviewState.active || screenView.hasContent)
				return;
			// 退避表循环使用：overview 打开期间可无限重试（此前到表尾就停，无法自愈）。
			screenView.retryIdx = (screenView.retryIdx + 1) % screenView.retryDelays.length;
			// 连续多次重建仍无首帧 → Hyprland toplevel-export 静默悬挂：
			// 请求 OverviewContent 的共享 kicker 跑一次 monitor 截图（wlr-screencopy），
			// 驱动输出提交让卡住的窗口捕获恢复（grim 实测有效，2026-09-03）。
			if (screenView.retryIdx >= 1 && overviewRoot?.requestCaptureKick)
				overviewRoot.requestCaptureKick();
			retryTimer.interval = screenView.retryDelays[screenView.retryIdx];
			retryTimer.restart();
		}

		function refreshCapture() {
			// 先置 null 清掉 mCaptureSource，再在同一帧恢复同一 toplevel，强制重建上下文。
			screenView.forceBlank = true;
			Qt.callLater(() => { screenView.forceBlank = false; });
		}

		Timer {
			id: retryTimer
			repeat: false
			onTriggered: {
				if (OverviewState.active && !screenView.hasContent) {
					screenView.refreshCapture();
				} else {
					screenView.retryIdx = -1;
				}
			}
		}

		// 看门狗：捕获已发起但迟迟没有首帧时，按退避表持续重建捕获。
		Timer {
			id: captureWatchdog
			interval: 1000
			repeat: true
			running: OverviewState.active && !!screenView.captureSource && !screenView.hasContent
			onTriggered: {
				if (!retryTimer.running)
					screenView.scheduleRetry();
			}
		}

		// 每次打开 overview 时，给没有画面的缩略图一次全新捕获机会
		// （此前失败的离屏窗口在切换工作区后重新可见，能恢复画面）。
		Connections {
			target: OverviewState
			function onActiveChanged() {
				if (OverviewState.active) {
					screenView.retryIdx = -1;
					screenView.scheduleRetry();
					// 新实例启动后窗口捕获常整体静默悬挂：打开时若仍无画面，
					// 立即请求一次 monitor 截图踢脚，不必等退避表走完。
					if (!screenView.hasContent && overviewRoot?.requestCaptureKick)
						overviewRoot.requestCaptureKick();
				}
			}
		}

		// monitor 截图踢脚完成 → 立刻重建一次捕获。
		Connections {
			target: overviewRoot
			function onCaptureKickDone() {
				if (OverviewState.active && !screenView.hasContent)
					screenView.refreshCapture();
			}
		}
	}

	Drag.keys: ["window"]
	Drag.active: mouseArea.drag.active
	Drag.source: windowItem
	Drag.hotSpot.x: width / 2
	Drag.hotSpot.y: height / 2

	MouseArea {
		id: mouseArea
		anchors.fill: parent
		drag.target: windowItem
		hoverEnabled: true
		acceptedButtons: Qt.LeftButton | Qt.MiddleButton

		onEntered: overviewRoot.hoveredWindowAddress = m_address
		onExited: overviewRoot.hoveredWindowAddress = ""

		onPressed: mouse => {
			if (mouse.button === Qt.MiddleButton) {
				mouse.accepted = true;
				HyprDispatch.call(
					`closewindow address:${windowAddress}`,
					`hl.dsp.window.close({ window = "address:${HyprDispatch.addressArg(windowAddress)}" })`
				);
				overviewRoot.restartSyncTimer();
				return;
			}
			windowItem.z = 100;
			const layer = windowItem.parent;
			const container = layer ? layer.parent : null;
			if (container)
				container.hasActiveDrag = true;
		}

		onReleased: mouse => {
			if (mouse.button === Qt.MiddleButton)
				return;
			windowItem.z = 1;
			const layer = windowItem.parent;
			const container = layer ? layer.parent : null;
			if (container)
				container.hasActiveDrag = false;

			const dropResult = windowItem.Drag.drop();
			if (dropResult === Qt.MoveAction)
				return;

			const activeWs = Hyprland.focusedMonitor?.activeWorkspace?.id ?? -999;
			const monX = Hyprland.focusedMonitor?.x || 0;
			const monY = Hyprland.focusedMonitor?.y || 0;
			const realX = Math.round(windowItem.x / scaleRatio + monX);
			const realY = Math.round(windowItem.y / scaleRatio + monY);

			if (currentWsId === activeWs) {
				if (m_floating) {
					HyprDispatch.call(
						`movewindowpixel exact ${realX} ${realY},address:${windowAddress}`,
						`hl.dsp.window.move({ x = ${realX}, y = ${realY}, relative = false, window = "address:${HyprDispatch.addressArg(windowAddress)}" })`
					);
				} else {
					const beforeOrder = overviewRoot.wsAddressesSortedByX(currentWsId);
					const curIndex = beforeOrder.indexOf(windowAddress);
					const targetIndex = overviewRoot.targetIndexForDrop(currentWsId, windowAddress, realX);
					const delta = (curIndex !== -1) ? (targetIndex - curIndex) : 0;
					if (delta !== 0) {
						const dir = delta > 0 ? "r" : "l";
						const cmds = [{
							legacy: `focuswindow address:${windowAddress}`,
							lua: `hl.dsp.focus({ window = "address:${HyprDispatch.addressArg(windowAddress)}" })`
						}];
						for (let step = 0; step < Math.abs(delta); ++step)
							cmds.push({
								legacy: `layoutmsg swapcol ${dir}`,
								lua: `hl.dsp.layout("swapcol ${dir}")`
							});
						overviewRoot.dispatchBatch(cmds);
					}
				}
				overviewRoot.restartSyncTimer();
			}
		}

		onClicked: mouse => {
			if (mouse.button !== Qt.LeftButton)
				return;
			HyprDispatch.call(
				`focuswindow address:${windowAddress}`,
				`hl.dsp.focus({ window = "address:${HyprDispatch.addressArg(windowAddress)}" })`
			);
			overviewRoot.closeOverview();
		}
	}
}
