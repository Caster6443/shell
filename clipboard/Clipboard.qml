pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import Quickshell.Io
import qs.spotlight
import qs.services
import qs.overview

// Independent window, shared ClipboardData singleton with Spotlight.
Item {
    id: root
    property bool opened: false
    property bool hadFocus: false
    readonly property var results: ClipboardData.query(search.text)
    readonly property color foreground: Colours.palette.m3onSurface
    readonly property color accent: Colours.palette.m3primary
    function show(): void {
        search.text = "";
        content.resetClipSelection();
        root.hadFocus = false;
        root.opened = true;
        search.forceActiveFocus();
        ClipboardData.refresh();
    }
    function choose(entry: var): void {
        if (!entry) return;
        ClipboardData.copy(entry);
        root.opened = false;
    }
    function moveSelection(delta: int): void { content.moveClipSelection(delta); }
    onOpenedChanged: if (!opened) content.clipConfirm = ""
    IpcHandler {
        target: "clipboard"
        function toggle(): void { if (root.opened) root.opened = false; else root.show(); }
        function open(): void { root.show(); }
        function close(): void { root.opened = false; }
        function isOpen(): bool { return root.opened; }
    }
    FloatingWindow {
        id: window
        title: "caelestia-clipboard"
        visible: root.opened
        color: "transparent"
        implicitWidth: 960
        implicitHeight: 600
        Connections {
            target: surface.Window.window
            function onActiveChanged(): void {
                if (surface.Window.window.active) {
                    root.hadFocus = true;
                    search.forceActiveFocus();
                } else if (root.opened && root.hadFocus) root.opened = false;
            }
        }
        Shortcut { sequence: "Escape"; enabled: root.opened; onActivated: { if (content.clipConfirm) content.clipConfirm = ""; else root.opened = false; } }
        Rectangle {
            id: surface
            anchors.fill: parent
            radius: 18
            color: Colours.tPalette.m3surfaceContainerHigh
            border.color: Qt.alpha(root.accent, 0.35)
            border.width: 1
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 20
                spacing: 12
                RowLayout {
                    Layout.fillWidth: true
                    Text { text: "剪贴板"; color: root.foreground; font.pixelSize: 20; font.bold: true }
                    Item { Layout.fillWidth: true }
                    Text { text: ClipboardData.busy ? "正在刷新…" : root.results.length + " 条"; color: Qt.alpha(root.foreground, 0.6); font.pixelSize: 12 }
                    ToolButton { text: "✕"; onClicked: root.opened = false }
                }
                TextField {
                    id: search
                    Layout.fillWidth: true
                    placeholderText: "搜索剪贴板历史…"
                    color: root.foreground
                    placeholderTextColor: Qt.alpha(root.foreground, 0.5)
                    font.pixelSize: 15
                    selectByMouse: true
                    background: Rectangle { radius: 10; color: Qt.alpha(root.foreground, 0.06); border.color: search.activeFocus ? root.accent : "transparent" }
                    onTextChanged: content.resetClipSelection()
                    onAccepted: { if (content.clipConfirm) content.confirmClipAction(); else content.copySelectedClip(); }
                    Keys.onDownPressed: root.moveSelection(1)
                    Keys.onUpPressed: root.moveSelection(-1)
                }
                ClipboardContent {
                    id: content
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    query: search.text
                    onCloseRequested: root.opened = false
                }
                Text { text: "↑ ↓ 选择    Enter 复制    Esc 关闭"; color: Qt.alpha(root.foreground, 0.5); font.pixelSize: 12 }
            }
        }
    }
}
