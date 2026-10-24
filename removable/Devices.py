"""UDisks2 removable-drive discovery and non-forced safe removal."""
import hashlib
import json
from pathlib import Path
import sys
from gi.repository import Gio, GLib

SERVICE = 'org.freedesktop.UDisks2'
ROOT = '/org/freedesktop/UDisks2'
DRIVE = SERVICE + '.Drive'
BLOCK = SERVICE + '.Block'
FS = SERVICE + '.Filesystem'
SWAP = SERVICE + '.Swapspace'


def bus():
    return Gio.bus_get_sync(Gio.BusType.SYSTEM, None)


def objects(connection):
    return connection.call_sync(SERVICE, ROOT, 'org.freedesktop.DBus.ObjectManager',
                                'GetManagedObjects', None, None, Gio.DBusCallFlags.NONE,
                                5000, None).unpack()[0]


def decode_path(value):
    return bytes(value).split(b'\0', 1)[0].decode('utf-8', 'replace')


def drive_for(path, data, seen=None):
    seen = set() if seen is None else seen
    if path in seen:
        return '/'
    seen.add(path)
    block = data.get(path, {}).get(BLOCK, {})
    if block.get('Drive', '/') != '/':
        return block['Drive']
    backing = block.get('CryptoBackingDevice', '/')
    return drive_for(backing, data, seen) if backing != '/' else '/'


GENERIC_MODELS = {'disk', 'scsi disk', 'usb disk', 'usb device', 'mass storage',
                  'usb mass storage device', 'storage device', 'generic', 'flash disk', 'flash drive'}


def hardware_name(drive, members):
    model = str(drive.get('Model', '')).strip()
    vendor = str(drive.get('Vendor', '')).strip()
    if model and model.lower() not in GENERIC_MODELS:
        return ' '.join(v for v in [vendor if vendor.lower() not in {'scsi', 'generic', 'usb'} else '', model] if v)
    # USB descriptors often retain a real product name when SCSI inquiry does not.
    for _, interfaces in members:
        device = decode_path(interfaces[BLOCK].get('PreferredDevice', []))
        path = (Path('/sys/class/block') / Path(device).name / 'device').resolve()
        for parent in [path, *path.parents]:
            if not (parent / 'idVendor').exists() or not (parent / 'idProduct').exists():
                continue
            def read(name):
                try:
                    return (parent / name).read_text().strip()
                except OSError:
                    return ''
            product = read('product')
            if product and product.lower() not in GENERIC_MODELS:
                return product
            identity = read('idVendor').upper() + ':' + read('idProduct').upper()
            return 'USB 存储 · ' + identity
    return model if model and model.lower() not in GENERIC_MODELS else '移动存储设备'


def scan(data):
    result = []
    for path, interfaces in data.items():
        drive = interfaces.get(DRIVE)
        if not drive or not drive.get('MediaAvailable', True):
            continue
        if not (drive.get('ConnectionBus') == 'usb' or drive.get('Removable') or drive.get('MediaRemovable')):
            continue
        members = [(p, i) for p, i in data.items() if BLOCK in i and drive_for(p, data) == path]
        # Protect system/boot disks, including external disks used as the OS.
        if not members or any(i[BLOCK].get('HintSystem') for _, i in members):
            continue
        volumes = []
        for p, i in members:
            if FS in i:
                volumes.append({'path': p, 'name': i[BLOCK].get('IdLabel') or decode_path(i[BLOCK].get('PreferredDevice', [])),
                                'mounts': [decode_path(v) for v in i[FS].get('MountPoints', [])]})
        mounts = [m for v in volumes for m in v['mounts']]
        if any(m in ['/', '/boot', '/boot/efi', '/efi', '/home', '/usr', '/var'] for m in mounts):
            continue
        if any(i.get(SWAP, {}).get('Active') for _, i in members):
            continue
        model = hardware_name(drive, members)
        label = next((i[BLOCK].get('IdLabel') for _, i in members if i[BLOCK].get('IdLabel')), '')
        result.append({'path': path, 'name': model, 'model': model, 'label': label,
                       'size': drive.get('Size', 0), 'volumes': volumes,
                       'identity': hashlib.sha256(json.dumps([drive.get(k) for k in ['Id', 'Serial', 'TimeDetected', 'TimeMediaDetected', 'Size']]).encode()).hexdigest(),
                       'mounted': bool(mounts), 'canPowerOff': drive.get('CanPowerOff', False),
                       'ejectable': drive.get('Ejectable', False)})
    return sorted(result, key=lambda x: (x['name'], x['path']))


def call(connection, path, interface, method):
    return connection.call_sync(SERVICE, path, interface, method,
                                GLib.Variant('(a{sv})', ({'auth.no_user_interaction': GLib.Variant('b', True)},)),
                                None, Gio.DBusCallFlags.NONE, 120000, None)


def remove(connection, path, identity):
    # Resolve fresh; the UI cannot authorize an internal/replaced/system disk.
    initial = objects(connection)
    device = next((d for d in scan(initial) if d['path'] == path), None)
    if device is None:
        raise RuntimeError('设备已移除，或不属于可安全弹出的移动设备')
    if device['identity'] != identity:
        raise RuntimeError('设备已被更换，请刷新后重试')
    sibling = initial[path][DRIVE].get('SiblingId', '')
    if device['canPowerOff'] and sibling and any(p != path and i.get(DRIVE, {}).get('SiblingId') == sibling
                                                and i[DRIVE].get('MediaAvailable', True) for p, i in initial.items() if DRIVE in i):
        raise RuntimeError('此读卡器还有其他介质，不能单独断电；请先在文件管理器中卸载其他介质')
    for volume in device['volumes']:
        if volume['mounts']:
            call(connection, volume['path'], FS, 'Unmount')
    current = next((d for d in scan(objects(connection)) if d['path'] == path), None)
    if current is None:
        raise RuntimeError('设备状态发生变化，请刷新后重试')
    if current['identity'] != identity:
        raise RuntimeError('设备状态发生变化，未执行断电')
    if current['mounted']:
        raise RuntimeError('仍有分区处于挂载状态，未弹出设备')
    if current['canPowerOff']:
        call(connection, path, DRIVE, 'PowerOff')
        return '已安全弹出，可以拔出设备'
    if current['ejectable']:
        call(connection, path, DRIVE, 'Eject')
        return '已安全弹出，可以取出设备'
    return '所有分区已卸载，可以拔出设备'


def emit(payload):
    print(json.dumps(payload, ensure_ascii=False), flush=True)


def watch(connection):
    pending = [False]
    def update():
        pending[0] = False
        try:
            emit({'devices': scan(objects(connection)), 'error': ''})
        except Exception as error:
            emit({'error': str(error)})
        return False
    def changed(*args):
        if not pending[0]:
            pending[0] = True
            GLib.timeout_add(150, update)
    connection.signal_subscribe(SERVICE, None, None, None, None, Gio.DBusSignalFlags.NONE, changed)
    update()
    GLib.MainLoop().run()


if __name__ == '__main__':
    try:
        connection = bus()
        if sys.argv[1:] == ['watch']:
            watch(connection)
        elif len(sys.argv) == 4 and sys.argv[1] == 'remove':
            emit({'ok': True, 'message': remove(connection, sys.argv[2], sys.argv[3])})
        else:
            emit({'devices': scan(objects(connection)), 'error': ''})
    except Exception as error:
        message = str(error)
        if 'DeviceBusy' in message:
            message = '设备正在使用，请关闭访问它的文件或程序后重试。' + message
        elif 'NotAuthorized' in message:
            message = '当前会话没有卸载或断电权限，请在文件管理器中处理。' + message
        emit({'ok': False, 'error': message})
        sys.exit(1)
