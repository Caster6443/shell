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
	// 工作区名字（特殊工作区是 "special:xxx"，普通工作区是 "1" 这类）。
	// 必须是 required：普通/特殊两个模型都要提供该角色，否则拿不到值（踩过：非 required 带默认值收不到角色，
	// 结果 layerKey 退化成 id，找不到卡片 → 缩略图被塞进 anyWorkspaceLayer()，出现在 1 号工作区上）。
	required property string m_wsName

	required property var overviewRoot
	required property Item orphanLayer

	property string windowAddress: m_address
	property int currentWsId: m_wsId

	readonly property bool isHovered: overviewRoot.hoveredWindowAddress === m_address
	readonly property bool isSpecialRow: m_wsId <= 0
	// 卡片登记键：普通工作区用 id，特殊工作区用名字（空插槽还没有 id）
	readonly property string layerKey: isSpecialRow ? (m_wsName !== "" ? m_wsName : String(m_wsId)) : String(m_wsId)
	readonly property var rowModel: overviewRoot ? (isSpecialRow ? overviewRoot.specialWindowModelRef : overviewRoot.windowModelRef) : null

	function rowInSameWorkspace(row): bool {
		return isSpecialRow ? row.m_wsName === m_wsName : row.m_wsId === m_wsId;
	}

	readonly property int wsWindowCount: {
		let n = 0;
		const model = rowModel;
		if (!model)
			return 1;
		for (let i = 0; i < model.count; ++i)
			if (rowInSameWorkspace(model.get(i)))
				n++;
		return n;
	}

	readonly property real hoverScale: wsWindowCount <= 1 ? 1.06 : 1.18

	readonly property real pushOffset: {
		const hAddr = overviewRoot.hoveredWindowAddress;
		if (!hAddr || hAddr === m_address)
			return 0;
		const model = rowModel;
		if (!model)
			return 0;
		for (let i = 0; i < model.count; ++i) {
			const it = model.get(i);
			if (it.m_address !== hAddr || !rowInSameWorkspace(it))
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

	parent: {
		const layers = overviewRoot.wsLayers;
		if (layers && layers[layerKey])
			return layers[layerKey];
		// 找不到自己的卡片时宁可放进隐藏的 orphanLayer，也不要塞到别的工作区卡片里
		if (windowItem.loggedMissingLayer !== layerKey) {
			windowItem.loggedMissingLayer = layerKey;
			console.info(`[overview-preview] ${m_address} 没找到卡片 key=${layerKey}，现有键=${Object.keys(layers ?? {}).join(",")}`);
		}
		return orphanLayer;
	}
	property string loggedMissingLayer: ""
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
		// 旧版（最初版 overview）语义：预览是常驻实时流，不随 surface 开关门控。
		// 关闭/隐藏时视图不参与绘制，ScreencopyView 不会喂帧（Quickshell view.cpp
		// 只在 updatePaintNode 里请求下一帧），因此不会产生后台空转开销。
		live: true

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

		captureSource: forceBlank ? null : (myToplevel?.wayland ?? null)

		Component.onCompleted: {
			if (overviewRoot?.registerPreview)
				overviewRoot.registerPreview(windowAddress);
		}

		Component.onDestruction: {
			if (overviewRoot?.unregisterPreview)
				overviewRoot.unregisterPreview(windowAddress);
		}

		onHasContentChanged: {
			if (overviewRoot?.setPreviewHasContent)
				overviewRoot.setPreviewHasContent(windowAddress, screenView.hasContent);
			if (screenView.hasContent) {
				screenView.gaveUpNoFrame = false;
				console.info(`[overview] ${windowAddress} capture ok`);
			}
		}

		// 合成器终止画面流（如离屏窗口首帧失败、混合显卡拷贝失败）后，
		// ScreencopyView 不会自愈：同指针 setCaptureSource 直接返回，
		// live=true 也只在已有上下文时捕获。这里重建捕获上下文。
		onStopped: {
			console.info(`[overview] ${windowAddress} stream stopped, rebuild`);
			screenView.recover();
		}

		// 静默卡死兜底（最小化）：长时间无首帧时只重建一次捕获上下文，
		// 仍无帧即放弃自动重试，等待 OverviewContent 的按需解锁踢脚再恢复。
		property bool gaveUpNoFrame: false

		Timer {
			id: firstFrameWatchdog
			interval: 4000
			repeat: false
			running: !screenView.gaveUpNoFrame && !screenView.hasContent && !!screenView.captureSource
			onTriggered: {
				if (!screenView.hasContent && !!screenView.captureSource) {
					console.info(`[overview] ${windowAddress} no first frame, rebuild`);
					screenView.gaveUpNoFrame = true;
					screenView.recover();
				}
			}
		}

		// 重建保护：forceBlank 置 null 销毁旧捕获上下文，再恢复同一 toplevel 强制重建。
		// 冷却期内不再重建，避免合成器反复终止流时无限循环。
		property bool recovering: false
		property bool recoverCooldown: false

		function recover() {
			if (screenView.recovering || screenView.recoverCooldown)
				return;
			screenView.recovering = true;
			screenView.forceBlank = true;
			Qt.callLater(() => {
				screenView.forceBlank = false;
				screenView.recovering = false;
				screenView.recoverCooldown = true;
				recoverCooldownTimer.restart();
			});
		}

		// 解锁踢脚完成后的重建：合成器侧已恢复，强制清冷却并重建一次。
		function recoverAfterKick() {
			screenView.gaveUpNoFrame = false;
			screenView.recoverCooldown = false;
			screenView.recover();
			firstFrameWatchdog.interval = 8000;
			firstFrameWatchdog.restart();
		}

		// 解锁踢脚（monitor 截图）完成 → 仍无首帧的预览立刻重建捕获。
		Connections {
			target: overviewRoot
			function onCaptureKickDone() {
				if (!screenView.hasContent && !!screenView.captureSource)
					screenView.recoverAfterKick();
			}
		}

		Timer {
			id: recoverCooldownTimer
			interval: 8000
			onTriggered: screenView.recoverCooldown = false
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
			if (container) {
				container.hasActiveDrag = true;
				overviewRoot.dragFromSpecialSection = !!container.isSpecial;
			}
		}

		onReleased: mouse => {
			overviewRoot.dragFromSpecialSection = false;
			if (mouse.button === Qt.MiddleButton)
				return;
			// 还原 hover 用的 z 绑定（直接赋常数会把绑定永久改掉）
			windowItem.z = Qt.binding(() => windowItem.isHovered ? 30 : 20);
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

		// 拖拽被打断（抢焦点、手势取消）时同样复位，避免列层级停在抬升状态。
		onCanceled: {
			overviewRoot.dragFromSpecialSection = false;
			windowItem.z = Qt.binding(() => windowItem.isHovered ? 30 : 20);
			const layer = windowItem.parent;
			const container = layer ? layer.parent : null;
			if (container)
				container.hasActiveDrag = false;
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
