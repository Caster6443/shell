pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import Caelestia.Config
import Quickshell.Io
import qs.overview

Item {
    id: root
    anchors.fill: parent
    z: 20
    visible: false
    property var entry: null
    readonly property bool canSave: !loading && !saving && editor.text.length > 0
    readonly property int textLength: editor.text.length
    property bool loading: false
    property bool saving: false
    property string error: ""
    signal saved()
    function open(entry: var): void {
        if (!entry || entry.isImage || root.saving) return;
        root.entry = entry;
        decode.running = false;
        editor.text = "";
        root.error = "";
        root.loading = true;
        root.visible = true;
        decode.command = ["bash", "-o", "pipefail", "-c", "printf '%s' " + ClipboardData.shq(entry.raw) + " | cliphist decode"];
        decode.running = true;
    }
    function cancel(): void {
        if (root.saving) return;
        decode.running = false;
        root.visible = false;
        editor.text = "";
    }
    function save(): void {
        if (root.loading || root.saving || editor.text.length === 0) return;
        root.error = "";
        root.saving = true;
        saveProc.stdinEnabled = true;
        saveProc.running = true;
    }
    onVisibleChanged: if (!visible && !saving) { decode.running = false; editor.text = ""; }
    // The editable text occupies exactly the existing right-hand preview body.
    ScrollView {
        anchors.fill: parent
        clip: true
        TextArea {
            id: editor
            enabled: !root.loading && !root.saving
            selectByMouse: true
            textFormat: TextEdit.PlainText
            wrapMode: TextEdit.WrapAnywhere
            color: M3Palette.m3onSurface
            font: Tokens.font.body.medium
            renderType: Text.NativeRendering
            padding: 0
            background: null
            Keys.onEscapePressed: event => { root.cancel(); event.accepted = true; }
            Keys.onPressed: event => {
                if ((event.modifiers & Qt.ControlModifier) && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
                    root.save(); event.accepted = true;
                }
            }
        }
    }
    Process {
        id: decode
        stdout: StdioCollector { onStreamFinished: if (root.visible) editor.text = this.text }
        onExited: (code, status) => {
            root.loading = false;
            if (!root.visible) return;
            if (code !== 0) root.error = "读取失败，请取消后重试";
            else Qt.callLater(() => editor.forceActiveFocus());
        }
    }
    Process {
        id: saveProc
        command: ["python", "-c", "import sys,subprocess; data=sys.stdin.buffer.read(); subprocess.run(['cliphist','store'],input=data,check=True); subprocess.run(['wl-copy','--type','text/plain;charset=utf-8'],input=data,check=True)"]
        onStarted: { saveProc.write(editor.text); saveProc.stdinEnabled = false; }
        onExited: (code, status) => {
            root.saving = false;
            if (code !== 0) { root.error = "保存或复制失败，请重试（原记录未改动）"; return; }
            ClipboardData.refresh();
            root.visible = false;
            root.saved();
        }
    }
}
