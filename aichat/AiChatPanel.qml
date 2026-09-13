pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Quickshell
import qs.aichat

// AI 对话面板内容：头部（模型 / 设置 / 清空 / 关闭）+ 消息列表 + 输入行。
// 消息点击即复制；流式输出时最后一条气泡实时追加，输入行右侧按钮变成"停止"。
Item {
	id: root

	implicitWidth: 480
	implicitHeight: 640

	Rectangle {
		id: shell

		anchors.fill: parent
		radius: 24
		color: Qt.alpha(AiChatTheme.background, 0.94)
		border.width: 1
		border.color: Qt.alpha(AiChatTheme.textColor, 0.12)
		clip: true

		Column {
			anchors.fill: parent
			anchors.margins: 14
			spacing: 10

			// ---------------- 头部 ----------------
			Item {
				id: header

				width: parent.width
				height: 34

				Text {
					id: title

					anchors.left: parent.left
					anchors.verticalCenter: parent.verticalCenter
					text: "AI 对话"
					color: AiChatTheme.textColor
					font.pixelSize: AiChatTheme.fs(15)
					font.bold: true
				}

				Text {
					anchors.left: title.right
					anchors.leftMargin: 8
					anchors.verticalCenter: parent.verticalCenter
					text: AiChatService.model
					color: AiChatTheme.muted
					font.pixelSize: AiChatTheme.fs(11)
				}

				Row {
					anchors.right: parent.right
					anchors.verticalCenter: parent.verticalCenter
					spacing: 6

					Repeater {
						model: [
							{ glyph: "⚙", tip: "设置接口 / 模型 / API key" },
							{ glyph: "🗂", tip: "会话（聊天记录）" },
							{ glyph: "🗑", tip: "新建会话（清空当前对话）" },
							{ glyph: "✕", tip: "关闭" }
						]

						delegate: Rectangle {
							id: headButton
							required property var modelData

							width: 30
							height: 30
							radius: 9
							color: headMouse.containsMouse
								? Qt.alpha(AiChatTheme.primary, 0.28)
								: Qt.alpha(AiChatTheme.surface, 0.7)

							Text {
								anchors.centerIn: parent
								text: headButton.modelData.glyph
								color: AiChatTheme.textColor
								font.pixelSize: AiChatTheme.fs(13)
							}

							MouseArea {
								id: headMouse

								anchors.fill: parent
								hoverEnabled: true
								onClicked: {
									const glyph = headButton.modelData.glyph;
									if (glyph === "⚙") {
										AiChatService.settingsOpen = !AiChatService.settingsOpen;
										AiChatService.chatsOpen = false;
									} else if (glyph === "🗂") {
										AiChatService.chatsOpen = !AiChatService.chatsOpen;
										AiChatService.settingsOpen = false;
										if (AiChatService.chatsOpen)
											AiChatService.refreshChats();
									} else if (glyph === "🗑") {
										AiChatService.newChat();
									} else {
										AiChatState.active = false;
									}
								}
							}
						}
					}
				}
			}

			// ---------------- 设置 ----------------
			Rectangle {
				id: settingsBox

				width: parent.width
				height: AiChatService.settingsOpen ? settingsColumn.implicitHeight + 20 : 0
				visible: AiChatService.settingsOpen
				radius: 12
				color: Qt.alpha(AiChatTheme.surface, 0.7)

				Column {
					id: settingsColumn

					anchors.fill: parent
					anchors.margins: 10
					spacing: 6

					TextField {
						id: endpointField

						width: parent.width
						placeholderText: "接口地址：按服务商文档填；只填域名会自动试常见路径变体"
						color: AiChatTheme.textColor
						font.pixelSize: AiChatTheme.fs(12)
						onTextChanged: AiChatService.endpoint = text
					}

					Text {
						width: parent.width
						text: "实际请求：" + (AiChatService.resolvedEndpoint === "" ? "(未填)" : AiChatService.resolvedEndpoint)
						color: AiChatTheme.muted
						font.pixelSize: AiChatTheme.fs(10)
						elide: Text.ElideMiddle
						textFormat: Text.PlainText
					}

					TextField {
						id: modelField

						width: parent.width
						placeholderText: "模型名，例如 deepseek-chat"
						color: AiChatTheme.textColor
						font.pixelSize: AiChatTheme.fs(12)
						onTextChanged: AiChatService.model = text
					}

					TextField {
						id: keyField

						width: parent.width
						placeholderText: "API key（明文存在 ~/.config/caelestia/aichat.json，权限 600）"
						text: AiChatService.apiKey
						echoMode: TextInput.Password
						color: AiChatTheme.textColor
						font.pixelSize: AiChatTheme.fs(12)
						onTextChanged: AiChatService.apiKey = text
					}

					Row {
						width: parent.width
						height: 28
						spacing: 8

						Rectangle {
							width: 64
							height: parent.height
							radius: 9
							color: saveMouse.containsMouse ? Qt.alpha(AiChatTheme.primary, 0.75) : AiChatTheme.primary

							Text {
								anchors.centerIn: parent
								text: "保存"
								color: AiChatTheme.onPrimary
								font.pixelSize: AiChatTheme.fs(12)
							}

							MouseArea {
								id: saveMouse

								anchors.fill: parent
								hoverEnabled: true
								onClicked: AiChatService.save()
							}
						}

						Text {
							anchors.verticalCenter: parent.verticalCenter
							text: AiChatService.savedHint !== ""
								? AiChatService.savedHint
								: ("保存位置：" + AiChatService.settingsPath)
							color: AiChatService.savedHint !== "" ? AiChatTheme.primary : AiChatTheme.muted
							font.pixelSize: AiChatTheme.fs(10)
							elide: Text.ElideMiddle
							textFormat: Text.PlainText
							width: parent.width - 72
						}
					}
				}
			}

			// ---------------- 会话列表（🗂 展开）：保存当前对话 / 新建 / 载入 / 删除 ----------------
			Rectangle {
				id: chatsBox

				width: parent.width
				height: AiChatService.chatsOpen ? chatsColumn.implicitHeight + 20 : 0
				visible: AiChatService.chatsOpen
				radius: 12
				color: Qt.alpha(AiChatTheme.surface, 0.7)

				Column {
					id: chatsColumn

					anchors.fill: parent
					anchors.margins: 10
					spacing: 6

					Row {
						width: parent.width
						height: 28
						spacing: 8

						TextField {
							id: chatNameField

							width: parent.width - saveChatButton.width - 8
							height: parent.height
							placeholderText: "会话名（例如 桌面调试）"
							color: AiChatTheme.textColor
							font.pixelSize: AiChatTheme.fs(12)
							leftPadding: 10
							onAccepted: saveChatButton.run()
						}

						Rectangle {
							id: saveChatButton

							width: 64
							height: parent.height
							radius: 9
							color: saveChatMouse.containsMouse ? Qt.alpha(AiChatTheme.primary, 0.75) : AiChatTheme.primary

							function run(): void {
								AiChatService.saveChatTo(chatNameField.text, false);
								chatNameField.text = "";
							}

							Text {
								anchors.centerIn: parent
								text: "保存"
								color: AiChatTheme.onPrimary
								font.pixelSize: AiChatTheme.fs(12)
							}

							MouseArea {
								id: saveChatMouse

								anchors.fill: parent
								hoverEnabled: true
								onClicked: saveChatButton.run()
							}
						}
					}

					Row {
						width: parent.width
						height: 28
						spacing: 8

						Rectangle {
							width: 64
							height: parent.height
							radius: 9
							color: newChatMouse.containsMouse
								? Qt.alpha(AiChatTheme.surface, 0.95)
								: Qt.alpha(AiChatTheme.background, 0.6)

							Text {
								anchors.centerIn: parent
								text: "新建"
								color: AiChatTheme.textColor
								font.pixelSize: AiChatTheme.fs(12)
							}

							MouseArea {
								id: newChatMouse

								anchors.fill: parent
								hoverEnabled: true
								onClicked: AiChatService.newChat()
							}
						}

						Text {
							anchors.verticalCenter: parent.verticalCenter
							width: parent.width - 72
							text: AiChatService.chatHint !== ""
								? AiChatService.chatHint
								: `当前：${AiChatService.currentChat}・共 ${AiChatService.savedChats.length} 个会话`
							color: AiChatService.chatHint !== "" ? AiChatTheme.primary : AiChatTheme.muted
							font.pixelSize: AiChatTheme.fs(10)
							elide: Text.ElideRight
							textFormat: Text.PlainText
						}
					}

					Column {
						id: chatListColumn

						width: parent.width
						spacing: 4

						Repeater {
							model: AiChatService.savedChats.slice(0, 8)

							delegate: Rectangle {
								id: chatRow

								required property var modelData

								width: chatListColumn.width
								height: 26
								radius: 8
								color: chatRowMouse.containsMouse
									? Qt.alpha(AiChatTheme.primary, 0.22)
									: Qt.alpha(AiChatTheme.background, 0.55)

								MouseArea {
									id: chatRowMouse

									anchors.fill: parent
									hoverEnabled: true
									onClicked: AiChatService.loadChatFrom(chatRow.modelData.name, false)
								}

								Text {
									anchors.left: parent.left
									anchors.leftMargin: 8
									anchors.verticalCenter: parent.verticalCenter
									width: parent.width - 34
									text: `${chatRow.modelData.name}・${Qt.formatDateTime(new Date(chatRow.modelData.ts * 1000), "MM-dd HH:mm")}`
									color: chatRow.modelData.name === AiChatService.currentChat ? AiChatTheme.primary : AiChatTheme.textColor
									font.pixelSize: AiChatTheme.fs(12)
									elide: Text.ElideMiddle
									textFormat: Text.PlainText
								}

								Text {
									anchors.right: parent.right
									anchors.rightMargin: 8
									anchors.verticalCenter: parent.verticalCenter
									text: "✕"
									color: chatDeleteMouse.containsMouse ? AiChatTheme.error : AiChatTheme.muted
									font.pixelSize: AiChatTheme.fs(11)

									MouseArea {
										id: chatDeleteMouse

										anchors.fill: parent
										hoverEnabled: true
										onClicked: AiChatService.deleteChat(chatRow.modelData.name)
									}
								}
							}
						}
					}

					Text {
						width: parent.width
						visible: AiChatService.savedChats.length > 8
						text: `只列出最近 8 个（共 ${AiChatService.savedChats.length} 个）`
						color: AiChatTheme.muted
						font.pixelSize: AiChatTheme.fs(10)
					}
				}
			}

			// ---------------- 消息列表 ----------------
			ListView {
				id: msgList

				width: parent.width
				height: parent.height - header.height - settingsBox.height - chatsBox.height - inputRow.height - parent.spacing * 4
				clip: true
				spacing: 8
				model: AiChatService.messages
				currentIndex: -1

				onCountChanged: Qt.callLater(() => msgList.positionViewAtEnd())

				Connections {
					target: AiChatService
					function onMessagesChanged() {
						Qt.callLater(() => msgList.positionViewAtEnd());
					}
				}

				delegate: Item {
					id: msgRow
					required property var modelData
					required property int index

					readonly property bool isUser: modelData.role === "user"
					readonly property bool isTool: modelData.kind === "tool"
					readonly property bool isLast: msgRow.index === AiChatService.messages.length - 1
					readonly property string text: (modelData.content === "" && !modelData.error && AiChatService.streaming && msgRow.isLast)
						? "…"
						: modelData.content

					width: msgList.width
					height: msgRow.isTool ? toolBox.height : bubble.height

					Rectangle {
						id: bubble

						width: Math.min(msgText.implicitWidth + 22, msgRow.width * 0.88)
						height: msgText.implicitHeight + 18
						radius: 12
						visible: !msgRow.isTool
						anchors.right: msgRow.isUser ? parent.right : undefined
						anchors.left: msgRow.isUser ? undefined : parent.left
						color: msgRow.isUser
							? Qt.alpha(AiChatTheme.primary, 0.85)
							: (msgRow.modelData.error ? Qt.alpha(AiChatTheme.error, 0.22) : Qt.alpha(AiChatTheme.surface, 0.85))

						Text {
							id: msgText

							anchors.fill: parent
							anchors.margins: 11
							text: msgRow.text
							color: msgRow.isUser ? AiChatTheme.onPrimary : AiChatTheme.textColor
							font.pixelSize: AiChatTheme.fs(13)
							wrapMode: Text.Wrap
							textFormat: Text.PlainText
						}

						MouseArea {
							anchors.fill: parent
							acceptedButtons: Qt.MiddleButton
							onPressed: mouse => {
								if (mouse.button === Qt.MiddleButton) {
									Quickshell.clipboardText = msgRow.modelData.content;
									console.info("[aichat] 已复制该条消息");
								}
							}
						}
					}

					// ---- 工具调用（agent 步骤）----
					Rectangle {
						id: toolBox

						width: msgRow.width
						height: toolColumn.implicitHeight + 18
						radius: 12
						visible: msgRow.isTool
						color: Qt.alpha(AiChatTheme.surface, 0.7)
						border.width: 1
						border.color: msgRow.modelData.pending
							? AiChatTheme.primary
							: Qt.alpha(AiChatTheme.textColor, 0.12)

						Column {
							id: toolColumn

							anchors.fill: parent
							anchors.margins: 9
							spacing: 6

							Text {
								width: parent.width
								text: `⚙ ${msgRow.modelData.name}`
								color: AiChatTheme.primary
								font.pixelSize: AiChatTheme.fs(12)
								font.bold: true
								textFormat: Text.PlainText
							}

							Text {
								width: parent.width
								visible: (msgRow.modelData.detail ?? "") !== ""
								text: msgRow.modelData.detail ?? ""
								color: AiChatTheme.textColor
								font.pixelSize: AiChatTheme.fs(12)
								font.family: "monospace"
								wrapMode: Text.Wrap
								textFormat: Text.PlainText
							}

							Text {
								width: parent.width
								visible: (msgRow.modelData.output ?? "") !== ""
								text: (msgRow.modelData.output ?? "").slice(0, 600)
								color: AiChatTheme.muted
								font.pixelSize: AiChatTheme.fs(11)
								font.family: "monospace"
								wrapMode: Text.Wrap
								maximumLineCount: 8
								elide: Text.ElideRight
								textFormat: Text.PlainText
							}

							Text {
								width: parent.width
								visible: msgRow.modelData.running === true
								text: "运行中…"
								color: AiChatTheme.muted
								font.pixelSize: AiChatTheme.fs(11)
							}

							Row {
								width: parent.width
								height: 28
								spacing: 8
								visible: msgRow.modelData.pending === true

								Rectangle {
									width: 64
									height: parent.height
									radius: 9
									color: runMouse.containsMouse ? Qt.alpha(AiChatTheme.primary, 0.85) : AiChatTheme.primary

									Text {
										anchors.centerIn: parent
										text: "运行"
										color: AiChatTheme.onPrimary
										font.pixelSize: AiChatTheme.fs(12)
										font.bold: true
									}

									MouseArea {
										id: runMouse

										anchors.fill: parent
										hoverEnabled: true
										onClicked: AiChatService.approvePending()
									}
								}

								Rectangle {
									width: 64
									height: parent.height
									radius: 9
									color: rejectMouse.containsMouse
										? Qt.alpha(AiChatTheme.error, 0.35)
										: Qt.alpha(AiChatTheme.surface, 0.8)

									Text {
										anchors.centerIn: parent
										text: "拒绝"
										color: AiChatTheme.textColor
										font.pixelSize: AiChatTheme.fs(12)
									}

									MouseArea {
										id: rejectMouse

										anchors.fill: parent
										hoverEnabled: true
										onClicked: AiChatService.rejectPending()
									}
								}
							}
						}
					}
				}
			}

			// ---------------- 输入行 ----------------
			Row {
				id: inputRow

				width: parent.width
				height: 44
				spacing: 8

				TextField {
					id: input

					width: parent.width - sendButton.width - 8
					height: parent.height
					placeholderText: AiChatService.pendingToolCall !== null
						? "等待你批准上一条命令…"
						: (AiChatService.streaming ? "生成中…（点右侧停止）" : "问点什么…（Enter 发送）")
					color: AiChatTheme.textColor
					font.pixelSize: AiChatTheme.fs(13)
					leftPadding: 12
					enabled: !AiChatService.streaming && AiChatService.pendingToolCall === null

					Keys.onEscapePressed: event => {
						AiChatState.active = false;
						event.accepted = true;
					}

					onAccepted: {
						const t = text;
						text = "";
						AiChatService.send(t);
					}
				}

				Rectangle {
					id: sendButton

					width: 76
					height: parent.height
					radius: 12
					color: sendMouse.containsMouse
						? Qt.alpha(AiChatTheme.primary, 0.8)
						: Qt.alpha(AiChatTheme.primary, 0.65)

					Text {
						anchors.centerIn: parent
						text: AiChatService.streaming ? "停止" : "发送"
						color: AiChatTheme.onPrimary
						font.pixelSize: AiChatTheme.fs(13)
						font.bold: true
					}

					MouseArea {
						id: sendMouse

						anchors.fill: parent
						hoverEnabled: true
						onClicked: {
							if (AiChatService.streaming)
								AiChatService.stop();
							else {
								const t = input.text;
								input.text = "";
								AiChatService.send(t);
							}
						}
					}
				}
			}
		}
	}

	Connections {
		target: AiChatState
		function onActiveChanged() {
			if (!AiChatState.active)
				return;
			// 打开动画（110ms）结束后再要焦点，太早会被滑出动画/窗口激活吃掉
			focusTimer.restart();
		}
	}

	Timer {
		id: focusTimer

		interval: 160
		repeat: false
		onTriggered: {
			if (AiChatService.settingsOpen) {
				endpointField.text = AiChatService.endpoint;
				modelField.text = AiChatService.model;
				keyField.text = AiChatService.apiKey;
			} else {
				input.forceActiveFocus();
				// 拿到焦点后再同步输入法（此时 fcitx5 的"当前上下文"才是本面板）
				AiChatService.ensureIme();
			}
		}
	}

	Component.onCompleted: {
		if (AiChatState.active)
			focusTimer.restart();
	}
}
