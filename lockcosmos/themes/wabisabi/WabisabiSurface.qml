pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import qs.lockcosmos
import qs.lockcosmos.services as Services
import qs.services as CaelestiaServices
import qs.desktoptodo

// "Ensō" theme: wabi-sabi, the beauty of the imperfect and the passing.
//
// Lock-in: the desktop yellows like an old print along an uneven front, a
// tea stain gathers at its edge, and it fades into washi paper with your
// wallpaper printed on it faintly in sumi, the things of the season drifting
// down. The passcode is an ensō: each keystroke carries the brush further
// round the circle (every lock's circle is a little different). A wrong one
// sends the ink briefly back along its path; a lockout closes the gate.
// Coming home completes the circle and the desktop comes back out of paper.
//
// Theme contract (see ThemeHost): ctx, shot, shown, still, minScale.
Item {
    id: sabi

    required property var ctx
    property url shot
    property bool shown: true
    property bool still: false
    property bool previewOnly: false
    property real minScale: 0.7

    readonly property real sc: Math.max(minScale, Math.min(2, Math.min(width / 1920, height / 1080)))
    readonly property real edge: 64 * sc
    readonly property point center: Qt.point(width * 0.4, height * 0.45)

    // Choreography.
    property real age: 0
    property real uiIn: 0
    property real ghostIn: 0
    property real gold: 0
    property real bleed: 0
    property real denialTrail: 0
    property real denialRetreat: 0
    property bool denialVisible: false
    property color strokeInk: Wabi.sumi
    property real inkOpacity: 1
    property real lockoutPulse: 0.42
    property real lockoutSweep: 0
    property bool lockoutInkActive: false

    // Where the brush has got to: a little further per keystroke, back to
    // the start when a passcode is rejected, sealed shut when PAM locks input.
    readonly property int progressCells: ctx.phase === "verifying"
        ? Math.max(ctx.cells, ctx.submittedCells) : ctx.cells
    readonly property bool lockoutActive: ctx.lockedOut && !granted
    readonly property real target: granted ? 1
        : still ? 0.7 : Math.min(0.9, progressCells * 0.055)
    property real sweep: target
    // Both failure types hold the submitted stroke through two blinks; then
    // ordinary failure retreats, while PAM lockout continues to a full ring.
    readonly property real displayedSweep: lockoutInkActive ? lockoutSweep
        : denialVisible ? denialTrail * (1 - denialRetreat) : sweep
    Behavior on sweep {
        NumberAnimation {
            duration: sabi.granted ? 650 : 240
            easing.type: Easing.OutCubic
        }
    }
    Behavior on strokeInk {
        ColorAnimation { duration: 180; easing.type: Easing.OutCubic }
    }

    readonly property bool granted: ctx.phase === "granted" || ctx.phase === "exiting"
    property var seasonalInfo: Wabi.solarInfo(ctx.now)
    readonly property string solarDateKey: Qt.formatDate(ctx.now, "yyyy-MM-dd")
    readonly property int calendarYear: ctx.now.getFullYear()
    readonly property int calendarMonth: ctx.now.getMonth()
    readonly property int calendarDay: ctx.now.getDate()
    readonly property list<string> chineseDigits: ["〇", "一", "二", "三", "四", "五", "六", "七", "八", "九"]
    readonly property string calendarChineseYear: String(calendarYear).split("").map(digit => chineseDigits[Number(digit)]).join("")
    readonly property string calendarChineseMonth: chineseNumber(calendarMonth + 1)
    readonly property string calendarChineseDay: chineseNumber(calendarDay)
    readonly property string todayWeekday: ["日", "一", "二", "三", "四", "五", "六"][ctx.now.getDay()]
    readonly property int monthStartOffset: (new Date(calendarYear, calendarMonth, 1).getDay() + 6) % 7
    readonly property int monthDayCount: new Date(calendarYear, calendarMonth + 1, 0).getDate()
    readonly property int calendarCell: 28 * sc
    readonly property list<string> weekdays: ["一", "二", "三", "四", "五", "六", "日"]
    readonly property bool hasPendingTodoToday: {
        const revision = TodoData.revision;
        return TodoData.loaded && TodoData.tasks.some(task => task.date === solarDateKey && !task.done);
    }

    function chineseNumber(value) {
        if (value <= 10)
            return value === 10 ? "十" : chineseDigits[value];
        if (value < 20)
            return "十" + chineseDigits[value % 10];
        if (value < 30)
            return "二十" + (value % 10 ? chineseDigits[value % 10] : "");
        return "三十" + (value % 10 ? chineseDigits[value % 10] : "");
    }

    function startLockoutFill() {
        if (!lockoutActive || lockoutInkActive)
            return;

        denialSettle.stop();
        denialRetreatFx.stop();
        lockoutFallback.stop();
        strokeInk = Wabi.shu;
        inkOpacity = 1;

        // PAM clears its buffer on failure. Keep the submitted length as the
        // starting point so lockout continues the rejected stroke forward.
        const submitted = Math.max(ctx.deniedCells, ctx.submittedCells);
        lockoutSweep = Math.max(denialVisible ? denialTrail : sweep, Math.min(0.9, submitted * 0.055));
        lockoutInkActive = true;
        denialVisible = false;
        denialRetreat = 0;
        lockoutFx.restart();
    }

    onSolarDateKeyChanged: seasonalInfo = Wabi.solarInfo(ctx.now)

    Component {
        id: calendarDateBrush
        Shape {
            id: dateBrushShape
            anchors.fill: parent
            antialiasing: true
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: "transparent"
                strokeColor: Wabi.shu
                strokeWidth: 1.6 * sabi.sc
                capStyle: ShapePath.RoundCap
                startX: 0.746 * dateBrushShape.width
                startY: 0.852 * dateBrushShape.height
                PathArc {
                    x: 0.852 * dateBrushShape.width
                    y: 0.746 * dateBrushShape.height
                    radiusX: 0.43 * dateBrushShape.width
                    radiusY: 0.43 * dateBrushShape.height
                    useLargeArc: true
                    direction: PathArc.Clockwise
                }
            }
        }
    }

    Component.onCompleted: {
        if (lockoutActive) {
            strokeInk = Wabi.shu;
            lockoutSweep = 1;
            lockoutInkActive = true;
        }
        if (still) {
            age = 1;
            uiIn = 1;
            ghostIn = 1;
        } else if (shown) {
            startIntro();
        } else {
            introFallback.start();
        }
    }

    onShownChanged: if (shown && !still) startIntro()

    property bool _introStarted: false

    function startIntro() {
        if (_introStarted)
            return;
        _introStarted = true;
        introFallback.stop();
        intro.start();
    }

    Timer {
        id: introFallback
        interval: 500
        onTriggered: sabi.startIntro()
    }

    Connections {
        target: sabi.ctx

        function onPhaseChanged() {
            if (sabi.ctx.phase === "exiting") {
                intro.stop();
                outro.start();
            }
        }

        function onDenied(costLife) {
            if (denialSettle.running || sabi.denialVisible || deniedFx.running || denialRetreatFx.running || sabi.lockoutInkActive)
                return;
            lockoutFallback.stop();
            // Show the rejected stroke in vermilion immediately. PAM may emit
            // the lockout state shortly after denied(), so keep this arc fixed
            // while the red stroke holds briefly and the PAM state settles.
            const submitted = Math.max(sabi.ctx.deniedCells, sabi.ctx.submittedCells);
            sabi.denialTrail = Math.max(sabi.sweep, Math.min(0.9, submitted * 0.055));
            sabi.denialRetreat = 0;
            sabi.denialVisible = sabi.denialTrail > 0.02;
            sabi.strokeInk = Wabi.shu;
            sabi.inkOpacity = 1;
            denialSettle.restart();
        }

        function onTyped(index) {
            if (sabi.lockoutActive)
                return;
            denialSettle.stop();
            deniedFx.stop();
            denialRetreatFx.stop();
            sabi.denialVisible = false;
            sabi.denialRetreat = 0;
            sabi.strokeInk = Wabi.sumi;
            sabi.inkOpacity = 1;
        }

        function onLockedOutChanged() {
            if (sabi.lockoutActive) {
                lockoutFallback.restart();
            } else {
                lockoutFallback.stop();
                denialSettle.stop();
                deniedFx.stop();
                denialRetreatFx.stop();
                lockoutFx.stop();
                sabi.lockoutInkActive = false;
                sabi.denialVisible = false;
                sabi.denialRetreat = 0;
                sabi.lockoutSweep = 0;
                sabi.strokeInk = Wabi.sumi;
                sabi.inkOpacity = 1;
                sabi.lockoutPulse = 0.42;
            }
        }

        function onGranted() {
            grantFx.restart();
        }
    }

    SequentialAnimation on bleed {
        running: sabi.ctx.phase === "verifying"
        loops: Animation.Infinite
        onRunningChanged: if (!running) sabi.bleed = 0
        NumberAnimation { from: 0; to: 1; duration: 520; easing.type: Easing.OutQuad }
        NumberAnimation { to: 0.3; duration: 520; easing.type: Easing.InOutQuad }
    }

    Timer {
        id: denialSettle
        interval: 40
        onTriggered: {
            const submitted = Math.max(sabi.ctx.deniedCells, sabi.ctx.submittedCells);
            sabi.denialTrail = Math.max(sabi.denialTrail, sabi.sweep, Math.min(0.9, submitted * 0.055));
            sabi.denialRetreat = 0;
            sabi.denialVisible = sabi.denialTrail > 0.02;
            deniedFx.restart();
        }
    }

    Timer {
        id: lockoutFallback
        interval: 180
        onTriggered: {
            if (sabi.lockoutActive && !sabi.lockoutInkActive && !deniedFx.running && !sabi.denialVisible)
                sabi.startLockoutFill();
        }
    }

    // ── Paper ────────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        color: Wabi.paper
    }

    Item {
        width: 0
        height: 0
        clip: true

        Image {
            id: wallpaper
            width: sabi.width
            height: sabi.height
            source: sabi.shot
            sourceSize: Qt.size(Math.max(1, sabi.width), Math.max(1, sabi.height))
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: false
        }
    }

    ShaderEffect {
        anchors.fill: parent
        visible: wallpaper.status === Image.Ready

        property variant wall: wallpaper
        property real itemWidth: width
        property real itemHeight: height
        property real time: sabi.ctx.ambientTime
        property real season: Wabi.season(sabi.ctx.now)
        property real inkPrint: 0.34
        property color paperColor: Wabi.paper
        property color inkColor: Wabi.sumi
        property color ageColor: "#9c7a52"

        fragmentShader: Qt.resolvedUrl("../../shaders/lock_washi.frag.qsb")
    }

    LockInput {
        ctx: sabi.ctx
        active: !sabi.still && (!sabi.previewOnly || sabi.shown)
        onEscapePressed: {
            if (sabi.previewOnly && sabi.shown) sabi.ctx.previewEscape();
            else sabi.ctx.clearInput();
        }
    }

    // ── The painting ─────────────────────────────────────────────────
    component Ink: Text {
        font.family: Wabi.serif
        font.pixelSize: 16 * sabi.sc
        color: Wabi.sumi
    }

    Item {
        id: painting
        anchors.fill: parent
        Enso {
            id: circle
            x: sabi.center.x - width / 2
            y: sabi.center.y - height / 2
            width: 560 * sabi.sc
            height: width
            sweep: sabi.displayedSweep
            ghost: sabi.denialVisible || sabi.lockoutInkActive ? 0 : sabi.ghostIn
            bleed: sabi.lockoutInkActive ? sabi.lockoutPulse : sabi.bleed
            thickness: 0.15
            seed: (sabi.ctx.lockedAt % 1000) / 97
            gold: sabi.gold
            inkColor: sabi.strokeInk
            goldColor: Wabi.gold
            opacity: sabi.inkOpacity
        }

        // The time, inside the circle.
        Column {
            anchors.horizontalCenter: circle.horizontalCenter
            anchors.verticalCenter: circle.verticalCenter
            spacing: 2 * sabi.sc
            opacity: sabi.uiIn

            Ink {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Qt.formatTime(sabi.ctx.now, "H:mm")
                font.weight: Font.Light
                font.pixelSize: 116 * sabi.sc
            }

            Ink {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Wabi.weekdays[sabi.ctx.now.getDay()]
                font.pixelSize: 16 * sabi.sc
                font.letterSpacing: 1 * sabi.sc
                color: Wabi.sumiSoft
            }

        }

        // Chinese civil date and solar terms calculated for that date.
        Column {
            id: inscription
            x: circle.x + circle.width + 30 * sabi.sc
            y: circle.y + 110 * sabi.sc
            spacing: 12 * sabi.sc
            opacity: sabi.uiIn

            Ink {
                text: Qt.formatDate(sabi.ctx.now, "yyyy年M月d日")
                font.pixelSize: 24 * sabi.sc
            }

            Ink {
                text: sabi.seasonalInfo.season + " · " + sabi.seasonalInfo.current.name
                font.pixelSize: 31 * sabi.sc
            }

            Ink {
                text: "始于 " + Qt.formatDate(sabi.seasonalInfo.current.date, "M月d日")
                font.pixelSize: 15 * sabi.sc
                color: Wabi.sumiSoft
            }

            Rectangle {
                width: 210 * sabi.sc
                height: 1 * sabi.sc
                color: Wabi.alpha(Wabi.sumi, 0.25)
            }

            Ink {
                text: "下个节气 · " + sabi.seasonalInfo.next.name
                font.pixelSize: 17 * sabi.sc
            }

            Ink {
                text: Qt.formatDate(sabi.seasonalInfo.next.date, "M月d日")
                    + " · " + (sabi.seasonalInfo.daysUntilNext === 0 ? "今日" : sabi.seasonalInfo.daysUntilNext + " 天后")
                font.pixelSize: 14 * sabi.sc
                color: Wabi.sumiSoft
            }
        }

        // Under the circle: what the brush is doing, or the welcome home.
        Item {
            id: prompt
            x: sabi.center.x - width / 2
            y: circle.y + circle.height + 6 * sabi.sc
            width: 760 * sabi.sc
            height: 120 * sabi.sc
            opacity: sabi.uiIn

            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 6 * sabi.sc
                visible: !sabi.granted

                Ink {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: sabi.previewOnly && sabi.shown
                        ? "预览：输入任意内容后按 Enter 模拟解锁"
                        : ""
                    visible: text.length > 0
                    font.pixelSize: (sabi.previewOnly && sabi.shown ? 14 : 15) * sabi.sc
                    color: Wabi.sumiSoft
                }

                Ink {
                    anchors.horizontalCenter: parent.horizontalCenter
                    readonly property var c: sabi.ctx
                    text: c.capsLock ? "大写锁定已开启" : ""
                    visible: text.length > 0
                    font.pixelSize: 15 * sabi.sc
                    color: Wabi.shu
                }
            }

            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 6 * sabi.sc
                visible: sabi.granted

                Ink {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "欢迎回来，" + sabi.ctx.userName
                    font.pixelSize: 28 * sabi.sc
                }
            }
        }
    }

    // ── Around the edges ─────────────────────────────────────────────
    Item {
        anchors.fill: parent
        opacity: sabi.uiIn

        // A quiet month calendar; today's pending tasks are marked without details.
        Column {
            id: miniCalendar
            x: sabi.edge
            y: 46 * sabi.sc
            width: 7 * sabi.calendarCell
            spacing: 7 * sabi.sc

            Column {
                spacing: -2 * sabi.sc
                Ink {
                    text: "公历 · " + sabi.calendarChineseYear + "年"
                    font.pixelSize: 10 * sabi.sc
                    font.letterSpacing: 1.2 * sabi.sc
                    color: Wabi.sumiSoft
                }
                Ink {
                    text: sabi.calendarChineseMonth + "月"
                    font.pixelSize: 22 * sabi.sc
                    font.weight: Font.Medium
                    color: Wabi.sumi
                }
            }

            Rectangle {
                width: parent.width
                height: 1 * sabi.sc
                color: Wabi.alpha(Wabi.sumiSoft, 0.3)
            }

            Row {
                spacing: 0
                Repeater {
                    model: sabi.weekdays
                    delegate: Ink {
                        required property string modelData
                        width: sabi.calendarCell
                        text: modelData
                        horizontalAlignment: Text.AlignHCenter
                        font.pixelSize: 12 * sabi.sc
                        color: Wabi.sumiSoft
                    }
                }
            }

            Grid {
                columns: 7
                spacing: 0
                Repeater {
                    model: 42
                    delegate: Item {
                        id: dateCell
                        required property int index
                        readonly property int day: index - sabi.monthStartOffset + 1
                        readonly property bool inMonth: day >= 1 && day <= sabi.monthDayCount
                        readonly property bool today: day === sabi.calendarDay
                        width: sabi.calendarCell
                        height: sabi.calendarCell
                        visible: inMonth

                        Loader {
                            anchors.centerIn: parent
                            width: 25 * sabi.sc
                            height: width
                            active: dateCell.today
                            sourceComponent: calendarDateBrush
                        }

                        Ink {
                            anchors.centerIn: parent
                            text: dateCell.inMonth ? String(dateCell.day) : ""
                            width: parent.width
                            height: parent.height
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            font.pixelSize: 13 * sabi.sc
                            color: dateCell.today ? Wabi.sumi : Wabi.sumiSoft
                        }

                        Rectangle {
                            visible: dateCell.today && sabi.hasPendingTodoToday
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.rightMargin: 3 * sabi.sc
                            anchors.bottomMargin: 3 * sabi.sc
                            width: 3.5 * sabi.sc
                            height: width
                            radius: width / 2
                            color: Wabi.shu
                        }
                    }
                }
            }

            Ink {
                text: sabi.calendarChineseDay + "日 · 星期" + sabi.todayWeekday
                font.pixelSize: 12 * sabi.sc
                font.letterSpacing: 0.4 * sabi.sc
                color: Wabi.sumiSoft
            }
        }

        // Battery and caps, top right.
        Column {
            anchors.right: parent.right
            anchors.rightMargin: sabi.edge
            y: 48 * sabi.sc
            spacing: 4 * sabi.sc

            Ink {
                anchors.right: parent.right
                readonly property real pct: Services.Battery.percentage
                text: "电量 " + Math.round(pct) + "%" + (Services.Battery.charging ? " · 正在充电" : "")
                font.pixelSize: 15 * sabi.sc
                color: pct <= 20 && !Services.Battery.charging ? Wabi.shu : Wabi.sumiSoft
            }

            Row {
                anchors.right: parent.right
                spacing: 7 * sabi.sc
                visible: !!CaelestiaServices.Weather.cc

                Glyph {
                    anchors.verticalCenter: parent.verticalCenter
                    text: CaelestiaServices.Weather.icon
                    font.pixelSize: 18 * sabi.sc
                }

                Ink {
                    anchors.verticalCenter: parent.verticalCenter
                    text: CaelestiaServices.Weather.city + " · "
                        + CaelestiaServices.Weather.description + " " + CaelestiaServices.Weather.temp
                    font.pixelSize: 14 * sabi.sc
                    color: Wabi.sumiSoft
                }
            }

            Ink {
                anchors.right: parent.right
                visible: sabi.ctx.capsLock
                text: "大写锁定"
                font.pixelSize: 14 * sabi.sc
                color: Wabi.shu
            }
        }

        // What's playing, bottom centre.
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 56 * sabi.sc
            spacing: 12 * sabi.sc
            visible: Services.Media.activePlayer !== null

            Glyph {
                anchors.verticalCenter: parent.verticalCenter
                text: "music_note"
                font.pixelSize: 20 * sabi.sc
            }

            Repeater {
                // Static model: only the icon follows play/pause.
                model: ["previous", "playPause", "next"]

                Glyph {
                    id: mediaKey
                    required property string modelData
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData === "playPause" ? (Services.Media.isPlaying ? "pause" : "play_arrow") : modelData === "previous" ? "skip_previous" : "skip_next"
                    filled: true
                    font.pixelSize: 18 * sabi.sc
                    color: mediaArea.containsMouse ? Wabi.sumi : Wabi.sumiSoft

                    MouseArea {
                        id: mediaArea
                        anchors.fill: parent
                        anchors.margins: -6 * sabi.sc
                        enabled: !sabi.still && !sabi.previewOnly
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Services.Media[mediaKey.modelData]()
                    }
                }
            }

            Ink {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, 440 * sabi.sc)
                elide: Text.ElideRight
                text: Services.Media.title + (Services.Media.artist ? "  —  " + Services.Media.artist : "")
                font.pixelSize: 15 * sabi.sc
            }
        }

        // Stones, bottom right: hold one and the brush circles it.
        Row {
            anchors.right: parent.right
            anchors.rightMargin: sabi.edge
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 40 * sabi.sc
            spacing: 18 * sabi.sc

            Repeater {
                model: [
                    { icon: "bedtime", label: "睡眠", act: "suspend" },
                    { icon: "restart_alt", label: "重启", act: "reboot" },
                    { icon: "power_settings_new", label: "关机", act: "poweroff" }
                ]

                Column {
                    id: stone
                    required property var modelData
                    spacing: 6 * sabi.sc

                    Item {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 48 * sabi.sc
                        height: width

                        Rectangle {
                            anchors.fill: parent
                            radius: width / 2
                            topRightRadius: width * 0.36
                            bottomLeftRadius: width * 0.42
                            color: Wabi.alpha(Wabi.sumi, stoneHold.containsMouse ? 0.14 : 0.07)
                            border.width: 1
                            border.color: Wabi.alpha(Wabi.sumi, 0.35)
                        }

                        Shape {
                            anchors.fill: parent
                            anchors.margins: -5 * sabi.sc
                            visible: stoneHold.progress > 0
                            preferredRendererType: Shape.CurveRenderer

                            ShapePath {
                                fillColor: "transparent"
                                strokeColor: Wabi.sumi
                                strokeWidth: 3 * sabi.sc
                                capStyle: ShapePath.RoundCap
                                PathAngleArc {
                                    centerX: 29 * sabi.sc
                                    centerY: 29 * sabi.sc
                                    radiusX: 27 * sabi.sc
                                    radiusY: 27 * sabi.sc
                                    startAngle: 130
                                    sweepAngle: 330 * stoneHold.progress
                                }
                            }
                        }

                        Glyph {
                            anchors.centerIn: parent
                            text: stone.modelData.icon
                            font.pixelSize: 21 * sabi.sc
                        }

                        HoldArea {
                            id: stoneHold
                            anchors.fill: parent
                            enabled: !sabi.still && !sabi.previewOnly
                            onConfirmed: sabi.ctx[stone.modelData.act]()
                        }
                    }

                    Ink {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: stone.modelData.label
                        font.pixelSize: 12 * sabi.sc
                        color: Wabi.sumiSoft
                    }
                }
            }
        }
    }

    // ── The desktop, ageing into paper ───────────────────────────────
    CaptureImage {
        id: capture
        source: sabi.shot
        imageWidth: sabi.width
        imageHeight: sabi.height
    }

    ShaderEffect {
        anchors.fill: parent
        visible: capture.ready && sabi.age < 1

        property variant source: capture.image
        property real itemWidth: width
        property real itemHeight: height
        property real progress: sabi.age
        property color paperColor: Wabi.paper
        property color stainColor: "#8a6a44"

        fragmentShader: Qt.resolvedUrl("../../shaders/lock_sabi.frag.qsb")
    }

    Rectangle {
        anchors.fill: parent
        color: "black"
        visible: !capture.ready && opacity > 0
        opacity: 1 - sabi.age
    }

    // ── Choreography ─────────────────────────────────────────────────
    ParallelAnimation {
        id: intro
        SequentialAnimation {
            PauseAnimation { duration: 80 }
            NumberAnimation { target: sabi; property: "age"; from: 0; to: 1; duration: 1050; easing.type: Easing.InOutSine }
        }
        SequentialAnimation {
            PauseAnimation { duration: 700 }
            NumberAnimation { target: sabi; property: "ghostIn"; from: 0; to: 1; duration: 600; easing.type: Easing.OutCubic }
        }
        SequentialAnimation {
            PauseAnimation { duration: 820 }
            NumberAnimation { target: sabi; property: "uiIn"; from: 0; to: 1; duration: 650; easing.type: Easing.OutCubic }
        }
    }

    // The desktop comes back out of the paper: the last frame is the desktop
    // exactly.
    ParallelAnimation {
        id: outro
        NumberAnimation { target: sabi; property: "uiIn"; to: 0; duration: 300; easing.type: Easing.InQuad }
        NumberAnimation { target: sabi; property: "ghostIn"; to: 0; duration: 300 }
        SequentialAnimation {
            PauseAnimation { duration: 180 }
            NumberAnimation { target: sabi; property: "age"; to: 0; duration: 900; easing.type: Easing.OutCubic }
        }
    }

    SequentialAnimation {
        id: deniedFx
        PauseAnimation { duration: 350 }
        ScriptAction {
            script: {
                if (sabi.lockoutActive)
                    sabi.startLockoutFill();
                else
                    denialRetreatFx.start();
            }
        }
    }

    SequentialAnimation {
        id: denialRetreatFx
        NumberAnimation { target: sabi; property: "denialRetreat"; from: 0; to: 0.2; duration: 110; easing.type: Easing.OutQuad }
        NumberAnimation { target: sabi; property: "denialRetreat"; to: 1; duration: 260; easing.type: Easing.InOutCubic }
        ScriptAction { script: { sabi.denialVisible = false; sabi.denialRetreat = 0; sabi.strokeInk = Wabi.sumi; sabi.inkOpacity = 1; } }
    }

    SequentialAnimation {
        id: lockoutFx
        NumberAnimation { target: sabi; property: "lockoutSweep"; to: 1; duration: 900; easing.type: Easing.OutCubic }
    }

    ParallelAnimation {
        id: grantFx
        SequentialAnimation {
            PauseAnimation { duration: 350 }
            NumberAnimation { target: sabi; property: "gold"; from: 0; to: 1; duration: 700; easing.type: Easing.InOutSine }
        }
    }
}
