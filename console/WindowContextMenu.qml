pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Caelestia.Config
import qs.overview
import qs.components
import qs.services

Popup {
    id: root

    property string address: ""
    required property var targetWindow
    required property var workspaces
    property bool choosingWorkspace: false
    property bool overlayHovered: false
    readonly property bool pointerInsideHost: overlayHovered || menuHover.hovered
    property real pageOffset: 0
    property real pageOpacity: 1
    onChoosingWorkspaceChanged: {
        if (root.opened) pageTransition.restart();
    }
    ParallelAnimation {
        id: pageTransition
        NumberAnimation { target: root; property: "pageOffset"; from: root.choosingWorkspace ? 24 : -24; to: 0; duration: 220; easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "pageOpacity"; from: 0; to: 1; duration: 170; easing.type: Easing.OutCubic }
    }
    property point anchorPosition: Qt.point(6, 6)
    property Item targetPreview: null
    property rect previewRect: Qt.rect(0, 0, 0, 0)
    readonly property color attachmentColour: M3Palette.m3tertiary
    readonly property int gap: 8
    readonly property string attachmentSide: {
        if (!targetPreview) return "none";
        if (previewRect.x + previewRect.width + gap + width <= parent.width - 6) return "right";
        if (previewRect.x - gap - width >= 6) return "left";
        if (previewRect.y - gap - height >= 6) return "above";
        return "below";
    }
    function updatePreviewRect(): void {
        if (!targetPreview || !parent) return;
        const a = targetPreview.mapToItem(parent, 0, 0);
        const b = targetPreview.mapToItem(parent, targetPreview.width, targetPreview.height);
        root.previewRect = Qt.rect(a.x, a.y, b.x - a.x, b.y - a.y);
    }
    Connections {
        target: root.targetPreview
        function onXChanged() { root.updatePreviewRect(); }
        function onYChanged() { root.updatePreviewRect(); }
        function onWidthChanged() { root.updatePreviewRect(); }
        function onHeightChanged() { root.updatePreviewRect(); }
        function onScaleChanged() { root.updatePreviewRect(); }
    }
    onTargetPreviewChanged: updatePreviewRect()
    signal actionRequested(string action, string workspace)
    readonly property color destructiveColour: Colours.palette.m3error

    readonly property var entries: {
        if (!root.choosingWorkspace)
            return [
                { label: "移到工作区", icon: "drive_file_move", action: "workspaces", workspace: "", disabled: false },
                { label: root.targetWindow?.floating ? "改为平铺" : "改为浮动", icon: root.targetWindow?.floating ? "grid_view" : "picture_in_picture", action: "float", workspace: "", disabled: false },
                { label: "关闭窗口", icon: "close", action: "close", workspace: "", disabled: false }
            ];
        return [{ label: "返回窗口操作", icon: "arrow_back", action: "back", workspace: "", disabled: false }].concat(
            root.workspaces.map(item => ({ label: item.label, icon: item.workspace.startsWith("special:") ? "layers" : "desktop_windows",
                action: "move", workspace: item.workspace, disabled: item.workspace === root.targetWindow?.workspace })));
    }

    function showFor(windowAddress: string, position: point): void {
        root.address = windowAddress;
        if (!root.targetWindow)
            return;
        pageTransition.stop();
        root.choosingWorkspace = false;
        root.pageOffset = 0;
        root.pageOpacity = 1;
        root.overlayHovered = false;
        root.anchorPosition = position;
        root.updatePreviewRect();
        root.open();
        menuList.currentIndex = 0;
    }

    function activate(index: int): void {
        const entry = root.entries[index];
        if (!entry || entry.disabled || !root.targetWindow)
            return;
        if (entry.action === "workspaces" || entry.action === "back") {
            root.choosingWorkspace = entry.action === "workspaces";
            menuList.currentIndex = 0;
            menuList.positionViewAtBeginning();
            return;
        }
        root.actionRequested(entry.action, entry.workspace);
        root.close();
    }

    function moveSelection(step: int): void {
        const count = root.entries.length;
        let next = menuList.currentIndex;
        for (let i = 0; i < count; ++i) {
            next = (next + step + count) % count;
            if (!root.entries[next].disabled) {
                menuList.currentIndex = next;
                menuList.positionViewAtIndex(next, ListView.Contain);
                return;
            }
        }
    }

    onTargetWindowChanged: {
        if (visible && !targetWindow)
            close();
    }
    onOpened: menuList.forceActiveFocus()
    onAboutToHide: pageTransition.stop()
    Behavior on height {
        enabled: root.opened
        NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
    }

    width: Math.min(264, parent.width - 12)
    height: Math.min(root.choosingWorkspace ? 380 : 190, parent.height - 12)
    x: Math.max(6, Math.min(attachmentSide === "right" ? previewRect.x + previewRect.width + gap
        : attachmentSide === "left" ? previewRect.x - width - gap
        : attachmentSide === "none" ? anchorPosition.x : previewRect.x + (previewRect.width - width) / 2,
        parent.width - width - 6))
    y: Math.max(6, Math.min(attachmentSide === "above" ? previewRect.y - height - gap
        : attachmentSide === "below" ? previewRect.y + previewRect.height + gap
        : attachmentSide === "none" ? anchorPosition.y : previewRect.y + (previewRect.height - height) / 2,
        parent.height - height - 6))
    transformOrigin: attachmentSide === "right" ? Popup.Left : attachmentSide === "left" ? Popup.Right
        : attachmentSide === "above" ? Popup.Bottom : Popup.Top
    enter: Transition {
        ParallelAnimation {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 170; easing.type: Easing.OutCubic }
            NumberAnimation { property: "scale"; from: 0.90; to: 1; duration: 220; easing.type: Easing.OutCubic }
        }
    }
    exit: Transition {
        ParallelAnimation {
            NumberAnimation { property: "opacity"; to: 0; duration: 120 }
            NumberAnimation { property: "scale"; to: 0.94; duration: 120 }
        }
    }
    padding: 10
    modal: true
    focus: true
    closePolicy: Popup.CloseOnPressOutside
    // Keep the panel's palette and brightness while blocking input behind the menu.
    Overlay.modal: Rectangle {
        id: hostOverlay
        color: "transparent"
        readonly property bool insideHost: {
            const point = overlayHover.point.position;
            const local = hostOverlay.mapToItem(root.parent, point.x, point.y);
            return overlayHover.hovered && local.x >= 0 && local.y >= 0
                && local.x < root.parent.width && local.y < root.parent.height;
        }
        onInsideHostChanged: root.overlayHovered = insideHost
        HoverHandler { id: overlayHover }
    }

    background: Rectangle {
        radius: 14
        color: M3Palette.m3surfaceContainerHigh
        border.color: Qt.alpha(root.attachmentColour, 0.7)
        border.width: 1
        // The diamond shares the surface and outline; its inward half is covered by the menu.
        Rectangle {
            visible: root.attachmentSide !== "none"
            width: 10; height: 10; rotation: 45
            color: parent.color
            border.color: parent.border.color
            border.width: 1
            x: root.attachmentSide === "right" ? -5 : root.attachmentSide === "left" ? parent.width - 5
                : Math.max(18, Math.min(root.previewRect.x + root.previewRect.width / 2 - root.x, parent.width - 18)) - 5
            y: root.attachmentSide === "below" ? -5 : root.attachmentSide === "above" ? parent.height - 5
                : Math.max(18, Math.min(root.previewRect.y + root.previewRect.height / 2 - root.y, parent.height - 18)) - 5
        }
        Rectangle {
            anchors.fill: parent; anchors.margins: 1
            radius: 13; color: parent.color
        }
    }

    contentItem: Item {
        clip: true
        opacity: root.pageOpacity
        transform: Translate { x: root.pageOffset }
        HoverHandler { id: menuHover }
        Item {
            id: header
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 30
            MaterialIcon {
                x: 8; anchors.verticalCenter: parent.verticalCenter
                text: root.choosingWorkspace ? "drive_file_move" : "window"
                color: root.attachmentColour
                fontStyle: Tokens.font.icon.medium
            }
            ConsoleText {
                x: 38; y: 2
                width: parent.width - 46
                height: 24
                text: root.choosingWorkspace ? "移到工作区" : (root.targetWindow?.title || "窗口")
                elide: Text.ElideRight
                color: M3Palette.m3onSurface
                textRole: "body"
                strong: true
            }
            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 1
                color: Qt.alpha(M3Palette.m3outlineVariant, 0.6)
            }
        }

        ListView {
            id: menuList
            anchors.top: header.bottom
            anchors.topMargin: 8
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            clip: true
            model: root.entries
            spacing: 2
            keyNavigationEnabled: false
            ScrollBar.vertical: ScrollBar {}

            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape) {
                    if (root.choosingWorkspace) root.activate(0); else root.close();
                } else if (event.key === Qt.Key_Up || event.key === Qt.Key_Down) {
                    root.moveSelection(event.key === Qt.Key_Up ? -1 : 1);
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                    if (!event.isAutoRepeat) root.activate(menuList.currentIndex);
                }
                // All keys belong to the popup while it is open.
                event.accepted = true;
            }

            delegate: Rectangle {
                id: menuRow
                required property var modelData
                required property int index
                width: menuList.width
                readonly property bool destructive: modelData.action === "close"
                height: destructive ? 46 : 40
                radius: 9
                color: "transparent"
                scale: rowMouse.pressed && !modelData.disabled ? 0.97 : 1
                Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
                opacity: modelData.disabled ? 0.45 : 1

                Rectangle {
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: 4
                    height: 1
                    visible: menuRow.destructive
                    color: Qt.alpha(M3Palette.m3outlineVariant, 0.6)
                }
                Rectangle {
                    y: menuRow.destructive ? 8 : 0
                    width: parent.width
                    height: 38
                    radius: 9
                    color: menuList.currentIndex === menuRow.index
                        ? Qt.alpha(menuRow.destructive ? root.destructiveColour : M3Palette.m3primary, rowMouse.pressed ? 0.24 : 0.14) : "transparent"
                    Behavior on color { ColorAnimation { duration: 110 } }
                }
                MaterialIcon {
                    x: 10
                    y: (parent.height - height) / 2 + (menuRow.destructive ? 4 : 0)
                    text: menuRow.modelData.icon
                    color: menuRow.destructive ? root.destructiveColour : M3Palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.medium
                }
                ConsoleText {
                    objectName: "windowMenuLabel"
                    anchors.fill: parent
                    anchors.topMargin: menuRow.destructive ? 8 : 0
                    anchors.leftMargin: 42
                    anchors.rightMargin: 28
                    text: menuRow.modelData.label
                    elide: Text.ElideRight
                    verticalAlignment: Text.AlignVCenter
                    color: menuRow.destructive ? root.destructiveColour : M3Palette.m3onSurface
                                        textRole: "body"
                }
                MaterialIcon {
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    visible: menuRow.modelData.action === "workspaces" || menuRow.modelData.disabled
                    text: menuRow.modelData.disabled ? "check" : "chevron_right"
                    color: M3Palette.m3onSurfaceVariant
                }
                MouseArea {
                    id: rowMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.AllButtons
                    onEntered: {
                        if (!menuRow.modelData.disabled) menuList.currentIndex = menuRow.index;
                    }
                    onClicked: mouse => {
                        if (mouse.button === Qt.LeftButton) root.activate(menuRow.index);
                    }
                }
            }
        }
    }
}
