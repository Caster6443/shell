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
    property point anchorPosition: Qt.point(6, 6)
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
        root.choosingWorkspace = false;
        root.anchorPosition = position;
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

    width: Math.min(264, parent.width - 12)
    height: Math.min(root.choosingWorkspace ? 380 : 212, parent.height - 12)
    x: Math.max(6, Math.min(anchorPosition.x, parent.width - width - 6))
    y: Math.max(6, Math.min(anchorPosition.y, parent.height - height - 6))
    padding: 10
    modal: true
    focus: true
    closePolicy: Popup.CloseOnPressOutside
    // Keep the panel's palette and brightness while blocking input behind the menu.
    Overlay.modal: Rectangle { color: "transparent" }

    background: Rectangle {
        radius: 14
        color: M3Palette.m3surfaceContainerHighest
        border.color: Qt.alpha(M3Palette.m3outline, 0.25)
        border.width: 1
    }

    contentItem: Item {
        Item {
            id: header
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 50
            ConsoleText {
                x: 8; y: 2
                text: root.choosingWorkspace ? "移到工作区" : "窗口操作"
                color: M3Palette.m3onSurfaceVariant
                                textRole: "caption"
            }
            ConsoleText {
                x: 8; y: 21
                width: parent.width - 16
                text: root.targetWindow?.title || "窗口"
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
                        ? Qt.alpha(menuRow.destructive ? root.destructiveColour : M3Palette.m3primary, 0.14) : "transparent"
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
