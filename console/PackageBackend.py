#!/usr/bin/env python3
"""Console's pacman package browser. Queries never refresh the system sync DB.
Only explicit UI actions invoke pkexec; no service, timer or shell hook is installed.
"""
import argparse
import fcntl
import fnmatch
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import time
import urllib.parse
import urllib.request

ENV = dict(os.environ, LC_ALL='C', LANG='C', PATH='/usr/bin:/bin')
NAME = re.compile(r'[a-zA-Z0-9@_+][a-zA-Z0-9@._+\-]*\Z')
STATE = Path(os.environ.get('XDG_STATE_HOME') or Path.home()/'.local/state')/'caelestia/console-packages'


def run(argv, allowed=(0,), timeout=30, env=None):
    p = subprocess.run(argv, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                       env=env or ENV, timeout=timeout)
    if p.returncode not in allowed:
        raise RuntimeError(((p.stderr + '\n' + p.stdout).strip() or f'{argv[0]} exited {p.returncode}').strip()[-1800:])
    return p.stdout


def read_json(path, fallback):
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return fallback


def save_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix='.write-')
    try:
        with os.fdopen(fd, 'w') as f:
            json.dump(value, f, ensure_ascii=False)
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp): os.unlink(tmp)


def desc(text):
    result = {}
    key = None
    for line in text.splitlines():
        if line.startswith('%') and line.endswith('%'):
            key = line.strip('%'); result[key] = []
        elif line and key:
            result[key].append(line)
    return result


def value(record, key, default=''):
    return next(iter(record.get(key, [])), default)


def config(key):
    return run(['pacman-conf', key]).splitlines()


def installed():
    db = Path(config('DBPath')[0])/'local'
    records = {}
    for file in db.glob('*/desc'):
        r = desc(file.read_text())
        records[value(r, 'NAME')] = r
    return records


def sync_packages(dbpath=None):
    result = {}
    db = Path(dbpath or config('DBPath')[0])/'sync'
    # First repository wins, exactly as pacman repository priority does.
    for repo in run(['pacman-conf', '--repo-list']).splitlines():
        path = db/(repo+'.db')
        if not path.exists(): continue
        with tarfile.open(path, 'r:*') as archive:
            for member in archive:
                if not member.name.endswith('/desc'): continue
                stream = archive.extractfile(member)
                if stream is None: continue
                r = desc(stream.read().decode('utf-8', 'replace'))
                name = value(r, 'NAME')
                if name and name not in result:
                    result[name] = {'version': value(r, 'VERSION'), 'source': repo}
    return result


def depname(spec):
    return re.split(r'[<>=]', spec.split(': ', 1)[0], maxsplit=1)[0]


def ignored_reason(name, record, patterns, groups):
    matches = [p for p in patterns if fnmatch.fnmatchcase(name, p)]
    matches += ['组 '+g for g in record.get('GROUPS', []) if any(fnmatch.fnmatchcase(g, p) for p in groups)]
    return '、'.join(matches)


def preferences():
    data = read_json(STATE/'preferences.json', {})
    return data if isinstance(data, dict) else {}


def inventory():
    local = installed()
    sync = sync_packages()
    cache = read_json(STATE/'updates.json', {})
    if not isinstance(cache, dict): cache = {}
    remote = cache.get('versions', {})
    if not isinstance(remote, dict): remote = {}
    patterns, groups = config('IgnorePkg'), config('IgnoreGroup')
    orphans = set(run(['pacman', '-Qdtq'], allowed=(0, 1)).splitlines())
    watched = set(preferences().get('watched', []))
    rows = []
    for name, r in local.items():
        candidate = remote.get(name, sync.get(name, {}))
        current, new = value(r, 'VERSION'), candidate.get('version', '')
        # Batch libalpm comparison below: vercmp is only needed for actual differences.
        update = bool(new and new != current and int(run(['vercmp', new, current]).strip()) > 0)
        reason = ignored_reason(name, r, patterns, groups)
        rows.append({'name': name, 'version': current, 'available': new,
                     'description': value(r, 'DESC'), 'source': candidate.get('source') or value(r, 'INSTALLED_DB', '本地 / 外部包'),
                     'size': int(value(r, 'SIZE', '0')), 'explicit': value(r, 'REASON', '0') == '0',
                     'orphan': name in orphans, 'ignored': bool(reason), 'ignoreReason': reason,
                     'watched': name in watched, 'update': update})
    return {'packages': rows, 'checkedAt': cache.get('checkedAt', 0), 'warnings': cache.get('warnings', []),
            'scope': 'pacman / AUR；不含 Flatpak、AppImage；开发包仅比较已发布版本'}


def detail(name):
    records = installed()
    if name not in records: raise RuntimeError('软件包已不在已安装列表中，请刷新')
    providers = {}
    for n, r in records.items():
        providers.setdefault(n, []).append(n)
        for p in r.get('PROVIDES', []): providers.setdefault(depname(p), []).append(n)
    def links(items):
        return [{'label': s, 'target': (providers.get(depname(s)) or [''])[0]} for s in items]
    r = records[name]
    required = []
    optional_for = []
    # pacman resolves virtual providers, optional dependencies and version constraints.
    info = run(['pacman', '-Qi', '--', name])
    fields = {}
    last = None
    for line in info.splitlines():
        m = re.match(r'^([^\s].*?)\s+: (.*)$', line)
        if m:
            last = m.group(1).strip(); fields[last] = m.group(2)
        elif last and line.startswith(' '): fields[last] += ' '+line.strip()
    for field, target in [('Required By', required), ('Optional For', optional_for)]:
        target.extend(x for x in fields.get(field, '').split() if x != 'None')
    return {'name': name, 'url': value(r, 'URL'), 'licenses': r.get('LICENSE', []),
            'dependencies': links(r.get('DEPENDS', [])), 'optional': links(r.get('OPTDEPENDS', [])),
            'requiredBy': links(required), 'optionalFor': links(optional_for)}


def check_updates():
    warnings = []
    with tempfile.TemporaryDirectory(prefix='console-check-') as temp:
        env = dict(ENV, CHECKUPDATES_DB=temp)
        # checkupdates itself filters ignored packages; read its resulting sync DB instead.
        run(['checkupdates', '--nocolor'], allowed=(0, 2), timeout=180, env=env)
        remote = sync_packages(temp)
    foreign = run(['pacman', '-Qmq'], allowed=(0, 1)).splitlines()
    for offset in range(0, len(foreign), 100):
        names = foreign[offset:offset+100]
        query = urllib.parse.urlencode([('arg[]', n) for n in names])
        try:
            req = urllib.request.Request('https://aur.archlinux.org/rpc/v5/info?'+query,
                                         headers={'User-Agent': 'Console-PackageBrowser/1'})
            with urllib.request.urlopen(req, timeout=20) as response:
                data = json.load(response)
            if data.get('type') == 'error': raise RuntimeError(data.get('error', 'AUR 请求失败'))
            for p in data['results']:
                remote[p['Name']] = {'version': p['Version'], 'source': 'AUR'}
        except Exception as exc:
            warnings.append('AUR 检查不完整：'+str(exc)[:180])
            # Preserve last known AUR versions; partial failures never claim "up to date".
            old = read_json(STATE/'updates.json', {}).get('versions', {})
            for n in names:
                if n in old: remote.setdefault(n, old[n])
    save_json(STATE/'updates.json', {'versions': remote, 'checkedAt': int(time.time()), 'warnings': warnings})
    return inventory()


def remove_preview(name):
    # Keep config backups (.pacsave), do not force dependency removal.
    output = run(['pacman', '-Rs', '--print', '--print-format', '%n', '--', name])
    names = [n for n in output.splitlines() if NAME.fullmatch(n)]
    if not names or name not in names: raise RuntimeError('包管理器未给出有效卸载计划')
    records = installed()
    return {'names': names, 'bytes': sum(int(value(records.get(n, {}), 'SIZE', '0')) for n in names)}


def rewrite_ignore(text, name, enable):
    """Edit only exact IgnorePkg tokens in [options], preserving all other config.
    Wildcards, IgnoreGroup and included files are never silently overridden.
    """
    lines = text.splitlines(keepends=True)
    in_options, indices, header = False, [], None
    pattern = re.compile(r'^(\s*IgnorePkg\s*=\s*)([^#\n]*)(.*)$')
    for i, line in enumerate(lines):
        section = re.match(r'^\s*\[([^]]+)\]', line)
        if section:
            in_options = section[1] == 'options'
            if in_options: header = i
        if in_options and pattern.match(line.rstrip('\n')): indices.append(i)
    if enable and any(name in pattern.match(lines[i].rstrip('\n'))[2].split() for i in indices):
        return text
    if enable and not indices:
        if header is None: raise RuntimeError('pacman.conf 缺少 [options]')
        lines.insert(header + 1, 'IgnorePkg = '+name+'\n')
    else:
        for i in indices:
            m = pattern.match(lines[i].rstrip('\n'))
            tokens = m[2].split()
            if enable and i == indices[0]: tokens.append(name)
            if not enable: tokens = [t for t in tokens if t != name]
            lines[i] = m[1]+' '.join(tokens)+(' '+m[3] if m[3] else '')+'\n'
    return ''.join(lines)


def change_ignore(name, enable):
    if os.geteuid() != 0: raise RuntimeError('修改忽略升级设置需要系统授权')
    # pkexec exposes the authenticated initiating user, never accept a path from argv.
    import pwd
    uid = int(os.environ.get('PKEXEC_UID', '-1'))
    if uid <= 0: raise RuntimeError('只能通过软件管理页面授权此操作')
    owner = pwd.getpwuid(uid)
    record = installed().get(name)
    if record is None: raise RuntimeError('只能管理已安装的软件包')
    with open('/run/console-package-ignore.lock', 'w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        path = Path('/etc/pacman.conf')
        if path.is_symlink() or not path.is_file(): raise RuntimeError('pacman.conf 不是普通文件，请手动管理')
        patterns, groups = config('IgnorePkg'), config('IgnoreGroup')
        if not enable and (any(p != name and fnmatch.fnmatchcase(name, p) for p in patterns) or
                           any(any(fnmatch.fnmatchcase(g, p) for p in groups) for g in record.get('GROUPS', []))):
            raise RuntimeError('该包被通配符或 IgnoreGroup 忽略，请在 pacman 配置中调整对应规则')
        original = path.read_text()
        revised = rewrite_ignore(original, name, enable)
        if not enable and ignored_reason(name, record, patterns, groups) and revised == original:
            raise RuntimeError('忽略规则来自 Include 文件，请手动修改该文件')
        # Validate the complete candidate including Includes before replacing the live file.
        fd, tmp = tempfile.mkstemp(prefix='.console-pacman-', dir='/etc')
        try:
            with os.fdopen(fd, 'w') as stream: stream.write(revised)
            effective = run(['pacman-conf', '--config', tmp, 'IgnorePkg']).splitlines()
            if (any(fnmatch.fnmatchcase(name, p) for p in effective)) != enable:
                raise RuntimeError('其他配置文件仍有匹配的忽略规则，请手动调整')
            backup = Path(owner.pw_dir)/'Documents/bakFiles/etc'/('pacman.conf-'+time.strftime('%Y%m%d-%H%M%S')+'-console')
            # Write backup as the initiating user; root never follows user-owned backup paths.
            pid = os.fork()
            if pid == 0:
                try:
                    os.setgroups([]); os.setgid(owner.pw_gid); os.setuid(uid)
                    backup.parent.mkdir(parents=True, exist_ok=True)
                    with backup.open('x') as stream: stream.write(original)
                    os._exit(0)
                except Exception: os._exit(1)
            if os.waitpid(pid, 0)[1] != 0: raise RuntimeError('配置备份失败，未修改忽略规则')
            stat = path.stat(); os.chmod(tmp, stat.st_mode & 0o777); os.chown(tmp, stat.st_uid, stat.st_gid)
            # Refuse to overwrite a concurrent external edit.
            if path.read_text() != original: raise RuntimeError('配置已被其他程序修改，请刷新后重试')
            os.replace(tmp, path)
        finally:
            if os.path.exists(tmp): os.unlink(tmp)
    return {'ok': True}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['list', 'check', 'detail', 'watch', 'preview', 'ignore', 'terminal'])
    parser.add_argument('name', nargs='?', default='')
    parser.add_argument('argument', nargs='?', default='')
    args = parser.parse_args()
    if args.action not in ('list', 'check', 'terminal') and not NAME.fullmatch(args.name):
        raise RuntimeError('无效的软件包名称')
    if args.action == 'list': return inventory()
    if args.action == 'check': return check_updates()
    if args.action == 'detail': return detail(args.name)
    if args.action == 'preview': return remove_preview(args.name)
    if args.action == 'watch':
        if args.name not in installed(): raise RuntimeError('软件包已被卸载')
        prefs = preferences(); watched = set(prefs.get('watched', []))
        if args.argument == '1': watched.add(args.name)
        else: watched.discard(args.name)
        prefs['watched'] = sorted(watched); save_json(STATE/'preferences.json', prefs)
        return inventory()
    if args.action == 'ignore':
        if args.argument not in ('0', '1'): raise RuntimeError('无效的忽略状态')
        return change_ignore(args.name, args.argument == '1')
    if args.action == 'terminal':
        if args.name == 'upgrade': command = ['paru', '-Syu']
        elif args.name in ('remove', 'explicit') and NAME.fullmatch(args.argument):
            if args.argument not in installed(): raise RuntimeError('软件包已被卸载')
            command = ['sudo', 'pacman'] + (['-Rs', '--', args.argument] if args.name == 'remove' else ['-D', '--asexplicit', '--', args.argument])
        else: raise RuntimeError('无效的操作')
        print('将执行：'+' '.join(command), flush=True)
        if input('输入 yes 继续，其他输入取消：').strip().lower() != 'yes': return {'cancelled': True}
        code = subprocess.call(command)
        print('\n操作完成，退出码：', code)
        input('按回车关闭终端…')
        return {'exitCode': code}


if __name__ == '__main__':
    try:
        print(json.dumps(main(), ensure_ascii=False))
    except Exception as exc:
        print(json.dumps({'error': str(exc)}, ensure_ascii=False))
        sys.exit(1)
