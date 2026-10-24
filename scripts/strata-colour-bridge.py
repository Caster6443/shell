#!/usr/bin/env python3
"""Publish Caelestia colours to Strata 1.0's live Quattro theme interface.
No Omarchy install or service is involved; refuse to overwrite foreign state.
"""
import json
import os
import re
import tempfile
from pathlib import Path

HOME = Path.home()
STATE = HOME / ".local/state/omarchy/current"
MARKER = STATE / ".caelestia-strata-bridge"

def atomic_write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(prefix=".strata-", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as stream:
            stream.write(text)
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)

def main():
    if STATE.exists() and not MARKER.is_file():
        raise SystemExit("Refusing to replace unmanaged Omarchy theme state")
    scheme = json.loads((HOME / ".local/state/caelestia/scheme.json").read_text())
    colours = json.loads(os.environ["SCHEME_COLOURS"]) if "SCHEME_COLOURS" in os.environ else scheme["colours"]
    roles = {
        "background": "background", "foreground": "onSurface",
        "accent": "primary", "selection": "primaryContainer",
        "color8": "surfaceContainer", "color1": "error",
        "magenta": "tertiary", "green": "green", "orange": "peach",
        "cyan": "secondary", "yellow": "yellow",
    }
    values = {}
    for target, source in roles.items():
        value = colours[source].lstrip("#")
        if not re.fullmatch(r"[0-9a-fA-F]{6}", value):
            raise SystemExit(f"Invalid colour for {source}")
        values[target] = "#" + value.lower()
    STATE.mkdir(parents=True, exist_ok=True)
    atomic_write(MARKER, "Managed by strata-colour-bridge.py; not an Omarchy installation.\n")
    atomic_write(STATE / "theme.name", "caelestia-dynamic\n")
    atomic_write(STATE / "theme/colors.toml", "# Caelestia → Strata live theme bridge\n" + "".join(f'{key} = "{value}"\n' for key, value in values.items()))

if __name__ == "__main__":
    main()
