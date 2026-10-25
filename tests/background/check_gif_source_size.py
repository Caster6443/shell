#!/usr/bin/env python3
"""Guard the deployed Qt 6.12 GIF crash workaround after rebuilding an overlay."""
from pathlib import Path
import re
import sys

root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path.home()/'.config/quickshell/caelestia'
checked = 0
for relative in ['modules/background/DesktopClock.qml', 'modules/session/Content.qml']:
    text = (root/relative).read_text()
    for start in re.finditer(r'\bAnimatedImage\s*\{', text):
        depth = 1
        end = start.end()
        while depth and end < len(text):
            depth += (text[end] == '{') - (text[end] == '}')
            end += 1
        body = text[start.end():end-1]
        if re.search(r'^\s*sourceSize\s*[.:]', body, re.M):
            raise SystemExit(f'FAIL: {relative} configures AnimatedImage.sourceSize')
        checked += 1
assert checked >= 2, 'Critical GIF components were not found'
print(f'PASS: {checked} deployed AnimatedImage components avoid sourceSize')
