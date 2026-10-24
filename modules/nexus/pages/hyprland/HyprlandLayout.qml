import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Caelestia.I18n
import qs.components.controls
import qs.modules.nexus.common

PageBase {
    id: root

    property string currentLayout: ""
    property string requestedLayout: ""
    readonly property list<MenuItem> layoutItems: [
        MenuItem { property string layoutId: "scrolling"; text: "Scrolling" },
        MenuItem { property string layoutId: "dwindle"; text: "Dwindle" },
        MenuItem { property string layoutId: "master"; text: "Master" },
        MenuItem { property string layoutId: "monocle"; text: "Monocle" }
    ]

    title: "Hyprland 布局"

    Component.onCompleted: layoutReader.running = true

    function chooseLayout(name: string): void {
        // This host uses Hyprland's native Lua parser; legacy `hyprctl keyword` is rejected.
        root.requestedLayout = name;
        const escapedName = JSON.stringify(name);
        const layoutOptions = name === "scrolling"
            ? `, scrolling = { fullscreen_on_one_column = true, focus_fit_method = 1, column_width = 0.5, follow_focus = true, follow_min_visible = 0.0, explicit_column_widths = "0.35, 0.5, 0.65, 1.0" }`
            : name === "dwindle"
                ? ", dwindle = { preserve_split = true, smart_split = false, smart_resizing = true }"
                : "";
        const luaCommands = [
            `hl.config({ general = { layout = ${escapedName} }${layoutOptions} })`,
            `hl.animation({ leaf = "workspaces", enabled = true, speed = 3, bezier = "standard", style = "slidefade${name === "scrolling" ? "vert" : ""} 20%" })`,
            'hl.unbind("SHIFT + mouse_down")',
            'hl.unbind("SHIFT + mouse_up")'
        ];

        if (name === "scrolling") {
            luaCommands.push('hl.bind("SHIFT + mouse_down", hl.dsp.layout("move +col"))');
            luaCommands.push('hl.bind("SHIFT + mouse_up", hl.dsp.layout("move -col"))');
        }

        const wasScrolling = root.currentLayout === "scrolling";
        const willBeScrolling = name === "scrolling";
        if (wasScrolling !== willBeScrolling) {
            const nextGesture = willBeScrolling ? "scroll_move" : "workspace";
            luaCommands.push('hl.gesture({ fingers = require("variables").gestureFingers, direction = "horizontal", action = "unset" })');
            luaCommands.push(`hl.gesture({ fingers = require("variables").gestureFingers, direction = "horizontal", action = "${nextGesture}" })`);
        }

        layoutWriter.command = ["hyprctl", "eval", luaCommands.join("; ")];
        layoutWriter.running = true;

        // Persist to ~/.config/hypr/variables.lua so restarts/reloads retain this layout
        layoutPersister.command = ["sed", "-i", `s/^\\([[:space:]]*layout[[:space:]]*=[[:space:]]*\\)"[^"]*"\\(.*\\)/\\1"${name}"\\2/`, Quickshell.env("HOME") + "/.config/hypr/variables.lua"];
        layoutPersister.running = true;
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
            enabled: root.currentLayout !== "" && root.currentLayout !== "未知"
            label: "Hyprland 布局"
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

        Process {
            id: layoutPersister
            running: false
        }
    }
}
