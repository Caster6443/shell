pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

Item {
    id: root
    implicitWidth: 0
    implicitHeight: 0
    required property real scaleFactor
    signal backRequested

    readonly property var alarmDays: ["日", "一", "二", "三", "四", "五", "六"]
    readonly property var weekDayList: [
        { name: "一", day: 1 },
        { name: "二", day: 2 },
        { name: "三", day: 3 },
        { name: "四", day: 4 },
        { name: "五", day: 5 },
        { name: "六", day: 6 },
        { name: "日", day: 0 }
    ]

    property bool editing: false
    property string editingId: ""
    property string alarmLabel: "闹钟"
    property string mode: "once"
    property int selectedHour: 7
    property int selectedMinute: 0
    property var selectedDays: []
    property string statusText: ""
    property bool pointerEntered: false

    function resetDraft(): void {
        editing = false;
        editingId = "";
        alarmLabel = "闹钟";
        mode = "once";
        selectedHour = 7;
        selectedMinute = 0;
        selectedDays = [];
        statusText = "";
    }

    function newAlarm(): void {
        const nextMinute = new Date(Date.now() + 60_000);
        editingId = "";
        alarmLabel = "闹钟";
        mode = "once";
        selectedHour = nextMinute.getHours();
        selectedMinute = nextMinute.getMinutes();
        selectedDays = [];
        statusText = "";
        editing = true;
        focusTimer.restart();
    }

    function editAlarm(alarm: var): void {
        editingId = alarm.id;
        alarmLabel = alarm.label || "闹钟";
        mode = alarm.mode === "weekly" ? "weekly" : "once";
        selectedHour = alarm.hour;
        selectedMinute = alarm.minute;
        selectedDays = Array.isArray(alarm.days) ? alarm.days.slice() : [];
        statusText = "";
        editing = true;
        focusTimer.restart();
    }

    function toggleDay(day: int): void {
        const days = selectedDays.slice();
        const index = days.indexOf(day);
        if (index >= 0)
            days.splice(index, 1);
        else
            days.push(day);
        selectedDays = days.sort((a, b) => a - b);
    }

    function saveAlarm(): void {
        if (mode === "weekly" && selectedDays.length === 0) {
            statusText = "至少选择一个响铃日";
            return;
        }
        const savedId = TodoData.saveAlarm({
            enabled: true,
            mode: mode,
            hour: selectedHour,
            minute: selectedMinute,
            days: mode === "weekly" ? selectedDays : [],
            label: alarmLabel
        }, editingId);
        if (!savedId) {
            statusText = "闹钟设置无效";
            return;
        }
        editingId = savedId;
        resetDraft();
    }

    function scheduleText(alarm: var): string {
        if (alarm.mode !== "weekly")
            return "仅一次";
        if (alarm.days.length === 5 && [1, 2, 3, 4, 5].every(d => alarm.days.includes(d)))
            return "工作日";
        if (alarm.days.length === 2 && [0, 6].every(d => alarm.days.includes(d)))
            return "周末";
        if (alarm.days.length === 7)
            return "每天";
        return alarm.days.map(day => alarmDays[day]).join("、");
    }

    function timeText(alarm: var): string {
        return String(alarm.hour).padStart(2, "0") + ":" + String(alarm.minute).padStart(2, "0");
    }

    HoverHandler {
        onHoveredChanged: {
            if (hovered)
                root.pointerEntered = true;
            else if (root.visible && root.pointerEntered)
                root.backRequested();
        }
    }

    Timer {
        id: focusTimer
        interval: 160
        onTriggered: {
            if (root.visible && root.editing) {
                if (nameInput)
                    nameInput.forceActiveFocus();
            }
        }
    }

    Shortcut {
        sequence: "Escape"
        enabled: root.visible
        onActivated: {
            if (root.editing)
                root.resetDraft();
            else
                root.backRequested();
        }
    }

    onVisibleChanged: {
        if (visible)
            pointerEntered = false;
        else
            resetDraft();
    }

    // 底板：与 Caelestia 风格对齐的表面容器与微光边框
    StyledRect {
        anchors.fill: parent
        radius: Tokens.rounding.extraLarge * root.scaleFactor
        color: Colours.tPalette.m3surfaceContainer
        border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.28)
        border.width: 1 * root.scaleFactor
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Tokens.padding.medium * root.scaleFactor
        spacing: Tokens.spacing.small * root.scaleFactor

        // 顶栏 Header
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small * root.scaleFactor

            IconButton {
                icon: "arrow_back"
                type: IconButton.Tonal
                Layout.preferredWidth: 36 * root.scaleFactor
                Layout.preferredHeight: 36 * root.scaleFactor
                onClicked: {
                    if (root.editing)
                        root.resetDraft();
                    else
                        root.backRequested();
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1 * root.scaleFactor

                StyledText {
                    text: root.editing ? (root.editingId ? "编辑闹钟" : "新建闹钟") : "闹钟提醒"
                    color: Colours.palette.m3onSurface
                    font: Tokens.font.clock.size(Tokens.font.title.medium.pointSize * root.scaleFactor).weight(Font.Bold).build()
                }

                StyledText {
                    text: root.editing ? "设置响铃时间与周期" : `${TodoData.alarms.length} 个闹钟`
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.clock.size(Tokens.font.body.small.pointSize * 0.85 * root.scaleFactor).build()
                }
            }

            IconButton {
                visible: !root.editing
                icon: "add"
                type: IconButton.Filled
                Layout.preferredWidth: 36 * root.scaleFactor
                Layout.preferredHeight: 36 * root.scaleFactor
                onClicked: root.newAlarm()
            }
        }

        // ==================== 列表视图 ====================
        StyledRect {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !root.editing
            radius: Tokens.rounding.large * root.scaleFactor
            color: Colours.tPalette.m3surfaceContainerLow
            border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.20)
            border.width: 1 * root.scaleFactor

            ListView {
                id: alarmList
                anchors.fill: parent
                anchors.margins: 6 * root.scaleFactor
                clip: true
                spacing: 6 * root.scaleFactor
                model: TodoData.alarms.slice().sort((a, b) => (a.hour * 60 + a.minute) - (b.hour * 60 + b.minute))
                boundsBehavior: Flickable.StopAtBounds

                delegate: StyledRect {
                    id: alarmDelegate
                    required property var modelData
                    width: alarmList.width
                    height: 64 * root.scaleFactor
                    radius: Tokens.rounding.medium * root.scaleFactor
                    color: itemHover.hovered
                        ? (modelData.enabled ? Colours.tPalette.m3surfaceContainerHigh : Colours.tPalette.m3surfaceContainerHighest)
                        : (modelData.enabled ? Colours.tPalette.m3surfaceContainer : Qt.alpha(Colours.palette.m3surfaceContainerHigh, 0.45))
                    border.color: modelData.enabled
                        ? Qt.alpha(Colours.palette.m3primary, 0.40)
                        : Qt.alpha(Colours.palette.m3outlineVariant, 0.20)
                    border.width: 1 * root.scaleFactor

                    Behavior on color { CAnim {} }
                    Behavior on border.color { CAnim {} }

                    HoverHandler {
                        id: itemHover
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12 * root.scaleFactor
                        anchors.rightMargin: 10 * root.scaleFactor
                        spacing: 10 * root.scaleFactor

                        // 状态图标
                        MaterialIcon {
                            text: modelData.mode === "weekly" ? "update" : "alarm"
                            color: modelData.enabled ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                            fontStyle: Tokens.font.icon.builders.medium.scale(root.scaleFactor).build()
                        }

                        // 时间与标签信息
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1 * root.scaleFactor

                            StyledText {
                                text: root.timeText(modelData)
                                color: modelData.enabled ? Colours.palette.m3onSurface : Colours.palette.m3onSurfaceVariant
                                font: Tokens.font.clock.size(Tokens.font.headline.small.pointSize * 0.95 * root.scaleFactor).weight(Font.Bold).build()
                            }

                            StyledText {
                                text: `${modelData.label} · ${root.scheduleText(modelData)}`
                                color: Colours.palette.m3onSurfaceVariant
                                font: Tokens.font.clock.size(Tokens.font.body.small.pointSize * 0.82 * root.scaleFactor).build()
                                elide: Text.ElideRight
                            }
                        }

                        // 启停开关切换
                        IconButton {
                            icon: modelData.enabled ? "alarm_on" : "alarm_off"
                            type: modelData.enabled ? IconButton.Filled : IconButton.Tonal
                            Layout.preferredWidth: 34 * root.scaleFactor
                            Layout.preferredHeight: 34 * root.scaleFactor
                            onClicked: TodoData.setAlarmEnabled(modelData.id, !modelData.enabled)
                        }

                        // 编辑按钮
                        IconButton {
                            icon: "edit"
                            type: IconButton.Text
                            opacity: itemHover.hovered ? 0.85 : 0.35
                            Behavior on opacity { NumberAnimation { duration: 150 } }
                            Layout.preferredWidth: 32 * root.scaleFactor
                            Layout.preferredHeight: 32 * root.scaleFactor
                            onClicked: root.editAlarm(modelData)
                        }

                        // 删除按钮
                        IconButton {
                            icon: "delete_outline"
                            type: IconButton.Text
                            opacity: itemHover.hovered ? 0.85 : 0.25
                            Behavior on opacity { NumberAnimation { duration: 150 } }
                            Layout.preferredWidth: 32 * root.scaleFactor
                            Layout.preferredHeight: 32 * root.scaleFactor
                            onClicked: TodoData.removeAlarm(modelData.id)
                        }
                    }
                }
            }

            // 空列表占位
            ColumnLayout {
                anchors.centerIn: parent
                visible: alarmList.count === 0
                spacing: 8 * root.scaleFactor

                MaterialIcon {
                    Layout.alignment: Qt.AlignHCenter
                    text: "alarm_add"
                    color: Colours.palette.m3primary
                    fontStyle: Tokens.font.icon.builders.extraLarge.scale(1.3 * root.scaleFactor).build()
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: "还没有设置闹钟"
                    color: Colours.palette.m3onSurface
                    font: Tokens.font.clock.size(Tokens.font.title.small.pointSize * root.scaleFactor).weight(Font.Bold).build()
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: "点击右上角的 ＋ 号新建闹钟"
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.clock.size(Tokens.font.body.small.pointSize * 0.9 * root.scaleFactor).build()
                }
            }
        }

        // ==================== 编辑视图 ====================
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.editing
            spacing: 8 * root.scaleFactor

            // 中间主要配置区：左右双栏并排，无需滚动
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 10 * root.scaleFactor

                // 左栏：大号时间微调盘
                StyledRect {
                    Layout.preferredWidth: 175 * root.scaleFactor
                    Layout.fillHeight: true
                    radius: Tokens.rounding.large * root.scaleFactor
                    color: Colours.tPalette.m3surfaceContainerLow
                    border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.20)
                    border.width: 1 * root.scaleFactor

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 6 * root.scaleFactor

                        Tumbler {
                            id: hourTumbler
                            Layout.preferredWidth: 64 * root.scaleFactor
                            Layout.preferredHeight: 108 * root.scaleFactor
                            model: 24
                            currentIndex: root.selectedHour
                            visibleItemCount: 3
                            wrap: true
                            onCurrentIndexChanged: root.selectedHour = currentIndex

                            WheelHandler {
                                target: null
                                blocking: true
                                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                                onWheel: event => {
                                    const nextHour = (root.selectedHour + (event.angleDelta.y < 0 ? 1 : 23)) % 24;
                                    root.selectedHour = nextHour;
                                    hourTumbler.positionViewAtIndex(nextHour, Tumbler.SnapPosition);
                                    event.accepted = true;
                                }
                            }

                            delegate: StyledText {
                                required property int index
                                required property var modelData
                                text: String(modelData).padStart(2, "0")
                                color: hourTumbler.currentIndex === index ? Colours.palette.m3primary : Qt.alpha(Colours.palette.m3onSurface, 0.35)
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                font: Tokens.font.clock.size((hourTumbler.currentIndex === index ? Tokens.font.headline.large.pointSize : Tokens.font.title.small.pointSize) * root.scaleFactor).weight(Font.Bold).build()
                            }
                        }

                        StyledText {
                            text: ":"
                            color: Colours.palette.m3primary
                            font: Tokens.font.clock.size(Tokens.font.headline.large.pointSize * root.scaleFactor).weight(Font.Bold).build()
                            Layout.alignment: Qt.AlignVCenter
                        }

                        Tumbler {
                            id: minuteTumbler
                            Layout.preferredWidth: 64 * root.scaleFactor
                            Layout.preferredHeight: 108 * root.scaleFactor
                            model: 60
                            currentIndex: root.selectedMinute
                            visibleItemCount: 3
                            wrap: true
                            onCurrentIndexChanged: root.selectedMinute = currentIndex

                            WheelHandler {
                                target: null
                                blocking: true
                                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                                onWheel: event => {
                                    const nextMinute = (root.selectedMinute + (event.angleDelta.y < 0 ? 1 : 59)) % 60;
                                    root.selectedMinute = nextMinute;
                                    minuteTumbler.positionViewAtIndex(nextMinute, Tumbler.SnapPosition);
                                    event.accepted = true;
                                }
                            }

                            delegate: StyledText {
                                required property int index
                                required property var modelData
                                text: String(modelData).padStart(2, "0")
                                color: minuteTumbler.currentIndex === index ? Colours.palette.m3primary : Qt.alpha(Colours.palette.m3onSurface, 0.35)
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                font: Tokens.font.clock.size((minuteTumbler.currentIndex === index ? Tokens.font.headline.large.pointSize : Tokens.font.title.small.pointSize) * root.scaleFactor).weight(Font.Bold).build()
                            }
                        }
                    }
                }

                // 右栏：名称、模式切换与星期设置
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 8 * root.scaleFactor

                    // 闹钟名称
                    StyledRect {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 38 * root.scaleFactor
                        radius: Tokens.rounding.medium * root.scaleFactor
                        color: Colours.tPalette.m3surfaceContainerLow
                        border.color: nameInput.activeFocus ? Colours.palette.m3primary : Qt.alpha(Colours.palette.m3outlineVariant, 0.20)
                        border.width: 1 * root.scaleFactor
                        Behavior on border.color { CAnim {} }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10 * root.scaleFactor
                            anchors.rightMargin: 10 * root.scaleFactor
                            spacing: 8 * root.scaleFactor

                            MaterialIcon {
                                text: "label"
                                color: nameInput.activeFocus ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                                fontStyle: Tokens.font.icon.builders.small.scale(0.9 * root.scaleFactor).build()
                                Behavior on color { CAnim {} }
                            }

                            TextFieldBase {
                                id: nameInput
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                text: root.alarmLabel
                                placeholderText: "闹钟名称（如：早起、打卡）"
                                selectByMouse: true
                                font: Tokens.font.clock.size(Tokens.font.body.medium.pointSize * root.scaleFactor).build()
                                onTextEdited: root.alarmLabel = text
                            }
                        }
                    }

                    // 模式切换胶囊
                    StyledRect {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 34 * root.scaleFactor
                        radius: Tokens.rounding.full
                        color: Colours.tPalette.m3surfaceContainerHigh

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 3 * root.scaleFactor
                            spacing: 4 * root.scaleFactor

                            ButtonBase {
                                isRound: true
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                implicitWidth: 80 * root.scaleFactor
                                implicitHeight: 28 * root.scaleFactor
                                type: root.mode === "once" ? ButtonBase.Filled : ButtonBase.Text
                                inactiveColour: root.mode === "once" ? Colours.palette.m3primary : "transparent"
                                inactiveOnColour: root.mode === "once" ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
                                activeColour: Colours.palette.m3primary
                                activeOnColour: Colours.palette.m3onPrimary
                                onClicked: root.mode = "once"

                                StyledText {
                                    anchors.centerIn: parent
                                    text: "仅响一次"
                                    color: parent.onColour
                                    font: Tokens.font.clock.size(Tokens.font.body.small.pointSize * 0.88 * root.scaleFactor).weight(root.mode === "once" ? Font.Bold : Font.Normal).build()
                                }
                            }

                            ButtonBase {
                                isRound: true
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                implicitWidth: 80 * root.scaleFactor
                                implicitHeight: 28 * root.scaleFactor
                                type: root.mode === "weekly" ? ButtonBase.Filled : ButtonBase.Text
                                inactiveColour: root.mode === "weekly" ? Colours.palette.m3primary : "transparent"
                                inactiveOnColour: root.mode === "weekly" ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
                                activeColour: Colours.palette.m3primary
                                activeOnColour: Colours.palette.m3onPrimary
                                onClicked: {
                                    root.mode = "weekly";
                                    if (root.selectedDays.length === 0)
                                        root.selectedDays = [new Date().getDay()];
                                }

                                StyledText {
                                    anchors.centerIn: parent
                                    text: "按周重复"
                                    color: parent.onColour
                                    font: Tokens.font.clock.size(Tokens.font.body.small.pointSize * 0.88 * root.scaleFactor).weight(root.mode === "weekly" ? Font.Bold : Font.Normal).build()
                                }
                            }
                        }
                    }

                    // 响铃日 / 周期说明
                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 34 * root.scaleFactor

                        // 按周重复时的星期选择
                        RowLayout {
                            anchors.fill: parent
                            visible: root.mode === "weekly"
                            spacing: 4 * root.scaleFactor

                            Repeater {
                                model: root.weekDayList
                                delegate: ButtonBase {
                                    required property var modelData
                                    readonly property bool selected: root.selectedDays.includes(modelData.day)
                                    isRound: true
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    implicitWidth: 28 * root.scaleFactor
                                    implicitHeight: 30 * root.scaleFactor
                                    type: selected ? ButtonBase.Filled : ButtonBase.Tonal
                                    inactiveColour: selected ? Colours.palette.m3primary : Colours.tPalette.m3surfaceContainerHigh
                                    inactiveOnColour: selected ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
                                    activeColour: Colours.palette.m3primary
                                    activeOnColour: Colours.palette.m3onPrimary
                                    onClicked: root.toggleDay(modelData.day)

                                    StyledText {
                                        anchors.centerIn: parent
                                        text: modelData.name
                                        color: parent.onColour
                                        font: Tokens.font.clock.size(Tokens.font.body.small.pointSize * 0.85 * root.scaleFactor).weight(selected ? Font.Bold : Font.Normal).build()
                                    }
                                }
                            }
                        }

                        // 仅响一次时的说明占位
                        StyledRect {
                            anchors.fill: parent
                            visible: root.mode !== "weekly"
                            radius: Tokens.rounding.medium * root.scaleFactor
                            color: Colours.tPalette.m3surfaceContainerLow
                            border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.15)
                            border.width: 1 * root.scaleFactor

                            RowLayout {
                                anchors.centerIn: parent
                                spacing: 6 * root.scaleFactor

                                MaterialIcon {
                                    text: "event"
                                    color: Colours.palette.m3onSurfaceVariant
                                    fontStyle: Tokens.font.icon.builders.small.scale(0.85 * root.scaleFactor).build()
                                }

                                StyledText {
                                    text: "仅在设定时间响铃一次后自动关闭"
                                    color: Colours.palette.m3onSurfaceVariant
                                    font: Tokens.font.clock.size(Tokens.font.body.small.pointSize * 0.82 * root.scaleFactor).build()
                                }
                            }
                        }
                    }
                }
            }

            // 底部操作栏
            RowLayout {
                Layout.fillWidth: true
                spacing: 8 * root.scaleFactor

                StyledText {
                    visible: root.statusText !== ""
                    Layout.fillWidth: true
                    text: root.statusText
                    color: Colours.palette.m3error
                    font: Tokens.font.clock.size(Tokens.font.body.small.pointSize * 0.85 * root.scaleFactor).build()
                    elide: Text.ElideRight
                }

                Item {
                    visible: root.statusText === ""
                    Layout.fillWidth: true
                }

                ButtonBase {
                    Layout.preferredWidth: 84 * root.scaleFactor
                    Layout.preferredHeight: 34 * root.scaleFactor
                    implicitWidth: 84 * root.scaleFactor
                    implicitHeight: 34 * root.scaleFactor
                    isRound: true
                    type: ButtonBase.Tonal
                    inactiveColour: Colours.tPalette.m3surfaceContainerHighest
                    inactiveOnColour: Colours.palette.m3onSurface
                    activeColour: Colours.tPalette.m3surfaceContainerHigh
                    activeOnColour: Colours.palette.m3onSurface
                    onClicked: root.resetDraft()

                    StyledText {
                        anchors.centerIn: parent
                        text: "取消"
                        color: parent.onColour
                        font: Tokens.font.clock.size(Tokens.font.body.medium.pointSize * 0.9 * root.scaleFactor).weight(Font.DemiBold).build()
                    }
                }

                ButtonBase {
                    Layout.preferredWidth: 104 * root.scaleFactor
                    Layout.preferredHeight: 34 * root.scaleFactor
                    implicitWidth: 104 * root.scaleFactor
                    implicitHeight: 34 * root.scaleFactor
                    isRound: true
                    type: ButtonBase.Filled
                    inactiveColour: Colours.palette.m3primary
                    inactiveOnColour: Colours.palette.m3onPrimary
                    activeColour: Colours.palette.m3primary
                    activeOnColour: Colours.palette.m3onPrimary
                    onClicked: root.saveAlarm()

                    StyledText {
                        anchors.centerIn: parent
                        text: "保存闹钟"
                        color: parent.onColour
                        font: Tokens.font.clock.size(Tokens.font.body.medium.pointSize * 0.9 * root.scaleFactor).weight(Font.Bold).build()
                    }
                }
            }
        }
    }
}
