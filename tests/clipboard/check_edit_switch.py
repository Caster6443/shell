"""Real mouse events on each host's actual clipboard row handler, with isolated state."""
from pathlib import Path
import tempfile, subprocess, os
base = Path(__file__).resolve().parents[2]
for relative in ['clipboard/ClipboardContent.qml', 'console/ConsolePanel.qml']:
    source = (base / relative).read_text()
    marker = source.index('id: clipRowMouse')
    start = source.rfind('MouseArea {', 0, marker)
    depth = 0
    for end in range(source.index('{', start), len(source)):
        if source[end] == '{': depth += 1
        elif source[end] == '}':
            depth -= 1
            if depth == 0: break
    area = source[start:end + 1].replace('ClipboardData.', 'root.fakeData.')
    with tempfile.TemporaryDirectory(prefix='clip-switch-') as temp:
        p = Path(temp)
        (p / 'tst_switch.qml').write_text('''import QtQuick
import QtTest
Item {
 id: root; width: 400; height: 200
 readonly property bool editing: clipEditor.visible
 readonly property bool clipEditing: clipEditor.visible
 property int copies: 0; property int pins: 0; property int previews: 0
 property var fakeData: ({ensurePreview: entry => { root.previews++; }, remove: entry => {}})
 readonly property string previewId: clipEditor.visible ? "old" : clipList.currentIndex === 1 ? "new" : "old"
 function copyClipEntry(entry) { copies++; }
 function pasteSelectedClip() { copies++; }
 function toggleSelectedClipPin() { pins++; }
 QtObject { id: clipList; property int currentIndex: 0 }
 QtObject { id: clipRow; property int index: 1; property var modelData: ({id: "new", isImage: false}) }
 Item {
  id: clipEditor; visible: false; property bool saving: false; property string draft: ""
  function cancel() { visible=false; draft=""; }
 }
 Item { id: row; x: 100; y: 60; width: 200; height: 56
 ''' + area + '''
 }
 TestCase {
  name: "EditSwitch"; when: windowShown
  function init() {
   mouseMove(root, 0, 0); clipEditor.saving=false; clipEditor.visible=true; clipEditor.draft="未保存";
   clipList.currentIndex=0; root.copies=0; root.pins=0; root.previews=0;
   clipRow.modelData=({id: "new", isImage: false});
  }
  function test_hover_keeps_draft() {
   mouseMove(row, 30, 20); compare(clipEditor.visible, true); compare(clipEditor.draft, "未保存"); compare(clipList.currentIndex, 0);
  }
  function test_click_cancels_and_previews() {
   mouseClick(row, 30, 20); compare(clipEditor.visible, false); compare(clipEditor.draft, "");
   compare(clipList.currentIndex, 1); compare(root.previewId, "new"); compare(root.previews, 1); compare(root.copies, 0);
  }
  function test_image_switch() {
   clipRow.modelData=({id: "new", isImage: true}); mouseClick(row, 30, 20);
   compare(clipEditor.visible, false); compare(root.previewId, "new"); compare(root.previews, 1); compare(root.copies, 0);
  }
  function test_saving_keeps_target() {
   clipEditor.saving=true; mouseClick(row, 30, 20); compare(clipEditor.visible, true); compare(clipList.currentIndex, 0); compare(root.copies, 0);
  }
  function test_click_current_pastes_immediately() {
   clipEditor.visible=false; clipList.currentIndex=1;
   mouseClick(row, 30, 20); compare(root.copies, 1); compare(root.previews, 0);
  }
  function test_second_click_after_pause_pastes() {
   mouseClick(row, 30, 20); compare(root.copies, 0); compare(root.previews, 1);
   wait(600); mouseClick(row, 30, 20); compare(root.copies, 1); compare(root.previews, 1);
  }
  function test_editing_current_discards_draft_then_pastes() {
   clipList.currentIndex=1; clipEditor.draft="未保存";
   mouseClick(row, 30, 20); compare(root.copies, 1); compare(clipEditor.visible, false); compare(clipEditor.draft, "");
  }
  function test_hover_selects_then_click_pastes() {
   clipEditor.visible=false; mouseMove(root, 40, 140); wait(20); compare(clipRowMouse.containsMouse, false, "mouse left"); compare(root.editing, false, "editing stopped"); mouseMove(row, 40, 25); tryCompare(clipList, "currentIndex", 1);
   mouseClick(row, 40, 25); compare(root.copies, 1); compare(root.previews, 0);
  }
 }
}''')
        result = subprocess.run(['/usr/lib/qt6/bin/qmltestrunner', '-input', temp], env=dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software'), text=True, capture_output=True, timeout=20)
        print(relative, result.stdout, result.stderr)
        if result.returncode: raise SystemExit(result.returncode)
