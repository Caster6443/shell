pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.services
import qs.console
import qs.overview

Item {
    id: root
    property alias query: search.text
    property string clipConfirm: ""
    readonly property bool editing: clipEditor.dirty || clipEditor.hasFocus
    property bool savedSelectionPending: false
    readonly property color fg: Colours.palette.m3onSurface
    readonly property color muted: Qt.alpha(fg, 0.65)
    readonly property color accent: Colours.palette.m3primary
    readonly property var entry: root.editing && clipEditor.documentEntry ? clipEditor.documentEntry : selectedClipEntry()
    function cancelEdit(): void { clipEditor.cancel(); }
    function focusSearch(): void { search.forceActiveFocus(); }
    signal closeRequested()
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
	}

	function copySelectedClip(): void {
		if (clipEditor.dirty) clipEditor.copy();
        else root.copyClipEntry(clipList.currentItem?.modelData ?? clipList.model?.[clipList.currentIndex]);
	}

    function pasteSelectedClip(): void {
        if (clipEditor.dirty || clipEditor.saving) return;
        ClipboardData.paste(root.selectedClipEntry());
    }
    Connections {
        target: ClipboardData
        function onPasteReady(): void { root.closeRequested(); }
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
		console.info(`[console-clip] ${pinned ? "置顶" : "取消置顶"} id=${id}`);
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

    Connections {
        target: ClipboardData
        function onEntriesChanged(): void {
            if (!root.savedSelectionPending) {
                if (root.editing && clipEditor.documentEntry) Qt.callLater(() => root.selectClipById(clipEditor.documentEntry.id));
                return;
            }
            root.savedSelectionPending = false;
            Qt.callLater(root.resetClipSelection);
        }
    }
    RowLayout {
        anchors.fill: parent
        spacing: 24
        ColumnLayout {
            Layout.preferredWidth: Math.round((root.width - 24) * 0.38)
            Layout.minimumWidth: Layout.preferredWidth
            Layout.maximumWidth: Layout.preferredWidth
            Layout.fillHeight: true
            spacing: 12
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 34
                ClipText { text: "剪贴板"; font: Tokens.font.title.builders.medium.weight(Font.DemiBold).build() }
                ClipText { text: ClipboardData.busy ? "刷新中" : clipList.count; color: root.muted; font: Tokens.font.label.builders.medium.weight(Font.Normal).build() }
                Item { Layout.fillWidth: true }
                ClipIconButton {
                    symbol: "delete_sweep"; label: "清空历史"; enabled: !clipEditor.dirty && !clipEditor.saving && clipList.count > 0
                    onClicked: clearMenu.open()
                    Menu {
                        id: clearMenu
                        MenuItem { text: "清空未置顶"; font: Tokens.font.body.small; onTriggered: root.requestClipConfirm("clearUnpinned") }
                        MenuItem { text: "清空全部"; font: Tokens.font.body.small; onTriggered: root.requestClipConfirm("clearAll") }
                    }
                }
            }
            TextField {
                id: search
                Layout.fillWidth: true
                Layout.preferredHeight: 52
                font: Tokens.font.body.small
                renderType: Text.NativeRendering
                color: root.fg
                placeholderText: "搜索剪贴板…"
                placeholderTextColor: root.muted
                leftPadding: 16; rightPadding: 16
                selectByMouse: true
                background: Rectangle {
                    radius: 12
                    color: ConsoleStyle.field
                    border.width: 1
                    border.color: search.activeFocus ? Qt.alpha(root.accent, 0.55) : "transparent"
                }
                onTextChanged: root.resetClipSelection()
                onAccepted: { if (root.clipConfirm) root.confirmClipAction(); else root.pasteSelectedClip(); }
                Keys.onDownPressed: root.moveClipSelection(1)
                Keys.onUpPressed: root.moveClipSelection(-1)
            }
            ListView {
                id: clipList
                Layout.fillWidth: true
                Layout.fillHeight: true
                enabled: !clipEditor.saving
                clip: true
                spacing: 4
                model: ClipboardData.query(root.query)
                currentIndex: -1
                ScrollBar.vertical: ScrollBar { }
                onCountChanged: {
                    if (currentIndex < 0 && count > 0) currentIndex = 0;
                    Qt.callLater(() => ClipboardData.ensurePreview(root.selectedClipEntry()));
                }
                onCurrentIndexChanged: Qt.callLater(() => ClipboardData.ensurePreview(root.selectedClipEntry()))
                delegate: Rectangle {
                    id: clipRow
                    required property var modelData
                    required property int index
                    readonly property bool selected: clipList.currentIndex === index
                    width: clipList.width
                    height: 60
                    radius: 12
                    color: selected ? ConsoleStyle.selection : (clipRowMouse.containsMouse ? Qt.alpha(root.fg, 0.06) : "transparent")
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10; anchors.rightMargin: 12
                        spacing: 12
                        Item {
                            Layout.preferredWidth: 36; Layout.preferredHeight: 36
                            MaterialIcon {
                                anchors.centerIn: parent
                                visible: !clipRow.modelData.isImage
                                text: "description"
                                color: clipRow.selected ? ConsoleStyle.selectedText : root.accent
                            }
                            Image {
                                anchors.fill: parent
                                visible: clipRow.modelData.isImage
                                source: visible ? ClipboardData.thumbFor(clipRow.modelData.id) : ""
                                sourceSize: Qt.size(96, 96)
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true; cache: false
                                Component.onCompleted: if (clipRow.modelData.isImage) ClipboardData.requestThumb(clipRow.modelData)
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 3
                            ClipText {
                                Layout.fillWidth: true
                                text: clipRow.modelData.isImage ? "图片" : clipRow.modelData.preview
                                font: Tokens.font.body.small
                                color: clipRow.selected ? ConsoleStyle.selectedText : root.fg
                                elide: Text.ElideRight
                                maximumLineCount: 1
                            }
                            ClipText {
                                Layout.fillWidth: true
                                text: clipRow.modelData.meta
                                font: Tokens.font.label.builders.medium.weight(Font.Normal).build()
                                color: clipRow.selected ? Qt.alpha(ConsoleStyle.selectedText, 0.75) : root.muted
                                elide: Text.ElideRight
                            }
                        }
                        MaterialIcon {
                            visible: ClipboardData.isPinned(clipRow.modelData)
                            text: "keep"
                            color: clipRow.selected ? ConsoleStyle.selectedText : root.accent
                        }
                    }
                    MouseArea {
									id: clipRowMouse

									anchors.fill: parent
									hoverEnabled: true
									acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
									onEntered: if (!root.editing) clipList.currentIndex = clipRow.index
									onClicked: mouse => {
                                        if (clipEditor.saving) return;
                                        if (mouse.button === Qt.LeftButton) {
                                            if (root.editing) clipEditor.cancel();
                                            // Compare before changing selection: another row previews,
                                            // the row already shown in the details pane pastes.
                                            if (clipList.currentIndex === clipRow.index) {
                                                root.pasteSelectedClip();
                                                return;
                                            }
                                            clipList.currentIndex = clipRow.index;
                                            ClipboardData.ensurePreview(clipRow.modelData);
                                            return;
                                        }
                                        if (root.editing) return;
                                        clipList.currentIndex = clipRow.index;
                                        if (mouse.button === Qt.MiddleButton)
                                            ClipboardData.remove(clipRow.modelData);
                                        else if (mouse.button === Qt.RightButton)
                                            root.toggleSelectedClipPin();
                                    }
								}
                }
                ClipText {
                    anchors.centerIn: parent
                    width: parent.width - 24
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    visible: clipList.count === 0
                    text: ClipboardData.busy ? "读取剪贴板历史…" : root.query ? "没有匹配的条目" : "剪贴板历史为空"
                    color: root.muted
                }
            }
            ClipText { text: "↑ ↓ 选择    再点当前条目或 Enter 粘贴"; font: Tokens.font.label.small; color: root.muted }
        }
        ColumnLayout {
            id: clipPreviewPane
            property var entry: root.entry
            property bool loading: !!entry && (entry.isImage
                ? ClipboardData.previewBusyId === entry.id && ClipboardData.previewFor(entry.id) === ""
                : ClipboardData.textBusyId === entry.id && ClipboardData.textFor(entry) === "")
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 12
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 34
                ClipText {
                    Layout.fillWidth: true
                    text: root.entry ? (root.entry.isImage ? "图片剪贴板条目" : "文本剪贴板条目") : "内容预览"
                    font: Tokens.font.title.builders.small.weight(Font.DemiBold).build()
                    elide: Text.ElideRight
                }
                Row {
                    spacing: 6
                    ClipIconButton { symbol: "content_copy"; label: "复制"; enabled: !!root.entry && !clipEditor.saving; onClicked: root.copySelectedClip() }
                    ClipIconButton { symbol: "keep"; label: root.entry && ClipboardData.isPinned(root.entry) ? "取消置顶" : "置顶"; emphasized: root.entry && ClipboardData.isPinned(root.entry); enabled: !!root.entry && !clipEditor.saving; onClicked: root.toggleSelectedClipPin() }
                    ClipIconButton { symbol: "check"; label: "保存并复制 · Ctrl+Enter"; enabled: clipEditor.canSave; onClicked: clipEditor.save() }
                    ClipIconButton { symbol: "undo"; label: "撤销修改"; enabled: clipEditor.dirty && !clipEditor.saving; onClicked: clipEditor.cancel() }
                    ClipIconButton { symbol: "delete"; label: "删除"; destructive: true; enabled: !!root.entry && !clipEditor.saving; onClicked: root.requestClipConfirm("delete") }
                    ClipIconButton { symbol: "close"; label: "关闭"; enabled: !clipEditor.saving; onClicked: root.closeRequested() }
                }
            }
            ClipText {
                Layout.fillWidth: true
                Layout.preferredHeight: 20
                text: clipEditor.error || (root.entry
                    ? (root.entry.isImage ? root.entry.info : `文本 · ${clipEditor.textLength} 字符`)
                        + (clipEditor.dirty ? " · 未保存" : "")
                        + (ClipboardData.isPinned(root.entry) ? " · 已置顶" : "")
                    : "选择左侧记录查看内容")
                font: Tokens.font.label.builders.medium.weight(Font.Normal).build()
                color: clipEditor.error ? Colours.palette.m3error : root.muted
                elide: Text.ElideRight
            }
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: ConsoleStyle.content
                radius: 20
                border.width: 1
                border.color: ConsoleStyle.outline
                Item {
                    id: clipPreviewBody
                    anchors.fill: parent
                    anchors.margins: 16
                    ClipboardTextEditor {
                        id: clipEditor
                        visible: !!root.entry && !root.entry.isImage
                        entry: root.entry
                        onFocusSearchRequested: root.focusSearch()
                        onCopied: {}
                        onSaved: {
                            root.savedSelectionPending = true;
                            ClipboardData.refresh();
                        }
                    }
                    Image {
                        anchors.fill: parent
                        visible: !!root.entry && root.entry.isImage
                        source: visible ? ClipboardData.previewFor(root.entry.id) : ""
                        sourceSize: Qt.size(1024, 1024)
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        cache: false
                    }
                    ClipText {
                        anchors.centerIn: parent
                        visible: !!root.entry && (root.entry.isImage ? clipPreviewPane.loading : clipEditor.loading)
                        text: "读取中…"
                        color: root.muted
                    }
                }
                ClipText { anchors.centerIn: parent; visible: !root.entry; text: "暂无预览"; color: root.muted }
            }
        }
    }
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

					ClipText {
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

							ClipText {
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

							ClipText {
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
