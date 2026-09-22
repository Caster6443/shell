pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Window
import Quickshell
import qs.cheatsheet

// 快捷键速查弹窗。渲染结构：分类区块（标题在上）+ 每行"键帽 | 描述"。
// 普通窗口（非 layer shell），Escape / q / 失焦关闭。
// 开启动画由 Hyprland 窗口规则（title=^cheatsheet$ -> slide top）负责，
// 窗口与内容作为整体从上往下滑入，内容层不再自己做动画。
FloatingWindow {
	id: root

	title: "cheatsheet"
	color: "transparent"
	visible: CheatsheetState.active

	// 键帽显示名：把生硬的键名映射成人类可读的写法
	function keyLabel(k: string): string {
		const map = {
			"super": "Super",
			"super_l": "Win",
			"super_r": "Win",
			"ctrl": "Ctrl",
			"shift": "Shift",
			"alt": "Alt",
			"left": "←",
			"right": "→",
			"up": "↑",
			"down": "↓",
			"page_up": "PgUp",
			"page_down": "PgDn",
			"slash": "/",
			"backslash": "\\",
			"period": ".",
			"comma": ",",
			"minus": "-",
			"equal": "=",
			"escape": "Esc",
			"return": "Enter",
			"enter": "Enter",
			"space": "Space",
			"print": "PrtSc",
			"tab": "Tab",
			"mouse_up": "滚轮上",
			"mouse_down": "滚轮下",
			"mouse:272": "左键",
			"mouse:273": "右键",
		};
		return map[k.toLowerCase()] ?? k;
	}

	implicitWidth: Math.round(Screen.width * 0.72)
	implicitHeight: Math.round(Screen.height * 0.72)

	// ---- 动态分栏 ----
	// 分类按估算高度贪心分配到 N 列，各列独立堆叠：
	// 避免 Grid 行高取最高列导致的整块空白。
	property var cheatsheetData: KeybindsData.data
	property var columnModels: []
	readonly property int columnCount: Math.max(1, Math.floor(((Screen.width * 0.72 - 80) + 44) / (380 + 44)))

	function rebuildColumns(): void {
		const cols = [];
		for (let i = 0; i < columnCount; i++)
			cols.push({ items: [], height: 0 });

		const titleH = 34; // 分类标题的估算高度
		const entryH = 40; // 单条快捷键的估算高度
		const gap = 40;    // 分类之间的间距

		for (const cat of (cheatsheetData || [])) {
			if (!cat.keybinds || cat.keybinds.length === 0)
				continue;
			const h = titleH + cat.keybinds.length * entryH;
			let best = 0;
			for (let i = 1; i < cols.length; i++) {
				if (cols[i].height < cols[best].height)
					best = i;
			}
			cols[best].items.push(cat);
			cols[best].height += h + gap;
		}
		columnModels = cols.map(c => c.items);
	}

	onCheatsheetDataChanged: rebuildColumns()
	Component.onCompleted: rebuildColumns()

	Shortcut {
		sequence: "Escape"
		onActivated: CheatsheetState.active = false
	}

	Shortcut {
		sequence: "q"
		onActivated: CheatsheetState.active = false
	}

	onVisibleChanged: {
		if (visible) {
			focusCatcher.forceActiveFocus();
			scroll.contentY = 0; // 每次打开都回到顶部，不保留上次的滚动位置
		}
	}

	Item {
		id: focusCatcher

		anchors.fill: parent
		focus: true

		onActiveFocusChanged: {
			if (!activeFocus)
				CheatsheetState.active = false;
		}

		Keys.onPressed: event => {
			if (event.key === Qt.Key_Escape || event.key === Qt.Key_Q) {
				CheatsheetState.active = false;
				event.accepted = true;
			}
		}
	}

	Rectangle {
		anchors.fill: parent
		color: Qt.alpha(CheatsheetTheme.background, 0.86)
		radius: 18
		border.color: CheatsheetTheme.primary
		border.width: 1
		clip: true

		Text {
			id: title

			anchors.top: parent.top
			anchors.left: parent.left
			anchors.right: parent.right
			anchors.topMargin: 40
			anchors.leftMargin: 40
			anchors.rightMargin: 40
			text: "Caelestia Cheatsheet"
			horizontalAlignment: Text.AlignHCenter
			font.pixelSize: 30
			font.bold: true
			font.family: "PingFang SC"
			color: CheatsheetTheme.primary
		}

		Flickable {
			id: scroll

			anchors.top: title.bottom
			anchors.left: parent.left
			anchors.right: parent.right
			anchors.bottom: parent.bottom
			anchors.topMargin: 28
			anchors.leftMargin: 40
			anchors.rightMargin: 40
			anchors.bottomMargin: 40
			clip: true
			contentHeight: columnsRow.implicitHeight + 1

			Row {
				id: columnsRow

				width: implicitWidth
				spacing: 44

				Repeater {
					model: root.columnModels

					delegate: Column {
						required property var modelData

						width: 380
						spacing: 40

						Repeater {
							model: modelData

							delegate: Column {
								required property var modelData

								width: 380
								spacing: 18

								Text {
									text: (modelData ? modelData.category : "").charAt(0).toUpperCase() + (modelData ? modelData.category : "").slice(1)
									font.pixelSize: 22
									font.bold: true
									font.family: "PingFang SC"
									color: CheatsheetTheme.primary
								}

								Column {
									spacing: 12

									Repeater {
										model: modelData && modelData.keybinds ? modelData.keybinds : []

										delegate: Item {
											required property var modelData

											width: 380
											height: Math.max(36, descText.implicitHeight)

											// 键帽区：跟随内容宽度（上限 300px 防溢出），描述紧跟在键帽后
											Item {
												id: keysClip

												anchors.left: parent.left
												anchors.verticalCenter: parent.verticalCenter
												width: Math.min(300, keysRow.implicitWidth)
												height: keysRow.implicitHeight
												clip: true

												Row {
													id: keysRow

													anchors.left: parent.left
													anchors.verticalCenter: parent.verticalCenter
													spacing: 6

													Repeater {
														id: keyRepeater

														// 只把真正的键名画成键帽；"+" 分隔符是纯字符，不进模型
														model: modelData.key ? modelData.key.split(" ").filter(k => k.trim() !== "" && k !== "+") : []

														delegate: Row {
															required property string modelData
															required property int index

															spacing: 5
															anchors.verticalCenter: parent.verticalCenter

															Rectangle {
																color: CheatsheetTheme.primary
																radius: 5
																implicitWidth: keyFace.implicitWidth + 3
																implicitHeight: keyFace.implicitHeight + 4

																Rectangle {
																	id: keyFace

																	anchors.fill: parent
																	anchors.topMargin: 2
																	anchors.leftMargin: 3
																	anchors.rightMargin: 1
																	// 底边略厚于顶边，保留一点立体感
																	anchors.bottomMargin: 4

																	implicitWidth: keyText.implicitWidth + 14
																	implicitHeight: keyText.implicitHeight + 8
																	color: CheatsheetTheme.surface
																	radius: 4

																	Text {
																		id: keyText

																		text: root.keyLabel(modelData)
																		anchors.centerIn: parent
																		font.pixelSize: 13
																		font.family: "PingFang SC"
																		font.bold: true
																		color: CheatsheetTheme.primary
																	}
																}
															}

															Text {
																text: "+"
																visible: index < (keyRepeater.count - 1)
																anchors.verticalCenter: parent.verticalCenter
																font.pixelSize: 12
																color: CheatsheetTheme.textColor
																opacity: 0.55
															}
														}
													}
												}
											}

											Text {
												id: descText

												// 描述紧跟在键帽之后，长组合键自动把描述右移，避免重叠
												x: keysClip.width + 24
												width: parent.width - x - 12
												anchors.verticalCenter: parent.verticalCenter
												text: modelData.desc
												font.pixelSize: 15
												font.family: "PingFang SC"
												color: CheatsheetTheme.textColor
												wrapMode: Text.WordWrap
											}
										}
									}
								}
							}
						}
					}
				}
			}
		}
	}
}
