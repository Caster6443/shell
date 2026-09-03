pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.overview

Item {
	id: workspaceContainer

	required property int index
	required property var overviewRoot
	required property ListModel windowModel
	property bool isSpecial: false
	property int specialWsId: -1
	property real cardW: 400
	property real cardH: 260
	property bool filterActive: false
	property var launchOnWorkspace: null

	property int wsId: isSpecial ? specialWsId : index + 1
	property bool hasActiveDrag: false

	readonly property real workspaceW: cardW
	readonly property real workspaceH: cardH

	readonly property int matchingCount: {
		let n = 0;
		for (let i = 0; i < windowModel.count; ++i) {
			if (windowModel.get(i).m_wsId === wsId)
				n++;
		}
		return n;
	}

	visible: !(filterActive && matchingCount === 0)

	property real contentMaxWidth: {
		let monW = Hyprland.focusedMonitor?.width || 1920;
		let totalW = 0;
		let count = 0;
		for (let i = 0; i < windowModel.count; ++i) {
			const it = windowModel.get(i);
			if (it.m_wsId !== wsId)
				continue;
			const w = it.m_sizeW;
			totalW += (w > 0 ? w : monW / 2);
			count++;
		}
		const gap = 40;
		if (count > 0)
			totalW += (count - 1) * gap;
		totalW += gap * 2;
		return Math.max(monW, totalW);
	}

	readonly property real scaleRatio: workspaceW / contentMaxWidth

	width: workspaceW
	height: workspaceH
	z: hasActiveDrag ? 100 : 0

	Rectangle {
		anchors.fill: parent
		radius: 18
		clip: true

		color: {
			if (isSpecial)
				return Qt.darker(M3Palette.m3surfaceContainer, 1.4);
			return Hyprland.focusedMonitor?.activeWorkspace?.id === wsId ? M3Palette.m3surfaceContainer : M3Palette.m3surface;
		}
		border.width: 1
		border.color: isSpecial ? Qt.alpha(M3Palette.m3onSurface, 0.12) : (Hyprland.focusedMonitor?.activeWorkspace?.id === wsId ? M3Palette.m3primary : M3Palette.m3outlineVariant)

		Image {
			anchors.fill: parent
			source: isSpecial ? "" : overviewRoot.currentWallpaperPath
			fillMode: Image.PreserveAspectCrop
			opacity: 0.6
		}

		MouseArea {
			anchors.fill: parent
			onClicked: {
				if (isSpecial)
					HyprDispatch.call("togglespecialworkspace special", 'hl.dsp.workspace.toggle_special("special")');
				else
					HyprDispatch.call(`workspace ${wsId}`, `hl.dsp.focus({ workspace = "${wsId}" })`);
				overviewRoot.closeOverview();
			}
		}

		Text {
			anchors.top: parent.top
			anchors.left: parent.left
			anchors.margins: 8
			text: isSpecial ? "S" : wsId
			color: isSpecial ? M3Palette.m3onTertiaryContainer : M3Palette.m3onSurface
			font.pixelSize: 13
			font.bold: true
			z: 10
		}

		DropArea {
			anchors.fill: parent
			keys: ["window", "app"]
			onDropped: drop => {
				if (drop.source && drop.source.appEntry) {
					if (workspaceContainer.launchOnWorkspace)
						workspaceContainer.launchOnWorkspace(drop.source.appEntry, wsId, isSpecial);
					drop.accepted = true;
					drop.action = Qt.MoveAction;
				} else if (drop.source && drop.source.windowAddress) {
					if (drop.source.currentWsId !== wsId) {
						const addr = HyprDispatch.addressArg(drop.source.windowAddress);
						if (isSpecial) {
							HyprDispatch.call(
								`movetoworkspacesilent special,address:${drop.source.windowAddress}`,
								`hl.dsp.window.move({ window = "address:${addr}", workspace = "special", follow = false })`
							);
						} else {
							HyprDispatch.call(
								`movetoworkspacesilent ${wsId},address:${drop.source.windowAddress}`,
								`hl.dsp.window.move({ window = "address:${addr}", workspace = "${wsId}", follow = false })`
							);
						}
						drop.action = Qt.MoveAction;
					} else {
						drop.action = Qt.CopyAction;
					}
					drop.accepted = true;
					overviewRoot.restartSyncTimer();
				}
			}
		}
	}

	Item {
		id: windowLayer
		anchors.fill: parent
		z: 5
		Component.onCompleted: overviewRoot.registerWorkspace(wsId, windowLayer)
	}
}
