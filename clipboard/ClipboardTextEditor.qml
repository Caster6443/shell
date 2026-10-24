pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import Quickshell.Io
import Caelestia.Config
import qs.console
import qs.overview

// One document for both display and editing. Focus never reloads its contents.
Item {
    id: root
    anchors.fill: parent
    property var entry: null
    property var documentEntry: null
    property string loadedRaw: ""
    property string originalText: ""
    property bool loaded: false
    property bool loading: false
    property bool saving: false
    property bool copying: false
    property string error: ""
    readonly property bool dirty: loaded && editor.text !== originalText
    readonly property bool hasFocus: editor.activeFocus
    readonly property bool canSave: loaded && dirty && !loading && !saving && !copying && editor.text.length > 0
    readonly property int textLength: editor.text.length
    readonly property string text: editor.text
    signal saved()
    signal copied()
    signal focusSearchRequested()
    onEntryChanged: loadEntry()
    function loadEntry(): void {
        const raw = entry && !entry.isImage ? String(entry.raw) : "";
        if (raw === loadedRaw && (loaded || loading)) return;
        decode.running = false;
        loadedRaw = raw;
        documentEntry = raw ? entry : null;
        loaded = false;
        loading = false;
        error = "";
        originalText = "";
        editor.text = "";
        editor.focus = false;
        scroll.contentItem.contentY = 0;
        if (raw === "") return;
        loading = true;
        decode.command = ["bash", "-o", "pipefail", "-c", "printf '%s' " + ClipboardData.shq(raw) + " | cliphist decode"];
        decode.running = true;
    }
    function cancel(): void {
        if (saving || copying) return;
        editor.text = originalText;
        error = "";
        editor.focus = false;
        root.focusSearchRequested();
    }
    function save(): void {
        if (!canSave) return;
        saving = true;
        error = "";
        saveProc.stdinEnabled = true;
        saveProc.running = true;
    }
    function copy(): void {
        if (!loaded || loading || saving || copying) return;
        copying = true;
        error = "";
        copyProc.stdinEnabled = true;
        copyProc.running = true;
    }
    ScrollView {
        id: scroll
        anchors.fill: parent
        clip: true
        TextArea {
            id: editor
            objectName: "clipboardInlineText"
            width: scroll.availableWidth
            readOnly: !root.loaded || root.loading || root.saving || root.copying
            selectByMouse: true
            persistentSelection: true
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
        stdout: StdioCollector {
            onStreamFinished: {
                if (!root.loading) return;
                root.originalText = this.text;
                editor.text = this.text;
            }
        }
        onExited: (code, status) => {
            root.loading = false;
            root.loaded = code === 0;
            if (code !== 0) root.error = "读取失败，请重新选择此条目";
            // No forceActiveFocus: selection and focus are independent.
        }
    }
    Process {
        id: saveProc
        command: ["python", "-c", "import sys,subprocess; data=sys.stdin.buffer.read(); subprocess.run(['cliphist','store'],input=data,check=True); subprocess.run(['wl-copy','--type','text/plain;charset=utf-8'],input=data,check=True)"]
        onStarted: { saveProc.write(editor.text); saveProc.stdinEnabled = false; }
        onExited: (code, status) => {
            root.saving = false;
            if (code !== 0) { root.error = "保存失败，原记录未改动"; return; }
            root.originalText = editor.text;
            editor.focus = false;
            root.focusSearchRequested();
            root.saved();
        }
    }
    Process {
        id: copyProc
        command: ["wl-copy", "--type", "text/plain;charset=utf-8"]
        onStarted: { copyProc.write(editor.text); copyProc.stdinEnabled = false; }
        onExited: (code, status) => {
            root.copying = false;
            if (code !== 0) { root.error = "复制失败，请重试"; return; }
            root.copied();
        }
    }
}
