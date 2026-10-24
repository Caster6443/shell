#!/usr/bin/env python3
"""Render the real AiSettings page to a PNG for visual review (offscreen, mock palette).

Usage: python tests/ai/shot_ai_settings.py [output.png] [--edit|--usage|--empty]
Seeds one service and enables translation; no network, no real credentials.
"""
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

BASE = next(parent for parent in Path(__file__).resolve().parents if (parent/'aibackend/Backend.py').is_file())
DEPLOYED = Path.home()/'.config/quickshell/caelestia'
arguments = [a for a in sys.argv[1:] if not a.startswith('--')]
OUT = Path(arguments[0]).resolve() if arguments else None

with tempfile.TemporaryDirectory(prefix='caelestia-ai-shot-') as temp:
    t = Path(temp); app = t/'app'; app.mkdir()
    for name in ('config', 'cache', 'state', 'data', 'runtime'):
        (t/name).mkdir(mode=0o700)
    for name in ('services', 'modules/nexus', 'modules/drawers', 'utils'):
        (app/name).mkdir(parents=True)
    (app/'components').symlink_to(DEPLOYED/'components', target_is_directory=True)
    (app/'modules/nexus/common').symlink_to(DEPLOYED/'modules/nexus/common', target_is_directory=True)
    shutil.copy2(DEPLOYED/'modules/nexus/NexusState.qml', app/'modules/nexus/NexusState.qml')
    shutil.copytree(BASE/'aibackend', app/'aibackend')
    (app/'modules/drawers/ContentWindow.qml').write_text('import QtQuick\nimport Quickshell\nFloatingWindow {property Item interactionWrapper}')
    (app/'utils/Placeholder.qml').write_text('import QtQuick\nQtObject {}')
    keys = set()
    for source in [DEPLOYED/'components', DEPLOYED/'modules/nexus/common']:
        for p in source.rglob('*.qml'):
            keys.update(re.findall(r'\bm3\w+', p.read_text()))
    palette = {k: '#e9e4d8' if k.lower().startswith('m3on') else '#353329' for k in keys}
    palette.update(m3primary='#c4d7a3', m3onSurface='#eeeadd', m3onSurfaceVariant='#c1bcaf',
                   m3outline='#9e9b8b', m3error='#ffb4ab')
    scheme=Path.home()/'.local/state/caelestia/scheme.json'
    if '--theme' in sys.argv and scheme.exists():
        for key,value in json.loads(scheme.read_text()).get('colours',{}).items():
            if not key.startswith('term'):palette['m3'+key]=value if value.startswith('#') else '#'+value
    (app/'services/Colours.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { property bool light:false; '
                                            'property var palette:(' + json.dumps(palette) + ');property var tPalette:palette;'
                                            'function layer(c,l){return c;} }')
    (t/'pacman').mkdir()
    env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software', DISPLAY='', WAYLAND_DISPLAY='',
               CAELESTIA_PACMAN_DB=str(t/'pacman'), XDG_CONFIG_HOME=str(t/'config'), XDG_CACHE_HOME=str(t/'cache'),
               XDG_STATE_HOME=str(t/'state'), XDG_DATA_HOME=str(t/'data'), XDG_RUNTIME_DIR=str(t/'runtime'))

    if '--native' in sys.argv:
        env['QT_QPA_PLATFORM']='wayland'
        env['WAYLAND_DISPLAY']=str(Path(os.environ['XDG_RUNTIME_DIR'])/os.environ['WAYLAND_DISPLAY'])
        env['QT_NO_XDG_DESKTOP_PORTAL']='1'
    def backend(payload):
        result = subprocess.run([sys.executable, str(app/'aibackend/Backend.py')],
                                input=json.dumps(payload), capture_output=True, text=True, env=env)
        return json.loads(result.stdout)

    if '--nolimit' in sys.argv:
        backend({'action': 'configure', 'limits': {'enabled': False}})
    if '--empty' not in sys.argv:
        saved = backend({'action': 'saveProfile', 'profile': {'name': 'DeepSeek', 'format': 'openai',
                 'baseUrl': 'https://api.deepseek.com', 'storage': 'file', 'model': 'deepseek-flash'},
                 'apiKey': 'not-a-real-key'})
        backend({'action': 'saveModels', 'profileId': saved['profileId'],
                 'models': ['deepseek-flash', 'deepseek-v4-pro']})
        backend({'action': 'configure', 'enabled': True, 'translation': True})
    test_state=next((v for v in ('running','success','timeout','error') if '--test-'+v in sys.argv), '')
    preview_test = 'pageItem.modelTests='+json.dumps({'deepseek-flash':{'state':test_state,'elapsedMs':1258,'error':'请求超时，未自动重试'}})+';' if test_state else ''
    page = 'AiServiceEditorPage' if '--edit' in sys.argv else 'AiUsagePage' if '--usage' in sys.argv else 'AiSettings'
    background=palette.get('m3surface', '#202119')
    width=720 if '--compact' in sys.argv else 1000
    (app/'shell.qml').write_text(f'''import QtQuick
import QtQuick.Window
import Quickshell
import qs.aibackend
import qs.modules.nexus
import qs.modules.nexus.common
ShellRoot {{
 id: fixture
 property NexusState fixtureState: NexusState {{}}
 FloatingWindow {{
  id: previewWindow; implicitWidth: {width}; implicitHeight: 1500; visible: true; color: "{background}"
  Item {{
   id: stage
   anchors.left: parent.left
   anchors.right: parent.right
   anchors.top: parent.top
   height: Math.min(parent.height, pageItem.contentChild.implicitHeight + 160)
   Rectangle {{ anchors.fill: parent; color: "{background}" }}
   {page} {{ id: pageItem; anchors.fill: parent; nState: fixture.fixtureState }}
  }}
 }}
 Timer {{ interval: 200; running: true; onTriggered: {{
  if (!Ai.loaded) return;
  pageItem.flickable.layer.enabled = false;
  if (pageItem.load && Ai.activeProfile) pageItem.load(Ai.activeProfile);
  {preview_test}
  stop();
  capture.start();
 }} }}
 Timer {{ id: capture; interval: 700; onTriggered: {{
  stage.grabToImage(result => {{
   if ({json.dumps(str(OUT)) if OUT else '""'} && !result.saveToFile({json.dumps(str(OUT)) if OUT else '""'})) {{ console.error("SAVE_FAILED"); Qt.exit(1); }}
   console.log("SHOT_OK", pageItem.height); Qt.exit(0);
  }});
 }} }}
 Timer {{ interval: 8000; running: true; onTriggered: {{ console.error("TIMEOUT"); Qt.exit(1); }} }}
}}
''')
    process = subprocess.run(['dbus-run-session', '--', 'qs', '-p', str(app), '--no-color'],
                             env=env, capture_output=True, text=True, timeout=30)
    output = process.stdout + process.stderr
    if 'SHOT_OK' not in output:
        print(output)
        sys.exit(1)
    print('SHOT_OK', OUT if OUT else '(no file)')
