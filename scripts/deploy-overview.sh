#!/usr/bin/env bash
# 部署 overview 外挂到用户级 caelestia 配置。
# 用法: bash scripts/deploy-overview.sh [-r]
#   -r  部署完成后重启 caelestia
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="${QS_CAELESTIA_DIR:-$HOME/.config/quickshell/caelestia}"
SYSTEM_CONFIG="/etc/xdg/quickshell/caelestia"
RESTART=0
[[ "${1:-}" == "-r" ]] && RESTART=1

# 1. 用户配置缺失时，从系统包整体复制（用户目录遮蔽 /etc/xdg）
if [[ ! -f "$TARGET/shell.qml" ]]; then
  echo "==> 从系统包初始化用户配置: $TARGET"
  cp -a "$SYSTEM_CONFIG/." "$TARGET/"
fi

# 2. 同步 overview 模块
echo "==> 同步 overview 模块到 $TARGET/overview"
mkdir -p "$TARGET"
cp -a "$REPO_DIR/overview/." "$TARGET/overview/"

# 3. 幂等写入 shell.qml 钩子（import "overview" + Overview {}）
python3 - "$TARGET/shell.qml" <<'PY'
import re
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    lines = f.read().splitlines(keepends=True)

changed = False

def has(pattern: str) -> bool:
    return any(re.search(pattern, line) for line in lines)

if not has(r'^\s*import "overview"\s*$'):
    for i, line in enumerate(lines):
        if re.match(r'^\s*import "modules/lock"\s*$', line):
            lines.insert(i + 1, 'import "overview"\n')
            changed = True
            break
    else:
        for i, line in enumerate(lines):
            if re.match(r'^\s*import Quickshell\s*$', line):
                lines.insert(i, 'import "overview"\n')
                changed = True
                break

if not has(r'^\s*Overview\s*\{\}\s*$'):
    for i, line in enumerate(lines):
        if re.match(r'^\s*(ConfigToasts|Shortcuts|BatteryMonitor)\s*\{\}\s*$', line):
            lines.insert(i, '    Overview {}\n')
            changed = True
            break
    else:
        lines.append('    Overview {}\n')
        changed = True

if changed:
    with open(path, "w", encoding="utf-8") as f:
        f.write("".join(lines))
    print("==> 已写入 shell.qml 钩子")
else:
    print("==> shell.qml 钩子已存在，跳过")
PY

echo "==> 部署完成: $TARGET"

if [[ "$RESTART" -eq 1 ]]; then
  echo "==> 重启 caelestia"
  qs -c caelestia kill || true
  sleep 1
  caelestia shell -d
fi
