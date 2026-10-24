#!/usr/bin/env python3
"""Backend regressions; fake package databases, no privileged/system mutations."""
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location('backend', Path(__file__).resolve().parents[2]/'console/PackageBackend.py')
b = importlib.util.module_from_spec(spec); spec.loader.exec_module(b)

class BackendTests(unittest.TestCase):
    def test_desc_and_epoch_dependencies(self):
        self.assertEqual(b.desc('%NAME%\nfoo\n\n%REASON%\n1\n')['REASON'], ['1'])
        self.assertEqual(b.depname('foo>=1:2.0'), 'foo')
        self.assertEqual(b.depname('foo: description'), 'foo')

    def test_ignore_add_keeps_comments_and_sections(self):
        old = '[options]\nIgnorePkg = foo # keep\nIgnoreGroup = group\n[repo]\nServer = x\n'
        new = b.rewrite_ignore(old, 'bar', True)
        self.assertIn('IgnorePkg = foo bar # keep', new)
        self.assertIn('IgnoreGroup = group\n[repo]\nServer = x', new)
        self.assertEqual(b.rewrite_ignore(new, 'bar', True), new)

    def test_ignore_remove_exact_not_prefix_or_wildcard(self):
        old = '[options]\nIgnorePkg = foo foobar foo*\nIgnorePkg = foo baz\n'
        new = b.rewrite_ignore(old, 'foo', False)
        self.assertIn('foobar foo*', new)
        self.assertIn('IgnorePkg = baz', new)
        self.assertNotIn(' foo ', new)

    def test_ignore_insert_and_missing_options(self):
        self.assertEqual(b.rewrite_ignore('[options]\n[repo]\n', 'foo', True), '[options]\nIgnorePkg = foo\n[repo]\n')
        with self.assertRaises(RuntimeError): b.rewrite_ignore('[repo]\n', 'foo', True)

    def test_ignore_group_and_pattern(self):
        self.assertTrue(b.ignored_reason('foo-git', {'GROUPS':['desktop']}, ['*-git'], []))
        self.assertIn('组 desktop', b.ignored_reason('foo', {'GROUPS':['desktop']}, [], ['desk*']))

    def test_inventory_ignored_included_without_false_downgrade(self):
        local = {'foo':{'VERSION':['2'], 'REASON':['0'], 'SIZE':['100']}}
        with patch.object(b, 'installed', return_value=local), patch.object(b, 'sync_packages', return_value={'foo':{'version':'1','source':'repo'}}), patch.object(b, 'read_json', return_value={}), patch.object(b, 'config', side_effect=lambda key:['foo'] if key=='IgnorePkg' else []), patch.object(b, 'preferences', return_value={'watched':['foo']}), patch.object(b, 'run', side_effect=lambda argv,**kw: '-1' if argv[0]=='vercmp' else ''):
            row=b.inventory()['packages'][0]
            self.assertTrue(row['ignored']);self.assertTrue(row['watched']);self.assertTrue(row['explicit']);self.assertFalse(row['update']);self.assertEqual(row['available'],'1')

    def test_preview_only_and_dependency_failure(self):
        with patch.object(b,'run',return_value='foo\nbar\n') as call, patch.object(b,'installed',return_value={'foo':{'SIZE':['10']},'bar':{'SIZE':['20']}}):
            self.assertEqual(b.remove_preview('foo'), {'names':['foo','bar'],'bytes':30})
            self.assertIn('--print',call.call_args.args[0]);self.assertNotIn('--noconfirm',call.call_args.args[0])
        with patch.object(b,'run',side_effect=RuntimeError('required by bar')):
            with self.assertRaisesRegex(RuntimeError,'required by'):b.remove_preview('foo')

    def test_preview_rejects_missing_target(self):
        with patch.object(b,'run',return_value='bar\n'):
            with self.assertRaises(RuntimeError):b.remove_preview('foo')

    def test_watch_persistence_in_temporary_state(self):
        with tempfile.TemporaryDirectory() as temp, patch.object(b,'STATE',Path(temp)), patch.object(b,'installed',return_value={'foo':{}}), patch.object(b,'inventory',return_value={'packages':[]}):
            with patch.object(sys,'argv',['backend','watch','foo','1']):b.main()
            self.assertEqual(b.preferences()['watched'],['foo'])
            with patch.object(sys,'argv',['backend','watch','foo','0']):b.main()
            self.assertEqual(b.preferences()['watched'],[])

    def test_checks_use_private_database_and_keep_ignored(self):
        calls=[]
        def run(argv,**kwargs):
            calls.append((argv,kwargs))
            return ''
        with patch.object(b,'run',side_effect=run),patch.object(b,'sync_packages',return_value={'ignored':{'version':'3','source':'repo'}}),patch.object(b,'save_json') as save,patch.object(b,'inventory',return_value={'packages':[]}):
            b.check_updates()
            self.assertNotEqual(calls[0][1]['env']['CHECKUPDATES_DB'],'/var/lib/pacman')
            self.assertIn('ignored',save.call_args.args[1]['versions'])

    def test_aur_failure_is_partial_and_preserves_previous(self):
        def run(argv,**kwargs):return 'foo\n' if argv[:2]==['pacman','-Qmq'] else ''
        with patch.object(b,'run',side_effect=run),patch.object(b,'sync_packages',return_value={}),patch.object(b.urllib.request,'urlopen',side_effect=OSError('offline')),patch.object(b,'read_json',return_value={'versions':{'foo':{'version':'2','source':'AUR'}}}),patch.object(b,'save_json') as save,patch.object(b,'inventory',return_value={}):
            b.check_updates();data=save.call_args.args[1]
            self.assertTrue(data['warnings']);self.assertEqual(data['versions']['foo']['version'],'2')

    def test_name_injection_rejected_before_command(self):
        with patch.object(sys,'argv',['backend','preview','foo;touch /tmp/bad']),patch.object(b,'run') as call:
            with self.assertRaises(RuntimeError):b.main()
            call.assert_not_called()

    def test_ignore_requires_authenticated_privilege(self):
        with patch.object(b.os,'geteuid',return_value=1000):
            with self.assertRaises(RuntimeError):b.change_ignore('foo',True)

if __name__ == '__main__':unittest.main()
