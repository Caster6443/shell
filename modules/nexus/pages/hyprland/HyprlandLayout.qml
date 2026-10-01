import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import Caelestia.I18n
import qs.components.controls
import qs.modules.nexus.common

PageBase {
    id: root

    property string currentLayout: ""
    property string requestedLayout: ""
    readonly property list<MenuItem> layoutItems: [
        MenuItem { property string layoutId: "scrolling"; text: "滚动（Scrolling）" },
        MenuItem { property string layoutId: "dwindle"; text: "二叉树平铺（Dwindle）" },
        MenuItem { property string layoutId: "master"; text: "主从平铺（Master）" },
        MenuItem { property string layoutId: "monocle"; text: "单窗口占满（Monocle）" }
    ]

    title: "Hyprland 布局"

    Component.onCompleted: layoutReader.running = true

    function chooseLayout(name: string): void {
        // This host uses Hyprland's native Lua parser; legacy `hyprctl keyword` is rejected.
        root.requestedLayout = name;
        const escapedName = JSON.stringify(name);
        layoutWriter.command = ["hyprctl", "eval", `hl.config({ general = { layout = ${escapedName} } })`];
        layoutWriter.running = true;
    }

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        SectionHeader {
            first: true
            text: "窗口布局"
        }

        SelectRow {
            first: true
            last: true
            label: "Hyprland 布局"
            subtext: "立即切换当前会话使用的窗口布局"
            menuItems: root.layoutItems
            active: root.layoutItems.find(item => item.layoutId === root.currentLayout) ?? null
            fallbackText: root.currentLayout || "读取中…"
            onSelected: item => root.chooseLayout(item.layoutId)
        }

        Process {
            id: layoutReader
            command: ["hyprctl", "-j", "getoption", "general:layout"]
            running: false

            stdout: StdioCollector {
                onStreamFinished: {
                    try {
                        root.currentLayout = JSON.parse(text).str;
                    } catch (error) {
                        root.currentLayout = "未知";
                    }
                }
            }
        }

        Process {
            id: layoutWriter
            running: false

            onExited: (exitCode, exitStatus) => {
                if (exitCode === 0)
                    root.currentLayout = root.requestedLayout;
                else
                    layoutReader.running = true;
            }
        }
    }
}
