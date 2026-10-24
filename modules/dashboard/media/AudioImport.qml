pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Dialogs
import Quickshell
import Quickshell.Io
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

RowLayout {
	id: root

	required property ScreenState screenState

	property string phase: "idle" // idle, name, download, artist, tag
	Component.onDestruction: root.screenState.dashboardTextInput = false
	Connections {
		target: root.screenState
		function onDashboardChanged(): void {
			if (!root.screenState.dashboard)
				root.screenState.dashboardTextInput = false;
		}
	}

	function updateTextInputFocus(): void {
		root.screenState.dashboardTextInput = titleField.activeFocus || artistField.activeFocus;
	}
	property string songTitle: ""
	property string artist: ""
	property string directory: "/home/caster/Music/list"
	property string statusText: ""
	property string tempPath: ""
	property string finalPath: ""
	property string mpdRelativePath: ""
	property string sourceUrl: ""
	property bool cancelRequested: false
	readonly property string musicRoot: "/home/caster/Music"
	readonly property string statePath: `${Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") || "") + "/.local/state"}/caelestia/audio-import.json`
	readonly property bool mpdActive: {
		const id = String(Players.active?.identity ?? "").toLowerCase().replace(/[^a-z0-9]/g, "");
		const label = String(Players.getIdentity(Players.active) ?? "").toLowerCase().replace(/[^a-z0-9]/g, "");
		return id.includes("mpd") || label.includes("mpd") || label.includes("musicplayerdaemon");
	}

	spacing: Tokens.spacing.extraSmall
	visible: !root.mpdActive
	implicitWidth: capsule.implicitWidth + (folderButton.visible ? folderButton.implicitWidth + spacing : 0)
	implicitHeight: capsule.implicitHeight

	function cleanName(value: string): string {
		return String(value).replace(/[/:*?"<>|]/g, "_").replace(/[\u0000-\u001f]/g, "_").trim().replace(/^[. ]+|[. ]+$/g, "");
	}

	function startDownload(): void {
		if (root.phase !== "name")
			return;
		const title = root.cleanName(root.songTitle);
		const url = String(Players.active?.metadata?.["xesam:url"] ?? "").trim();
		if (!title) {
			root.statusText = "请输入歌曲名";
			return;
		}
		if (!url.toLowerCase().startsWith("http://") && !url.toLowerCase().startsWith("https://")) {
			root.statusText = "当前播放器没有提供可下载链接";
			return;
		}
		if (!root.directory.startsWith("/")) {
			root.statusText = "保存目录无效";
			return;
		}

		root.songTitle = title;
		root.sourceUrl = url;
		const token = Date.now().toString();
		root.tempPath = `/home/caster/.cache/caelestia/audio-import/${token}.mp3`;
		root.finalPath = `${root.directory}/${title}.mp3`;
		root.statusText = "准备下载…";
		root.cancelRequested = false;
		root.phase = "download";
		prepareProc.running = true;
	}


	function finishWithArtist(): void {
		const value = root.cleanName(root.artist);
		if (!value) {
			root.statusText = "请输入歌手名";
			return;
		}
		root.artist = value;
		root.phase = "tag";
		root.statusText = "正在写入歌曲信息…";
		tagProc.command = [
			"ffmpeg", "-nostdin", "-v", "error", "-n", "-i", root.tempPath,
			"-map", "0", "-c", "copy", "-metadata", `title=${root.songTitle}`,
			"-metadata", `artist=${root.artist}`, "-id3v2_version", "3", root.finalPath
		];
		tagProc.running = true;
	}


	FileView {
		id: settingsFile
		path: root.statePath
		blockWrites: true
		printErrors: false
		onLoaded: {
			try {
				const saved = JSON.parse(text());
				if (typeof saved.directory === "string" && saved.directory.startsWith("/"))
					root.directory = saved.directory;
			} catch (e) {
				console.warn(`[audio-import] 读取默认目录设置失败: ${e}`);
			}
		}
		onLoadFailed: err => {
			if (err === FileViewError.FileNotFound)
				Qt.callLater(() => setText(JSON.stringify({ directory: root.directory })));
		}
	}

	FolderDialog {
		id: folderDialog
		title: "选择音频保存目录"
		currentFolder: Qt.resolvedUrl(encodeURI("file://" + root.directory))
		onAccepted: {
			const chosen = decodeURIComponent(selectedFolder.toString()).replace(/^file:\/\//, "");
			if (chosen.startsWith("/")) {
				root.directory = chosen;
				settingsFile.setText(JSON.stringify({ directory: chosen }, null, "\t"));
				Quickshell.execDetached(["mkdir", "-p", root.statePath.substring(0, root.statePath.lastIndexOf("/"))]);
				root.statusText = "默认保存目录已更新";
			}
		}
	}

	StyledRect {
		id: capsule

		Layout.alignment: Qt.AlignVCenter
		implicitWidth: root.phase === "idle" ? 44 : root.phase === "download" || root.phase === "tag" ? 164 : 228
		implicitHeight: 44
		radius: implicitHeight / 2
		color: Colours.palette.m3secondaryContainer
		clip: true

		Behavior on implicitWidth {
			Anim {}
		}

		StateLayer {
			anchors.fill: parent
			radius: parent.radius
			visible: root.phase === "idle"
			color: Colours.palette.m3onSecondaryContainer
			ToolTip.visible: containsMouse
			ToolTip.text: root.statusText || "下载当前媒体到本地"
			onClicked: {
				root.statusText = "";
				root.songTitle = String(Players.active?.trackTitle ?? "").trim();
				root.phase = "name";
				Qt.callLater(() => {
					titleField.forceActiveFocus();
					titleField.selectAll();
				});
			}
		}

		MaterialIcon {
			anchors.centerIn: parent
			visible: root.phase === "idle"
			text: "download"
			fontStyle: Tokens.font.icon.medium
			color: Colours.palette.m3onSecondaryContainer
		}


		RowLayout {
			anchors.fill: parent
			anchors.leftMargin: Tokens.padding.small
			anchors.rightMargin: Tokens.padding.extraSmall
			spacing: Tokens.spacing.extraSmall
			visible: root.phase !== "idle"

			StyledTextField {
				id: titleField
				Layout.fillWidth: true
				Layout.minimumWidth: 32
				visible: root.phase === "name"
				onActiveFocusChanged: root.updateTextInputFocus()
				placeholderText: "歌曲名"
				focus: visible
				activeFocusOnTab: true
				verticalPadding: Tokens.padding.extraSmall
				onVisibleChanged: {
					if (visible) {
						Qt.callLater(() => {
							forceActiveFocus();
							selectAll();
						});
					}
				}
				text: root.songTitle
				onTextEdited: {
					root.songTitle = text;
					root.statusText = "";
				}
				onAccepted: root.startDownload()
			}

			StyledTextField {
				id: artistField
				Layout.fillWidth: true
				Layout.minimumWidth: 32
				visible: root.phase === "artist"
				onActiveFocusChanged: root.updateTextInputFocus()
				focus: visible
				activeFocusOnTab: true
				placeholderText: "输入歌手名"
				verticalPadding: Tokens.padding.extraSmall
				text: root.artist
				onTextEdited: {
					root.artist = text;
					root.statusText = "";
				}
				onAccepted: root.finishWithArtist()
			}

			CircularIndicator {
				implicitSize: 20
				visible: root.phase === "download" || root.phase === "tag"
				running: visible
			}

			StyledText {
				Layout.fillWidth: true
				visible: root.phase === "download" || root.phase === "tag"
				text: root.statusText
				font: Tokens.font.label.small
				color: Colours.palette.m3onSecondaryContainer
				elide: Text.ElideRight
			}


			IconButton {
				icon: "check"
				isRound: true
				type: IconButton.Filled
				visible: root.phase === "name"
				ToolTip.visible: hovered && root.statusText !== ""
				ToolTip.text: root.statusText || "下载当前链接"
				onClicked: root.startDownload()
			}

			IconButton {
				icon: "check"
				isRound: true
				type: IconButton.Filled
				visible: root.phase === "artist"
				ToolTip.visible: hovered && root.statusText !== ""
				ToolTip.text: root.statusText || "写入歌曲信息"
				onClicked: root.finishWithArtist()
			}

			IconButton {
				icon: "close"
				isRound: true
				visible: root.phase === "download"
				ToolTip.visible: hovered
				ToolTip.text: "取消下载"
				onClicked: {
					root.cancelRequested = true;
					prepareProc.running = false;
					downloadProc.running = false;
					duplicateProc.running = false;
					root.phase = "name";
					root.statusText = "已取消";
				}
			}
		}
	}

	IconButton {
		id: folderButton
		Layout.alignment: Qt.AlignVCenter
		visible: root.phase === "name"
		icon: "folder_open"
		isRound: true
		disabled: root.phase === "download" || root.phase === "tag" || root.phase === "artist"
		ToolTip.visible: hovered
		ToolTip.text: `保存目录：${root.directory}（点击更改默认目录）`
		onClicked: folderDialog.open()
	}

	Process {
		id: prepareProc
		command: ["mkdir", "-p", "/home/caster/.cache/caelestia/audio-import"]
		running: false
		onExited: (code, status) => {
			if (root.cancelRequested) {
				root.cancelRequested = false;
				root.phase = "name";
				root.statusText = "已取消";
				return;
			}
			if (code !== 0) {
				root.phase = "name";
				root.statusText = "无法创建临时下载目录";
				return;
			}
			root.statusText = "正在下载音频…";
			downloadProc.command = [
				"yt-dlp", "--ignore-config", "--extract-audio", "--audio-format", "mp3", "--no-playlist",
				"--embed-thumbnail", "--cookies-from-browser", "firefox", "--socket-timeout", "15",
				"--no-progress", "--output", root.tempPath.slice(0, -4) + ".%(ext)s", "--", root.sourceUrl
			];
			downloadProc.running = true;
		}
	}

	Process {
		id: downloadProc
		running: false
		onExited: (code, status) => {
			if (root.cancelRequested) {
				root.cancelRequested = false;
				Quickshell.execDetached(["rm", "-f", root.tempPath]);
				root.phase = "name";
				root.statusText = "已取消";
			} else if (code === 0) {
				root.statusText = "正在检查重复音频…";
				duplicateProc.command = ["python", decodeURIComponent(Qt.resolvedUrl("AudioImportCheck.py").toString()).replace(/^file:\/\//, ""), root.tempPath, root.directory];
				duplicateProc.running = true;
			} else {
				Quickshell.execDetached(["rm", "-f", root.tempPath]);
				root.phase = "name";
				root.statusText = `下载失败（退出码 ${code}），请检查链接、网络或 Firefox cookies`;
			}
		}
	}

	Process {
		id: duplicateProc
		running: false
		stdout: StdioCollector { id: duplicateOutput }
		onExited: (code, status) => {
			if (root.cancelRequested) {
				root.cancelRequested = false;
				Quickshell.execDetached(["rm", "-f", root.tempPath]);
				return;
			}
			if (code === 0) {
				root.phase = "artist";
				root.artist = "";
				root.statusText = "下载完成，请输入歌手名";
			} else {
				root.phase = "name";
				root.statusText = String(duplicateOutput.text).trim() || "重复音频检查失败，未保存歌曲";
				Quickshell.execDetached(["rm", "-f", root.tempPath]);
			}
		}
	}

	Process {
		id: tagProc
		running: false
		onExited: (code, status) => {
			if (code !== 0) {
				root.phase = "artist";
				root.statusText = "元数据写入失败；临时音频保留，目标文件可能已存在";
				return;
			}
			Quickshell.execDetached(["rm", "-f", root.tempPath]);
			const dir = root.directory.endsWith("/") ? root.directory.slice(0, -1) : root.directory;
			if (dir === root.musicRoot || dir.startsWith(root.musicRoot + "/")) {
				const relative = root.finalPath.substring(root.musicRoot.length + 1);
				root.mpdRelativePath = relative;
				mpdRefreshProc.command = ["mpc", "--wait", "update", relative];
				mpdRefreshProc.running = true;
				root.statusText = "已保存，正在刷新 MPD 音乐库…";
			} else {
				root.phase = "idle";
				root.statusText = "已保存；目录位于 MPD 音乐库之外，未加入数据库";
			}
		}
	}

	Process {
		id: mpdRefreshProc
		running: false
		onExited: (code, status) => {
			if (code === 0) {
				mpdQueueProc.command = ["mpc", "add", root.mpdRelativePath];
				mpdQueueProc.running = true;
				root.statusText = "音乐库已更新，正在加入当前播放队列…";
			} else {
				root.phase = "idle";
				root.statusText = "已保存，但 MPD 音乐库刷新失败，未加入播放队列";
			}
		}
	}

	Process {
		id: mpdQueueProc
		running: false
		onExited: (code, status) => {
			root.phase = "idle";
			root.statusText = code === 0 ? "已保存、刷新音乐库并加入当前队列" : "音乐库已更新，但加入当前播放队列失败";
		}
	}
}
