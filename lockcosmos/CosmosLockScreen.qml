pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Shapes
import Quickshell
import Quickshell.Services.Notifications
import Caelestia
import Caelestia.Config
import Caelestia.Services
import Caelestia.Services
import Quickshell.Services.UPower
import qs.components
import qs.modules.lock
import qs.services
import qs.utils

Item {
    id: root

    required property var lock
    required property var pam
    property bool previewOnly: false
    property bool safePreview: false

    readonly property real scaleFactor: Math.max(0.72, Math.min(1.45, Math.min(width / 1920, height / 1080)))
    readonly property real edge: 58 * scaleFactor
    readonly property real clockY: height * 0.34
    readonly property color star: "#eef3ff"
    readonly property color dim: Qt.rgba(0.85, 0.9, 1, 0.58)
    readonly property color accent: Colours.palette.m3primary
    readonly property color accentTwo: Colours.palette.m3tertiary
    property date now: new Date()
    property int lockSeconds: 0
    property real animationTime: 0
    property real pulse: 0
    property real errorFlash: 0

    focus: !root.previewOnly
    // The session-lock surface can take a frame to acquire keyboard focus.
    // Keep this item as the key target while locked, as the stock password
    // input does, so PAM.handleKey continues receiving password keystrokes.
    onActiveFocusChanged: {
        if (!activeFocus && !root.previewOnly && root.lock.locked)
            Qt.callLater(() => root.forceActiveFocus());
    }
    Keys.onPressed: event => {
        if (root.lock.unlocking) {
            event.accepted = true;
            return;
        }
        if (!root.previewOnly)
            root.pam.handleKey(event);
        event.accepted = true;
    }
    Component.onCompleted: if (!root.previewOnly) Qt.callLater(() => root.forceActiveFocus())

    // Keep the animated shader on its own 30 Hz clock. lockSeconds is only
    // for the human-readable HUD and must not quantize the starfield to 1 Hz.
    Timer {
        interval: 33
        repeat: true
        running: true
        onTriggered: root.animationTime += interval / 1000
    }

    Timer {
        interval: 1000
        repeat: true
        running: true
        onTriggered: {
            root.now = new Date();
            root.lockSeconds += 1;
        }
    }

    ServiceRef { service: Cpu }
    ServiceRef { service: Memory }
    ServiceRef { service: Storage }

    NumberAnimation on pulse {
        running: root.pam.passwd.active
        from: 0
        to: 1
        duration: 900
        loops: Animation.Infinite
    }

    Connections {
        target: root.pam
        function onFlashMsg(): void { errorAnim.restart(); }
    }
    NumberAnimation {
        id: errorAnim
        target: root
        property: "errorFlash"
        from: 0
        to: 1
        duration: 220
        onFinished: reverse.start()
    }
    NumberAnimation {
        id: reverse
        target: root
        property: "errorFlash"
        to: 0
        duration: 320
    }

    ShaderEffect {
        anchors.fill: parent
        property real itemWidth: width
        property real itemHeight: height
        property real time: root.animationTime
        layer.enabled: true
        layer.smooth: true
        layer.textureSize: Qt.size(Math.max(1, Math.round(width * 0.75)), Math.max(1, Math.round(height * 0.75)))
        property real nebula: 1
        property color baseColor: "#03050b"
        property color tintA: root.accent
        property color tintB: root.accentTwo
        fragmentShader: Qt.resolvedUrl("shaders/lock_space.frag.qsb")
    }

    Rectangle {
        anchors.fill: parent
        color: "#03050b"
        opacity: 0.26
    }

    // Top-left Astral identity and elapsed lock session.
    Column {
        x: root.edge
        y: 40 * root.scaleFactor
        spacing: 5 * root.scaleFactor
        Text {
            text: "ASTRAL"
            font.family: "ESPACION"
            font.pixelSize: 24 * root.scaleFactor
            font.letterSpacing: 9 * root.scaleFactor
            color: root.star
        }
        Text {
            text: "COORDINATES LOCKED  ·  ORBIT HELD"
            font.family: "Adwaita Sans"
            font.pixelSize: 11 * root.scaleFactor
            font.letterSpacing: 2.5 * root.scaleFactor
            color: root.dim
        }
        Text {
            readonly property int seconds: root.lockSeconds
            text: "T+ " + String(Math.floor(seconds / 3600)).padStart(2, "0") + ":" + String(Math.floor(seconds / 60) % 60).padStart(2, "0") + ":" + String(seconds % 60).padStart(2, "0")
            font.family: "ESPACION"
            font.pixelSize: 18 * root.scaleFactor
            color: root.accent
        }
    }

    // Top-right hardware state and Caps Lock.
    Column {
        anchors.right: parent.right
        anchors.rightMargin: root.edge
        y: 42 * root.scaleFactor
        spacing: 9 * root.scaleFactor
        Text {
            anchors.right: parent.right
            text: "POWER  " + Math.round(UPower.displayDevice.percentage * 100) + "%"
                + (UPower.onBattery ? "" : "  ·  CHARGING")
            font.family: "Adwaita Sans"
            font.pixelSize: 12 * root.scaleFactor
            font.letterSpacing: 2 * root.scaleFactor
            color: UPower.onBattery && UPower.displayDevice.percentage <= 0.2 ? "#ff8a80" : root.dim
        }
        Rectangle {
            anchors.right: parent.right
            width: 170 * root.scaleFactor
            height: 2 * root.scaleFactor
            color: Qt.rgba(1, 1, 1, 0.18)
            Rectangle {
                width: parent.width * Math.max(0, Math.min(1, UPower.displayDevice.percentage))
                height: parent.height
                color: root.accent
            }
        }
        Text {
            anchors.right: parent.right
            visible: Hypr.capsLock
            text: "CAPS LOCK IS ON"
            font.family: "Adwaita Sans"
            font.pixelSize: 11 * root.scaleFactor
            font.letterSpacing: 2 * root.scaleFactor
            color: "#ff8a80"
        }
    }

    // Central clock and orbit.
    Item {
        id: orbit
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.clockY - height / 2
        width: 720 * root.scaleFactor
        height: 250 * root.scaleFactor
        rotation: -10
        readonly property real angle: (root.now.getSeconds() / 60) * 2 * Math.PI - Math.PI / 2

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: "transparent"
                strokeColor: Qt.rgba(1, 1, 1, 0.17)
                strokeWidth: 1 * root.scaleFactor
                PathAngleArc {
                    centerX: orbit.width / 2
                    centerY: orbit.height / 2
                    radiusX: orbit.width / 2
                    radiusY: orbit.height / 2
                    startAngle: 0
                    sweepAngle: 360
                }
            }
        }
        Rectangle {
            width: 20 * root.scaleFactor
            height: width
            radius: width / 2
            x: orbit.width / 2 + Math.cos(orbit.angle) * orbit.width / 2 - width / 2
            y: orbit.height / 2 + Math.sin(orbit.angle) * orbit.height / 2 - height / 2
            color: Qt.alpha(root.accent, 0.34)
            Rectangle {
                anchors.centerIn: parent
                width: 7 * root.scaleFactor
                height: width
                radius: width / 2
                color: root.accent
            }
        }
    }

    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.clockY - clockText.height / 2
        spacing: 4 * root.scaleFactor
        Text {
            id: clockText
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatTime(root.now, "hh:mm")
            font.family: "ESPACION"
            font.pixelSize: 148 * root.scaleFactor
            color: root.star
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDate(root.now, "dddd  ·  d MMMM").toUpperCase()
            font.family: "Adwaita Sans"
            font.pixelSize: 14 * root.scaleFactor
            font.letterSpacing: 5 * root.scaleFactor
            color: root.dim
        }
    }

    CosmosConstellation {
        id: constellation
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.height * 0.535
        width: Math.min(root.width * 0.64, 1100 * root.scaleFactor)
        height: 105 * root.scaleFactor
        passcode: root.pam.buffer
        scaleFactor: root.scaleFactor
        starColor: root.star
        hasError: root.errorFlash > 0
        pulse: root.pulse
        transform: Translate { x: root.errorFlash > 0 ? Math.sin(root.errorFlash * Math.PI * 8) * 8 * root.scaleFactor : 0 }
    }

    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        y: constellation.y + constellation.height + 12 * root.scaleFactor
        spacing: 8 * root.scaleFactor
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.pam.state === Pam.MaxTries ? ""
                : root.pam.passwd.active || root.pam.howdy.active ? "VERIFYING IDENTITY"
                : root.pam.state === Pam.Failed || root.pam.fprint.state === Pam.Failed || root.pam.howdy.state === Pam.Failed ? "SIGNAL LOST  ·  TRY AGAIN"
                : root.pam.buffer.length > 0 ? "CHARTING  ·  " + root.pam.buffer.length + (root.pam.buffer.length === 1 ? " STAR" : " STARS")
                : "CHART YOUR CONSTELLATION"
            font.family: "ESPACION"
            font.pixelSize: 15 * root.scaleFactor
            font.letterSpacing: 4 * root.scaleFactor
            color: root.errorFlash > 0 ? "#ff8a80" : root.star
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.pam.state === Pam.MaxTries ? ""
                : root.statusMessage || (Hypr.kbLayout !== Hypr.defaultKbLayout ? "KEYBOARD  ·  " + Hypr.kbLayoutFull.toUpperCase() : "TYPE YOUR PASSPHRASE  ·  ENTER TO UNLOCK")
            font.family: "Adwaita Sans"
            font.pixelSize: 12 * root.scaleFactor
            font.letterSpacing: 1.2 * root.scaleFactor
            color: root.errorFlash > 0 ? "#ff8a80" : root.dim
        }
    }

    readonly property string statusMessage: {
        if (root.pam.state === Pam.MaxTries)
            return "";
        if (root.pam.lockMessage)
            return root.pam.lockMessage;
        if (root.pam.fprint.state === Pam.Error)
            return "FINGERPRINT ERROR  ·  " + root.pam.fprint.message;
        if (root.pam.howdy.state === Pam.Error)
            return "FACE AUTHENTICATION ERROR  ·  " + root.pam.howdy.message;
        if (root.pam.state === Pam.Error)
            return root.pam.passwd.message;
        if (root.pam.fprint.state === Pam.Failed)
            return "FINGERPRINT NOT RECOGNISED  ·  " + root.pam.fprint.tries + "/" + GlobalConfig.lock.maxFprintTries;
        if (root.pam.howdy.state === Pam.Failed)
            return "FACE NOT RECOGNISED  ·  " + root.pam.howdy.tries + "/" + GlobalConfig.lock.maxHowdyTries;
        if (root.pam.state === Pam.Failed)
            return "INCORRECT PASSPHRASE  ·  TRY AGAIN";
        if (Hypr.capsLock)
            return "CAPS LOCK IS ON";
        return "";
    }

    // Compact translucent HUD panels replace the stock Material lock widgets.
    component HudPanel: Rectangle {
        color: Qt.rgba(0.015, 0.025, 0.06, 0.30)
        radius: 10 * root.scaleFactor
        border.width: 1
        border.color: Qt.alpha(root.accent, 0.28)
    }
    component HudLabel: Text {
        font.family: "ESPACION"
        font.pixelSize: 10 * root.scaleFactor
        font.letterSpacing: 2 * root.scaleFactor
        color: root.accent
    }

    Column {
        x: root.edge
        y: root.height * 0.415
        width: Math.min(350 * root.scaleFactor, root.width * 0.19)
        spacing: 12 * root.scaleFactor

        HudPanel {
            width: parent.width
            height: 145 * root.scaleFactor
            Column {
                anchors.fill: parent
                anchors.margins: 15 * root.scaleFactor
                spacing: 5 * root.scaleFactor
                HudLabel { text: "LOCAL CONDITIONS" }
                Row {
                    width: parent.width
                    spacing: 9 * root.scaleFactor
                    MaterialIcon {
                        text: Weather.icon
                        color: root.accentTwo
                        fontStyle: Tokens.font.headline.builders.large.scale(1.35).build()
                    }
                    Text {
                        text: Weather.temp
                        font.family: "ESPACION"
                        font.pixelSize: 34 * root.scaleFactor
                        color: root.star
                    }
                    Text {
                        y: parent.height - height - 4 * root.scaleFactor
                        text: Weather.city || Weather.resolvedCityName || "WEATHER"
                        font.pixelSize: 11 * root.scaleFactor
                        color: root.dim
                        elide: Text.ElideRight
                        width: parent.width - 130 * root.scaleFactor
                    }
                }
                Text {
                    width: parent.width
                    text: Weather.description + "   ·   " + Weather.feelsLike
                    font.pixelSize: 11 * root.scaleFactor
                    color: root.dim
                    elide: Text.ElideRight
                }
                Rectangle { width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.12) }
                Text {
                    width: parent.width
                    text: {
                        const today = Weather.forecast[0];
                        return "HIGH " + Weather.formatTemp(today?.maxTempC) + "    /    LOW " + Weather.formatTemp(today?.minTempC);
                    }
                    font.family: "ESPACION"
                    font.pixelSize: 9 * root.scaleFactor
                    font.letterSpacing: 1.2 * root.scaleFactor
                    color: root.dim
                }
            }
        }

        HudPanel {
            width: parent.width
            height: 126 * root.scaleFactor
            Column {
                anchors.fill: parent
                anchors.margins: 15 * root.scaleFactor
                spacing: 7 * root.scaleFactor
                HudLabel { text: "SYSTEM TELEMETRY" }
                Repeater {
                    model: [
                        { name: "CPU", value: Cpu.percentage, detail: "" },
                        { name: "MEMORY", value: Memory.percentage, detail: "" },
                        { name: "STORAGE", value: Storage.percentage, detail: "" }
                    ]
                    delegate: Row {
                        required property var modelData
                        width: parent.width
                        height: 14 * root.scaleFactor
                        spacing: 7 * root.scaleFactor
                        Text {
                            width: 51 * root.scaleFactor
                            text: modelData.name
                            font.family: "ESPACION"
                            font.pixelSize: 8 * root.scaleFactor
                            font.letterSpacing: 0.8 * root.scaleFactor
                            color: root.dim
                        }
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 112 * root.scaleFactor
                            height: 2 * root.scaleFactor
                            color: Qt.rgba(1, 1, 1, 0.16)
                            Rectangle {
                                width: parent.width * Math.max(0, Math.min(1, modelData.value))
                                height: parent.height
                                color: root.accent
                            }
                        }
                        Text {
                            width: 42 * root.scaleFactor
                            text: Math.round(modelData.value * 100) + "%"
                            horizontalAlignment: Text.AlignRight
                            font.family: "ESPACION"
                            font.pixelSize: 9 * root.scaleFactor
                            color: root.star
                        }
                        Text {
                            width: 34 * root.scaleFactor
                            text: modelData.detail
                            horizontalAlignment: Text.AlignRight
                            font.pixelSize: 8 * root.scaleFactor
                            color: root.dim
                        }
                    }
                }
            }
        }

        HudPanel {
            width: parent.width
            height: 98 * root.scaleFactor
            Column {
                anchors.fill: parent
                anchors.margins: 15 * root.scaleFactor
                spacing: 6 * root.scaleFactor
                HudLabel { text: "SESSION / " + SysInfo.osName.toUpperCase() }
                Text {
                    width: parent.width
                    text: "USER  " + SysInfo.user + "    ·    " + SysInfo.wm
                    font.pixelSize: 10 * root.scaleFactor
                    color: root.star
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    text: "UPTIME  " + SysInfo.uptimeShort + (UPower.displayDevice.isLaptopBattery ? "    ·    BATTERY " + Math.round(UPower.displayDevice.percentage * 100) + "%" : "")
                    font.pixelSize: 9 * root.scaleFactor
                    color: root.dim
                    elide: Text.ElideRight
                }
            }
        }
    }

    HudPanel {
        anchors.right: parent.right
        anchors.rightMargin: root.edge
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 150 * root.scaleFactor
        width: Math.min(390 * root.scaleFactor, root.width * 0.22)
        height: Math.min(260 * root.scaleFactor, root.height * 0.2)
        Column {
            anchors.fill: parent
            anchors.margins: 16 * root.scaleFactor
            spacing: 8 * root.scaleFactor
            Row {
                width: parent.width
                HudLabel { text: Config.lock.hideNotifs ? "SECURE CHANNEL" : "INCOMING SIGNALS" }
                Text {
                    width: 30 * root.scaleFactor
                    horizontalAlignment: Text.AlignRight
                    text: Config.lock.hideNotifs ? "•••" : String(Notifs.notClosed.length).padStart(2, "0")
                    font.family: "ESPACION"
                    font.pixelSize: 10 * root.scaleFactor
                    color: root.dim
                }
            }
            Rectangle { width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.12) }
            Item {
                width: parent.width
                height: parent.height - 38 * root.scaleFactor
                Text {
                    anchors.centerIn: parent
                    visible: Config.lock.hideNotifs || Notifs.notClosed.length === 0
                    text: Config.lock.hideNotifs ? "UNLOCK TO DECRYPT" : "NO ACTIVE SIGNALS"
                    font.family: "ESPACION"
                    font.pixelSize: 9 * root.scaleFactor
                    font.letterSpacing: 1.4 * root.scaleFactor
                    color: root.dim
                }
                Column {
                    anchors.fill: parent
                    spacing: 9 * root.scaleFactor
                    visible: !Config.lock.hideNotifs
                    Repeater {
                        model: Notifs.notClosed.slice(0, 3)
                        delegate: Column {
                            required property var modelData
                            width: parent.width
                            spacing: 3 * root.scaleFactor
                            Row {
                                width: parent.width
                                Text {
                                    width: parent.width - 38 * root.scaleFactor
                                    text: modelData.appName
                                    font.family: "ESPACION"
                                    font.pixelSize: 8 * root.scaleFactor
                                    font.letterSpacing: 0.8 * root.scaleFactor
                                    color: modelData.urgency === NotificationUrgency.Critical ? "#ff8a80" : root.accentTwo
                                    elide: Text.ElideRight
                                }
                                Text {
                                    width: 31 * root.scaleFactor
                                    horizontalAlignment: Text.AlignRight
                                    text: modelData.timeStr
                                    font.pixelSize: 8 * root.scaleFactor
                                    color: root.dim
                                }
                            }
                            Text {
                                width: parent.width
                                text: modelData.summary + (modelData.body ? "  ·  " + modelData.body : "")
                                font.pixelSize: 10 * root.scaleFactor
                                color: root.star
                                elide: Text.ElideRight
                                maximumLineCount: 1
                            }
                        }
                    }
                }
            }
        }
    }

    // User identity, media and session controls along the bottom edge.
    Row {
        x: root.edge
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 38 * root.scaleFactor
        spacing: 16 * root.scaleFactor
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "◉"
            font.pixelSize: 42 * root.scaleFactor
            color: root.accent
        }
        Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4 * root.scaleFactor
            Text {
                text: Quickshell.env("USER").toUpperCase()
                font.family: "ESPACION"
                font.pixelSize: 17 * root.scaleFactor
                font.letterSpacing: 3 * root.scaleFactor
                color: root.star
            }
            Text {
                text: "SYSTEM ACCESS  ·  " + (root.pam.fprint.canAttempt ? "FINGERPRINT READY" : root.pam.howdy.canAttempt ? "FACE AUTH READY" : "PASSPHRASE")
                font.family: "Adwaita Sans"
                font.pixelSize: 10 * root.scaleFactor
                font.letterSpacing: 1.5 * root.scaleFactor
                color: root.dim
            }
        }
    }

    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 48 * root.scaleFactor
        spacing: 14 * root.scaleFactor
        visible: !root.previewOnly && !root.safePreview && Players.active !== null
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "TRANSMISSION"
            font.pixelSize: 10 * root.scaleFactor
            font.letterSpacing: 2 * root.scaleFactor
            color: root.accent
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: Players.active?.trackTitle ?? ""
            width: Math.min(340 * root.scaleFactor, root.width * 0.2)
            elide: Text.ElideRight
            font.pixelSize: 12 * root.scaleFactor
            color: root.star
        }
        Repeater {
            model: ["previous", "playPause", "next"]
            delegate: Text {
                required property int index
                anchors.verticalCenter: parent.verticalCenter
                readonly property var player: Players.active
                text: ["◀", player?.isPlaying ? "Ⅱ" : "▶", "▶|"][index]
                color: root.star
                font.pixelSize: 15 * root.scaleFactor
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -6
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (index === 0) player?.previous();
                        else if (index === 1) player?.togglePlaying();
                        else player?.next();
                    }
                }
            }
        }
    }

    Row {
        anchors.right: parent.right
        anchors.rightMargin: root.edge
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 35 * root.scaleFactor
        spacing: 12 * root.scaleFactor
        visible: !root.previewOnly && !root.safePreview
        Repeater {
            model: [
                { label: "SUSPEND", command: Config.session.commands.hibernate },
                { label: "REBOOT", command: Config.session.commands.reboot },
                { label: "POWER OFF", command: Config.session.commands.shutdown }
            ]
            delegate: Rectangle {
                id: action
                required property var modelData
                width: 48 * root.scaleFactor
                height: width
                radius: width / 2
                color: mouse.containsMouse ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.06)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.24)
                Text {
                    anchors.centerIn: parent
                    text: action.modelData.label === "SUSPEND" ? "☾" : action.modelData.label === "REBOOT" ? "↻" : "⏻"
                    color: root.star
                    font.pixelSize: 19 * root.scaleFactor
                }
                MouseArea {
                    id: mouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    pressAndHoldInterval: 1100
                    onPressAndHold: {
                        if (!SessionManager.exec(action.modelData.command))
                            Quickshell.execDetached(action.modelData.command);
                    }
                    onClicked: root.forceActiveFocus()
                }
                ToolTip.visible: mouse.containsMouse
                ToolTip.text: action.modelData.label + "  ·  HOLD"
                ToolTip.delay: 500
            }
        }
    }
}
