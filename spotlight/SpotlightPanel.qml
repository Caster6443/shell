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
	// 顶部标签顺序（胶囊按索引滑动，cycleMode 也用这个顺序）
	readonly property var modeOrder: ["apps", "wallpaper", "clipboard", "emoji"]
	readonly property int modeIndex: Math.max(0, root.modeOrder.indexOf(root.mode))

	function modeLabel(m: string): string {
		if (m === "apps")
			return "应用";
		if (m === "wallpaper")
			return "壁纸";
		if (m === "clipboard")
			return "剪贴板";
		return "Emoji";
	}

	function modePlaceholder(m: string): string {
		if (m === "wallpaper")
			return "搜索壁纸…";
		if (m === "clipboard")
			return "搜索剪贴板历史…";
		if (m === "emoji")
			return "搜索 Emoji（英文关键词）…";
		return "搜索应用…";
	}
	// 壁纸模式默认视图：竖排列表（carousel）；用户 2026-09-04 确认不用网格
	property string wallView: "carousel"
	// 无本地结果时回车回退到浏览器搜索（?q= 后由 openWebSearch 自动拼接查询词）
	readonly property string webSearchBase: "https://www.bing.com/search?q="
	property real maxHeight: 900

	// ---------------- 生命周期 ----------------
	// 面板内容现在常驻（launcher Wrapper 的本地补丁：首次打开后不再销毁重建），
	// 所以这里同时负责「每次打开」和「完全关闭后」的重置工作。
	Component.onCompleted: Qt.callLater(() => {
		if (root.mode === "apps")
			root.resetAppSelection();
		// 预热（隐藏状态创建）时不要抢焦点，只在真正可见时补焦点。
		if (root.visible)
			input.forceActiveFocus();
	})

	// 打开流程里唯一会起外部进程的重活（cliphist list）：推迟到面板已经上屏之后再跑，
	// 不和入场动画抢主线程与 CPU。
	Timer {
		id: clipboardRefreshTimer
		interval: 250
		repeat: false
		onTriggered: ClipboardData.refresh()
	}

	onVisibleChanged: {
		if (visible) {
			hoverCloseTimer.stop();
			input.text = "";
			root.launchWatch = null;
			root.ghostVisible = false;
			SpotlightState.active = true;
			// 剪贴板历史每次打开刷新一次（一个 cliphist list 进程，很便宜）
			clipboardRefreshTimer.restart();
			ov.refresh();
			ov.unlockCaptureSequence();
			Qt.callLater(() => ov.settleToActive());
			input.forceActiveFocus();
			Qt.callLater(root.resetAppSelection);
		} else {
			SpotlightState.active = false;
			clipboardRefreshTimer.stop();
			// 面板常驻后不再随关闭销毁重建，这里显式回到默认标签页，
			// 保持与之前「每次打开都停在应用标签」一致的手感。
			root.mode = "apps";
		}
	}

	// 鼠标离开面板即自动关闭；给 150ms 宽限，避免贴着边缘/拖动时被误关。
	HoverHandler {
		onHoveredChanged: {
			if (hovered)
				hoverCloseTimer.stop();
			else if (root.visible)
				hoverCloseTimer.restart();
		}
	}

	Timer {
		id: hoverCloseTimer

		interval: 150
		repeat: false
		onTriggered: {
			if (root.visible)
				root.closeRequested();
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

	// ---------------- 应用 → 指定工作区启动 ----------------
	function shq(s: string): string {
		return "'" + String(s).replace(/'/g, "'\\''") + "'";
	}

	function buildLaunchArgv(entry: var): var {
		if (entry?.runInTerminal)
			return [...GlobalConfig.general.apps.terminal, `${Quickshell.shellDir}/assets/wrap_term_launch.sh`, ...(entry.command ?? [])];
		return entry?.command ?? [];
	}

	// 模式标签切换：滚轮向上 = 下一个标签，向下 = 上一个标签（按 modeOrder 循环；方向按用户实测反馈定）
	function cycleMode(deltaY: real): void {
		if (deltaY === 0)
			return;
		const order = root.modeOrder;
		const idx = order.indexOf(root.mode);
		const step = deltaY < 0 ? 1 : -1;
		const next = order[(idx + step + order.length) % order.length];
		if (next !== root.mode)
			root.mode = next;
	}

	// 壁纸视图（竖排 / 网格）切换：方向与标签一致
	function cycleWallView(deltaY: real): void {
		if (deltaY === 0)
			return;
		const order = ["carousel", "grid"];
		const idx = Math.max(0, order.indexOf(root.wallView));
		const step = deltaY < 0 ? 1 : -1;
		root.wallView = order[(idx + step + order.length) % order.length];
	}

	// ws 是工作区选择符字符串：普通工作区 "3"，特殊工作区 "special:slot1"
	function launchOnWorkspace(entry: var, ws: var, isSpecial: bool): void {
		launchRefreshTimer.restart();
		if (isSpecial) {
			root.pendingLaunch = { entry: entry, ws: ws, special: true };
			clientsProc.running = true;
			return;
		}
		const argv = root.buildLaunchArgv(entry);
		const cmdline = argv.map(root.shq).join(" ");
		const luaCmd = String(cmdline).replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\n/g, "\\n");
		const expr = `hl.dispatch(hl.dsp.exec_cmd("${luaCmd}", { workspace = "${ws} silent" }))`;
		console.info(`[spotlight-launch] eval ws=${ws}: ${cmdline.slice(0, 120)}`);
		Quickshell.execDetached(["hyprctl", "eval", expr]);
	}

	Timer {
		id: launchRefreshTimer

		interval: 1000
		repeat: false
		onTriggered: ov.refresh()
	}

	// wsId 这里其实是工作区选择符（普通 "3" / 特殊 "special:slot1"），用 var 接收
	function beginWatch(snapshot: var, entry: var, wsId: var, isSpecial: bool): void {
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
						const ws = String(watch.ws);
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

				placeholderText: root.modePlaceholder(root.mode)
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
					} else if (root.mode === "wallpaper") {
						root.moveWallSelection(0, 1);
						event.accepted = true;
					} else if (root.mode === "clipboard") {
						root.moveClipSelection(1, 0);
						event.accepted = true;
					} else if (root.mode === "emoji") {
						root.moveEmojiSelection(0, 1);
						event.accepted = true;
					}
				}
				Keys.onUpPressed: event => {
					if (root.mode === "apps") {
						root.moveAppSelection(-1);
						event.accepted = true;
					} else if (root.mode === "wallpaper") {
						root.moveWallSelection(0, -1);
						event.accepted = true;
					} else if (root.mode === "clipboard") {
						root.moveClipSelection(-1, 0);
						event.accepted = true;
					} else if (root.mode === "emoji") {
						root.moveEmojiSelection(0, -1);
						event.accepted = true;
					}
				}
				Keys.onLeftPressed: event => {
					if (root.mode === "wallpaper" && root.wallView === "grid") {
						root.moveWallSelection(-1, 0);
						event.accepted = true;
					} else if (root.mode === "emoji") {
						root.moveEmojiSelection(-1, 0);
						event.accepted = true;
					}
				}
				Keys.onRightPressed: event => {
					if (root.mode === "wallpaper" && root.wallView === "grid") {
						root.moveWallSelection(1, 0);
						event.accepted = true;
					} else if (root.mode === "emoji") {
						root.moveEmojiSelection(1, 0);
						event.accepted = true;
					}
				}
				onTextChanged: {
					if (root.mode === "apps")
						Qt.callLater(root.resetAppSelection);
					else if (root.mode === "wallpaper")
						Qt.callLater(root.resetWallSelection);
					else if (root.mode === "clipboard")
						Qt.callLater(root.resetClipSelection);
					else if (root.mode === "emoji")
						Qt.callLater(root.resetEmojiSelection);
				}
				onAccepted: {
					if (root.mode === "apps") {
						if (appList.count > 0)
							root.launchSelectedApp();
						else if (input.text.trim())
							root.openWebSearch(input.text);
					} else if (root.mode === "wallpaper") {
						root.applySelectedWallpaper();
					} else if (root.mode === "clipboard") {
						root.copySelectedClip();
					} else if (root.mode === "emoji") {
						root.copySelectedEmoji();
					}
				}
			}

			// 顶部：模式切换（应用 / 壁纸 / 剪贴板 / Emoji）
			Rectangle {
				id: modeHeader

				width: 300
				height: 30
				radius: 15
				color: Qt.alpha(M3Palette.m3surface, 0.55)
				border.color: Qt.alpha(M3Palette.m3onSurface, 0.15)
				border.width: 1

				// 滑块胶囊：单一元素在标签之间滑过去（按 modeIndex 定位）
				Rectangle {
					id: modePill

					y: 2
					width: (modeHeader.width - 4) / root.modeOrder.length
					height: modeHeader.height - 4
					radius: 13
					color: M3Palette.m3tertiary
					x: 2 + root.modeIndex * width

					Behavior on x {
						NumberAnimation {
							duration: 190
							easing.type: Easing.OutCubic
						}
					}
				}

				Row {
					anchors.fill: parent

					Repeater {
						model: root.modeOrder

						delegate: Item {
							id: modeTab
							required property string modelData

							width: modeHeader.width / root.modeOrder.length
							height: modeHeader.height

							Text {
								anchors.centerIn: parent
								text: root.modeLabel(modeTab.modelData)
								color: root.mode === modeTab.modelData
									? "#FFFFFF"
									: Qt.alpha(M3Palette.m3onSurface, 0.5)
								font.pixelSize: 11
								font.bold: root.mode === modeTab.modelData
							}

							MouseArea {
								anchors.fill: parent
								hoverEnabled: true
								// 悬停在选项卡上滚轮也能切换模式
								onWheel: wheel => {
									wheel.accepted = true;
									root.cycleMode(wheel.angleDelta.y);
								}
								onClicked: {
									root.mode = modeTab.modelData;
									if (modeTab.modelData === "clipboard")
										ClipboardData.refresh();
								}
							}
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

						// 零结果提示：回车会用默认浏览器搜索
						Text {
							id: webSearchHint

							anchors.top: appTitle.bottom
							anchors.left: parent.left
							anchors.right: parent.right
							anchors.topMargin: 8
							visible: appList.count === 0 && input.text.trim() !== ""
							text: "没有匹配的应用 — 回车用浏览器搜索"
							color: Qt.alpha(M3Palette.m3onSurface, 0.45)
							font.pixelSize: 12
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

							// 选中条平滑流动（原版 caelestia launcher 同款：highlight 跟随 currentItem.y）
							highlightFollowsCurrentItem: false
							preferredHighlightBegin: 0
							preferredHighlightEnd: appList.height
							highlightRangeMode: ListView.ApplyRange
							highlight: Rectangle {
								width: appList.width
								height: 52
								radius: 10
								color: Qt.alpha(M3Palette.m3tertiary, 0.26)
								border.color: Qt.alpha(M3Palette.m3tertiary, 0.7)
								border.width: 1

								y: appList.currentItem?.y ?? 0

								Behavior on y {
									NumberAnimation {
										duration: 220
										easing.type: Easing.OutCubic
									}
								}
							}

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
									// 选中态由 ListView 流动高亮条负责，行内只保留非选中时的悬停底
									color: rowMouse.containsMouse && !appRow.ListView.isCurrentItem
										? Qt.alpha(M3Palette.m3onSurface, 0.08)
										: "transparent"
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
										let hitWs = "";
										if (wasDrag) {
											const p = rowMouse.mapToItem(ov, mouse.x, mouse.y);
											hitWs = ov.workspaceAt(p);
											console.info(`[spotlight-drag] release ${modelData.name ?? ""} ws=${hitWs}`);
											if (hitWs !== "")
												root.launchOnWorkspace(modelData, hitWs, ov.isSpecialWorkspaceKey(hitWs));
										}
										appRow.Drag.active = false;
										appRow.opacity = 1;
										root.ghostVisible = false;
										rowMouse.pressMightDrag = false;
										if (!wasDrag) {
											console.info(`[spotlight-click] launch ${modelData.name ?? ""}`);
											Apps.launch(modelData);
											launchRefreshTimer.restart();
											// 点击启动后自动关闭；只有拖放到工作区（wasDrag）才保持打开
											root.closeRequested();
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

					// 随机 Booru 壁纸（只取 rating:safe）：抓一张随机图下载到缓存再应用
					Rectangle {
						id: booruButton

						width: booruLabel.implicitWidth + 20
						height: parent.height
						radius: 9
						color: BooruWallpaper.busy
							? Qt.alpha(M3Palette.m3tertiary, 0.5)
							: (booruArea.containsMouse ? Qt.alpha(M3Palette.m3tertiary, 0.35) : Qt.alpha(M3Palette.m3surface, 0.6))

						Text {
							id: booruLabel

							anchors.centerIn: parent
							text: BooruWallpaper.busy ? "抓取中…" : "🎲 随机壁纸"
							color: BooruWallpaper.busy ? "#FFFFFF" : M3Palette.m3onSurface
							font.pixelSize: 12
						}

						MouseArea {
							id: booruArea

							anchors.fill: parent
							hoverEnabled: true
							onClicked: BooruWallpaper.randomize()
						}
					}

					Text {
						anchors.verticalCenter: parent.verticalCenter
						visible: BooruWallpaper.status !== ""
						text: BooruWallpaper.status
						color: Qt.alpha(M3Palette.m3onSurface, 0.55)
						font.pixelSize: 11
					}

					// 竖排 / 网格 切换：单一滑块 + 滚轮切换（与顶部标签同一套手势方向）
					Rectangle {
						id: wallViewSwitch

						width: 116
						height: parent.height
						radius: 9
						color: Qt.alpha(M3Palette.m3surface, 0.6)

						Rectangle {
							id: wallViewPill

							y: 2
							width: (wallViewSwitch.width - 4) / 2
							height: wallViewSwitch.height - 4
							radius: 7
							color: M3Palette.m3tertiary
							x: 2 + (root.wallView === "carousel" ? 0 : width)

							Behavior on x {
								NumberAnimation {
									duration: 160
									easing.type: Easing.OutCubic
								}
							}
						}

						Row {
							anchors.fill: parent

							Item {
								width: wallViewSwitch.width / 2
								height: wallViewSwitch.height

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
									hoverEnabled: true
									onWheel: wheel => {
										wheel.accepted = true;
										root.cycleWallView(wheel.angleDelta.y);
									}
									onClicked: root.wallView = "carousel"
								}
							}

							Item {
								width: wallViewSwitch.width / 2
								height: wallViewSwitch.height

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
									hoverEnabled: true
									onWheel: wheel => {
										wheel.accepted = true;
										root.cycleWallView(wheel.angleDelta.y);
									}
									onClicked: root.wallView = "grid"
								}
							}
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
						spacing: 12
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
							height: Math.round(wallList.height * 0.46)

							readonly property bool isCurrent: modelData?.path === Wallpapers.actualCurrent
							readonly property bool isSelected: ListView.isCurrentItem

							// 外层只负责“选中放大”的基准缩放，点击回弹动画放到内层 wallFrame，互不干扰
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

								// 点击反馈：轻微缩小再快速回位。pressScale 由单一 SequentialAnimation 控制，
								// 不设 Behavior（避免 Behavior 与显式动画在同一属性上叠加打架）
								property real pressScale: 1
								scale: wallFrame.pressScale

								Image {
									id: wallImage

									anchors.top: parent.top
									anchors.left: parent.left
									anchors.right: parent.right
									height: parent.height
									source: modelData?.path ? "file://" + modelData.path : ""
									fillMode: Image.PreserveAspectCrop
									asynchronous: true
									sourceSize: Qt.size(
										Math.max(640, Math.round(width * 2)),
										Math.max(360, Math.round(height * 2))
									)
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
							}

							MouseArea {
								id: wallHover

								anchors.fill: parent
								hoverEnabled: true
								onClicked: {
									if (modelData?.path) {
										wallPressAnim.restart();
										Wallpapers.setWallpaper(modelData.path);
									}
								}
							}

							// 点击反馈单一动画源：快速收缩 → 带回弹回位
							SequentialAnimation {
								id: wallPressAnim

								running: false
								NumberAnimation {
									target: wallFrame
									property: "pressScale"
									to: 0.9
									duration: 60
								}
								NumberAnimation {
									target: wallFrame
									property: "pressScale"
									to: 1
									duration: 170
									easing.type: Easing.OutBack
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
						cellWidth: parent.width >= 900
							? Math.round((parent.width - 24) / 4)
							: Math.round((parent.width - 16) / 3)
						cellHeight: Math.round(cellWidth / 16 * 9 + 10)
						model: wallpaperResults(input.text)
						currentIndex: 0

						onCountChanged: {
							for (let i = 0; i < wallGrid.count; ++i) {
								if (wallGrid.model?.[i]?.path === Wallpapers.actualCurrent) {
									wallGrid.currentIndex = i;
									wallGrid.positionViewAtIndex(i, GridView.Center);
									return;
								}
							}
							wallGrid.currentIndex = 0;
						}

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

								// 点击反馈：轻微缩小再快速回位。pressScale 由单一 SequentialAnimation 控制，
								// 不设 Behavior（避免 Behavior 与显式动画在同一属性上叠加打架）
								property real pressScale: 1
								scale: gridFrame.pressScale

								Image {
									anchors.fill: parent
									source: modelData?.path ? "file://" + modelData.path : ""
									fillMode: Image.PreserveAspectCrop
									asynchronous: true
									sourceSize: Qt.size(
										Math.max(480, Math.round(width * 2)),
										Math.max(270, Math.round(height * 2))
									)
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
							}

							// 点击反馈单一动画源：快速收缩 → 带回弹回位
							SequentialAnimation {
								id: gridPressAnim

								running: false
								NumberAnimation {
									target: gridFrame
									property: "pressScale"
									to: 0.9
									duration: 60
								}
								NumberAnimation {
									target: gridFrame
									property: "pressScale"
									to: 1
									duration: 170
									easing.type: Easing.OutBack
								}
							}

							MouseArea {
								id: gridHover

								anchors.fill: parent
								hoverEnabled: true
								onClicked: {
									if (modelData?.path) {
										gridPressAnim.restart();
										Wallpapers.setWallpaper(modelData.path);
									}
								}
							}
						}
						}
					}
				}

			// ---------------- 剪贴板历史（cliphist） ----------------
			Item {
				id: clipboardBody

				visible: root.mode === "clipboard"
				width: parent.width
				height: parent.height - input.height - modeHeader.height - parent.spacing * 2

				Text {
					anchors.centerIn: parent
					visible: clipList.count === 0
					text: ClipboardData.busy
						? "读取剪贴板历史…"
						: (ClipboardData.entries.length === 0
							? "剪贴板历史为空（需要 cliphist + wl-paste --watch cliphist store）"
							: "没有匹配的条目")
					color: Qt.alpha(M3Palette.m3onSurface, 0.5)
					font.pixelSize: 14
				}

				ListView {
					id: clipList

					anchors.fill: parent
					clip: true
					spacing: 4
					model: ClipboardData.query(input.text)
					currentIndex: -1

					onCountChanged: {
						if (currentIndex < 0 && count > 0)
							currentIndex = 0;
					}

					delegate: Rectangle {
						id: clipRow
						required property var modelData
						required property int index

						width: clipList.width
						height: clipRow.modelData.isImage ? 152 : 56
						radius: 12
						color: (clipList.currentIndex === clipRow.index || clipRowMouse.containsMouse)
							? Qt.alpha(M3Palette.m3tertiary, 0.22)
							: Qt.alpha(M3Palette.m3surface, 0.3)

						Text {
							id: clipIcon

							anchors.left: parent.left
							anchors.leftMargin: 12
							anchors.verticalCenter: parent.verticalCenter
							visible: !clipRow.modelData.isImage
							text: "📄"
							font.pixelSize: 18
						}

						// 图片条目：解码一次画大预览（保持比例、完整显示，缓存见 ClipboardData.thumbs）
						Image {
							id: clipThumb

							anchors.left: parent.left
							anchors.right: parent.right
							anchors.leftMargin: 12
							anchors.rightMargin: 12
							anchors.verticalCenter: parent.verticalCenter
							visible: clipRow.modelData.isImage
							height: 132
							source: clipRow.modelData.isImage ? ClipboardData.thumbFor(clipRow.modelData.id) : ""
							sourceSize: Qt.size(512, 512)
							fillMode: Image.PreserveAspectFit
							asynchronous: true
							cache: false

							Component.onCompleted: {
								if (clipRow.modelData.isImage)
									ClipboardData.requestThumb(clipRow.modelData);
							}

							Rectangle {
								anchors.fill: parent
								visible: parent.status !== Image.Ready
								color: Qt.alpha(M3Palette.m3surface, 0.6)

								Text {
									anchors.centerIn: parent
									text: "🖼"
									font.pixelSize: 18
								}
							}
						}

						Text {
							anchors.left: clipRow.modelData.isImage ? clipThumb.right : clipIcon.right
							anchors.leftMargin: 10
							anchors.right: parent.right
							anchors.rightMargin: 12
							anchors.verticalCenter: parent.verticalCenter
							visible: !clipRow.modelData.isImage
							text: clipRow.modelData.preview
							textFormat: Text.PlainText
							elide: Text.ElideRight
							maximumLineCount: 1
							color: M3Palette.m3onSurface
							font.pixelSize: 15
						}

						// 图片条目：底部一条尺寸/大小说明（图片本体按比例完整显示，不裁剪）
						Text {
							anchors.left: parent.left
							anchors.bottom: parent.bottom
							anchors.leftMargin: 12
							anchors.bottomMargin: 6
							visible: clipRow.modelData.isImage && clipRow.modelData.info !== ""
							text: clipRow.modelData.info
							textFormat: Text.PlainText
							color: Qt.alpha(M3Palette.m3onSurface, 0.6)
							font.pixelSize: 12
						}

						MouseArea {
							id: clipRowMouse

							anchors.fill: parent
							hoverEnabled: true
							acceptedButtons: Qt.LeftButton | Qt.MiddleButton
							onEntered: clipList.currentIndex = clipRow.index
							onClicked: mouse => {
								if (mouse.button === Qt.MiddleButton) {
									ClipboardData.remove(clipRow.modelData);
									return;
								}
								root.copyClipEntry(clipRow.modelData);
							}
						}
					}
				}
			}

			// ---------------- Emoji 选择器 ----------------
			Item {
				id: emojiBody

				visible: root.mode === "emoji"
				width: parent.width
				height: parent.height - input.height - modeHeader.height - parent.spacing * 2

				Text {
					anchors.centerIn: parent
					visible: emojiGrid.count === 0
					text: EmojiData.loaded ? "没有匹配的 Emoji" : "正在载入 Emoji 数据…"
					color: Qt.alpha(M3Palette.m3onSurface, 0.5)
					font.pixelSize: 12
				}

				GridView {
					id: emojiGrid

					anchors.fill: parent
					clip: true
					cellWidth: 58
					cellHeight: 58
					model: EmojiData.query(input.text)
					currentIndex: -1

					onCountChanged: {
						if (currentIndex < 0 && count > 0)
							currentIndex = 0;
					}

					delegate: Rectangle {
						id: emojiCell
						required property var modelData
						required property int index

						width: emojiGrid.cellWidth - 4
						height: emojiGrid.cellHeight - 4
						radius: 10
						color: (emojiGrid.currentIndex === emojiCell.index || emojiCellMouse.containsMouse)
							? Qt.alpha(M3Palette.m3tertiary, 0.25)
							: "transparent"

						Text {
							anchors.centerIn: parent
							text: emojiCell.modelData.emoji
							font.pixelSize: 32
						}

						MouseArea {
							id: emojiCellMouse

							anchors.fill: parent
							hoverEnabled: true
							onEntered: emojiGrid.currentIndex = emojiCell.index
							onClicked: root.copyEmojiEntry(emojiCell.modelData)
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
	// 壁纸选中（carousel 列表 / grid 网格）当前项定位到“正在用的壁纸”
	function resetWallSelection(): void {
		if (root.wallView === "grid") {
			if (wallGrid.count > 0) {
				for (let i = 0; i < wallGrid.count; ++i) {
					if (wallGrid.model?.[i]?.path === Wallpapers.actualCurrent) {
						wallGrid.currentIndex = i;
						wallGrid.positionViewAtIndex(i, GridView.Center);
						return;
					}
				}
				wallGrid.currentIndex = 0;
			}
		} else {
			if (wallList.count > 0) {
				for (let i = 0; i < wallList.count; ++i) {
					if (wallList.model?.[i]?.path === Wallpapers.actualCurrent) {
						wallList.currentIndex = i;
						wallList.positionViewAtIndex(i, ListView.Center);
						return;
					}
				}
				wallList.currentIndex = 0;
			}
		}
	}

	// 方向键移动壁纸选中：carousel 只用 dy（上下），grid 用 dx+dy（四向）
	function moveWallSelection(dx: int, dy: int): void {
		if (root.wallView === "grid") {
			const cols = Math.max(1, Math.floor(wallGrid.width / wallGrid.cellWidth));
			const total = wallGrid.count;
			if (total === 0)
				return;
			let idx = wallGrid.currentIndex;
			if (dx !== 0) {
				const row = Math.floor(idx / cols);
				idx += dx;
				idx = Math.max(row * cols, Math.min(idx, Math.min((row + 1) * cols - 1, total - 1)));
			}
			if (dy !== 0) {
				idx += dy * cols;
				idx = Math.max(0, Math.min(idx, total - 1));
			}
			if (idx !== wallGrid.currentIndex) {
				wallGrid.currentIndex = idx;
				wallGrid.positionViewAtIndex(idx, GridView.Contain);
			}
		} else {
			const total = wallList.count;
			if (total === 0)
				return;
			const next = Math.max(0, Math.min(total - 1, wallList.currentIndex + dy));
			if (next !== wallList.currentIndex) {
				wallList.currentIndex = next;
				// Center：保持"中间完整、上下各露半张"的居中 carousel 视图（与滚轮一致）
				wallList.positionViewAtIndex(next, ListView.Center);
			}
		}
	}

	// 回车/确认应用当前选中的壁纸
	function applySelectedWallpaper(): void {
		const entry = root.wallView === "grid"
			? (wallGrid.count > 0
				? (wallGrid.currentItem?.modelData ?? wallGrid.model?.[wallGrid.currentIndex])
				: null)
			: (wallList.count > 0
				? (wallList.currentItem?.modelData ?? wallList.model?.[wallList.currentIndex])
				: null);
		if (!entry?.path)
			return;
		console.info(`[spotlight-key] wallpaper set ${entry.path}`);
		Wallpapers.setWallpaper(entry.path);
	}

	// ---------------- 剪贴板历史（cliphist） ----------------
	function resetClipSelection(): void {
		if (clipList.count > 0) {
			clipList.currentIndex = 0;
			clipList.positionViewAtIndex(0, ListView.Beginning);
		} else {
			clipList.currentIndex = -1;
		}
	}

	function moveClipSelection(delta: int): void {
		if (clipList.count === 0)
			return;
		if (clipList.currentIndex < 0) {
			clipList.currentIndex = 0;
			return;
		}
		const idx = Math.max(0, Math.min(clipList.currentIndex + delta, clipList.count - 1));
		clipList.currentIndex = idx;
		clipList.positionViewAtIndex(idx, ListView.Contain);
	}

	function copyClipEntry(entry: var): void {
		if (!entry)
			return;
		ClipboardData.copy(entry);
		root.closeRequested();
	}

	function copySelectedClip(): void {
		root.copyClipEntry(clipList.currentItem?.modelData ?? clipList.model?.[clipList.currentIndex]);
	}

	// ---------------- Emoji ----------------
	function resetEmojiSelection(): void {
		if (emojiGrid.count > 0) {
			emojiGrid.currentIndex = 0;
			emojiGrid.positionViewAtIndex(0, GridView.Beginning);
		} else {
			emojiGrid.currentIndex = -1;
		}
	}

	function moveEmojiSelection(dx: int, dy: int): void {
		const total = emojiGrid.count;
		if (total === 0)
			return;
		const cols = Math.max(1, Math.floor(emojiGrid.width / emojiGrid.cellWidth));
		let idx = emojiGrid.currentIndex < 0 ? 0 : emojiGrid.currentIndex;
		if (dx !== 0) {
			const row = Math.floor(idx / cols);
			idx = idx + dx;
			idx = Math.max(row * cols, Math.min(idx, Math.min((row + 1) * cols - 1, total - 1)));
		}
		if (dy !== 0)
			idx = Math.max(0, Math.min(idx + dy * cols, total - 1));
		emojiGrid.currentIndex = idx;
		emojiGrid.positionViewAtIndex(idx, GridView.Contain);
	}

	function copyEmojiEntry(item: var): void {
		if (!item)
			return;
		EmojiData.copy(item);
		root.closeRequested();
	}

	function copySelectedEmoji(): void {
		root.copyEmojiEntry(emojiGrid.currentItem?.modelData ?? emojiGrid.model?.[emojiGrid.currentIndex]);
	}

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

	function openWebSearch(query: string): void {
		const q = (query ?? "").trim();
		if (!q)
			return;
		const url = root.webSearchBase + encodeURIComponent(q);
		console.info(`[spotlight-web] open ${url}`);
		Quickshell.execDetached(["xdg-open", url]);
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
