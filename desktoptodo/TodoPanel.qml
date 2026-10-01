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
    property string statusText: ""
    property int selectedHour: new Date().getHours()
    property int selectedMinute: new Date().getMinutes()
    property bool timeEnabled: false
    property bool timePickerOpen: false
    property bool pointerEntered: false

    function formattedTime(): string {
        return `${String(selectedHour).padStart(2, "0")}:${String(selectedMinute).padStart(2, "0")}`;
    }

    onVisibleChanged: {
        if (visible) {
            pointerEntered = false;
            focusTimer.restart();
        }
    }

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
        onActivated: root.backRequested()
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
        spacing: 8 * root.scaleFactor

        RowLayout {
            Layout.fillWidth: true
            spacing: 8 * root.scaleFactor

            ButtonBase {
                isRound: true
                type: ButtonBase.Tonal
                inactiveColour: Colours.palette.m3secondaryContainer
                inactiveOnColour: Colours.palette.m3onSecondaryContainer
                activeColour: Colours.palette.m3secondaryContainer
                activeOnColour: Colours.palette.m3onSecondaryContainer
                Layout.preferredWidth: 38 * root.scaleFactor
                Layout.preferredHeight: 38 * root.scaleFactor
                implicitWidth: 38 * root.scaleFactor
                implicitHeight: 38 * root.scaleFactor
                onClicked: root.backRequested()

                MaterialIcon {
                    anchors.centerIn: parent
                    text: "arrow_back"
                    color: parent.onColour
                    fontStyle: Tokens.font.icon.builders.small.scale(root.scaleFactor).build()
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2 * root.scaleFactor
                StyledText {
                    text: "待办清单"
                    color: Colours.palette.m3onSurface
                    font: Tokens.font.clock.size(Tokens.font.title.medium.pointSize * root.scaleFactor).weight(Font.Bold).build()
                }
                StyledText {
                    text: {
                        const parts = root.dateKey.split("-").map(Number);
                        return new Date(parts[0], parts[1] - 1, parts[2], 12).toLocaleDateString(Qt.locale(), "dddd, MMMM d")
                    }
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.clock.size(Tokens.font.body.small.pointSize * 0.82 * root.scaleFactor).build()
                }
            }

            StyledRect {
                Layout.alignment: Qt.AlignVCenter
                radius: Tokens.rounding.large * root.scaleFactor
                implicitWidth: remainingCount.implicitWidth + 24 * root.scaleFactor
                implicitHeight: 30 * root.scaleFactor
                color: Colours.palette.m3secondaryContainer
                RowLayout {
                    anchors.centerIn: parent
                    spacing: 5 * root.scaleFactor
                    MaterialIcon {
                        text: "checklist"
                        color: Colours.palette.m3onSecondaryContainer
                        fontStyle: Tokens.font.icon.builders.small.scale(root.scaleFactor).build()
                    }
                    StyledText {
                        id: remainingCount
                        text: `${root.visibleTasks.filter(task => !task.done).length} 项待办`
                        color: Colours.palette.m3onSecondaryContainer
                        font: Tokens.font.clock.size(Tokens.font.body.small.pointSize * 0.88 * root.scaleFactor).weight(Font.DemiBold).build()
                    }
                }
            }
        }

        StyledRect {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Tokens.rounding.large * root.scaleFactor
            color: "transparent"
            border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.32)
            border.width: 1 * root.scaleFactor

            ListView {
                id: taskList
                anchors.fill: parent
                anchors.margins: 7 * root.scaleFactor
                clip: true
                spacing: 5 * root.scaleFactor
                model: root.visibleTasks
                boundsBehavior: Flickable.StopAtBounds

                delegate: StyledRect {
                    required property var modelData
                    width: taskList.width
                    height: 44 * root.scaleFactor
                    radius: Tokens.rounding.medium * root.scaleFactor
                    color: modelData.done
                        ? Qt.alpha(Colours.palette.m3surfaceContainerHigh, 0.34)
                        : Qt.alpha(Colours.palette.m3primaryContainer, 0.56)
                    border.color: modelData.done
                        ? Qt.alpha(Colours.palette.m3outlineVariant, 0.20)
                        : Qt.alpha(Colours.palette.m3primary, 0.50)
                    border.width: 1 * root.scaleFactor
                    Behavior on color { CAnim {} }
                    Behavior on border.color { CAnim {} }
                    readonly property string dueLabel: root.taskTime(modelData)

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 6 * root.scaleFactor
                        anchors.rightMargin: 5 * root.scaleFactor
                        spacing: 6 * root.scaleFactor

                        IconButton {
                            icon: modelData.done ? "check_circle" : "radio_button_unchecked"
                            type: IconButton.Text
                            Layout.preferredWidth: 34 * root.scaleFactor
                            Layout.preferredHeight: 34 * root.scaleFactor
                            onClicked: TodoData.setDone(modelData.id, !modelData.done)
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: modelData.title
                            color: modelData.done ? Colours.palette.m3onSurfaceVariant : Colours.palette.m3onPrimaryContainer
                            opacity: modelData.done ? 0.72 : 1
                            elide: Text.ElideRight
                            font: Tokens.font.clock.size(Tokens.font.body.medium.pointSize * root.scaleFactor).weight(modelData.done ? Font.Normal : Font.Medium).build()
                        }

                        StyledRect {
                            visible: root.taskTime(modelData) !== ""
                            radius: Tokens.rounding.small * root.scaleFactor
                            implicitWidth: dueText.implicitWidth + 12 * root.scaleFactor
                            implicitHeight: 24 * root.scaleFactor
                            color: Qt.alpha(Colours.palette.m3tertiaryContainer, 0.82)
                            RowLayout {
                                anchors.centerIn: parent
                                spacing: 3 * root.scaleFactor
                                MaterialIcon {
                                    text: "schedule"
                                    color: Colours.palette.m3onTertiaryContainer
                                    fontStyle: Tokens.font.icon.builders.small.scale(0.8 * root.scaleFactor).build()
                                }
                                StyledText {
                                    id: dueText
                                    text: root.taskTime(modelData)
                                    color: Colours.palette.m3onTertiaryContainer
                                    font: Tokens.font.clock.size(Tokens.font.body.small.pointSize * 0.82 * root.scaleFactor).weight(Font.DemiBold).build()
                                }
                            }
                        }

                        IconButton {
                            icon: "close"
                            type: IconButton.Text
                            Layout.preferredWidth: 30 * root.scaleFactor
                            Layout.preferredHeight: 30 * root.scaleFactor
                            onClicked: TodoData.remove(modelData.id)
                        }
                    }
                }

            }

            ColumnLayout {
                anchors.centerIn: parent
                visible: taskList.count === 0
                spacing: 6 * root.scaleFactor
                MaterialIcon {
                    Layout.alignment: Qt.AlignHCenter
                    text: "task_alt"
                    color: Colours.palette.m3primary
                    fontStyle: Tokens.font.icon.builders.extraLarge.scale(1.2 * root.scaleFactor).build()
                }
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: "今天还没有安排"
                    color: Colours.palette.m3onSurface
                    font: Tokens.font.clock.size(Tokens.font.title.small.pointSize * 0.9 * root.scaleFactor).weight(Font.DemiBold).build()
                }
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: "在下方写下第一件待办"
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.clock.size(Tokens.font.body.small.pointSize * 0.88 * root.scaleFactor).build()
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small * root.scaleFactor

            StyledTextField {
                id: taskInput
                Layout.fillWidth: true
                Layout.preferredHeight: 50 * root.scaleFactor
                verticalPadding: 7 * root.scaleFactor
                placeholderText: "写下一个待办…"
                selectByMouse: true
                onAccepted: root.addTask()
            }

            ButtonBase {
                Layout.preferredWidth: 100 * root.scaleFactor
                Layout.preferredHeight: 46 * root.scaleFactor
                implicitWidth: 100 * root.scaleFactor
                implicitHeight: 46 * root.scaleFactor
                type: root.timeEnabled ? ButtonBase.Tonal : ButtonBase.Text
                inactiveColour: root.timeEnabled ? Colours.palette.m3secondaryContainer : "transparent"
                inactiveOnColour: root.timeEnabled ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurfaceVariant
                activeColour: Colours.palette.m3primaryContainer
                activeOnColour: Colours.palette.m3onPrimaryContainer
                onClicked: {
                    root.timeEnabled = !root.timeEnabled;
                    root.timePickerOpen = root.timeEnabled;
                }

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 4 * root.scaleFactor
                    MaterialIcon {
                        text: root.timeEnabled ? "alarm" : "notifications_off"
                        color: parent.parent.onColour
                        fontStyle: Tokens.font.icon.builders.small.scale(root.scaleFactor).build()
                    }
                    StyledText {
                        text: root.timeEnabled ? root.formattedTime() : "不提醒"
                        color: parent.parent.onColour
                        font: Tokens.font.clock.size(Tokens.font.body.small.pointSize * root.scaleFactor).weight(Font.DemiBold).build()
                    }
                }
            }

            ButtonBase {
                id: addButton
                Layout.preferredWidth: 46 * root.scaleFactor
                Layout.preferredHeight: 46 * root.scaleFactor
                implicitWidth: 46 * root.scaleFactor
                implicitHeight: 46 * root.scaleFactor
                radius: Tokens.rounding.large * root.scaleFactor
                type: ButtonBase.Filled
                inactiveColour: Colours.palette.m3primary
                inactiveOnColour: Colours.palette.m3onPrimary
                activeColour: Colours.palette.m3primary
                activeOnColour: Colours.palette.m3onPrimary
                scale: pressed ? 0.88 : 1
                onClicked: root.addTask()

                MaterialIcon {
                    anchors.centerIn: parent
                    text: "add"
                    color: addButton.onColour
                    fontStyle: Tokens.font.icon.builders.medium.scale(root.scaleFactor).build()
                }

                Behavior on scale {
                    NumberAnimation {
                        duration: addButton.pressed ? 80 : 260
                        easing.type: addButton.pressed ? Easing.OutQuad : Easing.OutBack
                        easing.overshoot: 2.1
                    }
                }
            }
        }

        StyledRect {
            Layout.alignment: Qt.AlignRight
            visible: root.timePickerOpen
            Layout.preferredWidth: 186 * root.scaleFactor
            Layout.preferredHeight: visible ? 96 * root.scaleFactor : 0
            radius: Tokens.rounding.large * root.scaleFactor
            color: Qt.alpha(Colours.palette.m3surfaceContainerHigh, 0.88)
            border.color: Qt.alpha(Colours.palette.m3outlineVariant, 0.34)
            border.width: 1 * root.scaleFactor

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 7 * root.scaleFactor
                anchors.rightMargin: 4 * root.scaleFactor
                spacing: 2 * root.scaleFactor

            Tumbler {
                id: hourTumbler
                model: 24
                currentIndex: root.selectedHour
                visibleItemCount: 3
                wrap: true
                flickDeceleration: 9000
                Layout.preferredWidth: 58 * root.scaleFactor
                Layout.preferredHeight: 88 * root.scaleFactor
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
                    color: hourTumbler.currentIndex === index ? Colours.palette.m3onSurface : Qt.alpha(Colours.palette.m3onSurface, 0.42)
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
                currentIndex: root.selectedMinute
                visibleItemCount: 3
                wrap: true
                flickDeceleration: 9000
                Layout.preferredWidth: 58 * root.scaleFactor
                Layout.preferredHeight: 88 * root.scaleFactor
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
                    color: minuteTumbler.currentIndex === index ? Colours.palette.m3onSurface : Qt.alpha(Colours.palette.m3onSurface, 0.42)
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    font: Tokens.font.clock.size(Tokens.font.title.small.pointSize * root.scaleFactor).weight(Font.DemiBold).build()
                }
            }

            ButtonBase {
                implicitWidth: 38 * root.scaleFactor
                implicitHeight: 38 * root.scaleFactor
                Layout.preferredWidth: implicitWidth
                Layout.preferredHeight: implicitHeight
                type: ButtonBase.Text
                inactiveOnColour: Colours.palette.m3onSurfaceVariant
                activeOnColour: Colours.palette.m3onSurface
                onClicked: root.timePickerOpen = false
                MaterialIcon {
                    anchors.centerIn: parent
                    text: "check"
                    color: parent.onColour
                    fontStyle: Tokens.font.icon.builders.small.scale(root.scaleFactor).build()
                }
            }
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.preferredHeight: visible ? implicitHeight : 0
            visible: root.statusText !== ""
            text: root.statusText
            color: Colours.palette.m3error
            font: Tokens.font.clock.size(Tokens.font.body.small.pointSize * 0.82 * root.scaleFactor).build()
        }
    }
}
