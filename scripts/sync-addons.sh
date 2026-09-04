#!/usr/bin/env bash
# 同步 fork 外挂模块到用户级 caelestia 配置（不再依赖 pacman 系统包作部署基准）。
# 用法: bash scripts/sync-addons.sh [-r]
#   -r  同步完成后重启 caelestia
#
# 新模型（2026-09-04）：用户自主管理 caelestia，不随包管理器自动更新。
# 运行配置 = 系统包底座 + fork 外挂部分；本脚本只负责把仓库「拥有」的外挂部分同步过去，
# 仓库里的 modules/services 等本体源码一概不动（那是用户将来 git merge 官方代码的线）。
#
# 同步内容：
#   1. 自包含外挂模块目录：overview / cheatsheet / spotlight
#   2. shell.qml 顶层实例钩子：仅 cheatsheet（overview 已退役、spotlight 由 launcher 引用，均不写钩子）
# 底座（系统包 modules 等）不在本脚本职责内，如需刷新底座请手动执行
#   `sudo cp -a /etc/xdg/quickshell/caelestia/. ~/.config/quickshell/caelestia/`（慎用，会覆盖本地差异）。
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="${QS_CAELESTIA_DIR:-$HOME/.config/quickshell/caelestia}"
RESTART=0
[[ "${1:-}" == "-r" ]] && RESTART=1

# 1. 自包含外挂模块（整目录同步）。仅这些目录会被覆盖，仓库 modules/ 其余不动。
MODULES=("overview" "cheatsheet" "spotlight")

# 2. shell.qml 需要顶层实例化的模块（名字 → 实例化行）。
INSTANCE_HOOKS=("cheatsheet")

# 同步自包含外挂模块
mkdir -p "$TARGET"
for mod in "${MODULES[@]}"; do
  echo "==> 同步 $mod 模块到 $TARGET/$mod"
  mkdir -p "$TARGET/$mod"
  cp -a "$REPO_DIR/$mod/." "$TARGET/$mod/"
done

# shell.qml 必须存在（由系统包底座提供），本脚本只在其上追加 fork 钩子，不负责初始化底座。
if [[ ! -f "$TARGET/shell.qml" ]]; then
  echo "!! 未找到 $TARGET/shell.qml：底座缺失。" >&2
  echo "   本脚本只同步 fork 外挂部分，不初始化系统包底座。" >&2
  echo "   如需初始化，请先：cp -a /etc/xdg/quickshell/caelestia/. $TARGET/" >&2
  exit 1
fi

# 幂等写入 shell.qml 顶层实例钩子（仅 INSTANCE_HOOKS）
python3 - "$TARGET/shell.qml" "${INSTANCE_HOOKS[@]}" <<'PY'
import re
import sys

path = sys.argv[1]
modules = sys.argv[2:]
instances = {"cheatsheet": "Cheatsheet {}"}

with open(path, encoding="utf-8") as f:
    lines = f.read().splitlines(keepends=True)

changed = False

def has(pattern: str) -> bool:
    return any(re.search(pattern, line) for line in lines)

for mod in modules:
    if not has(rf'^\s*import "{mod}"\s*$'):
        for i, line in enumerate(lines):
            if re.match(r'^\s*import "modules/lock"\s*$', line):
                lines.insert(i + 1, f'import "{mod}"\n')
                changed = True
                break
        else:
            for i, line in enumerate(lines):
                if re.match(r'^\s*import Quickshell\s*$', line):
                    lines.insert(i, f'import "{mod}"\n')
                    changed = True
                    break

for mod in modules:
    inst = instances[mod]
    pattern = r'^\s*' + re.escape(inst.split()[0]) + r'\s*\{\}\s*$'
    if has(pattern):
        continue
    for i, line in enumerate(lines):
        if re.match(r'^\s*(ConfigToasts|Shortcuts|BatteryMonitor)\s*\{\}\s*$', line):
            lines.insert(i, f'    {inst}\n')
            changed = True
            break
    else:
        lines.append(f'    {inst}\n')
        changed = True

if changed:
    with open(path, "w", encoding="utf-8") as f:
        f.write("".join(lines))
    print("==> 已写入 shell.qml 钩子")
else:
    print("==> shell.qml 钩子已存在，跳过")
PY

echo "==> 同步完成: $TARGET"

if [[ "$RESTART" -eq 1 ]]; then
  echo "==> 重启 caelestia"
  qs -c caelestia kill || true
  sleep 1
  caelestia shell -d
fi
