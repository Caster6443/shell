#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""从 nexus QML 提取 qsTr 原文，生成 caelestia_zh_CN.ts。
翻译来自同目录 translations.py（key: "context||source"），未覆盖的留空=回退英文。
"""
import html
import os
import re
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, ROOT)
from translations import ZH  # noqa: E402

SRC = os.environ.get("NEXUS_SRC", os.path.expanduser("~/.config/quickshell/caelestia/modules/nexus"))
TS = os.path.join(ROOT, "translations", "caelestia_zh_CN.ts")

QS_RE = re.compile(r'qsTr\(\s*"((?:[^"\\]|\\.)*)"')


def unescape(s: str) -> str:
    return s.replace('\\"', '"').replace("\\\\", "\\")


def main() -> int:
    contexts = {}
    for dirpath, _dirs, files in os.walk(SRC):
        for fn in files:
            if not fn.endswith(".qml"):
                continue
            path = os.path.join(dirpath, fn)
            ctx = os.path.splitext(fn)[0]
            with open(path, encoding="utf-8") as f:
                text = f.read()
            msgs = sorted({unescape(m) for m in QS_RE.findall(text)})
            if msgs:
                contexts.setdefault(ctx, set()).update(msgs)

    os.makedirs(os.path.dirname(TS), exist_ok=True)
    out = []
    out.append('<?xml version="1.0" encoding="utf-8"?>')
    out.append('<!DOCTYPE TS>')
    out.append('<TS version="2.1" language="zh_CN" sourcelanguage="en">')
    for ctx in sorted(contexts):
        out.append(f"<context><name>{html.escape(ctx)}</name>")
        for src in sorted(contexts[ctx]):
            key = f"{ctx}||{src}"
            zh = ZH.get(key)
            out.append(f"<message><source>{html.escape(src)}</source>")
            if zh:
                out.append(f"<translation>{html.escape(zh)}</translation>")
            else:
                out.append('<translation type="unfinished"></translation>')
            out.append("</message>")
        out.append("</context>")
    out.append("</TS>")
    with open(TS, "w", encoding="utf-8") as f:
        f.write("\n".join(out) + "\n")
    print(f"OK: {len(contexts)} contexts, TS -> {TS}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
