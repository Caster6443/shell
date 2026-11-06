#!/usr/bin/env python3
"""Extract one bounded poster outside the shell; serialize and cache by file identity."""
import fcntl
import hashlib
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from urllib.parse import unquote, urlparse


def thumbnail(value):
    url = urlparse(value)
    source = Path(unquote(url.path) if url.scheme == 'file' else value).resolve(strict=True)
    info = source.stat()
    key = hashlib.sha256(f'v1:{source}:{info.st_size}:{info.st_mtime_ns}'.encode()).hexdigest()
    cache = Path(os.environ.get('XDG_CACHE_HOME', Path.home()/'.cache'))/'caelestia/video-posters'
    cache.mkdir(parents=True, exist_ok=True)
    target = cache/(key+'.png')
    with (cache/'extract.lock').open('w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if not target.exists():
            fd, name = tempfile.mkstemp(suffix='.png', dir=cache)
            os.close(fd)
            try:
                subprocess.run(['ffmpeg', '-nostdin', '-v', 'error', '-y', '-threads', '1',
                    '-i', str(source), '-an', '-sn', '-frames:v', '1',
                    '-vf', 'scale=640:640:force_original_aspect_ratio=decrease',
                    '-threads', '1', name], check=True, timeout=30)
                os.replace(name, target)
            finally:
                Path(name).unlink(missing_ok=True)
            entries = sorted(cache.glob('*.png'), key=lambda p: p.stat().st_mtime, reverse=True)
            total = 0
            for item in entries:
                total += item.stat().st_size
                if total > 128*1024*1024:
                    item.unlink(missing_ok=True)
    return target.as_uri()


if __name__ == '__main__':
    try:
        os.nice(10)
        print(thumbnail(sys.argv[1]), flush=True)
    except Exception as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
