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

# 细分区名 -> 大类（避免 cheatsheet 分类太碎）
CATEGORY_GROUPS = {
    "Launcher": "Shell",
    "Overview": "Shell",
    "Cheatsheet": "Shell",
    "Misc": "Shell",
    "Restore lock": "Shell",
    "Kill/restart": "Shell",
    "Brightness": "系统",
    "Media": "系统",
    "Volume": "系统",
    "Sleep": "系统",
    "Go to workspace -1/+1": "工作区",
    "Go to workspace group -1/+1": "工作区",
    "Move window to workspace -1/+1": "工作区",
    "Move window to/from special workspace": "工作区",
    "Workspaces": "工作区",
    "Special workspace toggles": "工作区",
    "Window groups": "窗口",
    "Window actions": "窗口",
    "鼠标滚轮横向切换窗口聚焦": "窗口",
    "Apps": "应用与工具",
    "Utilities": "应用与工具",
    "Clipboard and emoji picker": "应用与工具",
}


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


LOOP_RE = re.compile(r"for\s+i\s*=\s*1,\s*10\s+do\s*\n(.*?)\n\s*end", re.S)
LOOP_BIND_RE = re.compile(
    r"hl\.bind\(\s*(vars\.[A-Za-z0-9_]+)\s*\.\.\s*\"\s*\+\s*\"\s*\.\.\s*key\s*,"
    r"\s*fn\.wsaction\(\s*\"([^\"]*)\"\s*,\s*\"([^\"]*)\"\s*,\s*i\s*\)"
    r"(?:,\s*\{\s*description\s*=\s*\"([^\"]*)\"\s*\})?\s*\)"
)


def expand_workspace_loop(text: str, vars_: dict) -> str:
    """把 1..10 工作区循环折叠成一条代表绑定（Super+1 代表 1-10 号）。"""

    def repl(m: re.Match) -> str:
        body = m.group(1)
        out = []
        seen = set()
        for bm in LOOP_BIND_RE.finditer(body):
            var, action, group, desc = bm.groups()
            if var in seen:
                continue
            seen.add(var)
            base = vars_.get(var.replace("vars.", ""), var)
            out.append(
                f'hl.bind("{base} + 1", fn.wsaction("{action}", "{group}", 1), '
                f'{{ description = "{desc or ""}" }})\n'
            )
        return "\n".join(out)

    return LOOP_RE.sub(repl, text)


def extract_bind_calls(text: str):
    """按括号配平提取所有 hl.bind(...) 调用（支持多行），返回 (offset, call_text)。"""
    i = 0
    n = len(text)
    while True:
        m = re.search(r"\bhl\.bind\s*\(", text[i:])
        if not m:
            return
        start = i + m.start()
        j = i + m.end()
        depth = 1
        while j < n and depth > 0:
            c = text[j]
            if c in ('"', "'"):
                quote = c
                j += 1
                while j < n and text[j] != quote:
                    if text[j] == "\\":
                        j += 1
                    j += 1
            elif text.startswith("[[", j):
                j += 2
                k = text.find("]]", j)
                j = n if k == -1 else k + 2
                continue
            elif c == "(":
                depth += 1
            elif c == ")":
                depth -= 1
            j += 1
        yield start, text[start:j]
        i = j


def collect_sections(text: str):
    """解析 -- 分区注释。连续注释行算一组，取组内第一个标题；
    含全角冒号（：）的注释视为说明文字，不作为分区。"""
    sections = []
    group_started = False
    pending_header = None
    prev_end = None
    for m in re.finditer(r"^--\s+(.*?)\s*$", text, re.M):
        name = m.group(1).strip()
        sep = not name or name.startswith(("HYPRLAND", "KEYBINDS", "=")) or name.startswith("---")
        contiguous = prev_end is not None and m.start() == prev_end + 1
        if not group_started or not contiguous:
            group_started = True
            pending_header = None
        if not sep and pending_header is None:
            pending_header = name
            if "：" not in name:
                clean = re.split(r"[（(：:]", name)[0].strip() or name
                sections.append({"pos": m.start(), "name": clean})
        prev_end = m.end()
    return sections


def main() -> None:
    vars_ = load_vars(VARIABLES)
    try:
        with open(KEYBINDS, encoding="utf-8") as f:
            text = f.read()
    except OSError:
        text = ""

    text = expand_workspace_loop(text, vars_)
    sections = collect_sections(text)

    results = []
    for offset, call in extract_bind_calls(text):
        km = re.match(r'\s*hl\.bind\(\s*("(?:[^"]+)"|vars\.[A-Za-z0-9_]+)', call)
        if not km:
            continue
        raw_key = km.group(1)
        if "XF86" in raw_key or "launcherInterrupt" in call:
            continue
        dm = re.search(r'description\s*=\s*"([^"]*)"', call)
        if not dm or not dm.group(1).strip():
            continue
        key = resolve_key(raw_key, vars_)
        if not key:
            continue
        section = "General"
        for s in sections:
            if s["pos"] < offset:
                section = s["name"]
            else:
                break
        results.append({"section": section, "key": key, "desc": dm.group(1).strip()})

    merged = {}
    for r in results:
        group = CATEGORY_GROUPS.get(r["section"], r["section"])
        merged.setdefault(group, []).append({"key": r["key"], "desc": r["desc"]})

    json.dump(
        [{"category": g, "keybinds": kbs} for g, kbs in merged.items()],
        sys.stdout,
        ensure_ascii=False,
    )


if __name__ == "__main__":
    main()
