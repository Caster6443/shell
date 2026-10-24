"""Reuse a cliphist entry without re-recording it; paste only after focus returns."""
import json
import os
import re
import subprocess
import sys
import time

SHELL_TITLES = {"caelestia-clipboard", "caelestia-console"}


def query(name):
    return json.loads(subprocess.check_output(["hyprctl", "-j", name], timeout=2))


def target_window():
    if not os.environ.get("HYPRLAND_INSTANCE_SIGNATURE"):
        return None
    active = query("activewindow")
    if active.get("title") not in SHELL_TITLES:
        return None
    clients = [c for c in query("clients")
               if c.get("title") not in SHELL_TITLES and c.get("mapped")
               and not c.get("hidden") and c.get("acceptsInput", True)
               and c.get("focusHistoryID", -1) >= 0
               and c.get("workspace", {}).get("id") == active.get("workspace", {}).get("id")]
    target = min(clients, key=lambda c: c["focusHistoryID"], default=None)
    return target


def paste_when_restored(target):
    if not target or not re.fullmatch(r"0x[0-9a-fA-F]+", target.get("address", "")):
        return False
    deadline = time.monotonic() + 1.5
    while time.monotonic() < deadline:
        active = query("activewindow")
        if active.get("address") == target["address"]:
            # Address confines the event even if focus changes after the check.
            # Terminals commonly use Ctrl+Shift+V instead of Ctrl+V.
            terminal = re.search(r"kitty|alacritty|foot|wezterm|konsole|gnome-terminal|org\.gnome\.ptyxis", target.get("class", ""), re.I)
            mods = "CTRL|SHIFT" if terminal else "CTRL"
            code = 'hl.dispatch(hl.dsp.send_shortcut({mods=' + json.dumps(mods) + ',key="v",window=' + json.dumps("address:" + target["address"]) + '}))'
            out = subprocess.check_output(["hyprctl", "eval", code], timeout=2, text=True)
            if "error" in out.lower():
                raise RuntimeError("Hyprland rejected paste shortcut")
            return True
        if active.get("address") and active.get("title") not in SHELL_TITLES:
            return False
        time.sleep(0.025)
    return False


def main():
    mode = sys.argv[1]
    target = target_window() if mode == "paste" else None
    raw = sys.stdin.buffer.read()
    data = subprocess.check_output(["cliphist", "decode"], input=raw, timeout=10)
    # wl-paste exports CLIPBOARD_STATE=sensitive; cliphist skips this already-stored
    # selection. Existing history and its IDs/pins remain intact. This also tells
    # other clipboard consumers not to retain another copy of the selection.
    subprocess.run(["wl-copy", "--sensitive"], input=data, check=True, timeout=10)
    if mode == "paste":
        print("READY", flush=True)
        if not paste_when_restored(target):
            print("未向其他窗口发送按键；内容已复制，可手动粘贴。", file=sys.stderr)


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
