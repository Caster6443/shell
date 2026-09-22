#!/usr/bin/env bash
# 底座升级部署：用「新装的系统包底座」重建用户配置，再铺 fork 外挂与钩子。
# 用法: bash scripts/deploy-upgrade.sh [-r]
#   -r  完成后重启 caelestia
#
# 为什么需要它：Quickshell 取 XDG 顺序里第一个配置目录——只要 ~/.config/quickshell/caelestia 存在，
# 就**整体遮蔽** /etc/xdg/quickshell/caelestia。所以 `pacman -U` 装了新版包后，若不同步重建用户配置，
# 运行期用的仍是旧 QML（新版 C++ 插件 + 旧 QML 会因配置 schema 变更而报错）。
#
# 本脚本做三件事（幂等、可回滚）：
#   1. 备份当前用户配置到 bakFiles（按备份规范镜像路径 + 时间戳）；
#   2. 从系统包底座整体重建用户配置；
#   3. 调用 sync-addons.sh 铺 fork 外挂 + 幂等写 shell.qml 钩子。
# 前提：已 `sudo pacman -U` 安装新版 caelestia-shell-git（底座 = /etc/xdg/quickshell/caelestia）。
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="${QS_CAELESTIA_DIR:-$HOME/.config/quickshell/caelestia}"
SYSTEM_CONFIG="/etc/xdg/quickshell/caelestia"
RESTART="${1:-}"

# --- 安全护栏：确认底座存在、target 是预期的 caelestia 配置目录（本脚本会 rm -rf target）---
if [[ ! -f "$SYSTEM_CONFIG/shell.qml" ]]; then
  echo "!! 系统包底座不存在或缺少 shell.qml: $SYSTEM_CONFIG" >&2
  echo "   请先安装新版包：sudo pacman -U <caelestia-shell-git-*.pkg.tar.zst>" >&2
  exit 1
fi
case "$TARGET" in
  */quickshell/caelestia) ;;
  *)
    echo "!! 拒绝执行：TARGET 不是预期的 */quickshell/caelestia（当前: $TARGET）" >&2
    echo "   如确需自定义路径，请设 QS_CAELESTIA_DIR 指向 .../quickshell/caelestia 形式。" >&2
    exit 1
    ;;
esac

STAMP="$(date +%Y%m%d-%H%M)"
BAK_ROOT="$HOME/Documents/bakFiles"
BAK="$BAK_ROOT${TARGET}"

# 1. 备份当前用户配置（按备份规范：镜像绝对路径；同路径多版本加时间戳）
if [[ -d "$TARGET" ]]; then
  mkdir -p "$(dirname "$BAK")"
  if [[ -e "$BAK" ]]; then
    cp -a "$TARGET" "${BAK}-${STAMP}"
    echo "==> 已备份旧用户配置 → ${BAK}-${STAMP}"
  else
    cp -a "$TARGET" "$BAK"
    echo "==> 已备份旧用户配置 → $BAK"
  fi
else
  echo "==> 无既有用户配置，跳过备份"
fi

# 2. 从系统包底座整体重建（清掉旧 QML 与历史残留，避免旧文件继续遮蔽）
rm -rf -- "$TARGET"
mkdir -p "$(dirname "$TARGET")"
cp -a "$SYSTEM_CONFIG" "$TARGET"
echo "==> 已从 $SYSTEM_CONFIG 重建用户配置底座"

# 3. 铺 fork 外挂 + 写钩子（sync-addons.sh 幂等；-r 透传）
bash "$REPO_DIR/scripts/sync-addons.sh" "$RESTART"

echo "==> 部署完成。校验建议：qs -c caelestia log | rg -i 'error|unable|failed'"
