pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
import qs.aibackend
import qs.services

// Console 独立居中窗口；窗口本体不做入场滑动，减少面板打开时的额外布局动画。
FloatingWindow {
    id: root

    title: "caelestia-console"
    color: ConsoleMaterialStyle.background
    visible: ConsoleState.active
    implicitWidth: Math.min(1080, Math.max(900, Math.round(Screen.width * 0.48)), Screen.width - 64)
    implicitHeight: Math.min(760, Math.max(640, Math.round(Screen.height * 0.54)), Screen.height - 80)
    readonly property bool hasFullscreen: Hypr.focusedWorkspace?.toplevels.values.some(t => t.lastIpcObject.fullscreen > 1) ?? false
    // 持有引用让后台预翻译单例随 shell 启动即存在，即使从未打开 Console 也会补齐译文。
    readonly property int translationPending: Translator.pending

    IpcHandler {
        target: "console"

        function toggle(): void {
            if (!ConsoleState.active && root.hasFullscreen)
                return;
            ConsoleState.active = !ConsoleState.active;
        }

        function open(mode: string): void {
            if (root.hasFullscreen)
                return;
            if (["apps", "wallpaper", "clipboard", "emoji", "software"].indexOf(mode) >= 0)
                ConsoleState.requestedMode = mode;
            ConsoleState.active = true;
        }

        function close(): void {
            ConsoleState.active = false;
        }

        function clipboard(): void {
            if (root.hasFullscreen)
                return;
            ConsoleState.requestedMode = "clipboard";
            ConsoleState.active = true;
        }

        function closeSelected(): void {
            if (ConsoleState.active)
                panel.closeOverviewWindow();
        }
        function fullscreenSelected(mode: string): void {
            if (ConsoleState.active)
                panel.fullscreenOverview(mode);
        }
        function launch(command: string): void {
            if (ConsoleState.active)
                panel.launchShortcut(command);
        }
        function isOpen(): bool {
            return ConsoleState.active;
        }
    }

    ConsolePanel {
        id: panel

        anchors.fill: parent
        visible: ConsoleState.active
        screenState: ShellState.forActive()
        maxHeight: Screen.height - 80
        onCloseRequested: ConsoleState.active = false
    }
}
