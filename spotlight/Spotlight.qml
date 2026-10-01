pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
import qs.services

// Spotlight 独立居中窗口；窗口本体不做入场滑动，减少面板打开时的额外布局动画。
FloatingWindow {
    id: root

    title: "caelestia-spotlight"
    color: "transparent"
    visible: SpotlightState.active
    implicitWidth: Math.min(1080, Math.max(900, Math.round(Screen.width * 0.48)), Screen.width - 64)
    implicitHeight: Math.min(760, Math.max(640, Math.round(Screen.height * 0.54)), Screen.height - 80)
    readonly property bool hasFullscreen: Hypr.focusedWorkspace?.toplevels.values.some(t => t.lastIpcObject.fullscreen > 1) ?? false

    IpcHandler {
        target: "spotlight"

        function toggle(): void {
            if (!SpotlightState.active && root.hasFullscreen)
                return;
            SpotlightState.active = !SpotlightState.active;
        }

        function open(mode: string): void {
            if (root.hasFullscreen)
                return;
            if (["apps", "wallpaper", "clipboard", "emoji"].indexOf(mode) >= 0)
                SpotlightState.requestedMode = mode;
            SpotlightState.active = true;
        }

        function close(): void {
            SpotlightState.active = false;
        }

        function clipboard(): void {
            if (root.hasFullscreen)
                return;
            SpotlightState.requestedMode = "clipboard";
            SpotlightState.active = true;
        }

        function isOpen(): bool {
            return SpotlightState.active;
        }
    }

    SpotlightPanel {
        id: panel

        anchors.fill: parent
        visible: SpotlightState.active
        screenState: ShellState.forActive()
        maxHeight: Screen.height - 80
        onCloseRequested: SpotlightState.active = false
    }
}
