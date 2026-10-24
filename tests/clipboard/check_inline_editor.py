"""Real inline editor, isolated history and clipboard capture; no user data changes."""
from pathlib import Path
import tempfile,subprocess,os,json
repo=Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix='inline-editor-') as d:
 p=Path(d);(p/'rt').mkdir(mode=0o700)
 source=(repo/'clipboard/ClipboardTextEditor.qml').read_text().replace('import qs.console','').replace('import qs.overview','')
 source=source.replace('M3Palette.m3onSurface','"#eeeeee"').replace('ClipboardData.shq','root.shq')
 source=source.replace('id: root','''id: root
    function shq(s) { return "'" + s.replace(/'/g, "'\\\\''") + "'"; }''',1)
 source=source.replace("['cliphist','store']",repr(['cliphist','-db-path',str(p/'db'),'store']))
 source=source.replace("subprocess.run(['wl-copy','--type','text/plain;charset=utf-8'],input=data,check=True)",f"open({str(p/'copied')!r},'wb').write(data)")
 source=source.replace('" | cliphist decode"','" | cliphist -db-path '+str(p/'db')+' decode"')
 (p/'ClipboardTextEditor.qml').write_text(source)
 original='原文与换行\n'+('完整内容 ' * 50000)+'\n尾部\n';edited='修改后\n$HOME `literal` \' 引号\n末尾换行\n'
 cli=['cliphist','-db-path',str(p/'db')];subprocess.run(cli+['store'],input=original.encode(),check=True)
 raw=subprocess.check_output(cli+['list']).decode().splitlines()[0]
 shell='''import QtQuick
import QtQuick.Controls
import Quickshell
ShellRoot {
 FloatingWindow {
  visible:true;implicitWidth:700;implicitHeight:500;color:"#202020"
  Item {
   id: host; anchors.fill:parent
   property int step: 0
   property var document: null
   property var snapshot: null
   function find(item) {
    if(item.objectName==="clipboardInlineText") return item;
    for(let c of item.children || []) { let r=find(c);if(r)return r; }
    return null;
   }
   function check(ok, message) { if(!ok) { console.log("INLINE_FAIL",message);Qt.quit();return false; } return true; }
   TextField { id: search; visible:false }
   ClipboardTextEditor {
    id: edit
    onFocusSearchRequested: search.forceActiveFocus()
    onSaved: { if(host.check(!edit.dirty && !edit.saving,"saved state")) {console.log("INLINE_PASS");Qt.quit();} }
   }
   Timer { interval:50;running:true;repeat:true
    onTriggered: {
     if(host.step===0) { edit.entry=({id:"1",raw:RAW,isImage:false});host.step=1;return; }
     if(host.step===1 && edit.loaded) {
      if(!host.check(edit.text===ORIGINAL && !edit.dirty && !edit.canSave && !edit.hasFocus,"full load / passive focus"))return;
      const doc=host.find(edit);host.document=doc;
      host.snapshot=({size:doc.font.pixelSize,point:doc.font.pointSize,family:doc.font.family,width:doc.width,height:doc.contentHeight,lines:doc.lineCount});
      doc.forceActiveFocus();host.step=2;return;
     }
     if(host.step===2) {
      const doc=host.document;const before=host.snapshot;
      if(!host.check(edit.hasFocus && edit.text===ORIGINAL && !edit.loading && !edit.dirty,"focus must not reload"))return;
      if(!host.check(doc.font.pixelSize===before.size && doc.font.pointSize===before.point && doc.font.family===before.family && doc.width===before.width && doc.contentHeight===before.height && doc.lineCount===before.lines,"font / wrapping / geometry stable"))return;
      doc.text=EDITED;
      if(!host.check(edit.dirty && edit.canSave,"dirty enables save"))return;
      edit.entry=({id:"1",raw:RAW,isImage:false});
      if(!host.check(edit.text===EDITED && !edit.loading,"same entry refresh keeps draft"))return;
      edit.cancel();
      if(!host.check(edit.text===ORIGINAL && !edit.dirty && !edit.loading,"cancel without decode"))return;
      doc.text=EDITED;edit.save();host.step=3;
     }
    }
   }
   Timer { interval:10000;running:true;onTriggered:{console.log("INLINE_FAIL timeout");Qt.quit();} }
  }
 }
}'''.replace('RAW',json.dumps(raw)).replace('ORIGINAL',json.dumps(original)).replace('EDITED',json.dumps(edited))
 (p/'shell.qml').write_text(shell)
 result=subprocess.run(['qs','-p',str(p),'--no-color'],env=dict(os.environ,QT_QPA_PLATFORM='offscreen',QT_QUICK_BACKEND='software',XDG_RUNTIME_DIR=str(p/'rt')),capture_output=True,text=True,timeout=20)
 output=result.stdout+result.stderr
 assert 'INLINE_PASS' in output and 'INLINE_FAIL' not in output,output
 assert (p/'copied').read_bytes()==edited.encode()
 lines=subprocess.check_output(cli+['list']).decode().splitlines();assert len(lines)==2
 assert subprocess.check_output(cli+['decode'],input=lines[0].encode())==edited.encode()
 assert subprocess.check_output(cli+['decode'],input=lines[1].encode())==original.encode()
 print('PASS: full >256KiB decode, no focus steal, stable font/wrap/geometry on focus, dirty/save, draft retained on same-id refresh, cancel without reload, exact multiline save, original retained')
