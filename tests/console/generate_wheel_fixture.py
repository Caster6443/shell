#!/usr/bin/env python3
"""Extract actual wheel classification/accumulation functions into Qt Quick Test."""
from pathlib import Path
import sys
here = Path(__file__).resolve().parent
source = (here.parents[1] / "console/ConsolePanel.qml").read_text()
def extract(name):
    i = source.index("function " + name + "(")
    j = source.index("{", i)
    depth, end = 1, j + 1
    while depth:
        if source[end] == "{": depth += 1
        elif source[end] == "}": depth -= 1
        end += 1
    return source[i:end]
fixture = (here / "wheel.qml.in").read_text()
for name in ("isSmoothWheel", "wheelStep"):
    fixture = fixture.replace("@@" + name + "@@", extract(name))
out = Path(sys.argv[1]); out.mkdir(parents=True, exist_ok=True)
(out / "tst_wheel.qml").write_text(fixture)

start = source.index("HoverHandler {\n\t\t\t\t\t\t\t\tid: appListHover")
brace = source.index("{", start)
depth, end = 1, brace + 1
while depth:
    if source[end] == "{": depth += 1
    elif source[end] == "}": depth -= 1
    end += 1
pointer = (here / "pointer.qml.in").read_text().replace("@@HOVER@@", source[start:end])
(out / "tst_pointer.qml").write_text(pointer)

start = source.index("WheelHandler {", source.index("id: appList\n"))
brace = source.index("{", start)
depth, end = 1, brace + 1
while depth:
    if source[end] == "{": depth += 1
    elif source[end] == "}": depth -= 1
    end += 1
pointer = pointer.replace("@@WHEEL@@", source[start:end])
scroll_start = source.index("onContentYChanged:", source.index("id: appList\n"))
pointer = pointer.replace("@@SCROLL@@", source[scroll_start:].splitlines()[0])
for name in ("isSmoothWheel", "wheelStep", "moveAppSelection"):
    pointer = pointer.replace("@@" + name + "@@", extract(name))
(out / "tst_pointer.qml").write_text(pointer)
