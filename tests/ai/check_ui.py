#!/usr/bin/env python3
"""Actual theme components + actual AI worker, private XDG/D-Bus, no API calls."""
from pathlib import Path
import json, os, re, shutil, subprocess, sys, tempfile
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
import threading, time
class MockHandler(BaseHTTPRequestHandler):
 def log_message(self,*args):pass
 def do_GET(self):
  self.send_response(200);self.end_headers();self.wfile.write(b'{"data":[{"id":"fixture-model"}]}')
 def do_POST(self):
  payload=json.loads(self.rfile.read(int(self.headers["Content-Length"])))
  if "SLOW" in json.dumps(payload):time.sleep(2)
  self.send_response(200);self.end_headers()
  try:self.wfile.write(b'{"choices":[{"message":{"content":"OK"}}],"usage":{"prompt_tokens":5,"completion_tokens":1}}')
  except BrokenPipeError:pass
server=ThreadingHTTPServer(("127.0.0.1",0),MockHandler)
threading.Thread(target=server.serve_forever,daemon=True).start()
BASE=next(parent for parent in Path(__file__).resolve().parents if (parent/'aibackend/Backend.py').is_file())
DEPLOYED=Path.home()/'.config/quickshell/caelestia'
with tempfile.TemporaryDirectory(prefix='caelestia-ai-ui-') as temp:
 t=Path(temp);app=t/'app';app.mkdir()
 for name in ('config','cache','state','data','runtime'):(t/name).mkdir(mode=0o700)
 for name in ('services','modules/nexus','modules/drawers','utils'):(app/name).mkdir(parents=True)
 (app/'components').symlink_to(DEPLOYED/'components',target_is_directory=True)
 (app/'modules/nexus/common').symlink_to(DEPLOYED/'modules/nexus/common',target_is_directory=True)
 shutil.copy2(DEPLOYED/'modules/nexus/NexusState.qml',app/'modules/nexus/NexusState.qml')
 shutil.copytree(BASE/'aibackend',app/'aibackend')
 (app/'modules/drawers/ContentWindow.qml').write_text('import QtQuick\nimport Quickshell\nFloatingWindow {property Item interactionWrapper}')
 (app/'utils/Placeholder.qml').write_text('import QtQuick\nQtObject {}')
 keys=set()
 for source in [DEPLOYED/'components',DEPLOYED/'modules/nexus/common']:
  for p in source.rglob('*.qml'):keys.update(re.findall(r'\bm3\w+',p.read_text()))
 palette={k:'#e9e4d8' if k.lower().startswith('m3on') else '#353329' for k in keys}
 palette.update(m3primary='#c4d7a3',m3onSurface='#eeeadd',m3onSurfaceVariant='#c1bcaf',m3outline='#9e9b8b',m3error='#ffb4ab')
 (app/'services/Colours.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { property bool light:false; property var palette:('+json.dumps(palette)+');property var tPalette:palette;function layer(c,l){return c;} }')
 (app/'shell.qml').write_text('''import QtQuick
import QtQuick.Window
import Quickshell
import qs.aibackend
import qs.modules.nexus
ShellRoot {
 id:fixture
 property NexusState fixtureState:NexusState{}
 FloatingWindow {
  implicitWidth:960;implicitHeight:1000;visible:true;color:"#202119"
  AiServiceEditorPage {id:settings;x:24;y:20;width:parent.width-48;height:parent.height-40;nState:fixture.fixtureState}
  AiSettings {id:mainPage;visible:false;width:900;height:900;nState:fixture.fixtureState}
 }
 Timer {interval:100;running:true;repeat:true;onTriggered:{
  if (!Ai.loaded) return;
  settings.flickable.layer.enabled=false;
  stop();
  if (Ai.state.enabled || Ai.state.profiles.length || Ai.state.todayRequests) {console.error("DEFAULTS_FAILED");Qt.exit(1);return;}
  settings.serviceName="Local fixture";settings.baseUrl="MOCK_URL";settings.storage="file";settings.modelId="";settings.fetchAfterSave=false;
  settings.save();savedProbe.start();
 }}
 Timer {id:savedProbe;interval:100;repeat:true;onTriggered:{
  if(settings.pending)return;stop();
  if(!settings.editingId || Ai.state.profiles.length!==1 || Ai.state.profiles[0].hasKey){console.error("SAVE_FAILED",settings.message);Qt.exit(1);return;}
  if(Ai.state.enabled || Ai.state.todayRequests){console.error("UNEXPECTED_REQUEST");Qt.exit(1);return;}
  if(!Ai.state.profiles[0].model){settings.selectModel("fixture-model");start();return;}
  if(Ai.state.profiles[0].model!=="fixture-model"){console.error("MODEL_PERSIST_FAILED");Qt.exit(1);return;}
  capture.start();
 }}
 Timer {id:capture;interval:500;onTriggered:{
  settings.grabToImage(result=>{
   if(DESTINATION && !result.saveToFile(DESTINATION)){Qt.exit(1);return;}
   console.log("AI_UI_PASS",settings.width,settings.height,Ai.state.todayRequests);
   workflow.start();
  });
 }}
 property int stage:0
 property int callsBefore:0
 property string task:""
 property string statusTask:""
 Timer {id:workflow;interval:1;onTriggered:{fixture.task=Ai.request("configure",{enabled:true,translation:true});}}
 Timer {id:pickerProbe;interval:120;repeat:true;onTriggered:{
  if(settings.pending)return; stop();
  if(settings.discoveredModels.length!==1){console.error("MODEL_POOL_FAILED");Qt.exit(1);return;}
  settings.modelSearch="fixture";
  if(settings.filteredModels.length!==1){console.error("MODEL_SEARCH_FAILED");Qt.exit(1);return;}
  settings.modelSearch="";
  fixture.stage=2;settings.testSelectedModel();fixture.task=settings.operationId;
  if(settings.modelTests["fixture-model"].state!=="running"){console.error("TEST_SPINNER_FAILED");Qt.exit(1);}
 }}
 Timer {id:testProbe;interval:100;onTriggered:{
  const saved=settings.modelTests["fixture-model"];
  if(saved.state!=="success" || saved.elapsedMs<1){console.error("TEST_RESULT_FAILED");Qt.exit(1);return;}
  settings.recordTestResult({ok:false,code:"timeout",error:"请求超时"});
  if(settings.modelTests["fixture-model"].state!=="timeout"){Qt.exit(1);return;}
  settings.recordTestResult({ok:false,code:"http",error:"认证失败"});
  if(settings.modelTests["fixture-model"].state!=="error"){Qt.exit(1);return;}
  settings.modelTests={"fixture-model":saved};
  fixture.stage=3;fixture.task=Ai.request("translate",{name:"fixture",description:"Example software"});
 }}
 Timer {id:cancelProbe;interval:150;onTriggered:{fixture.statusTask=Ai.request("status",{});Ai.cancel(fixture.task);}}
 Connections {target:Ai;function onCompleted(id,result){
  if(id===fixture.statusTask){
   if(!result.ok || fixture.stage!==6){console.error("CANCEL_QUEUE_FAILED");Qt.exit(1);return;}
   console.log("AI_SERVICE_PASS",Ai.state.todayRequests);Qt.quit();return;
  }
  if(id!==fixture.task)return;
  if(fixture.stage===5){
   if(result.code!=="cancelled"){console.error("CANCEL_FAILED");Qt.exit(1);return;}
   fixture.stage=6;return;
  }
  if(!result.ok){console.error("SERVICE_FAILED",fixture.stage,result.error);Qt.exit(1);return;}
  if(fixture.stage===0){fixture.stage=1;fixture.task=Ai.request("models",{profileId:settings.editingId});}
  else if(fixture.stage===1){
   if(result.models[0]!=="fixture-model"){console.error("MODELS_FAILED");Qt.exit(1);return;}
   settings.run("models",{profileId:settings.editingId});
   fixture.stage=7;pickerProbe.start();
  } else if(fixture.stage===2){
   if(result.text!=="OK"){Qt.exit(1);return;}
   settings.modelSearch="no-such-model";if(settings.filteredModels.length){console.error("MODEL_SEARCH_FILTER_FAILED");Qt.exit(1);return;}settings.modelSearch="";
   testProbe.start();
  } else if(fixture.stage===3){
   fixture.callsBefore=Ai.state.todayRequests;
   fixture.stage=4;fixture.task=Ai.request("translate",{name:"fixture",description:"Example software"});
  } else if(fixture.stage===4){
   if(!result.cached || Ai.state.todayRequests!==fixture.callsBefore){console.error("CACHE_FAILED");Qt.exit(1);return;}
   fixture.stage=5;fixture.task=Ai.request("generate",{source:"cancel-test",messages:[{role:"user",content:"SLOW"}]});cancelProbe.start();
  }
 }}
 Timer {interval:8000;running:true;onTriggered:{console.error("UI_TIMEOUT");Qt.exit(1)}}
}'''.replace('MOCK_URL','http://127.0.0.1:'+str(server.server_port)+'/v1').replace('DESTINATION',json.dumps(str(Path(sys.argv[1]).resolve()) if len(sys.argv)>1 else '')))
 env=dict(os.environ,QT_QPA_PLATFORM='offscreen',QT_QUICK_BACKEND='software',DISPLAY='',WAYLAND_DISPLAY='',
   XDG_CONFIG_HOME=str(t/'config'),XDG_CACHE_HOME=str(t/'cache'),XDG_STATE_HOME=str(t/'state'),XDG_DATA_HOME=str(t/'data'),XDG_RUNTIME_DIR=str(t/'runtime'))
 p=subprocess.run(['dbus-run-session','--','qs','-p',str(app),'--no-color'],env=env,capture_output=True,text=True,timeout=12)
 output=p.stdout+p.stderr
 print(output)
 if p.returncode or ('AI_UI_PASS' not in output or 'AI_SERVICE_PASS' not in output) or any((' WARN ' in line or ' ERROR ' in line) and 'components/controls/Menu.qml[39' not in line and 'This plugin does not support setting window masks' not in line for line in output.splitlines()):sys.exit(1)
