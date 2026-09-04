pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Caelestia.Config
import qs.modules.launcher.services
import qs.overview
import qs.services
import qs.spotlight

// Spotlight 内容面板：左 overview 工作区列 + 右应用列表；壁纸模式双视图。
// 由 launcher 弹出面板实例化（原浮动窗已退役）。
Item {
	id: root

	signal closeRequested()

	implicitWidth: Math.round(Screen.width * 0.4)
	implicitHeight: Math.round(Screen.height * 0.6)

	property var pendingLaunch: null
	property var launchWatch: null
	property bool ghostVisible: false
	property string ghostIcon: ""
	property string mode: "apps"
	property string wallView: "carousel"
	property real maxHeight: 900
	property int kickBurstCount: 0

	// ---------------- 生命周期 ----------------
	Component.onCompleted: Qt.callLater(() => {
		if (root.mode === "apps")
			root.resetAppSelection();
		input.forceActiveFocus();
	})

	onVisibleChanged: {
		if (visible) {
			input.text = "";
			root.launchWatch = null;
			root.ghostVisible = false;
			SpotlightState.active = true;
			ov.refresh();
			Qt.callLater(() => ov.settleToActive());
			input.forceActiveFocus();
			Qt.callLater(root.resetAppSelection);
			root.kickBurstCount = 0;
			openKickTimer.start();
		} else {
			SpotlightState.active = false;
			openKickTimer.stop();
		}
	}

	Component.onDestruction: SpotlightState.active = false

	// overview 内点击工作区卡/窗口缩略图会经 closeOverview() 把 SpotlightState 置 false，
	// 此时启动器面板仍可见 → 视为“已选定目标”，自动关闭启动器
	Connections {
		target: SpotlightState

		function onActiveChanged() {
			if (!SpotlightState.active && root.visible)
				root.closeRequested();
		}
	}

	// 打开时连踢几次 monitor 截图：单次踢脚偶尔无效（实测需 2~3 次才稳定出帧）
	Timer {
		id: openKickTimer

		interval: 700
		repeat: true
		onTriggered: {
			ov.requestCaptureKick();
			if (++root.kickBurstCount >= 4)
				openKickTimer.stop();
		}
	}

	// ---------------- 应用 → 指定工作区启动 ----------------
	function shq(s: string): string {
		return "'" + String(s).replace(/'/g, "'\\''") + "'";
	}

	function buildLaunchArgv(entry: var): var {
		if (entry?.runInTerminal)
			return [...GlobalConfig.general.apps.terminal, `${Quickshell.shellDir}/assets/wrap_term_launch.sh`, ...(entry.command ?? [])];
		return entry?.command ?? [];
	}

	function launchOnWorkspace(entry: var, wsId: int, isSpecial: bool): void {
		launchRefreshTimer.restart();
		if (isSpecial) {
			root.pendingLaunch = { entry: entry, ws: wsId, special: true };
			clientsProc.running = true;
			return;
		}
		const argv = root.buildLaunchArgv(entry);
		const cmdline = argv.map(root.shq).join(" ");
		const luaCmd = String(cmdline).replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\n/g, "\\n");
		const expr = `hl.dispatch(hl.dsp.exec_cmd("${luaCmd}", { workspace = "${wsId} silent" }))`;
		console.info(`[spotlight-launch] eval ws=${wsId}: ${cmdline.slice(0, 120)}`);
		Quickshell.execDetached(["hyprctl", "eval", expr]);
	}

	Timer {
		id: launchRefreshTimer

		interval: 1000
		repeat: false
		onTriggered: ov.refresh()
	}

	function beginWatch(snapshot: var, entry: var, wsId: int, isSpecial: bool): void {
		const expected = new Set();
		for (const c of [entry?.startupClass, entry?.command?.[0]]) {
			if (!c)
				continue;
			expected.add(String(c).toLowerCase().split("/").pop().replace(/\..*$/, ""));
		}
		root.launchWatch = {
			expected: expected,
			ws: wsId,
			special: isSpecial,
			snapshot: new Set(snapshot),
			tries: 0
		};
		console.info(`[spotlight-launch] watch ws=${wsId} special=${isSpecial} expected=[${[...expected].join(",")}]`);
		Apps.launch(entry);
		root.pollLaunch();
	}

	function pollLaunch(): void {
		if (!root.launchWatch)
			return;
		if (root.launchWatch.tries++ >= 40) {
			console.info("[spotlight-launch] timeout: 未发现可移动的新窗口");
			root.launchWatch = null;
			return;
		}
		pollProc.running = true;
	}

	Timer {
		id: pollRetryTimer

		interval: 300
		repeat: false
		onTriggered: root.pollLaunch()
	}

	Process {
		id: pollProc

		command: ["hyprctl", "clients", "-j"]
		running: false

		stdout: StdioCollector {
			onStreamFinished: {
				const watch = root.launchWatch;
				if (!watch) {
					root.launchWatch = null;
					return;
				}
				try {
					const raw = JSON.parse(this.text);
					let moved = false;
					for (const c of raw) {
						if (!c.address || watch.snapshot.has(c.address))
							continue;
						const cls = (c.class || "").toLowerCase();
						const matched = watch.expected.size === 0 || watch.expected.has(cls);
						if (!matched)
							continue;
						const ws = watch.special ? "special" : String(watch.ws);
						console.info(`[spotlight-launch] move ${c.class ?? ""} ${c.address} -> ws ${ws}`);
						HyprDispatch.call(
							`movetoworkspacesilent ${ws},address:${HyprDispatch.addressArg(c.address)}`,
							`hl.dsp.window.move({ window = "address:${HyprDispatch.addressArg(c.address)}", workspace = "${ws}", follow = false })`
						);
						watch.snapshot.add(c.address);
						moved = true;
					}
					if (moved) {
						root.launchWatch = null;
						return;
					}
				} catch (e) {
					console.warn("Spotlight: 轮询新窗口失败", e);
				}
				pollRetryTimer.restart();
			}
		}
	}

	Process {
		id: clientsProc

		command: ["hyprctl", "clients", "-j"]
		running: false

		stdout: StdioCollector {
			onStreamFinished: {
				try {
					const raw = JSON.parse(this.text);
					const arr = [];
					for (const c of raw) {
						if (!c.address || !c.mapped)
							continue;
						arr.push(c.address);
					}
					const pending = root.pendingLaunch;
					root.pendingLaunch = null;
					if (pending)
						root.beginWatch(arr, pending.entry, pending.ws, pending.special);
				} catch (e) {
					console.warn("Spotlight: 解析 hyprctl clients 失败", e);
					root.pendingLaunch = null;
				}
			}
		}
	}

	// ---------------- UI ----------------
	Rectangle {
		id: shell

		anchors.fill: parent
		anchors.margins: 1
		radius: 20
		// 跟随全局透明度设置（Wallpaper & style → Transparency），不写死
		color: Colours.tPalette.m3surfaceContainerHigh
		border.color: Qt.alpha(M3Palette.m3onSurface, 0.12)
		border.width: 1
		clip: true

		Column {
			anchors.fill: parent
			anchors.margins: 12
			spacing: 10

			TextField {
				id: input

				objectName: "spotlightSearch"
				width: parent.width
				height: 40
				leftPadding: 40
				rightPadding: 14

				placeholderText: root.mode === "wallpaper" ? "搜索壁纸…" : "搜索应用…"
				placeholderTextColor: Qt.alpha(M3Palette.m3onSurface, 0.45)
				color: M3Palette.m3onSurface
				font: Tokens.font.body.large

				IconImage {
					asynchronous: true
					implicitSize: 18
					source: Quickshell.iconPath("system-search", "image-missing")
					anchors.left: parent.left
					anchors.verticalCenter: parent.verticalCenter
					anchors.leftMargin: 12
				}

				background: Rectangle {
					radius: 12
					color: Qt.alpha(M3Palette.m3surface, 0.5)
					border.color: input.activeFocus
						? M3Palette.m3tertiary
						: Qt.alpha(M3Palette.m3onSurface, 0.2)
					border.width: input.activeFocus ? 1.5 : 1
				}

				Keys.onEscapePressed: event => {
					root.closeRequested();
					event.accepted = true;
				}
				Keys.onDownPressed: event => {
					if (root.mode === "apps") {
						root.moveAppSelection(1);
						event.accepted = true;
					}
				}
				Keys.onUpPressed: event => {
					if (root.mode === "apps") {
						root.moveAppSelection(-1);
						event.accepted = true;
					}
				}
				onTextChanged: {
					if (root.mode === "apps")
						Qt.callLater(root.resetAppSelection);
				}
				onAccepted: {
					if (root.mode === "apps")
						root.launchSelectedApp();
				}
			}

			// 顶部：模式切换（应用 / 壁纸）
			Rectangle {
				id: modeHeader

				width: 172
				height: 30
				radius: 15
				color: Qt.alpha(M3Palette.m3surface, 0.55)
				border.color: Qt.alpha(M3Palette.m3onSurface, 0.15)
				border.width: 1

				Row {
					anchors.fill: parent

					Item {
						width: parent.width / 2
						height: parent.height

						Rectangle {
							anchors.fill: parent
							anchors.margins: 2
							radius: 13
							visible: root.mode === "apps"
							color: M3Palette.m3tertiary
						}

						Text {
							anchors.centerIn: parent
							text: "应用"
							color: root.mode === "apps"
								? "#FFFFFF"
								: Qt.alpha(M3Palette.m3onSurface, 0.5)
							font.pixelSize: 11
							font.bold: root.mode === "apps"
						}

						MouseArea {
							anchors.fill: parent
							hoverEnabled: true
							onClicked: root.mode = "apps"
						}
					}

					Item {
						width: parent.width / 2
						height: parent.height

						Rectangle {
							anchors.fill: parent
							anchors.margins: 2
							radius: 13
							visible: root.mode === "wallpaper"
							color: M3Palette.m3tertiary
						}

						Text {
							anchors.centerIn: parent
							text: "壁纸"
							color: root.mode === "wallpaper"
								? "#FFFFFF"
								: Qt.alpha(M3Palette.m3onSurface, 0.5)
							font.pixelSize: 11
							font.bold: root.mode === "wallpaper"
						}

						MouseArea {
							anchors.fill: parent
							hoverEnabled: true
							onClicked: root.mode = "wallpaper"
						}
					}
				}
			}

			// ---------------- 应用模式 ----------------
			Item {
				id: appsBody

				visible: root.mode === "apps"
				width: parent.width
				height: parent.height - input.height - modeHeader.height - parent.spacing * 2

				Row {
					anchors.fill: parent
					spacing: 10

					Item {
						id: leftZone

						width: 566
						height: parent.height

						OverviewContent {
							id: ov

							anchors.fill: parent
							surfaceState: SpotlightState
							visibleCards: 2
							cardWidth: 560
							cardHeight: 360
							showPanel: false
							settleTopAlign: true
							launchOnWorkspace: root.launchOnWorkspace
						}
					}

					Rectangle {
						width: 1
						height: parent.height
						color: Qt.alpha(M3Palette.m3onSurface, 0.1)
					}

					Item {
						id: appZone

						width: parent.width - leftZone.width - 11
						height: parent.height

						Text {
							id: appTitle

							text: input.text.trim() ? "应用匹配" : "应用"
							color: Qt.alpha(M3Palette.m3onSurface, 0.55)
							font.pixelSize: 11
							font.bold: true
						}

						ListView {
							id: appList

							anchors.top: appTitle.bottom
							anchors.left: parent.left
							anchors.right: parent.right
							anchors.bottom: parent.bottom
							anchors.topMargin: 6
							clip: true
							spacing: 2
							model: appResults(input.text)
							currentIndex: -1

							onCountChanged: {
								if (root.mode === "apps")
									Qt.callLater(root.resetAppSelection);
							}

							ScrollBar.vertical: ScrollBar {}

							delegate: Item {
								id: appRow

								required property var modelData

								width: appList.width
								height: 52
								opacity: 1

								property var appEntry: modelData

								Drag.keys: ["app"]
								Drag.source: appRow

								Rectangle {
									anchors.fill: parent
									radius: 10
									color: appRow.ListView.isCurrentItem
										? Qt.alpha(M3Palette.m3tertiary, 0.26)
										: rowMouse.containsMouse
											? Qt.alpha(M3Palette.m3onSurface, 0.08)
											: "transparent"
									border.color: appRow.ListView.isCurrentItem
										? Qt.alpha(M3Palette.m3tertiary, 0.7)
										: "transparent"
									border.width: appRow.ListView.isCurrentItem ? 1 : 0
								}

								Row {
									anchors.left: parent.left
									anchors.right: parent.right
									anchors.verticalCenter: parent.verticalCenter
									anchors.leftMargin: 8
									anchors.rightMargin: 6
									spacing: 8

									Item {
										width: 34
										height: 34

										Rectangle {
											anchors.fill: parent
											radius: 9
											color: Qt.alpha(M3Palette.m3onSurface, 0.08)
										}

										IconImage {
											anchors.centerIn: parent
											asynchronous: true
											implicitSize: 24
											source: Quickshell.iconPath(modelData.icon ?? "", "image-missing")
										}
									}

									Text {
										width: parent.width - 42
										text: modelData.name ?? ""
										color: M3Palette.m3onSurface
										font: Tokens.font.body.builders.large.weight(Font.DemiBold).build()
										elide: Text.ElideRight
										verticalAlignment: Text.AlignVCenter
									}
								}

								MouseArea {
									id: rowMouse

									anchors.fill: parent
									hoverEnabled: true
									acceptedButtons: Qt.LeftButton
									preventStealing: true

									property bool pressMightDrag: false
									property point pressPos

									onPressed: mouse => {
										rowMouse.pressMightDrag = true;
										rowMouse.pressPos = Qt.point(mouse.x, mouse.y);
									}
									onPositionChanged: mouse => {
										if (rowMouse.pressMightDrag && !appRow.Drag.active &&
											(Math.abs(mouse.x - rowMouse.pressPos.x) > 8 ||
											 Math.abs(mouse.y - rowMouse.pressPos.y) > 8)) {
											appRow.Drag.active = true;
											appRow.opacity = 0.45;
											root.ghostIcon = Quickshell.iconPath(modelData.icon ?? "", "image-missing");
											root.ghostVisible = true;
										}
										if (appRow.Drag.active) {
											const p = rowMouse.mapToItem(shell, mouse.x, mouse.y);
											dragGhost.x = p.x - 28;
											dragGhost.y = p.y - 28;
										}
									}
									onReleased: mouse => {
										const wasDrag = appRow.Drag.active;
										let hitWs = -1;
										if (wasDrag) {
											const p = rowMouse.mapToItem(ov, mouse.x, mouse.y);
											hitWs = ov.workspaceAt(p);
											console.info(`[spotlight-drag] release ${modelData.name ?? ""} ws=${hitWs}`);
											if (hitWs !== -1)
												root.launchOnWorkspace(modelData, hitWs, hitWs < 0);
										}
										appRow.Drag.active = false;
										appRow.opacity = 1;
										root.ghostVisible = false;
										rowMouse.pressMightDrag = false;
										if (!wasDrag) {
											console.info(`[spotlight-click] launch ${modelData.name ?? ""}`);
											Apps.launch(modelData);
											launchRefreshTimer.restart();
										}
									}
								}
							}
						}
					}
				}
			}

			// ---------------- 壁纸模式（竖排 / 网格） ----------------
			Item {
				id: wallBody

				visible: root.mode === "wallpaper"
				width: parent.width
				height: parent.height - input.height - modeHeader.height - parent.spacing * 2

				Row {
					id: wallToolbar

					anchors.top: parent.top
					anchors.right: parent.right
					height: 28
					spacing: 8

					Rectangle {
						width: 58
						height: parent.height
						radius: 9
						color: root.wallView === "carousel"
							? M3Palette.m3tertiary
							: Qt.alpha(M3Palette.m3surface, 0.6)

						Text {
							anchors.centerIn: parent
							text: "≡"
							color: root.wallView === "carousel"
								? "#FFFFFF"
								: Qt.alpha(M3Palette.m3onSurface, 0.55)
							font.pixelSize: 16
						}

						MouseArea {
							anchors.fill: parent
							onClicked: root.wallView = "carousel"
						}
					}

					Rectangle {
						width: 58
						height: parent.height
						radius: 9
						color: root.wallView === "grid"
							? M3Palette.m3tertiary
							: Qt.alpha(M3Palette.m3surface, 0.6)

						Text {
							anchors.centerIn: parent
							text: "▦"
							color: root.wallView === "grid"
								? "#FFFFFF"
								: Qt.alpha(M3Palette.m3onSurface, 0.55)
							font.pixelSize: 15
						}

						MouseArea {
							anchors.fill: parent
							onClicked: root.wallView = "grid"
						}
					}
				}

				Item {
					id: wallViewport

					anchors.top: wallToolbar.bottom
					anchors.bottom: parent.bottom
					anchors.left: parent.left
					anchors.right: parent.right
					anchors.topMargin: 6
					clip: true

					ListView {
						id: wallList

						anchors.fill: parent
						orientation: ListView.Vertical
						interactive: false
						spacing: 16
						boundsBehavior: Flickable.StopAtBounds
						model: wallpaperResults(input.text)
						clip: true
						visible: root.wallView === "carousel"
						currentIndex: 0

						Behavior on contentY {
							NumberAnimation {
								duration: 260
								easing.type: Easing.OutCubic
							}
						}

						onCountChanged: {
							for (let i = 0; i < wallList.count; ++i) {
								if (wallList.model?.[i]?.path === Wallpapers.actualCurrent) {
									wallList.currentIndex = i;
									wallList.positionViewAtIndex(i, ListView.Center);
									return;
								}
							}
							wallList.currentIndex = 0;
						}

						delegate: Item {
							id: wallCard

							required property var modelData

							width: wallList.width
							height: Math.round(wallList.height * 0.62)

							readonly property bool isCurrent: modelData?.path === Wallpapers.actualCurrent
							readonly property bool isSelected: ListView.isCurrentItem

							scale: wallCard.isSelected ? 1 : 0.94
							opacity: wallCard.isSelected ? 1 : 0.78

							Behavior on scale {
								NumberAnimation {
									duration: 180
									easing.type: Easing.OutCubic
								}
							}
							Behavior on opacity {
								NumberAnimation {
									duration: 180
									easing.type: Easing.OutCubic
								}
							}

							SequentialAnimation {
								id: wallClickAnim

								running: false
								NumberAnimation {
									target: wallFlash
									property: "opacity"
									to: 0.35
									duration: 70
								}
								NumberAnimation {
									target: wallFlash
									property: "opacity"
									to: 0
									duration: 260
									easing.type: Easing.OutCubic
								}
							}

							Rectangle {
								id: wallFrame

								width: parent.width
								height: Math.min(parent.height, Math.round(parent.width / 16 * 9))
								anchors.centerIn: parent
								radius: 16
								clip: true
								color: Qt.alpha(M3Palette.m3surface, 0.35)
								border.color: (wallHover.containsMouse || wallCard.isSelected || wallCard.isCurrent)
									? M3Palette.m3tertiary
									: Qt.alpha(M3Palette.m3onSurface, 0.12)
								border.width: (wallHover.containsMouse || wallCard.isSelected || wallCard.isCurrent) ? 2 : 1

								Image {
									id: wallImage

									anchors.top: parent.top
									anchors.left: parent.left
									anchors.right: parent.right
									height: parent.height
									source: modelData?.path ? "file://" + modelData.path : ""
									fillMode: Image.PreserveAspectCrop
									asynchronous: true
								}

								// 当前壁纸：右上角对勾（不用文字）
								Rectangle {
									visible: wallCard.isCurrent
									width: 24
									height: 24
									radius: 12
									color: M3Palette.m3tertiary
									anchors.top: parent.top
									anchors.right: parent.right
									anchors.margins: 8
									z: 5

									Text {
										anchors.centerIn: parent
										text: "✓"
										color: "#FFFFFF"
										font.pixelSize: 14
										font.bold: true
									}
								}

								// 点击反馈闪层
								Rectangle {
									id: wallFlash

									anchors.fill: parent
									radius: 16
									color: M3Palette.m3onSurface
									opacity: 0
									z: 6
								}
							}

							MouseArea {
								id: wallHover

								anchors.fill: parent
								hoverEnabled: true
								onClicked: {
									if (modelData?.path) {
										wallClickAnim.restart();
										Wallpapers.setWallpaper(modelData.path);
									}
								}
							}
						}
					}

					// 滚轮翻页（竖排模式）
					MouseArea {
						visible: root.wallView === "carousel"
						anchors.fill: parent
						acceptedButtons: Qt.NoButton
						onWheel: wheel => {
							const delta = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : wheel.angleDelta.x;
							let idx = wallList.currentIndex + (delta < 0 ? 1 : -1);
							idx = Math.max(0, Math.min(idx, wallList.count - 1));
							wallList.currentIndex = idx;
							wallList.positionViewAtIndex(idx, ListView.Center);
						}
					}

					// 网格视图
					GridView {
						id: wallGrid

						visible: root.wallView === "grid"
						anchors.fill: parent
						clip: true
						cellWidth: Math.max(150, Math.round((parent.width - 8) / 2))
						cellHeight: Math.round(cellWidth / 16 * 9 + 6)
						model: wallpaperResults(input.text)

						delegate: Item {
							id: gridCard

							required property var modelData

							width: wallGrid.cellWidth
							height: wallGrid.cellHeight

							readonly property bool isCurrent: modelData?.path === Wallpapers.actualCurrent

							Rectangle {
								id: gridFrame

								anchors.fill: parent
								anchors.margins: 4
								radius: 12
								clip: true
								color: Qt.alpha(M3Palette.m3surface, 0.35)
								border.color: (gridHover.containsMouse || gridCard.isCurrent)
									? M3Palette.m3tertiary
									: Qt.alpha(M3Palette.m3onSurface, 0.12)
								border.width: (gridHover.containsMouse || gridCard.isCurrent) ? 2 : 1

								Image {
									anchors.fill: parent
									source: modelData?.path ? "file://" + modelData.path : ""
									fillMode: Image.PreserveAspectCrop
									asynchronous: true
								}

								Rectangle {
									visible: gridCard.isCurrent
									width: 22
									height: 22
									radius: 11
									color: M3Palette.m3tertiary
									anchors.top: parent.top
									anchors.right: parent.right
									anchors.margins: 6
									z: 5

									Text {
										anchors.centerIn: parent
										text: "✓"
										color: "#FFFFFF"
										font.pixelSize: 13
										font.bold: true
									}
								}

								Rectangle {
									id: gridFlash

									anchors.fill: parent
									radius: 12
									color: M3Palette.m3onSurface
									opacity: 0
									z: 6
								}
							}

							SequentialAnimation {
								id: gridClickAnim

								running: false
								NumberAnimation {
									target: gridFlash
									property: "opacity"
									to: 0.35
									duration: 70
								}
								NumberAnimation {
									target: gridFlash
									property: "opacity"
									to: 0
									duration: 260
									easing.type: Easing.OutCubic
								}
							}

							MouseArea {
								id: gridHover

								anchors.fill: parent
								hoverEnabled: true
								onClicked: {
									if (modelData?.path) {
										gridClickAnim.restart();
										Wallpapers.setWallpaper(modelData.path);
									}
								}
							}
						}
					}
				}
			}
		}

		// 拖拽幽灵
		Item {
			id: dragGhost

			width: 56
			height: 56
			visible: root.ghostVisible
			z: 1000

			Rectangle {
				anchors.fill: parent
				radius: 14
				color: Qt.alpha(M3Palette.m3surfaceContainerHigh, 0.96)
				border.color: M3Palette.m3tertiary
				border.width: 1

				IconImage {
					anchors.centerIn: parent
					implicitSize: 34
					source: root.ghostIcon
				}
			}
		}
	}

	// ---------------- 数据 ----------------
	function resetAppSelection(): void {
		if (appList.count > 0) {
			appList.currentIndex = 0;
			appList.positionViewAtIndex(0, ListView.Beginning);
		} else {
			appList.currentIndex = -1;
		}
	}

	function moveAppSelection(delta: int): void {
		if (appList.count === 0)
			return;
		const next = Math.max(0, Math.min(appList.count - 1, appList.currentIndex + delta));
		if (next !== appList.currentIndex) {
			appList.currentIndex = next;
			appList.positionViewAtIndex(next, ListView.Contain);
		}
	}

	function launchSelectedApp(): void {
		const entry = appList.count > 0
			? (appList.currentItem?.modelData ?? appList.model?.[appList.currentIndex])
			: null;
		if (!entry)
			return;
		console.info(`[spotlight-key] launch ${entry.name ?? ""}`);
		Apps.launch(entry);
		root.closeRequested();
	}

	function appResults(text: string): var {
		text = (text || "").trim();
		return Apps.search(text).filter(a => !!a).slice(0, 60);
	}

	function wallpaperResults(text: string): var {
		text = (text || "").trim();
		return Wallpapers.query(text).filter(a => !!a);
	}
}
