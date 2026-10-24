"""UDisks fixtures only: never unmount or power off real hardware."""
import copy
import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('devices', Path(__file__).resolve().parents[2]/'removable/Devices.py')
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
D = '/drive/usb'; P = '/block/usb1'; P2 = '/block/usb2'

def data():
    return {D:{m.DRIVE:{'ConnectionBus':'usb','MediaAvailable':True,'CanPowerOff':True,'Size':1000,'TimeDetected':1,'Vendor':'Kingston','Model':'DataTraveler'}},
            P:{m.BLOCK:{'Drive':D,'IdLabel':'测试盘','PreferredDevice':b'/dev/sdz1\0'},m.FS:{'MountPoints':[b'/run/media/test\0']}}}

class DevicesTest(unittest.TestCase):
    def test_lists_only_external(self):
        d=data(); d['/internal']={m.DRIVE:{'ConnectionBus':'nvme'}}
        self.assertEqual(len(m.scan(d)),1); self.assertEqual(m.scan(d)[0]['name'],'Kingston DataTraveler')
        self.assertEqual(m.scan(d)[0]['label'],'测试盘')
    def test_system_mount_filtered(self):
        for point in ['/', '/boot', '/home']:
            d=data(); d[P][m.FS]['MountPoints']=[point.encode()+b'\0']; self.assertEqual(m.scan(d),[])
    def test_hint_system_swap_filtered(self):
        d=data();d[P][m.BLOCK]['HintSystem']=True;self.assertEqual(m.scan(d),[])
        d=data();d[P][m.SWAP]={'Active':True};self.assertEqual(m.scan(d),[])
    def test_crypto_mapping(self):
        d=data();d['/clear']={m.BLOCK:{'Drive':'/','CryptoBackingDevice':P},m.FS:{'MountPoints':[b'/media/clear\0']}}
        self.assertEqual(len(m.scan(d)[0]['volumes']),2)
    def test_unmount_all_before_poweroff(self):
        d=data();d[P2]=copy.deepcopy(d[P]);identity=m.scan(d)[0]['identity']; calls=[]
        def call(conn,p,i,method):
            calls.append((p,method))
            if method=='Unmount': d[p][m.FS]['MountPoints']=[]
        with patch.object(m,'objects',return_value=d),patch.object(m,'call',side_effect=call):
            self.assertIn('已安全弹出',m.remove(None,D,identity))
        self.assertEqual(calls,[(P,'Unmount'),(P2,'Unmount'),(D,'PowerOff')])
    def test_busy_never_powers_off(self):
        d=data(); identity=m.scan(d)[0]['identity']
        with patch.object(m,'objects',return_value=d),patch.object(m,'call',side_effect=RuntimeError('busy')) as call:
            with self.assertRaises(RuntimeError):m.remove(None,D,identity)
        self.assertEqual(call.call_count,1)
    def test_replaced_device_rejected(self):
        d=data();identity=m.scan(d)[0]['identity'];d[D][m.DRIVE]['TimeDetected']=2
        with patch.object(m,'objects',return_value=d),patch.object(m,'call') as call:
            with self.assertRaises(RuntimeError):m.remove(None,D,identity)
        call.assert_not_called()
    def test_sibling_reader_rejected(self):
        d=data();d[D][m.DRIVE]['SiblingId']='reader';d['/drive/other']={m.DRIVE:{'SiblingId':'reader','MediaAvailable':True}}
        with patch.object(m,'objects',return_value=d),patch.object(m,'call') as call:
            with self.assertRaises(RuntimeError):m.remove(None,D,m.scan(d)[0]['identity'])
        call.assert_not_called()
    def test_mount_race_never_powers_off(self):
        d=data()
        with patch.object(m,'objects',return_value=d),patch.object(m,'call') as call:
            with self.assertRaises(RuntimeError):m.remove(None,D,m.scan(d)[0]['identity'])
        self.assertEqual(call.call_args.args[-1],'Unmount')
    def test_eject_fallback(self):
        d=data();d[D][m.DRIVE].update(CanPowerOff=False,Ejectable=True);d[P][m.FS]['MountPoints']=[]
        with patch.object(m,'objects',return_value=d),patch.object(m,'call') as call:
            m.remove(None,D,m.scan(d)[0]['identity'])
        self.assertEqual(call.call_args.args[-1],'Eject')
    def test_no_force_options(self):
        class Connection:
            def call_sync(self,*args):
                self.options=args[4].unpack()[0]
        c=Connection();m.call(c,P,m.FS,'Unmount');self.assertNotIn('force',c.options)
        self.assertTrue(c.options['auth.no_user_interaction'])

if __name__=='__main__':unittest.main()
