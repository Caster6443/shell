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

    required property string dateKey
    property real scaleFactor: 1
    signal backRequested()
    signal pointerLeft()

    readonly property var visibleTasks: {
        const revision = TodoData.revision;
        return TodoData.tasksFor(root.dateKey);
    }
    readonly property int unfinishedCount: visibleTasks.filter(task => !task.done).length

    property string statusText: ""
    property int selectedHour: new Date().getHours()
    property int selectedMinute: new Date().getMinutes()
    property bool timeEnabled: false
    property bool timePickerOpen: false
    property bool pointerEntered: false

    function formattedTime(): string {
        return `${String(selectedHour).padStart(2, "0")}:${String(selectedMinute).padStart(2, "0")}`;
    }

    function resetDraft(): void {
        if (taskInput)
            taskInput.text = "";
        const now = new Date();
        selectedHour = now.getHours();
        selectedMinute = now.getMinutes();
        timeEnabled = false;
        timePickerOpen = false;
        statusText = "";
    }

    onVisibleChanged: {
        if (visible) {
            pointerEntered = false;
            focusTimer.restart();
        } else {
            resetDraft();
        }
    }

    onDateKeyChanged: resetDraft()

    HoverHandler {
        onHoveredChanged: {
            if (hovered)
                root.pointerEntered = true;
            else if (root.visible && root.pointerEntered)
                root.pointerLeft();
        }
    }

    Timer {
        id: focusTimer
        interval: 160
        onTriggered: if (root.visible) taskInput.forceActiveFocus()
    }

    Shortcut {
        sequence: "Escape"
        enabled: root.visible
        onActivated: {
            root.resetDraft();
            root.backRequested();
        }
    }

    function addTask(): void {
        const title = taskInput.text.trim();
        if (!title) {
            taskInput.forceActiveFocus();
            return;
        }
        const dueText = root.timeEnabled ? root.formattedTime() : "";
        if (!TodoData.add(root.dateKey, title, dueText)) {
            root.statusText = dueText ? "提醒时间需要晚于当前时间" : "无法添加待办事项";
            return;
        }
        taskInput.text = "";
        root.timePickerOpen = false;
        root.statusText = "";
        taskInput.forceActiveFocus();
    }

    function taskTime(task: var): string {
        if (!task.dueAt)
            return "";
        return new Date(task.dueAt).toLocaleTimeString(Qt.locale(), "HH:mm");
    }

    // 优雅的底板：与 Caelestia 风格对齐的表面容器与柔和微光边框
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
                    root.resetDraft();
                    root.backRequested();
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1 * root.scaleFactor

                StyledText {
                    text: "待办事项"
                    color: Colours.palette.m3onSurface
                    font: Tokens.font.clock.size(Tokens.font.title.medium.pointSize * root.scaleFactor).weight(Font.Bold).build()
                }

                StyledText {
                    text: {
                        const parts = root.dateKey.split("-").map(Number);
                        return new Date(parts[0], parts[1] - 1, parts[2], 12).toLocaleDateString(Qt.locale(), "M月d日 dddd");
                    }
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.clock.size(Tokens.font.body.small.pointSize * 0.85 * root.scaleFactor).build()
                }
            }

            // 任务计数胶囊
            StyledRect {
                Layout.alignment: Qt.AlignVCenter
                radius: Tokens.rounding.full
                implicitWidth: badgeRow.implicitWidth + 18 * root.scaleFactor
                implicitHeight: 28 * root.scaleFactor
                color: root.unfinishedCount > 0 ? Colours.tPalette.m3primaryContainer : Colours.tPalette.m3surfaceContainerHigh
                Behavior on color { CAnim {} }

                RowLayout {
                    id: badgeRow
                    anchors.centerIn: parent
                    spacing: 4 * root.scaleFactor

                    MaterialIcon {
                        text: root.unfinishedCount > 0 ? "pending_actions" : "done_all"
                        color: root.unfinishedCount > 0 ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurfaceVariant
                        fontStyle: Tokens.font.icon.builders.small.scale(0.85 * root.scaleFactor).build()
                    }

                    StyledText {
                        text: root.unfinishedCount > 0 ? `${root.unfinishedCount} 项进行中` : "全部完成"
                        color: root.unfinishedCount > 0 ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.clock.size(Tokens.font.body.small.pointSize * 0.82 * root.scaleFactor).weight(Font.DemiBold).build()
                    }
                }
            }
        }

        // 待办事项列表卡槽
        StyledRect {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Tokens.rounding.large * root.scaleFactor
            color: Colours.tPalette.m3surfaceContainerLow
            border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.20)
            border.width: 1 * root.scaleFactor

            ListView {
                id: taskList
                anchors.fill: parent
                anchors.margins: 6 * root.scaleFactor
                clip: true
                spacing: 6 * root.scaleFactor
                model: root.visibleTasks
                boundsBehavior: Flickable.StopAtBounds

                delegate: StyledRect {
                    id: taskDelegate
                    required property var modelData
                    width: taskList.width
                    height: 48 * root.scaleFactor
                    radius: Tokens.rounding.medium * root.scaleFactor
                    color: itemHover.hovered
                        ? (modelData.done ? Colours.tPalette.m3surfaceContainerHighest : Colours.tPalette.m3surfaceContainerHigh)
                        : (modelData.done ? Qt.alpha(Colours.palette.m3surfaceContainerHigh, 0.40) : Colours.tPalette.m3surfaceContainer)
                    border.color: modelData.done ? "transparent" : Qt.alpha(Colours.palette.m3outlineVariant, 0.25)
                    border.width: 1 * root.scaleFactor

                    Behavior on color { CAnim {} }
                    Behavior on border.color { CAnim {} }

                    HoverHandler {
                        id: itemHover
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8 * root.scaleFactor
                        anchors.rightMargin: 8 * root.scaleFactor
                        spacing: 8 * root.scaleFactor

                        IconButton {
                            icon: modelData.done ? "check_circle" : "radio_button_unchecked"
                            type: IconButton.Text
                            Layout.preferredWidth: 32 * root.scaleFactor
                            Layout.preferredHeight: 32 * root.scaleFactor
                            onClicked: TodoData.setDone(modelData.id, !modelData.done)
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: modelData.title
                            color: modelData.done ? Colours.palette.m3onSurfaceVariant : Colours.palette.m3onSurface
                            opacity: modelData.done ? 0.65 : 1
                            elide: Text.ElideRight
                            font: Tokens.font.clock.size(Tokens.font.body.medium.pointSize * root.scaleFactor).weight(modelData.done ? Font.Normal : Font.Medium).build()
                        }

                        // 时间提醒气泡
                        StyledRect {
                            visible: root.taskTime(modelData) !== ""
                            radius: Tokens.rounding.full
                            implicitWidth: dueRow.implicitWidth + 12 * root.scaleFactor
                            implicitHeight: 24 * root.scaleFactor
                            color: modelData.done ? Qt.alpha(Colours.palette.m3surfaceContainerHighest, 0.6) : Colours.tPalette.m3tertiaryContainer

                            RowLayout {
                                id: dueRow
                                anchors.centerIn: parent
                                spacing: 3 * root.scaleFactor

                                MaterialIcon {
                                    text: "schedule"
                                    color: modelData.done ? Colours.palette.m3onSurfaceVariant : Colours.palette.m3onTertiaryContainer
                                    fontStyle: Tokens.font.icon.builders.small.scale(0.8 * root.scaleFactor).build()
                                }

                                StyledText {
                                    text: root.taskTime(modelData)
                                    color: modelData.done ? Colours.palette.m3onSurfaceVariant : Colours.palette.m3onTertiaryContainer
                                    font: Tokens.font.clock.size(Tokens.font.body.small.pointSize * 0.8 * root.scaleFactor).weight(Font.DemiBold).build()
                                }
                            }
                        }

                        // 删除按钮（hover 或触摸时显示更加清晰）
                        IconButton {
                            icon: "delete_outline"
                            type: IconButton.Text
                            opacity: itemHover.hovered ? 0.85 : 0.25
                            Behavior on opacity { NumberAnimation { duration: 150 } }
                            Layout.preferredWidth: 30 * root.scaleFactor
                            Layout.preferredHeight: 30 * root.scaleFactor
                            onClicked: TodoData.remove(modelData.id)
                        }
                    }
                }
            }

            // Keep the empty state inside the reduced list area when the picker opens.
            RowLayout {
                id: emptyState
                anchors.centerIn: parent
                width: Math.min(implicitWidth, Math.max(0, parent.width - 24 * root.scaleFactor))
                visible: taskList.count === 0
                spacing: 12 * root.scaleFactor

                MaterialIcon {
                    Layout.alignment: Qt.AlignVCenter
                    text: "task_alt"
                    color: Colours.palette.m3primary
                    fontStyle: Tokens.font.icon.builders.extraLarge.scale(0.85 * root.scaleFactor).build()
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2 * root.scaleFactor

                    StyledText {
                        Layout.fillWidth: true
                        text: "今天还没有安排"
                        color: Colours.palette.m3onSurface
                        elide: Text.ElideRight
                        font: Tokens.font.clock.size(Tokens.font.body.medium.pointSize * root.scaleFactor).weight(Font.Bold).build()
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: "在下方写下第一件待办事项"
                        color: Colours.palette.m3onSurfaceVariant
                        elide: Text.ElideRight
                        font: Tokens.font.clock.size(Tokens.font.body.small.pointSize * 0.85 * root.scaleFactor).build()
                    }
                }
            }
        }

        // 底部集成式输入区
        StyledRect {
            Layout.fillWidth: true
            Layout.preferredHeight: 52 * root.scaleFactor
            radius: Tokens.rounding.large * root.scaleFactor
            color: Colours.tPalette.m3surfaceContainerHigh
            border.color: taskInput.activeFocus ? Colours.palette.m3primary : Qt.alpha(Colours.palette.m3outlineVariant, 0.3)
            border.width: taskInput.activeFocus ? 1.5 * root.scaleFactor : 1 * root.scaleFactor
            Behavior on border.color { CAnim {} }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12 * root.scaleFactor
                anchors.rightMargin: 6 * root.scaleFactor
                spacing: 8 * root.scaleFactor

                TextFieldBase {
                    id: taskInput
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    placeholderText: "写下一个待办事项…"
                    selectByMouse: true
                    font: Tokens.font.clock.size(Tokens.font.body.medium.pointSize * root.scaleFactor).build()
                    onAccepted: root.addTask()
                }

                // 提醒时间触发芯片
                ButtonBase {
                    Layout.preferredHeight: 36 * root.scaleFactor
                    implicitHeight: 36 * root.scaleFactor
                    Layout.preferredWidth: timeChipRow.implicitWidth + 18 * root.scaleFactor
                    implicitWidth: timeChipRow.implicitWidth + 18 * root.scaleFactor
                    isRound: true
                    type: root.timeEnabled ? ButtonBase.Tonal : ButtonBase.Text
                    inactiveColour: root.timeEnabled ? Colours.tPalette.m3secondaryContainer : "transparent"
                    inactiveOnColour: root.timeEnabled ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurfaceVariant
                    activeColour: Colours.tPalette.m3primaryContainer
                    activeOnColour: Colours.palette.m3onPrimaryContainer
                    onClicked: {
                        root.timeEnabled = !root.timeEnabled;
                        root.timePickerOpen = root.timeEnabled;
                    }

                    RowLayout {
                        id: timeChipRow
                        anchors.centerIn: parent
                        spacing: 4 * root.scaleFactor

                        MaterialIcon {
                            text: root.timeEnabled ? "alarm" : "notifications_off"
                            color: parent.parent.onColour
                            fontStyle: Tokens.font.icon.builders.small.scale(0.85 * root.scaleFactor).build()
                        }

                        StyledText {
                            text: root.timeEnabled ? root.formattedTime() : "提醒"
                            color: parent.parent.onColour
                            font: Tokens.font.clock.size(Tokens.font.body.small.pointSize * 0.85 * root.scaleFactor).weight(Font.DemiBold).build()
                        }
                    }
                }

                // 添加按钮
                IconButton {
                    id: addButton
                    icon: "add"
                    type: IconButton.Filled
                    Layout.preferredWidth: 38 * root.scaleFactor
                    Layout.preferredHeight: 38 * root.scaleFactor
                    onClicked: root.addTask()
                }
            }
        }

        // 时间微调弹出框
        StyledRect {
            visible: root.timePickerOpen
            Layout.alignment: Qt.AlignRight
            Layout.preferredWidth: 200 * root.scaleFactor
            Layout.preferredHeight: visible ? 96 * root.scaleFactor : 0
            radius: Tokens.rounding.large * root.scaleFactor
            color: Colours.tPalette.m3surfaceContainerHighest
            border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.35)
            border.width: 1 * root.scaleFactor

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10 * root.scaleFactor
                anchors.rightMargin: 8 * root.scaleFactor
                spacing: 4 * root.scaleFactor

                Tumbler {
                    id: hourTumbler
                    model: 24
                    currentIndex: root.timePickerOpen ? root.selectedHour : 0
                    visibleItemCount: 3
                    wrap: true
                    Layout.preferredWidth: 62 * root.scaleFactor
                    Layout.preferredHeight: 88 * root.scaleFactor
                    onCurrentIndexChanged: if (root.timePickerOpen) root.selectedHour = currentIndex

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
                        color: hourTumbler.currentIndex === index ? Colours.palette.m3onSurface : Qt.alpha(Colours.palette.m3onSurface, 0.40)
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        font: Tokens.font.clock.size(Tokens.font.title.small.pointSize * root.scaleFactor).weight(Font.DemiBold).build()
                    }
                }

                StyledText {
                    text: ":"
                    color: Colours.palette.m3onSurface
                    font: Tokens.font.clock.size(Tokens.font.title.small.pointSize * root.scaleFactor).weight(Font.Bold).build()
                }

                Tumbler {
                    id: minuteTumbler
                    model: 60
                    currentIndex: root.timePickerOpen ? root.selectedMinute : 0
                    visibleItemCount: 3
                    wrap: true
                    Layout.preferredWidth: 62 * root.scaleFactor
                    Layout.preferredHeight: 88 * root.scaleFactor
                    onCurrentIndexChanged: if (root.timePickerOpen) root.selectedMinute = currentIndex

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
                        color: minuteTumbler.currentIndex === index ? Colours.palette.m3onSurface : Qt.alpha(Colours.palette.m3onSurface, 0.40)
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        font: Tokens.font.clock.size(Tokens.font.title.small.pointSize * root.scaleFactor).weight(Font.DemiBold).build()
                    }
                }

                IconButton {
                    icon: "check"
                    type: IconButton.Tonal
                    Layout.preferredWidth: 34 * root.scaleFactor
                    Layout.preferredHeight: 34 * root.scaleFactor
                    onClicked: root.timePickerOpen = false
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.preferredHeight: visible ? implicitHeight : 0
            visible: root.statusText !== ""
            text: root.statusText
            color: Colours.palette.m3error
            horizontalAlignment: Text.AlignHCenter
            font: Tokens.font.clock.size(Tokens.font.body.small.pointSize * 0.85 * root.scaleFactor).build()
        }
    }
}
