pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Window
import Quickshell
import qs.cheatsheet

// 居中的快捷键速查弹窗。普通窗口（非 layer shell），只在显示时参与输入；
// Escape / q / 点击外部失焦都会关闭，不会卡住任何输入。
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

	// 失焦自动关闭（点击窗口外部即收起）
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

			text: "Caelestia Cheatsheet"
			anchors.top: parent.top
			anchors.left: parent.left
			anchors.right: parent.right
			anchors.topMargin: 36
			anchors.leftMargin: 36
			anchors.rightMargin: 36
			horizontalAlignment: Text.AlignHCenter
			font.pixelSize: 30
			font.bold: true
			color: CheatsheetTheme.primary
		}

		Flickable {
			id: scroll

			anchors.top: title.bottom
			anchors.left: parent.left
			anchors.right: parent.right
			anchors.bottom: parent.bottom
			anchors.topMargin: 20
			anchors.leftMargin: 36
			anchors.rightMargin: 36
			anchors.bottomMargin: 36
			clip: true
			contentHeight: grid.implicitHeight

			Grid {
				id: grid

				width: scroll.width
				columns: Math.max(1, Math.floor(scroll.width / 420))
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
							text: {
								const c = (modelData?.category ?? "");
								return c ? c.charAt(0).toUpperCase() + c.slice(1) : "";
							}
							font.pixelSize: 22
							font.bold: true
							color: CheatsheetTheme.primary
						}

						Column {
							spacing: 10

							Repeater {
								model: modelData && modelData.keybinds ? modelData.keybinds : []

								// 每行：左侧 220px 键帽区 + 右侧说明（对齐旧版 cheatsheet 排版）
								delegate: Item {
									required property var modelData

									width: 400
									height: Math.max(28, descText.implicitHeight)

									Row {
										id: keysRow

										anchors.left: parent.left
										anchors.verticalCenter: parent.verticalCenter
										width: 220
										spacing: 6

										Repeater {
											id: keyRepeater

											model: (modelData?.key ?? "").split(" ").filter(k => k.trim() !== "")

											delegate: Item {
												required property string modelData
												required property int index

												width: chipFace.implicitWidth + (index < keyRepeater.count - 1 ? plusText.implicitWidth + 6 : 0)
												height: chipFace.implicitHeight

												Rectangle {
													id: chipFace

													anchors.left: parent.left
													anchors.verticalCenter: parent.verticalCenter
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
													id: plusText

													text: "+"
													visible: index < keyRepeater.count - 1
													anchors.left: chipFace.right
													anchors.leftMargin: 6
													anchors.verticalCenter: parent.verticalCenter
													font.pixelSize: 14
													color: CheatsheetTheme.primary
													opacity: 0.7
												}
											}
										}
									}

									Text {
										id: descText

										anchors.left: parent.left
										anchors.leftMargin: 235
										anchors.right: parent.right
										anchors.verticalCenter: parent.verticalCenter
										text: modelData?.desc ?? ""
										font.pixelSize: 13
										color: CheatsheetTheme.onSurface
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
