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
	property string sourceUrl: ""
	property bool cancelRequested: false
	readonly property bool recognitionRunning: recognitionSinkProc.running || recognitionProc.running
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

	function startRecognition(device: string): void {
		const command = ["timeout", "18s", "songrec", "recognize", "--json", "--request-interval", "5"];
		if (device)
			command.push("--audio-device", device);
		recognitionProc.command = command;
		recognitionProc.running = true;
	}

	function findRecognizedTitle(value: var): string {
		if (!value || typeof value !== "object")
			return "";
		if (!Array.isArray(value)) {
			for (const key of ["track", "song", "title", "trackTitle", "track_title", "name"]) {
				const child = value[key];
				if ((key === "track" || key === "song") && child && typeof child === "object") {
					const nested = root.findRecognizedTitle(child);
					if (nested)
						return nested;
				}
				if (["title", "trackTitle", "track_title", "name"].includes(key) && typeof child === "string" && child.trim())
					return child.trim();
			}
			for (const child of Object.values(value)) {
				const nested = root.findRecognizedTitle(child);
				if (nested)
					return nested;
			}
		} else {
			for (const child of value) {
				const nested = root.findRecognizedTitle(child);
				if (nested)
					return nested;
			}
		}
		return "";
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

			CircularIndicator {
				implicitSize: 20
				visible: root.phase === "name" && root.recognitionRunning
				running: visible
			}

			IconButton {
				id: recognizeButton
				icon: "hearing"
				isRound: true
				visible: root.phase === "name" && !root.recognitionRunning
				ToolTip.visible: hovered
				ToolTip.text: root.statusText || "听歌识曲（读取当前扬声器输出）"
				onClicked: {
					root.statusText = "正在识别当前扬声器播放的声音…";
					recognitionSinkProc.running = true;
				}
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
				"yt-dlp", "--extract-audio", "--audio-format", "mp3", "--no-playlist",
				"--embed-thumbnail", "--cookies-from-browser", "firefox", "--socket-timeout", "15",
				"--no-progress", "--output", root.tempPath.slice(0, -4) + ".%(ext)s", root.sourceUrl
			];
			downloadProc.running = true;
		}
	}

	Process {
		id: recognitionSinkProc
		command: ["pactl", "get-default-sink"]
		running: false
		stdout: StdioCollector {
			id: recognitionSinkName
		}
		onExited: (code, status) => {
			const sink = code === 0 ? String(recognitionSinkName.text).trim() : "";
			if (!sink) {
				root.statusText = "无法读取当前默认扬声器";
				return;
			}
			root.startRecognition(`${sink}.monitor`);
		}
	}

	Process {
		id: recognitionProc
		command: []
		running: false
		stdout: StdioCollector {
			onStreamFinished: {
				try {
					const title = root.findRecognizedTitle(JSON.parse(String(this.text)));
					if (title) {
						root.songTitle = title;
						titleField.text = title;
						root.statusText = "已识别歌曲名，可修改后确认";
					} else {
						root.statusText = "没有识别到歌曲";
					}
				} catch (e) {
					root.statusText = "识曲结果解析失败";
				}
			}
		}
		onExited: (code, status) => {
			if (code === 124)
				root.statusText = "识曲超时，请再试一次";
			else if (code !== 0 && !root.statusText.startsWith("已识别"))
				root.statusText = "识曲失败，请检查扬声器输出和网络";
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
				root.phase = "artist";
				root.artist = "";
				root.statusText = "下载完成，请输入歌手名";
			} else {
				Quickshell.execDetached(["rm", "-f", root.tempPath]);
				root.phase = "name";
				root.statusText = `下载失败（退出码 ${code}），请检查链接、网络或 Firefox cookies`;
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
				mpdRefreshProc.command = ["mpc", "update", relative];
				mpdRefreshProc.running = true;
				root.statusText = "已保存，正在刷新 MPD 数据库…";
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
			root.phase = "idle";
			root.statusText = code === 0 ? "已保存并刷新 MPD 数据库" : "已保存，但 MPD 数据库刷新失败";
		}
	}
}
