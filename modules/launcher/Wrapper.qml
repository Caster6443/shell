pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Caelestia.Config
import qs.components
import qs.modules.launcher.services

Item {
    id: root

    required property ShellScreen screen
    required property ScreenState screenState
    required property var panels

    readonly property bool shouldBeActive: screenState.launcher && Config.launcher.enabled

    readonly property real maxHeight: {
        let max = screen.height - Config.border.thickness * 2 + Tokens.padding.extraLarge;
        if (screenState.dashboard)
            max -= panels.dashboard.nonAnimHeight;
        return max;
    }

    property real offsetScale: shouldBeActive ? 0 : 1

    // ---- 本地 fork 补丁（2026-09-11）：launcher 面板内容常驻 + 启动预热 ----
    // 上游行为是「打开时创建、关闭即销毁」，每次打开都要重建整棵 SpotlightPanel：
    // 重建会重新创建每个窗口的捕获上下文，进而触发 overview 的 grim 解锁踢脚
    // （约 0.4s 的全屏截屏），表现为打开慢半拍、动画卡一下。
    // 改为首次打开后常驻（配合启动后空闲预热），打开时就只剩入场动画本身。
    // 详见 ~/Github_repos/shell/patches/launcher/wrapper-keep-alive.patch
    property bool panelWarm: false

    onShouldBeActiveChanged: {
        if (shouldBeActive) {
            panelWarm = true;
            implicitHeight = Qt.binding(() => content.implicitHeight);
        } else {
            implicitHeight = implicitHeight; // Break binding during close anim
        }
    }

    visible: offsetScale < 1
    anchors.bottomMargin: (-implicitHeight - 5) * offsetScale
    implicitHeight: content.implicitHeight
    implicitWidth: content.implicitWidth || 630 // Hard coded fallback for first open
    opacity: 1 - offsetScale

    Component.onCompleted: Qt.callLater(() => Apps) // Load apps on init

    // 启动后空闲预热：让第一次打开也是热的（否则第一次打开仍要现场构建面板）
    Timer {
        id: prewarmTimer

        interval: 6000
        repeat: false
        running: true
        onTriggered: root.panelWarm = true
    }

    Behavior on offsetScale {
        Anim {}
    }

    Loader {
        id: content

        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter

        active: root.shouldBeActive || root.visible || root.panelWarm

        sourceComponent: Content {
            screenState: root.screenState
            panels: root.panels
            maxHeight: root.maxHeight
        }
    }
}
