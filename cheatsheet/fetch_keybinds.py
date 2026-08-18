#!/usr/bin/env python3
"""把 hyprland 的 lua 键位配置解析成 cheatsheet 用的 JSON。

用法: fetch_keybinds.py [keybinds.lua] [variables.lua]
输出: [{ "category": "...", "keybinds": [{ "key": "SUPER + X", "desc": "..." }] }]
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


# (正则, 描述)；按顺序第一个命中生效
DESC_PATTERNS = [
    (r"caelestia:launcher\b", "程序启动器"),
    (r"overview toggle", "工作区总览"),
    (r"cheatsheet toggle", "快捷键速查"),
    (r"caelestia:session", "会话面板"),
    (r"caelestia:sidebar", "侧边栏"),
    (r"caelestia:clearNotifs", "清除通知"),
    (r"caelestia:showall", "显示所有面板"),
    (r"caelestia:lock\b", "锁屏"),
    (r"caelestia:brightness", "屏幕亮度"),
    (r"caelestia:media", "媒体控制"),
    (r"qs -c caelestia kill", "重启 caelestia"),
    (r"window\.move\(\{ workspace", "移动窗口到工作区"),
    (r"window\.move\(\{ direction", "按方向移动窗口"),
    (r"window\.move\(\{ out_of_group", "移出窗口组"),
    (r"focus\(\{ workspace", "切换工作区"),
    (r"focus\(\{ direction", "按方向聚焦窗口"),
    (r"window\.cycle_next", "切换窗口组"),
    (r"group\.next", "下一个窗口组"),
    (r"group\.prev", "上一个窗口组"),
    (r"group\.toggle", "开关窗口组"),
    (r"group\.lock_active", "锁定窗口组"),
    (r"window\.pin", "固定/取消固定窗口"),
    (r"window\.float", "切换浮动"),
    (r"window\.drag", "拖动窗口"),
    (r"window\.resize", "调整窗口大小"),
    (r"window\.center", "窗口居中"),
    (r"window\.close|window\.kill", "关闭窗口"),
    (r"layout\(", "布局操作"),
    (r"window\(", "窗口操作"),
    (r"exec_cmd\(", "执行命令"),
    (r"global\(", "Shell 操作"),
]


def describe(action: str) -> str:
    a = re.sub(r"\s+", " ", action).strip()
    for pattern, label in DESC_PATTERNS:
        if re.search(pattern, a):
            return label
    return a


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

                if current is None:
                    current = {"category": "General", "keybinds": []}
                    sections.append(current)
                current["keybinds"].append({"key": key, "desc": describe(action)})
    except OSError:
        pass

    json.dump([s for s in sections if s.get("keybinds")], sys.stdout, ensure_ascii=False)


if __name__ == "__main__":
    main()
