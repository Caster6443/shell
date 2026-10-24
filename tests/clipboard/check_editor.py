"""Exercise the actual editor with isolated cliphist; replace only desktop copy with a byte capture."""
from pathlib import Path
import tempfile, subprocess, os, json

source = Path(__file__).resolve().parents[2] / 'console/ClipboardEditor.qml'
with tempfile.TemporaryDirectory(prefix='clip-edit-') as temp:
    p = Path(temp)
    (p / 'rt').mkdir(mode=0o700)
    s = source.read_text().replace('import qs.overview', '')
    s = s.replace('M3Palette.', 'root.testPalette.').replace('ClipboardData.', 'root.testData.')
    s = s.replace('id: root', '''id: root
    property var testPalette: ({m3surface: "#202020", m3onSurface: "white", m3error: "red"})
    property var testData: ({shq: s => "'" + s.replace(/'/g, "'\\\\''") + "'", refresh: () => {}})''', 1)
    s = s.replace("['cliphist','store']", repr(['cliphist', '-db-path', str(p / 'db'), 'store']))
    s = s.replace("subprocess.run(['wl-copy','--type','text/plain;charset=utf-8'],input=data,check=True)", f"open({str(p / 'copied')!r},'wb').write(data)")
    s = s.replace('" | cliphist decode"', '" | cliphist -db-path ' + str(p / 'db') + ' decode"')
    (p / 'ClipboardEditor.qml').write_text(s)
    original = '原文\n第二行\n'
    edited = '修改后\n$HOME `literal` \' 引号\n末尾换行\n'
    clip = ['cliphist', '-db-path', str(p / 'db')]
    subprocess.run(clip + ['store'], input=original.encode(), check=True)
    raw = subprocess.check_output(clip + ['list']).decode().splitlines()[0]
    (p / 'shell.qml').write_text('''import QtQuick
import Quickshell
ShellRoot {
 Item {
 width: 700; height: 500
 function find(item) {
  if(item.toString().indexOf("TextArea") >= 0) return item;
  for(let c of item.children || []) { let r=find(c); if(r) return r; }
  return null;
 }
 ClipboardEditor { id: edit; onSaved: { console.log("EDITOR_SAVE_PASS"); Qt.quit(); } }
 Timer { interval: 100; running: true; onTriggered: edit.open({raw: ''' + json.dumps(raw) + ''', isImage: false}) }
 Timer {
  interval: 50; running: true; repeat: true
  onTriggered: {
   if(edit.visible && !edit.loading) {
    let text=parent.find(edit);
    if(!text || text.text !== ''' + json.dumps(original) + ''') {console.log("DECODE_MISMATCH");Qt.quit();return;}
    text.text=''' + json.dumps(edited) + '''; stop(); edit.save();
   }
  }
 }
 Timer {interval: 5000; running: true; onTriggered: {console.log("CHECK_TIMEOUT");Qt.quit();} }
 }
}''')
    env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software', XDG_RUNTIME_DIR=str(p / 'rt'))
    result = subprocess.run(['qs', '-p', str(p), '--no-color'], env=env, text=True, capture_output=True, timeout=10)
    assert 'EDITOR_SAVE_PASS' in result.stdout + result.stderr, result.stdout + result.stderr
    assert (p / 'copied').read_bytes() == edited.encode()
    lines = subprocess.check_output(clip + ['list']).decode().splitlines()
    assert len(lines) == 2, lines
    assert subprocess.check_output(clip + ['decode'], input=lines[0].encode()) == edited.encode()
    assert subprocess.check_output(clip + ['decode'], input=lines[1].encode()) == original.encode()
    print('PASS: full decode, exact multiline stdin, isolated history saved, original retained')
