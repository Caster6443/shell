import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.lockcosmos
import qs.services as CaelestiaServices
import qs.modules.nexus.common

PageBase {
    id: root
    title: "锁屏"
    property bool previewOpen: false
    property string previewStyle: "cosmos"
    readonly property int lightStyleIndex: Math.max(0, styleIds.indexOf(LockStyleSettings.lightStyle))
    readonly property int darkStyleIndex: Math.max(0, styleIds.indexOf(LockStyleSettings.darkStyle))

    readonly property list<string> styleIds: ["cosmos", "enso"]
    readonly property list<MenuItem> styles: [
        MenuItem { text: "宇宙 · 星界" },
        MenuItem { text: "侘寂 · 圆相" }
    ]
    readonly property list<string> styleNames: [
        "宇宙 · 星界",
        "侘寂 · 圆相"
    ]
    readonly property list<string> styleDescriptions: [
        "动态星空、星座密码反馈与 Caelestia 信息面板。",
        "动态墨圈与和纸背景，显示中文日期、节气、天气和媒体信息。"
    ]

    function openPreview() {
        if (previewStyle === "enso")
            previewContext.resetPreview();
        previewOpen = true;
        loadStyle(fullPreview, previewStyle, false);
    }

    function sourceFor(id) {
        if (id === "enso") return Qt.resolvedUrl("themes/wabisabi/WabisabiSurface.qml");
        return Qt.resolvedUrl("CosmosLockScreen.qml");
    }

    function loadStyle(target, id, still) {
        if (id === "cosmos") {
            target.setSource(root.sourceFor(id), {
                "lock": previewLock,
                "pam": previewPam,
                "previewOnly": true,
                "safePreview": true
            });
        } else {
            target.setSource(root.sourceFor(id), {
                "ctx": previewContext,
                "shot": CaelestiaServices.Wallpapers.current,
                "shown": !still,
                "still": still,
                "previewOnly": true,
                "minScale": still ? 0.35 : 0.7
            });
        }
    }

    LockStylePreviewLock { id: previewLock }
    LockStylePreviewPam { id: previewPam }
    LockStyleContext {
        id: previewContext
        lock: previewLock
        pam: previewPam
    }

    Item {
        width: 0
        height: 0

        Connections {
            target: previewContext
            function onPreviewEscape() { root.previewOpen = false; }
            function onGranted() {
                if (root.previewStyle === "enso") unlockCloseTimer.restart();
            }
        }

        Timer {
            id: unlockCloseTimer
            interval: 1800
            onTriggered: root.previewOpen = false
        }
    }

    onPreviewOpenChanged: if (!previewOpen) unlockCloseTimer.stop()

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        SectionHeader { first: true; text: "外观" }
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 64
            radius: Tokens.rounding.large
            color: CaelestiaServices.Colours.tPalette.m3surfaceContainerHigh
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Tokens.padding.large
                anchors.rightMargin: Tokens.padding.large
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    StyledText { text: "按主题切换锁屏"; font: Tokens.font.body.medium }
                    StyledText {
                        text: "浅色：%1 · 深色：%2".arg(root.styleNames[root.lightStyleIndex]).arg(root.styleNames[root.darkStyleIndex])
                        color: CaelestiaServices.Colours.palette.m3outline
                        font: Tokens.font.body.small
                    }
                }
                StyledText {
                    text: CaelestiaServices.Colours.currentLight ? "浅色主题" : "深色主题"
                    color: CaelestiaServices.Colours.palette.m3primary
                    font: Tokens.font.body.medium
                }
            }
        }
        SelectRow {
            first: true
            last: true
            label: "预览样式"
            subtext: ""
            menuItems: root.styles
            active: root.styles[root.styleIds.indexOf(root.previewStyle)]
            onSelected: item => {
                root.previewStyle = root.styleIds[root.styles.indexOf(item)];
                root.loadStyle(thumbnail, root.previewStyle, true);
            }
        }
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(380, width * 0.5625)
            Layout.topMargin: Tokens.padding.large
            radius: Tokens.rounding.large
            color: CaelestiaServices.Colours.tPalette.m3surfaceContainerHigh
            border.color: Qt.alpha(CaelestiaServices.Colours.palette.m3primary, 0.55)
            border.width: 1
            clip: true

            Loader {
                id: thumbnail
                anchors.fill: parent
                anchors.margins: 1
            }
            Component.onCompleted: root.loadStyle(thumbnail, root.previewStyle, true)

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 72
                gradient: Gradient {
                    GradientStop { position: 0; color: "transparent" }
                    GradientStop { position: 1; color: "#bb10121a" }
                }
            }
            Column {
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                anchors.leftMargin: Tokens.padding.large
                anchors.bottomMargin: Tokens.padding.medium
                spacing: 3
                StyledText {
                    text: root.styleNames[root.styleIds.indexOf(root.previewStyle)]
                    font: Tokens.font.title.medium
                    color: "white"
                }
                StyledText {
                    text: "点击预览图查看锁屏动画效果"
                    font: Tokens.font.body.small
                    color: "#d8d8e0"
                }
            }
            MaterialIcon {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.rightMargin: Tokens.padding.large
                anchors.bottomMargin: Tokens.padding.medium
                text: "open_in_full"
                color: "white"
                fontStyle: Tokens.font.icon.large
            }
            MouseArea {
                z: 1
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.openPreview()
            }
        }
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.padding.medium
            spacing: Tokens.spacing.medium

            ButtonBase {
                Layout.fillWidth: true
                implicitWidth: 220
                implicitHeight: 54
                isRound: true
                inactiveColour: CaelestiaServices.Colours.palette.m3primaryContainer
                inactiveOnColour: CaelestiaServices.Colours.palette.m3onPrimaryContainer
                onClicked: LockStyleSettings.setStyle("light", root.previewStyle)

                RowLayout {
                    anchors.centerIn: parent
                    spacing: Tokens.spacing.small
                    MaterialIcon { text: LockStyleSettings.lightStyle === root.previewStyle ? "check" : "light_mode"; color: parent.parent.onColour; fontStyle: Tokens.font.icon.medium }
                    StyledText { text: LockStyleSettings.lightStyle === root.previewStyle ? "浅色主题 · 已设置" : "设为浅色主题锁屏"; color: parent.parent.onColour; font: Tokens.font.body.medium }
                }
            }

            ButtonBase {
                Layout.fillWidth: true
                implicitWidth: 220
                implicitHeight: 54
                isRound: true
                inactiveColour: CaelestiaServices.Colours.palette.m3primaryContainer
                inactiveOnColour: CaelestiaServices.Colours.palette.m3onPrimaryContainer
                onClicked: LockStyleSettings.setStyle("dark", root.previewStyle)

                RowLayout {
                    anchors.centerIn: parent
                    spacing: Tokens.spacing.small
                    MaterialIcon { text: LockStyleSettings.darkStyle === root.previewStyle ? "check" : "dark_mode"; color: parent.parent.onColour; fontStyle: Tokens.font.icon.medium }
                    StyledText { text: LockStyleSettings.darkStyle === root.previewStyle ? "深色主题 · 已设置" : "设为深色主题锁屏"; color: parent.parent.onColour; font: Tokens.font.body.medium }
                }
            }
        }
        Item {
            Layout.preferredWidth: 0
            Layout.preferredHeight: 0
            implicitWidth: 0
            implicitHeight: 0

            FloatingWindow {
                id: previewWindow
                title: "caelestia-lock-preview"
                visible: root.previewOpen
                fullscreen: true
                color: "#05060b"
                implicitWidth: Screen.width
                implicitHeight: Screen.height

                Loader {
                    id: fullPreview
                    anchors.fill: parent
                    active: root.previewOpen
                }
                MouseArea {
                    z: 10
                    anchors.fill: parent
                    enabled: root.previewOpen && root.previewStyle === "cosmos"
                }
                Shortcut {
                    context: Qt.ApplicationShortcut
                    sequence: "Escape"
                    enabled: root.previewOpen
                    onActivated: root.previewOpen = false
                }
            }
        }
    }
}
