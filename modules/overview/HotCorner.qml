pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.services

PanelWindow {
    id: hotCorner

    // 把窗口钉在左上角
    anchors.top: true
    anchors.left: true

    // 大小只需 2x2 像素（因为甩鼠标时一定会卡在 0,0 坐标）
    // 设得太大会挡住你点击全屏软件左上角的按钮
    implicitWidth: 2
    implicitHeight: 2
    color: "transparent"

    // 必须在最顶层，且不排挤其他窗口
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.exclusionMode: ExclusionMode.Ignore

    // 防误触计时器：鼠标必须在角落停留 150ms 才会触发
    Timer {
        id: triggerTimer
        interval: 150
        repeat: false
        onTriggered: {
            const vis = Visibilities.getForActive();
            // 如果 overview 没开，就打开它
            if (vis && !vis.overview) {
                vis.overview = true;
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true

        // 鼠标撞进左上角：开始倒计时
        onEntered: {
            triggerTimer.start();
        }
        // 鼠标滑出左上角：立刻取消倒计时
        onExited: {
            triggerTimer.stop();
        }
    }
}
