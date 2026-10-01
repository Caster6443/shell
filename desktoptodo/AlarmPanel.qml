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
    property bool editing: false
    property string editingId: ""
    property string alarmLabel: "闹钟"
    property string mode: "once"
    property int selectedHour: 7
    property int selectedMinute: 0
    property var selectedDays: []
    property string statusText: ""
    property bool pointerEntered: false

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
        editing = false;
    }

    function scheduleText(alarm: var): string {
        return alarm.mode === "weekly" ? alarm.days.map(day => alarmDays[day]).join("、") : "仅一次";
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
        onTriggered: if (root.visible && root.editing)
            alarmName.forceActiveFocus()
    }

    Shortcut {
        sequence: "Escape"
        enabled: root.visible
        onActivated: {
            if (root.editing)
                root.editing = false;
            else
                root.backRequested();
        }
    }

    onVisibleChanged: if (visible)
        pointerEntered = false

    StyledRect {
        anchors.fill: parent
        anchors.margins: 2 * root.scaleFactor
        radius: Tokens.rounding.extraLarge * root.scaleFactor
        color: "transparent"
        border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.38)
        border.width: 1 * root.scaleFactor
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12 * root.scaleFactor
        anchors.topMargin: 14 * root.scaleFactor
        spacing: 8 * root.scaleFactor

        RowLayout {
            id: headerRow
            Layout.fillWidth: true
            Layout.preferredHeight: 44 * root.scaleFactor
            spacing: 4 * root.scaleFactor
            ButtonBase {
                visible: true
                type: ButtonBase.Tonal
                inactiveColour: Colours.palette.m3secondaryContainer
                inactiveOnColour: Colours.palette.m3onSecondaryContainer
                activeColour: Colours.palette.m3secondaryContainer
                activeOnColour: Colours.palette.m3onSecondaryContainer
                Layout.preferredWidth: 96 * root.scaleFactor
                Layout.preferredHeight: 32 * root.scaleFactor
                implicitWidth: 96 * root.scaleFactor
                implicitHeight: 32 * root.scaleFactor
                onClicked: {
                    if (root.editing)
                        root.editing = false;
                    else
                        root.backRequested();
                }
                RowLayout {
                    anchors.centerIn: parent
                    spacing: 3 * root.scaleFactor
                    MaterialIcon {
                        text: "arrow_back"
                        color: parent.parent.onColour
                        fontStyle: Tokens.font.icon.builders.small.scale(0.8 * root.scaleFactor).build()
                    }
                    StyledText {
                        text: root.editing ? "返回列表" : "返回主界面"
                        color: parent.parent.onColour
                        font: Tokens.font.clock.size(Tokens.font.body.small.pointSize * 0.82 * root.scaleFactor).weight(Font.DemiBold).build()
                    }
                }
            }
            StyledRect {
                id: titleBox
                Layout.leftMargin: 6 * root.scaleFactor
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: titleRow.implicitWidth + 22 * root.scaleFactor
                implicitHeight: titleRow.implicitHeight + 12 * root.scaleFactor
                radius: Tokens.rounding.medium * root.scaleFactor
                color: Colours.palette.m3primaryContainer
                Behavior on color { CAnim {} }

                RowLayout {
                    id: titleRow
                    anchors.centerIn: parent
                    spacing: 6 * root.scaleFactor
                    MaterialIcon {
                        text: root.editing ? "edit_alarm" : "alarm"
                        color: Colours.palette.m3onPrimaryContainer
                        fontStyle: Tokens.font.icon.builders.small.scale(0.88 * root.scaleFactor).build()
                    }
                    StyledText {
                        text: root.editing ? (root.editingId ? "编辑闹钟" : "新建闹钟") : "闹钟"
                        color: Colours.palette.m3onPrimaryContainer
                        font: Tokens.font.clock.size(Tokens.font.title.small.pointSize * root.scaleFactor).weight(Font.Bold).build()
                    }
                }
            }
            Item {
                Layout.fillWidth: true
            }
            ButtonBase {
                visible: !root.editing
                type: ButtonBase.Filled
                inactiveColour: Colours.palette.m3primary
                inactiveOnColour: Colours.palette.m3onPrimary
                activeColour: Colours.palette.m3primary
                activeOnColour: Colours.palette.m3onPrimary
                Layout.preferredWidth: 82 * root.scaleFactor
                Layout.preferredHeight: 30 * root.scaleFactor
                implicitWidth: 82 * root.scaleFactor
                    implicitHeight: 30 * root.scaleFactor
                onClicked: root.newAlarm()
                RowLayout {
                    anchors.centerIn: parent
                    spacing: 3 * root.scaleFactor
                    MaterialIcon {
                        text: "add"
                        color: parent.parent.onColour
                        fontStyle: Tokens.font.icon.builders.small.scale(root.scaleFactor).build()
                    }
                    StyledText {
                        text: "新建"
                        color: parent.parent.onColour
                        font: Tokens.font.clock.size(Tokens.font.body.small.pointSize * 0.86 * root.scaleFactor).weight(Font.DemiBold).build()
                    }
                }
            }
        }

        StyledRect {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !root.editing
            radius: Tokens.rounding.large * root.scaleFactor
            color: "transparent"
            border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.32)
            border.width: 1 * root.scaleFactor

        ListView {
            id: alarmList
            anchors.fill: parent
            anchors.margins: 7 * root.scaleFactor
            clip: true
            spacing: 6 * root.scaleFactor
            model: TodoData.alarms.slice().sort((a, b) => (a.hour * 60 + a.minute) - (b.hour * 60 + b.minute))
            boundsBehavior: Flickable.StopAtBounds
            delegate: StyledRect {
                required property var modelData
                width: alarmList.width
                height: 58 * root.scaleFactor
                radius: Tokens.rounding.medium * root.scaleFactor
                color: modelData.enabled
                    ? Qt.alpha(Colours.palette.m3primaryContainer, 0.58)
                    : Qt.alpha(Colours.palette.m3surfaceContainerHigh, 0.34)
                border.color: modelData.enabled
                    ? Qt.alpha(Colours.palette.m3primary, 0.52)
                    : Qt.alpha(Colours.palette.m3outlineVariant, 0.20)
                border.width: 1 * root.scaleFactor
                Behavior on color { CAnim {} }
                Behavior on border.color { CAnim {} }
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 7 * root.scaleFactor
                    anchors.rightMargin: 5 * root.scaleFactor
                    spacing: 5 * root.scaleFactor
                    StyledRect {
                        Layout.preferredWidth: 38 * root.scaleFactor
                        Layout.preferredHeight: 38 * root.scaleFactor
                        radius: Tokens.rounding.medium * root.scaleFactor
                        color: modelData.enabled ? Colours.palette.m3primary : Colours.palette.m3surfaceContainerHighest
                        Behavior on color { CAnim {} }
                        MaterialIcon {
                            anchors.centerIn: parent
                            text: modelData.mode === "weekly" ? "event_repeat" : "alarm"
                            color: modelData.enabled ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
                            fontStyle: Tokens.font.icon.builders.medium.scale(root.scaleFactor).build()
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1 * root.scaleFactor
                        StyledText {
                            text: root.timeText(modelData)
                            color: modelData.enabled ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurfaceVariant
                            font: Tokens.font.clock.size(Tokens.font.title.small.pointSize * root.scaleFactor).weight(Font.Bold).build()
                        }
                        StyledText {
                            text: modelData.label + " · " + root.scheduleText(modelData)
                            color: modelData.enabled ? Qt.alpha(Colours.palette.m3onPrimaryContainer, 0.80) : Colours.palette.m3onSurfaceVariant
                            font: Tokens.font.clock.size(Tokens.font.body.small.pointSize * 0.78 * root.scaleFactor).build()
                            elide: Text.ElideRight
                        }
                    }
                    ButtonBase {
                        type: ButtonBase.Tonal
                        inactiveColour: modelData.enabled ? Colours.palette.m3secondaryContainer : Colours.palette.m3surfaceContainerHighest
                        inactiveOnColour: modelData.enabled ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurfaceVariant
                        activeColour: Colours.palette.m3primaryContainer
                        activeOnColour: Colours.palette.m3onPrimaryContainer
                        Layout.preferredWidth: 32 * root.scaleFactor
                        Layout.preferredHeight: 32 * root.scaleFactor
                        implicitWidth: 32 * root.scaleFactor
                        implicitHeight: 32 * root.scaleFactor
                        onClicked: TodoData.setAlarmEnabled(modelData.id, !modelData.enabled)
                        MaterialIcon {
                            anchors.centerIn: parent
                            text: modelData.enabled ? "pause" : "play_arrow"
                            color: parent.onColour
                        }
                    }
                    ButtonBase {
                        type: ButtonBase.Text
                        inactiveOnColour: Colours.palette.m3onSurfaceVariant
                        activeOnColour: Colours.palette.m3onSurface
                        Layout.preferredWidth: 30 * root.scaleFactor
                        Layout.preferredHeight: 30 * root.scaleFactor
                        implicitWidth: 30 * root.scaleFactor
                        implicitHeight: 30 * root.scaleFactor
                        onClicked: root.editAlarm(modelData)
                        MaterialIcon {
                            anchors.centerIn: parent
                            text: "edit"
                            color: parent.onColour
                        }
                    }
                    ButtonBase {
                        type: ButtonBase.Text
                        inactiveOnColour: Colours.palette.m3error
                        activeOnColour: Colours.palette.m3error
                        Layout.preferredWidth: 30 * root.scaleFactor
                        Layout.preferredHeight: 30 * root.scaleFactor
                        implicitWidth: 30 * root.scaleFactor
                        implicitHeight: 30 * root.scaleFactor
                        onClicked: TodoData.removeAlarm(modelData.id)
                        MaterialIcon {
                            anchors.centerIn: parent
                            text: "delete"
                            color: parent.onColour
                        }
                    }
                }
            }
            ColumnLayout {
                anchors.centerIn: parent
                visible: alarmList.count === 0
                spacing: 6 * root.scaleFactor
                MaterialIcon {
                    Layout.alignment: Qt.AlignHCenter
                    text: "alarm_add"
                    color: Colours.palette.m3primary
                    fontStyle: Tokens.font.icon.builders.extraLarge.scale(1.2 * root.scaleFactor).build()
                }
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: "还没有闹钟"
                    color: Colours.palette.m3onSurface
                    font: Tokens.font.clock.size(Tokens.font.title.small.pointSize * 0.9 * root.scaleFactor).weight(Font.DemiBold).build()
                }
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: "点击右上角的新建按钮开始设置"
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.clock.size(Tokens.font.body.small.pointSize * 0.82 * root.scaleFactor).build()
                }
            }
        }
            }

        StyledTextField {
            id: alarmName
            visible: root.editing
            Layout.fillWidth: true
            Layout.preferredHeight: 40 * root.scaleFactor
            verticalPadding: 7 * root.scaleFactor
            text: root.alarmLabel
            placeholderText: "给这个闹钟起个名字"
            leadingIcon: "label"
            onTextEdited: root.alarmLabel = text
        }

        StyledRect {
            visible: root.editing
            Layout.fillWidth: true
            Layout.preferredHeight: 38 * root.scaleFactor
            radius: Tokens.rounding.extraLarge * root.scaleFactor
            color: Colours.palette.m3surfaceContainerHigh

            RowLayout {
                anchors.fill: parent
                anchors.margins: 4 * root.scaleFactor
                spacing: 4 * root.scaleFactor
            ButtonBase {
                isRound: true
                type: root.mode === "once" ? ButtonBase.Tonal : ButtonBase.Text
                inactiveColour: root.mode === "once" ? Colours.palette.m3secondaryContainer : "transparent"
                inactiveOnColour: root.mode === "once" ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurfaceVariant
                activeColour: Colours.palette.m3primaryContainer
                activeOnColour: Colours.palette.m3onPrimaryContainer
                Layout.fillWidth: true
                implicitWidth: 80 * root.scaleFactor
                Layout.preferredHeight: 30 * root.scaleFactor
                implicitHeight: 30 * root.scaleFactor
                onClicked: root.mode = "once"
                StyledText {
                    anchors.centerIn: parent
                    text: "仅一次"
                    color: parent.onColour
                }
            }
            ButtonBase {
                isRound: true
                type: root.mode === "weekly" ? ButtonBase.Tonal : ButtonBase.Text
                inactiveColour: root.mode === "weekly" ? Colours.palette.m3secondaryContainer : "transparent"
                inactiveOnColour: root.mode === "weekly" ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurfaceVariant
                activeColour: Colours.palette.m3primaryContainer
                activeOnColour: Colours.palette.m3onPrimaryContainer
                Layout.fillWidth: true
                implicitWidth: 80 * root.scaleFactor
                Layout.preferredHeight: 30 * root.scaleFactor
                implicitHeight: 30 * root.scaleFactor
                onClicked: {
                    root.mode = "weekly";
                    if (root.selectedDays.length === 0)
                        root.selectedDays = [new Date().getDay()];
                }
                StyledText {
                    anchors.centerIn: parent
                    text: "每周"
                    color: parent.onColour
                }
            }
            }
        }

        StyledRect {
            visible: root.editing
            Layout.fillWidth: true
            Layout.preferredHeight: 64 * root.scaleFactor
            radius: Tokens.rounding.large * root.scaleFactor
            color: Colours.palette.m3surfaceContainerHigh
            RowLayout {
                anchors.centerIn: parent
                spacing: 6 * root.scaleFactor
                MaterialIcon {
                    text: "schedule"
                    color: Colours.palette.m3primary
                    fontStyle: Tokens.font.icon.builders.medium.scale(root.scaleFactor).build()
                }
            Tumbler {
                id: hourTumbler
                Layout.preferredWidth: 62 * root.scaleFactor
                Layout.preferredHeight: 58 * root.scaleFactor
                model: 24
                currentIndex: root.selectedHour
                visibleItemCount: 3
                wrap: true
                onCurrentIndexChanged: root.selectedHour = currentIndex
                delegate: StyledText {
                    required property int index
                    required property var modelData
                    text: String(modelData).padStart(2, "0")
                    color: hourTumbler.currentIndex === index ? Colours.palette.m3onSurface : Qt.alpha(Colours.palette.m3onSurface, 0.45)
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    font: Tokens.font.clock.size(Tokens.font.title.small.pointSize * root.scaleFactor).weight(Font.DemiBold).build()
                }
            }
            StyledText {
                text: ":"
                color: Colours.palette.m3onSurface
            }
            Tumbler {
                id: minuteTumbler
                Layout.preferredWidth: 62 * root.scaleFactor
                Layout.preferredHeight: 58 * root.scaleFactor
                model: 60
                currentIndex: root.selectedMinute
                visibleItemCount: 3
                wrap: true
                onCurrentIndexChanged: root.selectedMinute = currentIndex
                delegate: StyledText {
                    required property int index
                    required property var modelData
                    text: String(modelData).padStart(2, "0")
                    color: minuteTumbler.currentIndex === index ? Colours.palette.m3onSurface : Qt.alpha(Colours.palette.m3onSurface, 0.45)
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    font: Tokens.font.clock.size(Tokens.font.title.small.pointSize * root.scaleFactor).weight(Font.DemiBold).build()
                }
            }
            }
        }

        StyledText {
            visible: root.editing && root.mode === "weekly"
            Layout.fillWidth: true
            text: "响铃日（可多选）"
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.clock.size(Tokens.font.body.small.pointSize * 0.78 * root.scaleFactor).build()
        }

        RowLayout {
            visible: root.editing && root.mode === "weekly"
            Layout.fillWidth: true
            spacing: 3 * root.scaleFactor
            Repeater {
                model: root.alarmDays.length
                delegate: ButtonBase {
                    required property int index
                    readonly property bool selected: root.selectedDays.includes(index)
                    isRound: true
                    type: selected ? ButtonBase.Tonal : ButtonBase.Text
                    inactiveColour: selected ? Colours.palette.m3secondaryContainer : "transparent"
                    inactiveOnColour: selected ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurfaceVariant
                    activeColour: Colours.palette.m3primaryContainer
                    activeOnColour: Colours.palette.m3onPrimaryContainer
                    Layout.fillWidth: true
                    Layout.preferredHeight: 26 * root.scaleFactor
                    implicitWidth: 32 * root.scaleFactor
                    implicitHeight: 26 * root.scaleFactor
                    onClicked: root.toggleDay(index)
                    StyledText {
                        anchors.centerIn: parent
                        text: root.alarmDays[index]
                        color: parent.onColour
                    }
                }
            }
        }

        StyledText {
            visible: root.editing && root.statusText !== ""
            Layout.fillWidth: true
            text: root.statusText
            color: Colours.palette.m3error
            horizontalAlignment: Text.AlignHCenter
        }

        RowLayout {
            visible: root.editing
            Layout.fillWidth: true
            Item {
                Layout.fillWidth: true
            }
            ButtonBase {
                type: ButtonBase.Text
                inactiveOnColour: Colours.palette.m3onSurfaceVariant
                activeOnColour: Colours.palette.m3onSurface
                Layout.preferredWidth: 72 * root.scaleFactor
                Layout.preferredHeight: 30 * root.scaleFactor
                implicitWidth: 72 * root.scaleFactor
                implicitHeight: 30 * root.scaleFactor
                onClicked: root.editing = false
                StyledText {
                    anchors.centerIn: parent
                    text: "取消"
                    color: parent.onColour
                }
            }
            ButtonBase {
                type: ButtonBase.Filled
                inactiveColour: Colours.palette.m3primary
                inactiveOnColour: Colours.palette.m3onPrimary
                activeColour: Colours.palette.m3primary
                activeOnColour: Colours.palette.m3onPrimary
                Layout.preferredWidth: 72 * root.scaleFactor
                Layout.preferredHeight: 30 * root.scaleFactor
                implicitWidth: 72 * root.scaleFactor
                implicitHeight: 30 * root.scaleFactor
                onClicked: root.saveAlarm()
                StyledText {
                    anchors.centerIn: parent
                    text: "保存"
                    color: parent.onColour
                }
            }
        }
    }
}
