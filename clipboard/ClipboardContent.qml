pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import qs.spotlight
import qs.overview

// Original Spotlight clipboard layout and interactions, hosted independently.
Item {
    id: root
    property string query: ""
    property string clipConfirm: ""
    signal closeRequested()
    QtObject { id: input; readonly property string text: root.query }
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

	// ---------------- 剪贴板：置顶 / 删除 / 清空 ----------------
	// 统一取「当前选中条目」：委托被回收时 itemAtIndex 会返回 null，退回到 model 下标取数据
	function selectedClipEntry(): var {
		const idx = clipList.currentIndex;
		if (idx < 0 || idx >= clipList.count)
			return null;
		return clipList.itemAtIndex(idx)?.modelData ?? clipList.model?.[idx] ?? null;
	}

	function requestClipConfirm(kind: string): void {
		if (kind === "delete" && !root.selectedClipEntry())
			return;
		root.clipConfirm = kind;
	}

	function confirmClipAction(): void {
		const kind = root.clipConfirm;
		const entry = root.selectedClipEntry();
		root.clipConfirm = "";
		if (kind === "delete") {
			if (!entry)
				return;
			const id = entry.id;
			ClipboardData.remove(entry);
			// 删除后列表整体上移，尽量把相邻的那条继续选中
			Qt.callLater(() => root.selectClipById(id));
		} else if (kind === "clearUnpinned") {
			ClipboardData.clearUnpinned();
			Qt.callLater(root.resetClipSelection);
		} else if (kind === "clearAll") {
			ClipboardData.clearAll();
		}
	}

	function toggleSelectedClipPin(): void {
		const entry = root.selectedClipEntry();
		if (!entry)
			return;
		const id = entry.id;
		const pinned = ClipboardData.togglePin(entry);
		console.info(`[spotlight-clip] ${pinned ? "置顶" : "取消置顶"} id=${id}`);
		// 置顶会让列表重排（置顶块在最前），让同一条尽量保持在选中状态
		Qt.callLater(() => root.selectClipById(id));
	}

	function selectClipById(id: string): void {
		const model = clipList.model;
		if (!model || id === "")
			return;
		for (let i = 0; i < model.length; i++) {
			if (model[i] && model[i].id === id) {
				clipList.currentIndex = i;
				clipList.positionViewAtIndex(i, ListView.Contain);
				return;
			}
		}
	}

			Item {
				id: clipboardBody

				visible: true
				anchors.fill: parent

				// 切走或关面板时清掉未决确认框，避免下次打开还挂着旧弹窗
				onVisibleChanged: {
					if (!visible)
						root.clipConfirm = "";
				}

				Text {
					anchors.centerIn: parent
					visible: clipList.count === 0
					text: ClipboardData.busy
						? "读取剪贴板历史…"
						: (ClipboardData.entries.length === 0
							? "剪贴板历史为空（需要 cliphist + wl-paste --watch cliphist store）"
							: "没有匹配的条目")
					color: Qt.alpha(M3Palette.m3onSurface, 0.5)
					font.pixelSize: 15
				}

				Row {
					id: clipColumns

					visible: clipList.count > 0
					anchors.fill: parent
					spacing: 12

					// ---- 左：清空工具条 + 列表 ----
					Item {
						id: clipListPane

						width: Math.round((clipColumns.width - clipColumns.spacing) * 0.56)
						height: clipColumns.height

						Row {
							id: clipToolbar

							width: parent.width
							height: 26
							spacing: 8

							Repeater {
								model: [
									{ kind: "clearUnpinned", label: "清空未置顶" },
									{ kind: "clearAll", label: "清空全部" }
								]

								Rectangle {
									id: clipClearButton

									required property var modelData

									width: clipClearText.implicitWidth + 22
									height: clipToolbar.height
									radius: 8
									color: clipClearArea.containsMouse
										? Qt.alpha(M3Palette.m3error, 0.35)
										: Qt.alpha(M3Palette.m3surface, 0.5)

									Text {
										id: clipClearText

										anchors.centerIn: parent
										text: clipClearButton.modelData.label
										color: M3Palette.m3onSurface
										font.pixelSize: 13
									}

									MouseArea {
										id: clipClearArea

										anchors.fill: parent
										hoverEnabled: true
										onClicked: root.requestClipConfirm(clipClearButton.modelData.kind)
									}
								}
							}

							Text {
								id: clipCountLabel

								anchors.verticalCenter: parent.verticalCenter
								text: `共 ${clipList.count} 条`
								color: Qt.alpha(M3Palette.m3onSurface, 0.5)
								font.pixelSize: 12
							}
						}

						ListView {
							id: clipList

							anchors.top: clipToolbar.bottom
							anchors.topMargin: 6
							anchors.left: parent.left
							anchors.right: parent.right
							anchors.bottom: parent.bottom
							clip: true
							spacing: 4
							model: ClipboardData.query(input.text)
							currentIndex: -1

							onCountChanged: {
								if (currentIndex < 0 && count > 0)
									currentIndex = 0;
								Qt.callLater(() => ClipboardData.ensurePreview(root.selectedClipEntry()));
							}

							// 选中项变了就按需解码预览（图片解大图、文本解完整内容）；解码请求不在绑定里发
							onCurrentIndexChanged: Qt.callLater(() => ClipboardData.ensurePreview(root.selectedClipEntry()))

							delegate: Rectangle {
								id: clipRow
								required property var modelData
								required property int index

								width: clipList.width
								height: 56
								radius: 10
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

								// 图片条目：40×40 缩略图（大图看右侧预览栏；解码缓存见 ClipboardData.thumbs）
								Image {
									id: clipThumb

									anchors.left: parent.left
									anchors.leftMargin: 8
									anchors.verticalCenter: parent.verticalCenter
									visible: clipRow.modelData.isImage
									width: 40
									height: 40
									source: clipRow.modelData.isImage ? ClipboardData.thumbFor(clipRow.modelData.id) : ""
									sourceSize: Qt.size(128, 128)
									fillMode: Image.PreserveAspectCrop
									asynchronous: true
									cache: false

									Component.onCompleted: {
										if (clipRow.modelData.isImage)
											ClipboardData.requestThumb(clipRow.modelData);
									}
								}

								Text {
									id: clipRowLabel

									anchors.left: clipRow.modelData.isImage ? clipThumb.right : clipIcon.right
									anchors.leftMargin: 10
									anchors.right: clipPinnedMark.visible ? clipPinnedMark.left : parent.right
									anchors.rightMargin: 8
									anchors.verticalCenter: parent.verticalCenter
									text: clipRow.modelData.isImage ? clipRow.modelData.info : clipRow.modelData.preview
									textFormat: Text.PlainText
									elide: Text.ElideRight
									maximumLineCount: 1
									color: M3Palette.m3onSurface
									font.pixelSize: 16
								}

								Text {
									id: clipPinnedMark

									anchors.right: parent.right
									anchors.rightMargin: 10
									anchors.verticalCenter: parent.verticalCenter
									visible: ClipboardData.isPinned(clipRow.modelData)
									text: "📌"
									font.pixelSize: 14
								}

								MouseArea {
									id: clipRowMouse

									anchors.fill: parent
									hoverEnabled: true
									acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
									onEntered: clipList.currentIndex = clipRow.index
									onClicked: mouse => {
										clipList.currentIndex = clipRow.index;
										if (mouse.button === Qt.MiddleButton) {
											// 旧习惯保留：中键即时删除（不弹确认框）
											ClipboardData.remove(clipRow.modelData);
											return;
										}
										if (mouse.button === Qt.RightButton) {
											root.toggleSelectedClipPin();
											return;
										}
										root.copyClipEntry(clipRow.modelData);
									}
								}
							}
						}
					}

					// ---- 右：预览栏（内容 + 元信息 + 操作；布局对齐 noctalia 面板） ----
					Rectangle {
						id: clipPreviewPane

						property var entry: root.selectedClipEntry()
						property bool loading: !!entry
							&& (entry.isImage
								? (ClipboardData.previewBusyId === entry.id && ClipboardData.previewFor(entry.id) === "")
								: (ClipboardData.textBusyId === entry.id && ClipboardData.textFor(entry) === ""))

						width: clipColumns.width - clipListPane.width - clipColumns.spacing
						height: clipColumns.height
						radius: 12
						color: Qt.alpha(M3Palette.m3surface, 0.35)
						border.color: Qt.alpha(M3Palette.m3onSurface, 0.12)
						border.width: 1

						Column {
							id: clipPreviewColumn

							anchors.fill: parent
							anchors.margins: 12
							spacing: 8

							Text {
								id: clipPreviewTitle

								width: parent.width
								height: 20
								text: clipPreviewPane.entry
									? (clipPreviewPane.entry.isImage ? "图片" : "文本")
										+ (ClipboardData.isPinned(clipPreviewPane.entry) ? " · 已置顶 📌" : "")
									: "未选择条目"
								color: Qt.alpha(M3Palette.m3onSurface, 0.75)
								font.pixelSize: 15
								elide: Text.ElideRight
								verticalAlignment: Text.AlignVCenter
							}

							Item {
								id: clipPreviewBody

								width: parent.width
								height: Math.max(0, clipPreviewPane.height - 118)

								Image {
									id: clipPreviewImage

									anchors.fill: parent
									visible: !!clipPreviewPane.entry && clipPreviewPane.entry.isImage
									source: clipPreviewPane.entry && clipPreviewPane.entry.isImage
										? ClipboardData.previewFor(clipPreviewPane.entry.id)
										: ""
									sourceSize: Qt.size(1024, 1024)
									fillMode: Image.PreserveAspectFit
									asynchronous: true
									cache: false
								}

								ScrollView {
									id: clipPreviewScroll

									anchors.fill: parent
									visible: !!clipPreviewPane.entry && !clipPreviewPane.entry.isImage
									clip: true

									Text {
										width: clipPreviewScroll.availableWidth
										text: clipPreviewPane.entry ? ClipboardData.textFor(clipPreviewPane.entry) : ""
										textFormat: Text.PlainText
										wrapMode: Text.WrapAnywhere
										color: M3Palette.m3onSurface
										font.pixelSize: 15
									}
								}

								Text {
									anchors.centerIn: parent
									visible: clipPreviewPane.loading
									text: "解码中…"
									color: Qt.alpha(M3Palette.m3onSurface, 0.45)
									font.pixelSize: 13
								}
							}

							Text {
								id: clipPreviewMeta

								width: parent.width
								height: 18
								text: clipPreviewPane.entry
									? (clipPreviewPane.entry.isImage
										? clipPreviewPane.entry.info
										: `文本 · ${ClipboardData.textFor(clipPreviewPane.entry).length} 字符`)
									: ""
								color: Qt.alpha(M3Palette.m3onSurface, 0.55)
								font.pixelSize: 13
								elide: Text.ElideRight
								verticalAlignment: Text.AlignVCenter
							}

							Row {
								id: clipActionRow

								width: parent.width
								height: 32
								spacing: 8

								Repeater {
									model: ["pin", "copy", "delete"]

									Rectangle {
										id: clipActionButton

										required property string modelData

										width: Math.round((clipActionRow.width - 16) / 3)
										height: clipActionRow.height
										radius: 9
										color: clipActionArea.containsMouse
											? Qt.alpha(M3Palette.m3tertiary, 0.3)
											: Qt.alpha(M3Palette.m3surface, 0.55)

										Text {
											anchors.centerIn: parent
											text: {
												if (clipActionButton.modelData === "pin")
													return ClipboardData.isPinned(clipPreviewPane.entry) ? "取消置顶" : "置顶";
												if (clipActionButton.modelData === "copy")
													return "复制";
												return "删除";
											}
											color: M3Palette.m3onSurface
											font.pixelSize: 14
										}

										MouseArea {
											id: clipActionArea

											anchors.fill: parent
											hoverEnabled: true
											onClicked: {
												const kind = clipActionButton.modelData;
												if (kind === "pin")
													root.toggleSelectedClipPin();
												else if (kind === "copy")
													root.copySelectedClip();
												else
													root.requestClipConfirm("delete");
											}
										}
									}
								}
							}
						}
					}
				}

				// ---- 二次确认浮层（删除单条 / 清空未置顶 / 清空全部） ----
				Rectangle {
					id: clipConfirmCard

					visible: root.clipConfirm !== ""
					anchors.centerIn: parent
					width: Math.min(parent.width - 40, 380)
					height: 116
					radius: 14
					color: Qt.alpha(M3Palette.m3surface, 0.97)
					border.color: Qt.alpha(M3Palette.m3onSurface, 0.2)
					border.width: 1
					z: 10

					Text {
						id: clipConfirmLabel

						anchors.horizontalCenter: parent.horizontalCenter
						anchors.top: parent.top
						anchors.topMargin: 18
						width: parent.width - 32
						horizontalAlignment: Text.AlignHCenter
						wrapMode: Text.WordWrap
						text: {
							if (root.clipConfirm === "delete")
								return "删除这条记录？";
							if (root.clipConfirm === "clearUnpinned")
								return `清空 ${ClipboardData.unpinnedCount()} 条未置顶记录？（置顶的会保留）`;
							if (root.clipConfirm === "clearAll")
								return `清空全部 ${ClipboardData.entries.length} 条记录（含置顶）？`;
							return "";
						}
						color: M3Palette.m3onSurface
						font.pixelSize: 15
					}

					Row {
						id: clipConfirmButtons

						anchors.horizontalCenter: parent.horizontalCenter
						anchors.bottom: parent.bottom
						anchors.bottomMargin: 14
						spacing: 10

						Rectangle {
							id: clipConfirmCancel

							width: 92
							height: 30
							radius: 9
							color: clipCancelArea.containsMouse
								? Qt.alpha(M3Palette.m3onSurface, 0.18)
								: Qt.alpha(M3Palette.m3surface, 0.6)

							Text {
								anchors.centerIn: parent
								text: "取消"
								color: M3Palette.m3onSurface
								font.pixelSize: 14
							}

							MouseArea {
								id: clipCancelArea

								anchors.fill: parent
								hoverEnabled: true
								onClicked: root.clipConfirm = ""
							}
						}

						Rectangle {
							id: clipConfirmOk

							width: 92
							height: 30
							radius: 9
							color: clipOkArea.containsMouse
								? Qt.alpha(M3Palette.m3error, 0.55)
								: Qt.alpha(M3Palette.m3error, 0.35)

							Text {
								anchors.centerIn: parent
								text: "确认"
								color: "#FFFFFF"
								font.pixelSize: 14
							}

							MouseArea {
								id: clipOkArea

								anchors.fill: parent
								hoverEnabled: true
								onClicked: root.confirmClipAction()
							}
						}
					}
				}
			}

}
