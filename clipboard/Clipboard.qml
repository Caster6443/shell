pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import Quickshell.Io
import qs.console
import qs.services
import qs.overview

// Independent window, shared ClipboardData singleton with Console.
Item {
    id: root
    property bool opened: false
    property bool pointerHasEntered: false
    readonly property var results: ClipboardData.query(content.query)
    readonly property color foreground: Colours.palette.m3onSurface
    readonly property color accent: Colours.palette.m3primary
    function show(): void {
        content.query = "";
        content.resetClipSelection();
        root.pointerHasEntered = false;
        root.opened = true;
        content.focusSearch();
        ClipboardData.refresh();
    }
    function choose(entry: var): void {
        if (!entry) return;
        ClipboardData.copy(entry);
        root.opened = false;
    }
    function moveSelection(delta: int): void { content.moveClipSelection(delta); }
    onOpenedChanged: if (!opened) { content.clipConfirm = ""; content.cancelEdit(); }
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
                if (surface.Window.window.active && !content.editing) content.focusSearch();
            }
        }
        Shortcut { sequence: "Escape"; enabled: root.opened; onActivated: { if (content.editing) content.cancelEdit(); else if (content.clipConfirm) content.clipConfirm = ""; else root.opened = false; } }
        Rectangle {
            id: surface
            anchors.fill: parent
            radius: 28
            color: ConsoleStyle.background
            border.color: ConsoleStyle.outline
            border.width: 1
            HoverHandler {
                id: panelHover
                onHoveredChanged: {
                    if (hovered) root.pointerHasEntered = true;
                }
            }
            Timer {
                id: pointerLeaveTimer
                interval: 300
                running: root.opened && root.pointerHasEntered && !panelHover.hovered
                onTriggered: {
                    if (root.opened && root.pointerHasEntered && !panelHover.hovered)
                        root.opened = false;
                }
            }
            ClipboardContent {
                id: content
                anchors.fill: parent
                anchors.margins: 20
                onCloseRequested: root.opened = false
            }
        }
    }
}
