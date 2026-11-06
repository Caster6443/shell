"""Exercise production shared content in both host modes with isolated data/editor IO."""
from pathlib import Path
import os,re,subprocess,tempfile
repo=Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix='clipboard-hosts-') as directory:
 p=Path(directory)
 source=(repo/'clipboard/ClipboardContent.qml').read_text()
 source=re.sub(r'^import (qs\.|Caelestia\.).*\n','',source,flags=re.M)
 source=re.sub(r'Tokens\.font\.[^;\n}]+', 'Qt.font({pixelSize:14})',source)
 source=re.sub(r'(?:Colours\.palette|M3Palette|ConsoleMaterialStyle)\.\w+', '"#888888"',source)
 (p/'ClipboardContent.qml').write_text(source)
 (p/'qmldir').write_text('singleton ClipboardData 1.0 ClipboardData.qml\n')
 (p/'ClipboardData.qml').write_text('''pragma Singleton
import QtQuick
QtObject {
 property bool busy:false
 property var entries:[{id:'1',preview:'alpha',meta:'text',isImage:false},{id:'2',preview:'beta',meta:'text',isImage:false}]
 property string previewBusyId:'';property string textBusyId:''
 signal pasteReady()
 function query(text) {return entries.filter(e=>e.preview.includes(text));}
 function ensurePreview(entry) {} function isPinned(entry) {return false;}
 function textFor(entry) {return '';} function refresh() {}
}''')
 (p/'ClipboardTextEditor.qml').write_text('''import QtQuick
Item {
 property var entry:null; property var documentEntry:entry
 property bool dirty:false;property bool hasFocus:false;property bool saving:false
 property bool canSave:false;property bool loading:false;property string error:'';property int textLength:0
 signal focusSearchRequested();signal copied();signal saved()
 function cancel() {dirty=false;hasFocus=false;focusSearchRequested();}
}''')
 (p/'MaterialIcon.qml').write_text('import QtQuick\nText {}')
 (p/'ClipText.qml').write_text('import QtQuick\nText {}')
 (p/'ConsoleText.qml').write_text('import QtQuick\nText {property string textRole:""}')
 (p/'ClipIconButton.qml').write_text('import QtQuick.Controls\nToolButton {property string symbol;property string label;property bool emphasized:false;property bool destructive:false}')
 (p/'RaisedButtonSurface.qml').write_text('import QtQuick\nRectangle {property bool pressed:false;property bool hovered:false;property bool interactive:true}')
 (p/'tst_hosts.qml').write_text('''import QtQuick
import QtQuick.Controls
import QtTest
Item {
 id:host;width:1100;height:700
 property string query:'';property int focusRequests:0;property int closes:0
 ClipboardContent {id:content;width:1000;height:600;showSearch:false;query:host.query
  onFocusSearchRequested:host.focusRequests++
  onCloseRequested:host.closes++
 }
 TestCase {
  name:'SharedClipboardHosts';when:windowShown
  function init(){content.visible=true;host.query='';host.focusRequests=0;host.closes=0;wait(20);}
  function test_external_search_and_selection(){host.query='beta';wait(20);compare(content.selectedClipEntry().id,'2');host.query='no-match';wait(20);compare(content.selectedClipEntry(),null);host.query='alpha';wait(20);compare(content.selectedClipEntry().id,'1');}
  function test_external_focus_delegates(){content.focusSearch();compare(host.focusRequests,1);}
  function test_internal_search_keeps_host_separate(){content.showSearch=true;content.query='beta';wait(20);compare(host.query,'');compare(content.selectedClipEntry().id,'2');content.showSearch=false;}
  function test_hide_clears_confirmation(){content.clipConfirm='delete';content.visible=false;compare(content.clipConfirm,'');}
  function test_paste_closes_only_visible_host(){ClipboardData.pasteReady();compare(host.closes,1);content.visible=false;ClipboardData.pasteReady();compare(host.closes,1);}
 }
}''')
 result=subprocess.run(['/usr/lib/qt6/bin/qmltestrunner','-input',str(p)],env=dict(os.environ,QT_QPA_PLATFORM='offscreen',QT_QUICK_BACKEND='software'),capture_output=True,text=True,timeout=20)
 print(result.stdout,result.stderr)
 raise SystemExit(result.returncode)
