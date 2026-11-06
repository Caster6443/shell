#!/usr/bin/env python3
"""Exercise production wallpaper settings with real config persistence and private XDG."""
from pathlib import Path
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

repo = Path(__file__).resolve().parents[2]
qml_path = os.environ.get('QML_IMPORT_PATH', str(Path.home()/'.local/lib/caelestia-shell-native/qml'))
output = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else None
with tempfile.TemporaryDirectory(prefix='wallpaper-settings-') as temp:
    t = Path(temp); app = t/'app'; app.mkdir()
    for name in ['config/caelestia', 'cache', 'state', 'data', 'runtime']:
        (t/name).mkdir(parents=True, mode=0o700)
    for name in ['services', 'modules/nexus/pages/wallandstyle', 'modules/drawers', 'utils']:
        (app/name).mkdir(parents=True)
    (app/'components').symlink_to(repo/'components', target_is_directory=True)
    (app/'modules/nexus/common').symlink_to(repo/'modules/nexus/common', target_is_directory=True)
    shutil.copy2(repo/'modules/nexus/pages/wallandstyle/WallpaperTransitions.qml', app/'modules/nexus/pages/wallandstyle/WallpaperTransitions.qml')
    (app/'modules/drawers/ContentWindow.qml').write_text('import QtQuick\nimport Quickshell\nFloatingWindow { property Item interactionWrapper }')
    (app/'utils/Placeholder.qml').write_text('import QtQuick\nQtObject {}')
    keys = set()
    for folder in [repo/'components', repo/'modules/nexus/common']:
        for p in folder.rglob('*.qml'): keys.update(re.findall(r'\bm3\w+', p.read_text()))
    palette = {key: '#dce1f0' if key.startswith('m3on') else '#2a2e39' for key in keys}
    palette.update(m3surface='#15171c', m3surfaceContainer='#242832', m3secondaryContainer='#343e59',
                   m3primary='#b8c7f1', m3onPrimary='#1d305f', m3secondary='#bbc6e4', m3onSecondary='#27314b',
                   m3onSurface='#e3e5ee', m3onSurfaceVariant='#bfc3ce', m3outline='#9297a3')
    (app/'services/Colours.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject {property bool light:false;property var palette:('+json.dumps(palette)+');property var tPalette:palette;function layer(c,l){return c;}}')
    (app/'services/Wallpapers.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject {property string current: ""}')
    (t/'config/caelestia/shell.json').write_text(json.dumps({'background': {'wallpaperTransition': 'Random'}}))
    qml = '''import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.modules.nexus.pages.wallandstyle
import qs.components.widgets
ShellRoot {
 id: fixture
 WallpaperImpl {id:backend;source:"";width:300;height:200}
 function require(value, message) { if (!value) throw new Error(message); }
 function find(item,name) { if(item.objectName===name)return item;for(const c of item.children || []){const r=find(c,name);if(r)return r;}return null; }
 FloatingWindow {
  id: window; implicitWidth: 820; implicitHeight: 1120; visible: true; color:"#15171c"
  ColumnLayout { anchors.left:parent.left;anchors.right:parent.right;anchors.top:parent.top;anchors.margins:20
   WallpaperTransitions {id:settings;Layout.fillWidth:true}
  }
 }
 Timer {interval:150;running:true;onTriggered:{
  try {
   fixture.require(settings.selectedKey==="random","Random enum was not loaded");
   fixture.require(settings.chosen.length===27,"Default pool is not all effects");
   fixture.require(fixture.find(settings,"wallpaperRandomRangeSelector").visible,"Random range row hidden");
   settings.selectEffect("iris");
   fixture.require(settings.selectedKey==="iris","Fixed choice not applied");
   fixture.require(!fixture.find(settings,"wallpaperRandomRangeSelector").visible,"Range visible for fixed mode");
   GlobalConfig.background.wallpaperTransitionRandomEffects=["iris","smoke"];
   settings.selectEffect("random");
   fixture.require(settings.chosen.length===2,"Selected pool not retained");
   settings.toggleEffect("smoke");
   fixture.require(settings.chosen.length===1,"Toggle did not update pool");
   settings.toggleEffect("iris");
   fixture.require(settings.chosen.length===1,"Last effect could be removed");
   fixture.require(fixture.find(settings,"wallpaperRandomEffect_iris").disabled,"Last checkbox not disabled");
   fixture.find(settings,"wallpaperRandomSelectAll").clicked();
   fixture.require(settings.chosen.length===27,"Select all failed");
   GlobalConfig.background.wallpaperTransitionRandomEffects=["iris","smoke"];
   let previous = backend.activeTransition;
   for (let i=0;i<100;++i) {
    backend.selectTransition();
    fixture.require(["iris","smoke"].indexOf(backend.activeTransition)>=0,"Backend ignored configured pool");
    fixture.require(backend.activeTransition!==previous,"Backend repeated effect");
    previous=backend.activeTransition;
   }
   GlobalConfig.background.wallpaperTransition=WallpaperTransition.RandomSquares;
   backend.selectTransition();
   fixture.require(backend.activeTransition==="randomSquares","Fixed effect confused with Random");
   GlobalConfig.background.wallpaperTransition=WallpaperTransition.Random;
   fixture.find(settings,"wallpaperRandomRangeSelector").clicked(null);
   fixture.require(settings.rangeOpen,"Range row did not open");
   animationStep.start();
  } catch(e) { console.error("SETTINGS_FAIL",e);Qt.exit(1); }
 }}
 Timer {id:animationStep;interval:50;property int stage:0;onTriggered:{
  try {
   const panel=fixture.find(settings,"rangeContentExpansion");
   const effects=fixture.find(settings,"effectGridExpansion");
   if(stage===0) {
    fixture.require(panel.implicitHeight>0 && panel.implicitHeight<panel.children[0].implicitHeight+Tokens.padding.medium*2,"Range did not animate open");
    interval=800;
   } else if(stage===1) {
    fixture.require(panel.visible && panel.opacity===1,"Range did not finish opening");
    settings.rangeOpen=false;interval=50;
   } else if(stage===2) {
    fixture.require(panel.visible && panel.implicitHeight>0 && !panel.enabled,"Range vanished before close animation");
    settings.rangeOpen=true;settings.effectsOpen=true;interval=50;
   } else if(stage===3) {
    fixture.require(effects.implicitHeight>0 && effects.opacity<1,"Effects did not animate open");
    settings.effectsOpen=false;interval=800;
   } else if(stage===4) {
    fixture.require(!effects.visible && effects.implicitHeight===0,"Effects did not collapse");
    fixture.require(panel.visible && panel.opacity===1,"Interrupted close did not reopen");
    settings.grabToImage(result=>{
     if (DESTINATION && !result.saveToFile(DESTINATION)) {Qt.exit(1);return;}
     console.log("SETTINGS_PASS",settings.chosen.length,settings.selectedKey);
     Qt.quit();
    });
    return;
   }
   stage++;restart();
  } catch(e) {console.error("SETTINGS_FAIL",e);Qt.exit(1);}
 }}
 Timer {interval:8000;running:true;onTriggered:{console.error("TIMEOUT");Qt.exit(1)}}
}
'''.replace('DESTINATION', json.dumps(str(output) if output else ''))
    (app/'shell.qml').write_text(qml)
    env = dict(os.environ, QML_IMPORT_PATH=qml_path, QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software',
               WAYLAND_DISPLAY='', DISPLAY='', XDG_CONFIG_HOME=str(t/'config'), XDG_CACHE_HOME=str(t/'cache'),
               XDG_STATE_HOME=str(t/'state'), XDG_DATA_HOME=str(t/'data'), XDG_RUNTIME_DIR=str(t/'runtime'))
    result = subprocess.run(['qs','-p',str(app)], capture_output=True,text=True,env=env,timeout=15)
    print(result.stdout,result.stderr)
    result.check_returncode()
    assert 'SETTINGS_PASS' in result.stdout + result.stderr
    saved = json.loads((t/'config/caelestia/shell.json').read_text())['background']
    assert saved['wallpaperTransition'] == 'Random', saved
    assert saved['wallpaperTransitionRandomEffects'] == ['iris','smoke'], saved
    assert not re.search(r'(ReferenceError|TypeError|Unable to assign|Binding loop|SETTINGS_FAIL)',result.stdout+result.stderr)
    print('PASS: fixed/random visibility, subset retention, last-choice protection, all, disk persistence, animated expansion/collapse and interrupted reopening')
