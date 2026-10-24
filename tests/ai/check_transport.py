#!/usr/bin/env python3
"""Real HTTP transport with mock loopback server, synthetic credentials and private XDG."""
from pathlib import Path
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json, os, subprocess, tempfile, threading
BASE=next(parent for parent in Path(__file__).resolve().parents if (parent/'aibackend/Backend.py').is_file())
requests=[]
class Handler(BaseHTTPRequestHandler):
 def log_message(self,*args):pass
 def do_GET(self):
  requests.append(('GET',self.path,dict(self.headers),None))
  if self.path.startswith('/redirect'):
   self.send_response(302);self.send_header('Location','http://127.0.0.1:'+str(self.server.server_port)+'/must-not-receive-key');self.end_headers();return
  self.send_response(200);self.end_headers();self.wfile.write(json.dumps({'data':[{'id':'mock-model'}]}).encode())
 def do_POST(self):
  body=json.loads(self.rfile.read(int(self.headers['Content-Length'])))
  requests.append(('POST',self.path,dict(self.headers),body))
  data={'choices':[{'message':{'content':'GNOME 桌面外壳'}}], 'usage':{'prompt_tokens':20,'completion_tokens':5}}
  self.send_response(200);self.end_headers();self.wfile.write(json.dumps(data).encode())
server=ThreadingHTTPServer(('127.0.0.1',0),Handler);threading.Thread(target=server.serve_forever,daemon=True).start()
try:
 with tempfile.TemporaryDirectory(prefix='ai-http-') as temp:
  root=Path(temp);env=dict(os.environ)
  for key,sub in [('XDG_CONFIG_HOME','config'),('XDG_STATE_HOME','state'),('XDG_DATA_HOME','data')]:env[key]=str(root/sub)
  def call(action,**kwargs):
   p=subprocess.run(['python3',str(BASE/'aibackend/Backend.py')],input=json.dumps({'action':action,**kwargs})+'\n',env=env,text=True,capture_output=True,timeout=6)
   assert p.returncode==0,(p.returncode,p.stderr)
   assert 'synthetic-http-secret' not in p.stdout+p.stderr
   return json.loads(p.stdout)
  assert not call('status')['status']['enabled']
  profile={'name':'Mock','format':'openai','baseUrl':f'http://127.0.0.1:{server.server_port}/v1','storage':'file','model':'mock-model'}
  saved=call('saveProfile',profile=profile,apiKey='synthetic-http-secret');assert saved['ok'];profile=saved['status']['profiles'][0]
  assert not call('models',profileId=profile['id'])['ok'];assert not requests
  assert call('configure',enabled=True,translation=True)['ok']
  listed=call('models',profileId=profile['id']);assert listed['models']==['mock-model']
  first=call('translate',name='gnome-shell',description='GNOME desktop shell');assert first['text']=='GNOME 桌面外壳';assert not first['cached']
  second=call('translate',name='gnome-shell',description='GNOME desktop shell');assert second['cached'];assert len(requests)==2
  assert requests[0][2]['Authorization']=='Bearer synthetic-http-secret'
  assert requests[1][3]['max_tokens']==256
  status=call('status')['status'];assert status['todayRequests']==2
  assert call('configure',limits={'daily':2})['ok']
  limited=call('generate',messages=[{'role':'user','content':'hello'}]);assert limited['code']=='daily_limit';assert len(requests)==2
  assert call('configure',limits={'daily':100})['ok']
  profile['baseUrl']=f'http://127.0.0.1:{server.server_port}/redirect'
  assert call('saveProfile',profile=profile,apiKey='synthetic-http-secret')['ok']
  redirect=call('models',profileId=profile['id']);assert redirect['code']=='redirect';assert len(requests)==3
  assert all(x[1]!='/must-not-receive-key' for x in requests)
  print('PASS: private subprocess settings; disabled/no network; real model discovery/auth; translation; persistent cache/usage/limit; redirect credential protection')
finally:server.shutdown();server.server_close()
