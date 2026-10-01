pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Caelestia.Config
import Caelestia.Services
import qs.services

Variants {
    model: Screens.screens.filter(s => s.name !== "CAELESTIA-WALLPAPER-PREVIEW" && GlobalConfig.forScreen(s.name).background.enabled)

    PanelWindow {
        id: win

        required property ShellScreen modelData
        property bool hasRecentAudio: false
        readonly property HyprlandMonitor monitor: Hyprland.monitorFor(modelData)
        readonly property bool centerOccluded: {
            const output = monitor?.lastIpcObject;
            const width = Number(output?.width ?? win.width);
            const height = Number(output?.height ?? win.height);
            const radius = Math.min(530, width * 0.45, height * 0.45) * 0.43;
            const centerX = Number(output?.x ?? 0) + width / 2;
            const centerY = Number(output?.y ?? 0) + height / 2;
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
                    const left = Number(at[0]);
                    const top = Number(at[1]);
                    const right = left + Number(size[0]);
                    const bottom = top + Number(size[1]);
                    const nearestX = Math.max(left, Math.min(centerX, right));
                    const nearestY = Math.max(top, Math.min(centerY, bottom));
                    const dx = centerX - nearestX;
                    const dy = centerY - nearestY;
                    if (dx * dx + dy * dy < radius * radius)
                        return true;
                }
            }
            return false;
        }
        readonly property bool shouldRender: hasRecentAudio && !centerOccluded
        readonly property bool keepSurface: shouldRender || hideSurfaceTimer.running

        onShouldRenderChanged: {
            if (shouldRender)
                hideSurfaceTimer.stop();
            else
                hideSurfaceTimer.restart();
        }

        function updateAudioActivity(): void {
            let peak = 0;
            for (let i = 0; i < GlobalConfig.services.visualiserBars; i++)
                peak = Math.max(peak, Audio.cava.values[i] ?? 0);

            if (peak > 0.035) {
                hasRecentAudio = true;
                idleTimer.restart();
            }
        }

        screen: modelData
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
        visible: keepSurface

        Timer {
            id: hideSurfaceTimer
            interval: 380
        }

        Timer {
            id: idleTimer
            interval: 1100
            onTriggered: win.hasRecentAudio = false
        }

        Connections {
            target: Audio.cava
            function onValuesChanged(): void {
                win.updateAudioActivity();
            }
        }

        Component.onCompleted: updateAudioActivity()

        ServiceRef {
            // Audio analysis is unnecessary while the center visualization is occluded.
            // Null releases this consumer's ref; other visible Cava consumers can keep it alive.
            service: win.centerOccluded ? null : Audio.cava
        }

        Item {
            id: visualizer

            anchors.centerIn: parent
            width: Math.min(530, parent.width * 0.45, parent.height * 0.45)
            height: width
            opacity: win.shouldRender

            readonly property int bandCount: Math.max(1, GlobalConfig.services.visualiserBars)
            readonly property real center: width / 2
            readonly property real innerRadius: width * 0.175
            readonly property real maxBarLength: width * 0.25
            readonly property real rotationSpeed: 0.5
            readonly property real bass: Audio.cava.values[Math.floor((bandCount - 1) * 0.05)] ?? 0
            readonly property real mid: Audio.cava.values[Math.floor((bandCount - 1) * 0.3)] ?? 0
            readonly property real highMid: Audio.cava.values[Math.floor((bandCount - 1) * 0.6)] ?? 0
            readonly property real treble: Audio.cava.values[Math.floor((bandCount - 1) * 0.9)] ?? 0

            Behavior on opacity {
                NumberAnimation {
                    duration: 360
                    easing.type: Easing.OutCubic
                }
            }

            Shape {
                anchors.fill: parent
                asynchronous: true
                preferredRendererType: Shape.CurveRenderer

                ShapePath {
                    fillColor: "transparent"
                    strokeColor: Qt.alpha(Colours.palette.m3secondary, 0.5 + Math.min(0.35, visualizer.bass * 0.35))
                    strokeWidth: 2 + Math.min(4, visualizer.bass * 4)

                    PathAngleArc {
                        centerX: visualizer.center
                        centerY: visualizer.center
                        radiusX: visualizer.innerRadius
                        radiusY: visualizer.innerRadius
                        startAngle: 0
                        sweepAngle: 360
                    }
                }
            }

            Item {
                id: rotatingBars
                anchors.fill: parent

                NumberAnimation on rotation {
                    from: 0
                    to: 360
                    // Fancy shader: theta + time * rotation_speed * 0.2.
                    duration: 2 * Math.PI / (visualizer.rotationSpeed * 0.2) * 1000
                    loops: Animation.Infinite
                    running: win.shouldRender
                }

                Shape {
                    anchors.fill: parent
                    asynchronous: true
                    preferredRendererType: Shape.CurveRenderer
                    data: radialBars.instances
                }

                Variants {
                    id: radialBars

                    model: Array.from({
                        length: visualizer.bandCount
                    }, (_, i) => i)

                    ShapePath {
                        id: bar
                        required property int modelData

                        readonly property real value: Math.max(0, Math.min(1, Audio.cava.values[modelData] ?? 0))
                        readonly property real angle: modelData * 2 * Math.PI / visualizer.bandCount - Math.PI / 2
                        readonly property real distance: visualizer.innerRadius + visualizer.maxBarLength * value
                        readonly property real xDirection: Math.cos(angle)
                        readonly property real yDirection: Math.sin(angle)

                        fillColor: "transparent"
                        strokeColor: Qt.alpha(modelData % 2 ? Colours.palette.m3secondary : Colours.palette.m3primary, 0.74 + value * 0.26)
                        strokeWidth: Math.max(3, 2 * Math.PI * visualizer.innerRadius / visualizer.bandCount * 0.5)
                        capStyle: ShapePath.RoundCap

                        startX: visualizer.center + visualizer.innerRadius * xDirection
                        startY: visualizer.center + visualizer.innerRadius * yDirection

                        PathLine {
                            x: visualizer.center + bar.distance * bar.xDirection
                            y: visualizer.center + bar.distance * bar.yDirection
                        }
                    }
                }
            }

            Item {
                id: rotatingGridRing
                anchors.fill: parent

                NumberAnimation on rotation {
                    from: 0
                    to: 360
                    // Fancy shader grid: theta + time * rotation_speed.
                    duration: 2 * Math.PI / visualizer.rotationSpeed * 1000
                    loops: Animation.Infinite
                    running: win.shouldRender
                }

                Shape {
                    anchors.fill: parent
                    asynchronous: true
                    preferredRendererType: Shape.CurveRenderer
                    data: gridSegments.instances
                }

                Variants {
                    id: gridSegments

                    model: Array.from({
                        length: 32
                    }, (_, i) => i)

                    ShapePath {
                        required property int modelData

                        fillColor: "transparent"
                        strokeColor: Qt.alpha(Colours.palette.m3primary, 0.42 + Math.min(0.2, visualizer.mid * 0.25))
                        strokeWidth: 2
                        capStyle: ShapePath.RoundCap

                        PathAngleArc {
                            centerX: visualizer.center
                            centerY: visualizer.center
                            radiusX: visualizer.innerRadius * 0.85
                            radiusY: visualizer.innerRadius * 0.85
                            startAngle: modelData * 11.25
                            sweepAngle: 5.1
                        }
                    }
                }
            }

            Item {
                id: rotatingEnergyRing
                anchors.fill: parent

                NumberAnimation on rotation {
                    from: 0
                    to: 360
                    // Fancy shader energy segments: theta * 8 + time.
                    duration: 2 * Math.PI * 8 * 1000
                    loops: Animation.Infinite
                    running: win.shouldRender
                }

                Shape {
                    anchors.fill: parent
                    asynchronous: true
                    preferredRendererType: Shape.CurveRenderer
                    data: energySegments.instances
                }

                Variants {
                    id: energySegments

                    model: Array.from({
                        length: 8
                    }, (_, i) => i)

                    ShapePath {
                        required property int modelData

                        fillColor: "transparent"
                        strokeColor: Qt.alpha(Colours.palette.m3secondary, Math.max(0.3, Math.min(1, visualizer.highMid * 2)))
                        strokeWidth: 2 + Math.min(3, visualizer.highMid)
                        capStyle: ShapePath.RoundCap

                        PathAngleArc {
                            centerX: visualizer.center
                            centerY: visualizer.center
                            radiusX: visualizer.innerRadius * 0.65
                            radiusY: visualizer.innerRadius * 0.65
                            startAngle: modelData * 45
                            sweepAngle: 27
                        }
                    }
                }
            }

            Item {
                id: rotatingParticles
                anchors.fill: parent

                NumberAnimation on rotation {
                    from: 0
                    to: 360
                    duration: 2 * Math.PI / visualizer.rotationSpeed * 1000
                    loops: Animation.Infinite
                    running: win.shouldRender
                }

                Repeater {
                    model: 16

                    delegate: Rectangle {
                        required property int index

                        readonly property real angle: index * 2 * Math.PI / 16
                        readonly property real orbitRadius: visualizer.innerRadius * 0.75

                        width: 3 + Math.min(2, visualizer.treble * 1.5)
                        height: width
                        radius: width / 2
                        x: visualizer.center + orbitRadius * Math.cos(angle) - width / 2
                        y: visualizer.center + orbitRadius * Math.sin(angle) - height / 2
                        color: Qt.alpha(Colours.palette.m3secondary, 0.5 + Math.min(0.5, visualizer.treble * 0.5))
                    }
                }
            }
        }
    }
}
