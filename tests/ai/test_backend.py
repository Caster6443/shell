#!/usr/bin/env python3
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from concurrent.futures import ThreadPoolExecutor
import io
import urllib.error

BASE=next(parent for parent in Path(__file__).resolve().parents if (parent/'aibackend/Backend.py').is_file())
spec=importlib.util.spec_from_file_location('backend',BASE/'aibackend/Backend.py')
b=importlib.util.module_from_spec(spec);spec.loader.exec_module(b)

class Response:
    def __init__(self,data):self.data=json.dumps(data).encode()
    def __enter__(self):return self
    def __exit__(self,*args):pass
    def read(self,n):return self.data[:n]

class Tests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.root=Path(self.temp.name)
        b.CONFIG=self.root/'config';b.STATE=self.root/'state';b.DATA=self.root/'data'
        self.pacman=self.root/'pacman';self.pacman.mkdir()
        self.saved_pacman=b.PACMAN_LOCAL;b.PACMAN_LOCAL=self.pacman
        self.calls=[]
        self.saved=b.dispatch({'action':'saveProfile','profile':{'name':'mock','format':'openai','baseUrl':'https://example.invalid/v1','storage':'file','model':'example-model'},'apiKey':'test-private-not-a-real-key'})
        self.pid=self.saved['profileId'];b.dispatch({'action':'configure','enabled':True,'translation':True})
    def tearDown(self):b.PACMAN_LOCAL=self.saved_pacman;self.temp.cleanup()
    def package(self,name,description,explicit=True):
        entry=self.pacman/f'{name}-1.0-1';entry.mkdir(exist_ok=True)
        reason=0 if explicit else 1
        (entry/'desc').write_text(f'%NAME%\n{name}\n\n%VERSION%\n1.0-1\n\n%DESC%\n{description}\n\n%REASON%\n{reason}\n\n')
    def batch(self,size=8):return b.dispatch({'action':'translateBatch','size':size})
    def network(self,data):
        calls=self.calls
        class Opener:
            def open(self,req,timeout):
                calls.append(req);return Response(data)
        return patch.object(b.urllib.request,'build_opener',return_value=Opener())
    def generate(self):return b.dispatch({'action':'generate','source':'test','messages':[{'role':'user','content':'hello'}]})
    def test_credential_private_and_not_public(self):
        raw=json.dumps(b.status());self.assertNotIn('test-private',raw)
        p=b.get_profile(b.config());self.assertEqual(b.read_key(p),'test-private-not-a-real-key')
        self.assertEqual((b.credential_path(p).stat().st_mode&0o777),0o600)
        self.assertEqual((b.DATA/'credentials').stat().st_mode&0o777,0o700)
    def test_endpoint_change_requires_key(self):
        p=dict(b.get_profile(b.config()));p['baseUrl']='https://different.invalid/v1'
        with self.assertRaises(b.Failure):b.save_profile({'profile':p})
        self.assertEqual(b.get_profile(b.config())['baseUrl'],'https://example.invalid/v1')
    def test_url_validation(self):
        for url in ['http://remote.example/v1','https://user:password@host/v1','https://host/v1?api_key=secret','https://host/v1#key','https://host/v1/chat/completions']:
            with self.assertRaises(b.Failure):b.url_base(url)
        self.assertEqual(b.url_base('http://127.0.0.1:1234/v1/'),'http://127.0.0.1:1234/v1')
    def test_disabled_never_calls_network(self):
        b.dispatch({'action':'configure','enabled':False})
        with self.network({}), self.assertRaises(b.Failure):self.generate()
        self.assertEqual(len(self.calls),0)
    def test_openai_request_and_usage(self):
        with self.network({'choices':[{'message':{'content':'hello'}}],'usage':{'prompt_tokens':12,'completion_tokens':3}}):
            result=self.generate()
        self.assertEqual(result['text'],'hello');self.assertEqual(b.status()['usage'][0]['inputTokens'],12)
        req=self.calls[0];self.assertTrue(req.full_url.endswith('/v1/chat/completions'))
        self.assertEqual(req.get_header('Authorization'),'Bearer test-private-not-a-real-key')
        payload=json.loads(req.data);self.assertFalse(payload['stream']);self.assertEqual(payload['max_tokens'],512)
    def test_transport_timeouts_are_distinct(self):
        for error in (TimeoutError(), urllib.error.URLError(TimeoutError())):
            with patch.object(b.urllib.request, 'build_opener') as opener:
                opener.return_value.open.side_effect=error
                with self.assertRaises(b.Failure) as caught:self.generate()
                self.assertEqual(caught.exception.code,'timeout')
            # Remove the failed request cooldown before the second independent case.
            b.STATE.joinpath('usage.sqlite').unlink(missing_ok=True)
    def test_models_and_no_generation(self):
        with self.network({'data':[{'id':'model-a'},{'id':'model-b'}]}):result=b.models({'profileId':self.pid})
        self.assertEqual(result['models'],['model-a','model-b']);self.assertIsNone(self.calls[0].data)
    def test_translation_cache_and_technical_prompt(self):
        request={'action':'translate','name':'gnome-shell','description':'GNOME desktop shell'}
        with self.network({'choices':[{'message':{'content':'GNOME 桌面外壳'}}]}):
            first=b.dispatch(request);second=b.dispatch(request)
        self.assertEqual(first['text'],'GNOME 桌面外壳');self.assertTrue(second['cached']);self.assertEqual(len(self.calls),1)
        self.assertIn('GNOME',json.loads(self.calls[0].data)['messages'][0]['content'])
        self.assertEqual(b.status()['todayRequests'],1)
    def test_cached_translations_reads_existing_cache_without_api_or_key(self):
        request={'action':'translate','name':'gnome-shell','description':'GNOME desktop shell'}
        with self.network({'choices':[{'message':{'content':'GNOME 桌面外壳'}}]}):b.dispatch(request)
        with patch.object(b,'read_key',side_effect=AssertionError('no credential access')), patch.object(b,'http',side_effect=AssertionError('no remote API')):
            result=b.dispatch({'action':'cachedTranslations','items':[{'name':'gnome-shell','description':'GNOME desktop shell'},{'name':'unknown','description':'new'}]})
        self.assertEqual(result['translations'],{'gnome-shell\nGNOME desktop shell':'GNOME 桌面外壳'})
        self.assertEqual(b.status()['todayRequests'],1)
        b.dispatch({'action':'setModel','profileId':self.pid,'model':'different-model'})
        self.assertEqual(b.dispatch({'action':'cachedTranslations','items':[request]})['translations'],{})
    def test_model_change_invalidates_cache(self):
        request={'action':'translate','name':'pkg','description':'Text'}
        with self.network({'choices':[{'message':{'content':'译文'}}]}):
            b.dispatch(request);p=dict(b.get_profile(b.config()));p['model']='other-model';b.save_profile({'profile':p});b.dispatch(request)
        self.assertEqual(len(self.calls),2)
    def test_daily_limit_survives_process_state(self):
        b.dispatch({'action':'configure','limits':{'daily':1}})
        with self.network({'choices':[{'message':{'content':'ok'}}]}):
            self.generate()
            with self.assertRaises(b.Failure) as cm:self.generate()
        self.assertEqual(cm.exception.code,'daily_limit');self.assertEqual(len(self.calls),1)
    def test_limits_can_be_disabled(self):
        b.dispatch({'action':'configure','limits':{'daily':1,'enabled':False}})
        with self.network({'choices':[{'message':{'content':'ok'}}]}):
            for _ in range(3): self.generate()
        self.assertEqual(len(self.calls),3)
        self.assertEqual(b.status()['todayRequests'],3)
        self.assertFalse(b.config()['limits']['enabled'])
        payload=json.loads(self.calls[0].data)
        self.assertEqual(payload['max_tokens'],16384)
        b.dispatch({'action':'configure','limits':{'enabled':True}})
        self.assertEqual(json.loads(json.dumps(b.config()))['limits']['enabled'],True)
    def test_limits_disabled_keeps_explicit_output_cap(self):
        b.dispatch({'action':'configure','limits':{'enabled':False}})
        with self.network({'choices':[{'message':{'content':'ok'}}]}):
            b.dispatch({'action':'generate','messages':[{'role':'user','content':'hi'}],'maxTokens':256})
        self.assertEqual(json.loads(self.calls[0].data)['max_tokens'],256)
    def test_concurrent_reservations_are_atomic(self):
        b.dispatch({'action':'configure','limits':{'daily':1}});cfg=b.config();p=b.get_profile(cfg)
        def reserve(_):
            try:return b.reserve(p,'test','generate',cfg)
            except b.Failure:return None
        with ThreadPoolExecutor(max_workers=4) as executor:results=list(executor.map(reserve,range(4)))
        self.assertEqual(sum(x is not None for x in results),1)
    def test_remote_error_redacted_and_cooldown(self):
        error=urllib.error.HTTPError('https://example.invalid',401,'test-private-not-a-real-key',{},io.BytesIO(b'private body'))
        with patch.object(b.urllib.request.OpenerDirector,'open',side_effect=error):
            with self.assertRaises(b.Failure) as cm:self.generate()
        self.assertNotIn('test-private',str(cm.exception));self.assertEqual(b.status()['todayRequests'],1)
        with self.assertRaises(b.Failure) as cm:b.reserve(b.get_profile(b.config()),'test','generate',b.config())
        self.assertEqual(cm.exception.code,'cooldown')
    def test_no_redirect(self):
        self.assertIsNone(b.NoRedirect().redirect_request(None,None,302,'',{},'https://different.invalid'))
    def test_keyring_uses_stdin_and_no_secret_argv(self):
        p=dict(b.get_profile(b.config()));p['storage']='keyring'
        with patch.object(b.subprocess,'run',return_value=type('P',(),{'returncode':0,'stdout':''})()) as run:
            b.write_key(p,'test-private-key')
        self.assertNotIn('test-private-key',str(run.call_args.args));self.assertEqual(run.call_args.kwargs['input'],'test-private-key')
    def test_keyring_to_file_does_not_delete_new_credential(self):
        p=dict(b.get_profile(b.config()));p['storage']='keyring'
        with patch.object(b,'secret_tool',return_value=''):
            b.save_profile({'profile':p,'apiKey':'old-key'})
            p['storage']='file';b.save_profile({'profile':p,'apiKey':'new-key'})
        self.assertEqual(b.read_key(b.get_profile(b.config())),'new-key')
    def test_gemini_adapter(self):
        p=dict(b.get_profile(b.config()));p['format']='gemini'
        b.save_profile({'profile':p,'apiKey':'new-key'})
        with self.network({'candidates':[{'content':{'parts':[{'text':'ok'}]}}]}):r=self.generate()
        self.assertEqual(r['text'],'ok');req=self.calls[0]
        self.assertEqual(req.get_header('X-goog-api-key'),'new-key');self.assertNotIn('key=',req.full_url)
        self.assertIn('generationConfig',json.loads(req.data))
    def test_anthropic_adapter(self):
        p=dict(b.get_profile(b.config()));p['format']='anthropic'
        b.save_profile({'profile':p,'apiKey':'new-key'})
        with self.network({'content':[{'type':'text','text':'ok'}],'usage':{'input_tokens':2,'output_tokens':1}}):r=self.generate()
        self.assertEqual(r['text'],'ok');self.assertTrue(self.calls[0].full_url.endswith('/messages'))
    def test_input_and_output_caps(self):
        with self.assertRaises(b.Failure):b.generate({'messages':[{'role':'user','content':'x'*33000}]})
        with self.network({'choices':[{'message':{'content':'ok'}}]}):b.generate({'messages':[{'role':'user','content':'hi'}],'maxTokens':999999})
        self.assertEqual(json.loads(self.calls[0].data)['max_tokens'],512)
    def test_set_model_saves_without_touching_credentials_or_network(self):
        before=b.get_profile(b.config());secret=b.credential_path(before).read_bytes()
        with patch.object(b,'read_key',side_effect=AssertionError('must not read key')):
            result=b.dispatch({'action':'setModel','profileId':self.pid,'model':'chosen-model'})
        self.assertEqual(result['status']['profiles'][0]['model'],'chosen-model')
        self.assertEqual(b.config()['profiles'][0]['model'],'chosen-model')
        self.assertEqual(b.credential_path(before).read_bytes(),secret)
        self.assertEqual(b.status()['todayRequests'],0)
        with self.assertRaises(b.Failure):b.dispatch({'action':'setModel','profileId':self.pid,'model':''})
    def test_clear_profile_removes_file_secret(self):
        p=b.get_profile(b.config());b.dispatch({'action':'deleteProfile','profileId':self.pid})
        self.assertFalse(b.credential_path(p).exists());self.assertEqual(b.config()['active'],'')

    def test_pretranslation_batch_caches_and_advances(self):
        b.dispatch({'action':'configure','limits':{'outputTokens':1024}})
        for i in range(3): self.package(f'pkg{i}',f'Package number {i}')
        with self.network({'choices':[{'message':{'content':json.dumps(['译文零','译文一','译文二'],ensure_ascii=False)}}]}):
            result=self.batch()
        self.assertEqual(result['total'],3);self.assertEqual(result['done'],3);self.assertEqual(result['remaining'],0)
        self.assertEqual(sorted(result['translations']),['pkg0\nPackage number 0','pkg1\nPackage number 1','pkg2\nPackage number 2'])
        payload=json.loads(self.calls[0].data)
        self.assertIn('JSON 字符串数组',payload['messages'][0]['content'])
        self.assertEqual(payload['max_tokens'],1024)
        cached=b.dispatch({'action':'cachedTranslations','items':[{'name':'pkg1','description':'Package number 1'}]})
        self.assertEqual(cached['translations'],{'pkg1\nPackage number 1':'译文一'})
        with patch.object(b,'http',side_effect=AssertionError('no extra call')):
            again=self.batch()
        self.assertEqual(again['done'],0);self.assertEqual(len(self.calls),1)
    def test_pretranslation_new_and_changed_packages_requeue(self):
        self.package('old','Old description')
        with self.network({'choices':[{'message':{'content':json.dumps(['旧描述'],ensure_ascii=False)}}]}):self.batch()
        self.assertEqual(b.dispatch({'action':'translationStatus'})['pending'],0)
        self.package('new','Brand new description')
        self.package('old','Old description v2')
        status=b.dispatch({'action':'translationStatus'})
        self.assertEqual((status['total'],status['pending']),(2,2))
        with self.network({'choices':[{'message':{'content':json.dumps(['全新描述','旧描述二'],ensure_ascii=False)}}]}):
            result=self.batch()
        payload=json.loads(self.calls[-1].data)['messages'][1]['content']
        self.assertIn('new',payload);self.assertIn('old',payload)
        self.assertEqual(result['remaining'],0)
    def test_pretranslation_drops_uninstalled_packages(self):
        self.package('gone','Temporary package')
        with self.network({'choices':[{'message':{'content':json.dumps(['临时'],ensure_ascii=False)}}]}):self.batch()
        self.package('kept','Kept package')
        import shutil;shutil.rmtree(self.pacman/'gone-1.0-1')
        status=b.dispatch({'action':'translationStatus'})
        self.assertEqual((status['total'],status['pending']),(1,1))
    def test_pretranslation_parse_failure_is_bounded(self):
        self.package('weird','Description')
        for _ in range(3):
            with self.network({'choices':[{'message':{'content':'not a json array'}}]}):
                with self.assertRaises(b.Failure) as cm:self.batch(size=1)
            self.assertEqual(cm.exception.code,'parse')
        with self.network({'choices':[{'message':{'content':'["不应请求"]'}}]}):
            result=self.batch(size=1)
        self.assertEqual((result['done'],result['remaining']),(0,0));self.assertEqual(len(self.calls),3)
    def test_pretranslation_empty_response_is_bounded(self):
        self.package('quiet','Description')
        for _ in range(3):
            with self.network({'choices':[{'message':{'content':''}}]}):
                with self.assertRaises(b.Failure) as cm:self.batch(size=1)
            self.assertEqual(cm.exception.code,'response')
        with self.network({'choices':[{'message':{'content':'["不应请求"]'}}]}):
            result=self.batch(size=1)
        self.assertEqual((result['done'],result['remaining']),(0,0));self.assertEqual(len(self.calls),3)
    def test_pretranslation_batch_respects_output_budget(self):
        for i in range(5): self.package(f'b{i}',f'Batch {i}')
        b.dispatch({'action':'configure','limits':{'outputTokens':128}})
        with self.network({'choices':[{'message':{'content':json.dumps(['一'],ensure_ascii=False)}}]}):
            result=self.batch(size=12)
        self.assertEqual(result['done'],1);self.assertEqual(result['remaining'],4)
        self.assertEqual(json.loads(self.calls[0].data)['max_tokens'],128)
        b.dispatch({'action':'configure','limits':{'outputTokens':512}})
        for size in (0,13,True,'8'):
            with self.assertRaises(b.Failure):self.batch(size=size)
    def test_pretranslation_status_is_local_only(self):
        self.package('pkg','Local description')
        with patch.object(b,'http',side_effect=AssertionError('no network')), patch.object(b,'read_key',side_effect=AssertionError('no credential')):
            status=b.dispatch({'action':'translationStatus'})
        self.assertEqual((status['enabled'],status['total'],status['pending']),(True,1,1))
        self.assertEqual(b.status()['todayRequests'],0)
        b.dispatch({'action':'configure','translation':False})
        self.assertFalse(b.dispatch({'action':'translationStatus'})['enabled'])
    def test_save_models_dedupes_and_needs_no_network(self):
        with patch.object(b,'http',side_effect=AssertionError('no network')), patch.object(b,'read_key',side_effect=AssertionError('no credential')):
            result=b.dispatch({'action':'saveModels','profileId':self.pid,'models':['a','a',' b ','']})
        self.assertEqual(result['models'],['a','b'])
        self.assertEqual(b.get_profile(b.config())['models'],['a','b'])
        self.assertEqual(b.dispatch({'action':'saveModels','profileId':self.pid,'models':[]})['models'],[])
    def test_pretranslation_skips_dependencies(self):
        self.package('app','Explicit app')
        self.package('libdep','Dependency library',explicit=False)
        status=b.dispatch({'action':'translationStatus'})
        self.assertEqual((status['total'],status['explicit'],status['pending']),(2,1,1))
        with self.network({'choices':[{'message':{'content':json.dumps(['应用'],ensure_ascii=False)}}]}):
            result=self.batch()
        payload=json.loads(self.calls[0].data)['messages'][1]['content']
        self.assertIn('"app"',payload);self.assertNotIn('libdep',payload)
        self.assertEqual(result['remaining'],0)
    def test_pretranslation_model_change_requeues(self):
        self.package('pkg','Model bound description')
        with self.network({'choices':[{'message':{'content':json.dumps(['模型译文'],ensure_ascii=False)}}]}):self.batch()
        self.assertEqual(b.dispatch({'action':'translationStatus'})['pending'],0)
        b.dispatch({'action':'setModel','profileId':self.pid,'model':'other-model'})
        self.assertEqual(b.dispatch({'action':'translationStatus'})['pending'],1)

if __name__=='__main__':unittest.main()
