pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Caelestia.Config
import Caelestia.I18n
import Caelestia.Services
import qs.components
import qs.services
import qs.utils

Variants {
    id: root
    model: Screens.screens.filter(s => s.name !== "CAELESTIA-WALLPAPER-PREVIEW" && GlobalConfig.forScreen(s.name).background.enabled)

    PanelWindow {
        id: win

        required property ShellScreen modelData
        readonly property HyprlandMonitor monitor: Hyprland.monitorFor(modelData)

        readonly property bool occluded: {
            const output = monitor?.lastIpcObject;
            const screenX = Number(output?.x ?? 0);
            const screenY = Number(output?.y ?? 0);
            const left = screenX + win.leftInset;
            const top = screenY + win.topInset;
            const right = left + 380 * win.widgetScale;
            const bottom = top + 184 * win.widgetScale;
            const workspaces = [];
            const activeWorkspace = monitor?.activeWorkspace;
            if (activeWorkspace)
                workspaces.push(activeWorkspace);
            const specialName = output?.specialWorkspace?.name ?? "";
            if (specialName.startsWith("special:")) {
                const specialWorkspace = Hyprland.workspaces.values.find(ws => ws.name === specialName);
                if (specialWorkspace && specialWorkspace !== activeWorkspace)
                    workspaces.push(specialWorkspace);
            }

            for (const workspace of workspaces) {
                for (const toplevel of workspace.toplevels.values) {
                    const client = toplevel.lastIpcObject;
                    const at = client?.at;
                    const size = client?.size;
                    if (!client?.mapped || !at || !size || size.length < 2)
                        continue;

                    const clientLeft = Number(at[0]);
                    const clientTop = Number(at[1]);
                    const clientRight = clientLeft + Number(size[0]);
                    const clientBottom = clientTop + Number(size[1]);
                    if (left < clientRight && right > clientLeft
                        && top < clientBottom && bottom > clientTop)
                        return true;
                }
            }
            return false;
        }

        screen: modelData
        visible: !occluded
        color: "transparent"
        surfaceFormat.opaque: false
        mask: Region {}

        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        anchors.top: true
        anchors.bottom: true
        anchors.left: true
        anchors.right: true

        ServiceRef { service: Cpu }
        ServiceRef { service: Gpu }
        ServiceRef { service: Memory }

        // PanelWindow is not a QQuickItem, so attached Config/Tokens cannot
        // inherit its screen context. Resolve per-screen roots explicitly.
        readonly property var screenConfig: Config.forScreen(modelData.name)
        readonly property var screenTokens: Tokens.forScreen(modelData.name)
        readonly property real widgetScale: screenConfig.background.desktopClock.scale
        readonly property real leftInset: screenConfig.appearance.padding.extraLargeIncreased + screenTokens.sizes.bar.innerWidth + Math.max(screenConfig.appearance.padding.small, screenConfig.border.thickness)
        readonly property real topInset: screenConfig.appearance.padding.extraLargeIncreased
        readonly property real plateOpacity: screenConfig.background.desktopClock.background.enabled
            ? screenConfig.background.desktopClock.background.opacity
            : 0.68
        property var cpuSamples: []
        property var igpuSamples: []
        property var dgpuSamples: []
        property var memorySamples: []
        property real igpuUsage: -1
        property bool samplingReady: false

        function appendSample(history: var, value: real): var {
            const next = history.slice(1);
            next.push(Math.max(0, Math.min(100, value)));
            return next;
        }

        function sampleMetrics(): void {
            if (win.occluded)
                return;

            // Caelestia services expose ratios from 0 to 1; charts store percent points from 0 to 100.
            cpuSamples = appendSample(cpuSamples, Cpu.percentage * 100);
            memorySamples = appendSample(memorySamples, Memory.percentage * 100);
            dgpuSamples = appendSample(dgpuSamples, Gpu.type === GpuType.Nvidia ? Gpu.percentage * 100 : 0);
            igpuReadProc.running = true;
            samplingReady = true;
        }

        onOccludedChanged: {
            if (occluded) {
                igpuReadProc.running = false;
            } else {
                sampleMetrics();
            }
        }

        Component.onCompleted: {
            const blank = Array(48).fill(0);
            cpuSamples = blank.slice();
            igpuSamples = blank.slice();
            dgpuSamples = blank.slice();
            memorySamples = blank.slice();
            if (!occluded)
                sampleMetrics();
        }

        Timer {
            id: sampleTimer
            interval: 1000
            repeat: true
            running: !win.occluded
            onTriggered: win.sampleMetrics()
        }

        Process {
            id: igpuReadProc
            command: ["bash", "-c", "for d in /sys/class/drm/card[0-9]*/device; do [ -r \"$d/vendor\" ] || continue; [ \"$(cat \"$d/vendor\")\" = 0x1002 ] || continue; [ -r \"$d/gpu_busy_percent\" ] && cat \"$d/gpu_busy_percent\" && exit 0; done; echo -1"]
            running: false
            stdout: StdioCollector {
                onStreamFinished: {
                    if (win.occluded)
                        return;

                    const parsed = Number(String(this.text).trim());
                    win.igpuUsage = Number.isFinite(parsed) && parsed >= 0 ? Math.min(100, parsed) : -1;
                    win.igpuSamples = win.appendSample(win.igpuSamples, win.igpuUsage < 0 ? 0 : win.igpuUsage);
                }
            }
        }

        StyledRect {
            id: plate

            x: win.leftInset
            y: win.topInset
            width: 380 * win.widgetScale
            height: 184 * win.widgetScale
            radius: win.screenTokens.appearance.rounding.extraLarge * win.widgetScale
            color: Qt.alpha(Colours.palette.m3surface, win.plateOpacity)

            border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.28)
            border.width: 1

            layer.enabled: win.screenConfig.background.desktopClock.shadow.enabled
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: Colours.palette.m3shadow
                shadowOpacity: win.screenConfig.background.desktopClock.shadow.opacity
                shadowBlur: win.screenConfig.background.desktopClock.shadow.blur
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 13 * win.widgetScale
                spacing: 4 * win.widgetScale

                Repeater {
                    model: [
                        { label: "CPU", icon: "memory", colour: Colours.palette.m3primary,
                          value: Cpu.percentage, display: Strings.percentOne(Cpu.percentage),
                          history: win.cpuSamples, detail: Cpu.temperature > 0 ? Units.formatSensorTemp(Cpu.temperature) : "" },
                        { label: "核显", icon: "desktop_windows", colour: Colours.palette.m3secondary,
                          value: win.igpuUsage, display: win.igpuUsage >= 0 ? Strings.percentOne(win.igpuUsage / 100) : "--",
                          history: win.igpuSamples, detail: "" },
                        { label: "独显", icon: "videogame_asset", colour: Colours.palette.m3tertiary,
                          value: Gpu.type === GpuType.Nvidia ? Gpu.percentage : -1,
                          display: Gpu.type === GpuType.Nvidia ? Strings.percentOne(Gpu.percentage) : "--",
                          history: win.dgpuSamples, detail: "" },
                        { label: "内存", icon: "memory_alt", colour: Colours.palette.m3tertiary,
                          value: Memory.percentage, display: Strings.percentOne(Memory.percentage),
                          history: win.memorySamples, detail: Memory.total > 0 ? Units.formatKibUsage(Memory.used, Memory.total) : "" }
                    ]

                    delegate: RowLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.minimumHeight: 31 * win.widgetScale
                        spacing: 7 * win.widgetScale

                        MaterialIcon {
                            text: modelData.icon
                            color: modelData.colour
                            fontStyle: Tokens.font.icon.builders.medium.scale(win.widgetScale).build()
                        }

                        StyledText {
                            Layout.preferredWidth: 42 * win.widgetScale
                            text: modelData.label
                            color: Colours.palette.m3onSurface
                            font: Tokens.font.clock.size(Tokens.font.body.medium.pointSize * win.widgetScale).weight(Font.DemiBold).build()
                        }

                        EkgTrace {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 21 * win.widgetScale
                            samples: modelData.history
                            traceColour: modelData.colour
                            scaleFactor: win.widgetScale
                            opacity: modelData.value >= 0 ? 1 : 0.34
                        }

                        ColumnLayout {
                            Layout.preferredWidth: modelData.detail === "" ? 50 * win.widgetScale : 62 * win.widgetScale
                            spacing: 0
                            StyledText {
                                Layout.alignment: Qt.AlignRight
                                text: modelData.display
                                color: modelData.colour
                                font: Tokens.font.clock.size(Tokens.font.body.medium.pointSize * win.widgetScale).weight(Font.Bold).build()
                            }
                            StyledText {
                                Layout.alignment: Qt.AlignRight
                                text: modelData.detail
                                color: modelData.label === "CPU" && Cpu.temperature > 90 ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant
                                font: Tokens.font.clock.size(Tokens.font.body.small.pointSize * 0.68 * win.widgetScale).build()
                                visible: text !== ""
                            }
                        }
                    }
                }
            }
        }
    }
}
