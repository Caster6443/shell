pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Window
import Quickshell
import qs.cheatsheet

// 快捷键速查弹窗。渲染结构照搬旧版 cheatsheet：分类区块（标题在上）+ 每行"键帽 | 描述"。
// 普通窗口（非 layer shell），Escape / q / 失焦关闭。
FloatingWindow {
	id: root

	title: "cheatsheet"
	color: "transparent"
	visible: CheatsheetState.active

	// 键帽显示名：把生硬的键名映射成人类可读的写法
	function keyLabel(k: string): string {
		const map = {
			"SUPER": "Super",
			"SUPER_L": "Win",
			"SUPER_R": "Win",
			"CTRL": "Ctrl",
			"SHIFT": "Shift",
			"ALT": "Alt",
			"left": "←",
			"right": "→",
			"up": "↑",
			"down": "↓",
			"Page_Up": "PgUp",
			"Page_Down": "PgDn",
			"Page_up": "PgUp",
			"Page_down": "PgDn",
			"Slash": "/",
			"slash": "/",
			"Backslash": "\\",
			"backslash": "\\",
			"Period": ".",
			"Comma": ",",
			"Minus": "-",
			"Equal": "=",
			"Escape": "Esc",
			"Return": "Enter",
			"Enter": "Enter",
			"Space": "Space",
			"space": "Space",
			"Print": "PrtSc",
			"Tab": "Tab",
			"mouse_up": "滚轮上",
			"mouse_down": "滚轮下",
			"mouse:272": "左键",
			"mouse:273": "右键",
		};
		return map[k] ?? k;
	}

	implicitWidth: Math.round(Screen.width * 0.72)
	implicitHeight: Math.round(Screen.height * 0.72)

	Shortcut {
		sequence: "Escape"
		onActivated: CheatsheetState.active = false
	}

	Shortcut {
		sequence: "q"
		onActivated: CheatsheetState.active = false
	}

	onVisibleChanged: {
		if (visible)
			focusCatcher.forceActiveFocus();
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
		color: CheatsheetTheme.background
		opacity: 0.94
		radius: 18
		border.color: CheatsheetTheme.primary
		border.width: 1
		clip: true

		Text {
			id: title

			anchors.top: parent.top
			anchors.left: parent.left
			anchors.right: parent.right
			anchors.topMargin: 48
			anchors.leftMargin: 48
			anchors.rightMargin: 48
			text: "Caelestia Cheatsheet"
			horizontalAlignment: Text.AlignHCenter
			font.pixelSize: 34
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
			anchors.topMargin: 36
			anchors.leftMargin: 48
			anchors.rightMargin: 48
			anchors.bottomMargin: 48
			clip: true
			contentHeight: grid.implicitHeight

			Grid {
				id: grid

				width: scroll.width
				columns: Math.max(1, Math.floor(scroll.width / 480))
				columnSpacing: 66
				rowSpacing: 56

				Repeater {
					model: KeybindsData.data

					delegate: Column {
						required property var modelData

						width: 460
						spacing: 22
						visible: modelData && modelData.keybinds && modelData.keybinds.length > 0

						Text {
							text: (modelData ? modelData.category : "").charAt(0).toUpperCase() + (modelData ? modelData.category : "").slice(1)
							font.pixelSize: 24
							font.bold: true
							font.family: "PingFang SC"
							color: CheatsheetTheme.primary
						}

						Column {
							spacing: 16

							Repeater {
								model: modelData && modelData.keybinds ? modelData.keybinds : []

								delegate: Item {
									required property var modelData

									width: 460
									height: Math.max(36, descText.implicitHeight)

									// 键帽区：固定 260px，裁剪溢出，防止长组合键挤进描述区
									Item {
										id: keysClip

										anchors.left: parent.left
										anchors.verticalCenter: parent.verticalCenter
										width: 260
										height: keysRow.implicitHeight
										clip: true

										Row {
											id: keysRow

											anchors.left: parent.left
											anchors.verticalCenter: parent.verticalCenter
											spacing: 5

											Repeater {
												id: keyRepeater

												// 只把真正的键名画成键帽；"+" 分隔符是纯字符，不进模型
												model: modelData.key ? modelData.key.split(" ").filter(k => k.trim() !== "" && k !== "+") : []

												delegate: Row {
													required property string modelData
													required property int index

													spacing: 4
													anchors.verticalCenter: parent.verticalCenter

													Rectangle {
														color: CheatsheetTheme.primary
														radius: 5
														implicitWidth: keyFace.implicitWidth + 2
														implicitHeight: keyFace.implicitHeight + 4

														Rectangle {
															id: keyFace

															anchors.fill: parent
															anchors.topMargin: 1
															anchors.leftMargin: 2
															anchors.rightMargin: 1
															anchors.bottomMargin: 4

															implicitWidth: keyText.implicitWidth + 14
															implicitHeight: keyText.implicitHeight + 8
															color: CheatsheetTheme.surface
															radius: 4

															Text {
																id: keyText

																text: root.keyLabel(modelData)
																anchors.centerIn: parent
																font.pixelSize: 12
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
														font.pixelSize: 11
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
										x: Math.max(284, keysRow.width + 28)
										width: parent.width - x - 12
										anchors.verticalCenter: parent.verticalCenter
										text: modelData.desc
										font.pixelSize: 14
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
