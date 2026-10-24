#!/usr/bin/env python3
"""Background pretranslation through a real Quickshell process, fake pacman db, mock HTTP.

No real credentials, no real API, no system package changes.
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
import threading

BASE = next(parent for parent in Path(__file__).resolve().parents if (parent/'aibackend/Backend.py').is_file())
PACKAGES = {'alpha': 'First package', 'beta': 'Second package', 'gamma': 'Third package',
            'delta': 'Fourth package', 'epsilon': 'Fifth package'}
posted = []


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args): pass
    def do_POST(self):
        payload = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        posted.append(payload)
        items = json.loads(payload['messages'][-1]['content'])
        body = json.dumps([f'译文{i}' for i in range(len(items))], ensure_ascii=False)
        self.send_response(200); self.end_headers()
        self.wfile.write(json.dumps({'choices': [{'message': {'content': body}}],
                                     'usage': {'prompt_tokens': 10, 'completion_tokens': 5}}).encode())


server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
threading.Thread(target=server.serve_forever, daemon=True).start()
url = 'http://127.0.0.1:%d/v1' % server.server_port

with tempfile.TemporaryDirectory(prefix='caelestia-pretranslate-') as temp:
    root = Path(temp)
    app = root/'app'; app.mkdir()
    db = root/'pacman'; db.mkdir()
    for name, description in PACKAGES.items():
        entry = db/f'{name}-1.0-1'; entry.mkdir()
        (entry/'desc').write_text(f'%NAME%\n{name}\n\n%DESC%\n{description}\n\n')
    (root/'config').mkdir(); (root/'cache').mkdir(); (root/'state').mkdir()
    (root/'data').mkdir(); (root/'runtime').mkdir(mode=0o700)
    shutil.copytree(BASE/'aibackend', app/'aibackend')
    # Settings pages need the full Nexus component tree; this check only covers the transport.
    for name in ('AiSettings.qml', 'AiServiceEditorPage.qml', 'AiUsagePage.qml'):
        (app/'aibackend'/name).unlink()
    (app/'aibackend/qmldir').write_text('singleton Ai 1.0 Ai.qml\nsingleton Translator 1.0 Translator.qml\n')
    (app/'shell.qml').write_text('''import QtQuick
import Quickshell
import qs.aibackend
ShellRoot {
 id: fixture
 property int stage: 0
 property string cacheId: ""
 Timer { interval: 120; running: true; repeat: true; onTriggered: {
  if (!Ai.loaded) return;
  if (fixture.stage === 0) { if (Translator.total === 5) fixture.stage = 1; return; }
  if (fixture.stage === 1 && Translator.pending === 0 && Translator.done === 5) {
   fixture.stage = 2;
   fixture.cacheId = Ai.request("cachedTranslations", {items: [{name: "alpha", description: "First package"}]});
  }
 }}
 Connections {
  target: Ai
  function onCompleted(requestId, result): void {
   if (fixture.stage !== 2 || requestId !== fixture.cacheId) return;
   if (!result.ok || !result.translations["alpha\\nFirst package"]) { console.error("CACHE_FAILED", JSON.stringify(result)); Qt.exit(1); return; }
   if (Translator.lastError) { console.error("LAST_ERROR", Translator.lastError); Qt.exit(1); return; }
   console.log("PRETRANSLATE_PASS done=" + Translator.done);
   Qt.exit(0);
  }
 }
 Timer { interval: 15000; running: true; onTriggered: { console.error("PRETRANSLATE_TIMEOUT", Translator.total, Translator.pending, Translator.done); Qt.exit(1); } }
}
''')
    env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software', DISPLAY='',
               WAYLAND_DISPLAY='', CAELESTIA_PACMAN_DB=str(db),
               XDG_CONFIG_HOME=str(root/'config'), XDG_CACHE_HOME=str(root/'cache'),
               XDG_STATE_HOME=str(root/'state'), XDG_DATA_HOME=str(root/'data'),
               XDG_RUNTIME_DIR=str(root/'runtime'))
    def backend(payload):
        result = subprocess.run([sys.executable, str(app/'aibackend/Backend.py')],
                                input=json.dumps(payload), capture_output=True, text=True, env=env)
        return json.loads(result.stdout)
    saved = backend({'action': 'saveProfile', 'profile': {'name': 'mock', 'format': 'openai',
                     'baseUrl': url, 'storage': 'file', 'model': 'fixture-model'}, 'apiKey': 'test-not-a-real-key'})
    backend({'action': 'configure', 'enabled': True, 'translation': True,
             'limits': {'minute': 60, 'outputTokens': 1024}})
    process = subprocess.run(['dbus-run-session', '--', 'qs', '-p', str(app), '--no-color'],
                             env=env, capture_output=True, text=True, timeout=25)
    output = process.stdout + process.stderr
    print(output)
    extra = [line for line in output.splitlines()
             if (' WARN ' in line or ' ERROR ' in line)
             and 'does not support setting window masks' not in line
             and 'components/controls/Menu.qml[39' not in line]
    if process.returncode or 'PRETRANSLATE_PASS done=5' not in output or extra or len(posted) != 1:
        print('FAILED return=%s posts=%s extra=%s' % (process.returncode, len(posted), extra), file=sys.stderr)
        sys.exit(1)
    print('PASS: 5 packages pretranslated in one batch through the real singleton')
