pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Item {
    id: root

    // 暴露给前端（Overview.qml）的数据接口
    property var windowList: []
    property var workspaces: []
    property var activeWorkspace: null

    // 被前端调用的刷新指令
    function updateAll() {
        getClients.running = true;
        getWorkspaces.running = true;
        getActiveWorkspace.running = true;
    }

    Component.onCompleted: {
        updateAll();
    }

    // 【核心魔法】实时监听 Hyprland 底层事件
    // 只要你打开/关闭窗口、切换工作区，它瞬间就会触发刷新
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            // 过滤掉跟窗口无关的垃圾事件，节省性能
            if (["openlayer", "closelayer", "screencast", "activemon"].includes(event.name))
                return;
            updateAll();
        }
    }

    // 后台进程 1：获取所有窗口
    Process {
        id: getClients
        command: ["hyprctl", "clients", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.windowList = JSON.parse(this.text);
                } catch (e) {}
            }
        }
    }

    // 后台进程 2：获取所有工作区
    Process {
        id: getWorkspaces
        command: ["hyprctl", "workspaces", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var rawWorkspaces = JSON.parse(this.text);
                    // 过滤掉某些特殊的隐藏工作区（比如锁屏用的）
                    root.workspaces = rawWorkspaces.filter(ws => ws.id >= 1 && ws.id <= 100);
                } catch (e) {}
            }
        }
    }

    // 后台进程 3：获取当前活跃的工作区
    Process {
        id: getActiveWorkspace
        command: ["hyprctl", "activeworkspace", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.activeWorkspace = JSON.parse(this.text);
                } catch (e) {}
            }
        }
    }
}
