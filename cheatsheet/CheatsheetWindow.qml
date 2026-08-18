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

		Column {
			anchors.fill: parent
			anchors.margins: 40
			spacing: 30

			Text {
				id: title

				text: "Caelestia Cheatsheet"
				width: parent.width
				horizontalAlignment: Text.AlignHCenter
				font.pixelSize: 32
				font.bold: true
				font.family: "PingFang SC"
				color: CheatsheetTheme.primary
			}

			Grid {
				id: grid

				width: parent.width
				columns: Math.max(1, Math.floor(parent.width / 420))
				columnSpacing: 40
				rowSpacing: 35

				Repeater {
					model: KeybindsData.data

					delegate: Column {
						required property var modelData

						width: 400
						spacing: 15
						visible: modelData && modelData.keybinds && modelData.keybinds.length > 0

						Text {
							text: (modelData ? modelData.category : "").charAt(0).toUpperCase() + (modelData ? modelData.category : "").slice(1)
							font.pixelSize: 22
							font.bold: true
							font.family: "PingFang SC"
							color: CheatsheetTheme.primary
						}

						Column {
							spacing: 10

							Repeater {
								model: modelData && modelData.keybinds ? modelData.keybinds : []

								delegate: Item {
									required property var modelData

									width: 400
									height: Math.max(28, descText.implicitHeight)

									// 键帽区：固定 220px，裁剪溢出，防止长组合键挤进描述区
									Item {
										id: keysClip

										anchors.left: parent.left
										anchors.verticalCenter: parent.verticalCenter
										width: 220
										height: keysRow.implicitHeight
										clip: true

										Row {
											id: keysRow

											anchors.left: parent.left
											anchors.verticalCenter: parent.verticalCenter
											spacing: 4

											Repeater {
												id: keyRepeater

												model: modelData.key ? modelData.key.split(" ").filter(k => k.trim() !== "") : []

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

																text: modelData
																anchors.centerIn: parent
																font.pixelSize: 12
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

										x: 240
										width: 160
										anchors.verticalCenter: parent.verticalCenter
										text: modelData.desc
										font.pixelSize: 13
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
