#!/usr/bin/env python3
"""把 hyprland 的 lua 键位配置解析成 cheatsheet 用的 JSON。

用法: fetch_keybinds.py [keybinds.lua] [variables.lua]
输出: [{ "category": "...", "keybinds": [{ "key": "SUPER + X", "desc": "..." }] }]

规则（模仿旧版提取逻辑）：只输出有自定义 description 的键位；
没有描述的不进入 cheatsheet；vars.kbX 变量会翻译成实际按键。
"""

import json
import os
import re
import sys

HOME = os.path.expanduser("~")
KEYBINDS = sys.argv[1] if len(sys.argv) > 1 else f"{HOME}/.config/hypr/hyprland/keybinds.lua"
VARIABLES = sys.argv[2] if len(sys.argv) > 2 else f"{HOME}/.config/hypr/variables.lua"


def load_vars(path: str) -> dict:
    """解析 variables.lua 里的 name = "value" 字符串变量。"""
    out = {}
    try:
        with open(path, encoding="utf-8") as f:
            for line in f:
                m = re.match(r'\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*"([^"]*)"', line)
                if m:
                    out[m.group(1)] = m.group(2)
    except OSError:
        pass
    return out


def resolve_key(key: str, vars_: dict) -> str:
    """把键位字符串里的 vars.kbX 引用替换成实际值，规整空格。"""
    key = re.sub(r"vars\.([A-Za-z0-9_]+)", lambda m: vars_.get(m.group(1), m.group(0)), key)
    key = key.replace('"', "")
    key = re.sub(r"\s*\.\.\s*", "+", key)
    key = re.sub(r"\b(btn|key|i|n)\b", "KEY", key)
    key = re.sub(r"\s+", " ", key).strip(" +")
    return key


def main() -> None:
    vars_ = load_vars(VARIABLES)
    sections = []
    current = None

    try:
        with open(KEYBINDS, encoding="utf-8") as f:
            for raw in f:
                line = raw.strip()

                # 分区注释：-- Section
                if line.startswith("--") and not line.startswith("----"):
                    name = line[2:].strip()
                    if name and not name.startswith(("HYPRLAND", "KEYBINDS", "=")):
                        # 分类名去掉括号/冒号里的补充说明：-- Overview (in-shell module...) → Overview
                        clean = re.split(r"[（(：:]", name)[0].strip()
                        current = {"category": clean or name, "keybinds": []}
                        sections.append(current)
                    continue

                # 单行 hl.bind("KEY" | vars.kbX, ACTION, {opts})
                m = re.match(
                    r'hl\.bind\(\s*("(?:[^"]+)"|vars\.[A-Za-z0-9_]+)\s*,\s*(.+?)(?:,\s*\{[^}]*\})?\)\s*$',
                    line,
                )
                if not m:
                    continue

                raw_key = m.group(1)
                key = resolve_key(raw_key, vars_)
                action = m.group(2)
                if not key or "launcherInterrupt" in action:
                    continue

                # 描述来自 hyprland 绑定的 description 属性（用户自定义）
                dm = re.search(r'description\s*=\s*"([^"]*)"', line)
                desc = dm.group(1).strip() if dm else ""
                if not desc:
                    continue

                if current is None:
                    current = {"category": "General", "keybinds": []}
                    sections.append(current)
                current["keybinds"].append({"key": key, "desc": desc})
    except OSError:
        pass

    json.dump([s for s in sections if s.get("keybinds")], sys.stdout, ensure_ascii=False)


if __name__ == "__main__":
    main()
