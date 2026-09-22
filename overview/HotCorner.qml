pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.overview

PanelWindow {
	id: hotCorner

	anchors.top: true
	anchors.left: true

	implicitWidth: 2
	implicitHeight: 2
	color: "transparent"

	WlrLayershell.namespace: "caelestia-overview-hotcorner"
	WlrLayershell.layer: WlrLayer.Overlay
	WlrLayershell.exclusionMode: ExclusionMode.Ignore

	Timer {
		id: triggerTimer
		interval: 150
		repeat: false
		onTriggered: {
			if (!OverviewState.active)
				OverviewState.active = true;
		}
	}

	HoverHandler {
		onHoveredChanged: {
			if (hovered) {
				triggerTimer.restart();
			} else {
				triggerTimer.stop();
			}
		}
	}
}
