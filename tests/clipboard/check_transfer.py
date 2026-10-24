"""No user clipboard/history/keystrokes: real isolated cliphist, mocked desktop IO."""
import importlib.util
import io
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from unittest.mock import patch

repo = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('transfer', repo/'console/ClipboardTransfer.py')
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
with tempfile.TemporaryDirectory() as d:
    cli = ['cliphist', '-db-path', d+'/db']
    for text in [b'old\nmultiline\n', b'new entry']:
        subprocess.run(cli+['store'], input=text, check=True)
    before = subprocess.check_output(cli+['list'])
    raw = before.splitlines()[1]
    real_output, real_run = subprocess.check_output, subprocess.run
    copied = []
    def output(args, **kw):
        assert args == ['cliphist','decode']
        return real_output(cli+['decode'], **kw)
    def run(args, **kw):
        if args != ['wl-copy','--sensitive']:
            return real_run(args, **kw)
        copied.append(kw['input'])
        # Actual cliphist behavior with wl-paste's sensitive clipboard state.
        return real_run(cli+['store'], input=kw['input'], check=True,
                        env=dict(os.environ, CLIPBOARD_STATE='sensitive'))
    with patch.object(m.subprocess,'check_output',output), patch.object(m.subprocess,'run',run), patch.object(sys,'argv',['transfer','copy']), patch.object(sys,'stdin',io.TextIOWrapper(io.BytesIO(raw))):
        m.main()
    assert copied == [b'old\nmultiline\n']
    assert subprocess.check_output(cli+['list']) == before

shell={'address':'0x1','title':'caelestia-clipboard','workspace':{'id':1}}
target={'address':'0x2','title':'Editor','class':'editor','workspace':{'id':1},'mapped':True,'focusHistoryID':1}
with patch.dict(os.environ,HYPRLAND_INSTANCE_SIGNATURE='test'), patch.object(m,'query',side_effect=[shell,[shell,target]]):
    assert m.target_window()==target
with patch.object(m,'query',return_value={'address':'0x3','title':'Other'}), patch.object(m.subprocess,'check_output') as sent:
    assert not m.paste_when_restored(target); sent.assert_not_called()
with patch.object(m,'query',side_effect=[shell,target]), patch.object(m.time,'sleep'), patch.object(m.subprocess,'check_output',return_value='ok') as sent:
    assert m.paste_when_restored(target)
    assert 'address:0x2' in sent.call_args.args[0][2]
    assert '"CTRL"' in sent.call_args.args[0][2]
with patch.object(m,'query',return_value=target), patch.object(m.subprocess,'check_output',return_value='ok') as sent:
    assert m.paste_when_restored(dict(target,**{'class':'kitty'}))
    assert 'CTRL|SHIFT' in sent.call_args.args[0][2]
with patch.object(m.subprocess,'check_output') as sent:
    assert not m.paste_when_restored(None); sent.assert_not_called()
print('PASS: exact old content; real isolated history order/IDs unchanged; previous target; focus change abort; address-bound shortcut; terminal modifiers; missing target abort')
