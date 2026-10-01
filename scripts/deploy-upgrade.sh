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
# 本地运行补丁：先 dry-run；若新版包已包含则跳过，否则不匹配时明确失败。
UTILITIES_PATCH="$REPO_DIR/patches/utilities/synchronous-content.patch"
if patch --dry-run --forward --batch -p1 -d "$TARGET" < "$UTILITIES_PATCH" >/dev/null 2>&1; then
  patch --forward --batch -p1 -d "$TARGET" < "$UTILITIES_PATCH"
elif patch --dry-run --reverse --batch -p1 -d "$TARGET" < "$UTILITIES_PATCH" >/dev/null 2>&1; then
  echo "==> utilities 同步加载补丁已包含，跳过"
else
  echo "!! utilities 同步加载补丁与新底座不匹配，请检查后再重启" >&2
  exit 1
fi
# Dashboard 分页只在与视口有实际交集时预加载，边界相触不算可见。
DASHBOARD_VISIBLE_PATCH="$REPO_DIR/patches/dashboard/dashboard-visible-intersection.patch"
if patch --dry-run --forward --batch -p1 -d "$TARGET" < "$DASHBOARD_VISIBLE_PATCH" >/dev/null 2>&1; then
  patch --forward --batch -p1 -d "$TARGET" < "$DASHBOARD_VISIBLE_PATCH"
elif patch --dry-run --reverse --batch -p1 -d "$TARGET" < "$DASHBOARD_VISIBLE_PATCH" >/dev/null 2>&1; then
  echo "==> dashboard 视口交集预加载补丁已包含，跳过"
else
  echo "!! dashboard 视口交集预加载补丁与新底座不匹配，请检查后再重启" >&2
  exit 1
fi
# Dashboard 音频导入是底座媒体页的局部补丁，连同组件文件一并部署。
AUDIO_IMPORT_PATCH="$REPO_DIR/patches/dashboard/media-audio-import.patch"
if patch --dry-run --forward --batch -p1 -d "$TARGET" < "$AUDIO_IMPORT_PATCH" >/dev/null 2>&1; then
  patch --forward --batch -p1 -d "$TARGET" < "$AUDIO_IMPORT_PATCH"
elif patch --dry-run --reverse --batch -p1 -d "$TARGET" < "$AUDIO_IMPORT_PATCH" >/dev/null 2>&1; then
  echo "==> dashboard 音频导入补丁已包含，跳过"
else
  echo "!! dashboard 音频导入补丁与新底座不匹配，请检查后再重启" >&2
  exit 1
fi
# 媒体页文本输入时临时为 Dashboard 图层申请键盘焦点。
DASHBOARD_INPUT_FOCUS_PATCH="$REPO_DIR/patches/dashboard/media-input-focus.patch"
if patch --dry-run --forward --batch -p1 -d "$TARGET" < "$DASHBOARD_INPUT_FOCUS_PATCH" >/dev/null 2>&1; then
  patch --forward --batch -p1 -d "$TARGET" < "$DASHBOARD_INPUT_FOCUS_PATCH"
elif patch --dry-run --reverse --batch -p1 -d "$TARGET" < "$DASHBOARD_INPUT_FOCUS_PATCH" >/dev/null 2>&1; then
  echo "==> dashboard 输入焦点补丁已包含，跳过"
else
  echo "!! dashboard 输入焦点补丁与新底座不匹配，请检查后再重启" >&2
  exit 1
fi
# Cosmos/Astral full-screen lock: restore its LockSurface patch after rebuilding the package baseline.
COSMOS_LOCK_PATCH="$REPO_DIR/patches/lock/cosmos-lockscreen.patch"
if patch --dry-run --forward --batch -p1 -d "$TARGET" < "$COSMOS_LOCK_PATCH" >/dev/null 2>&1; then
  patch --forward --batch -p1 -d "$TARGET" < "$COSMOS_LOCK_PATCH"
elif patch --dry-run --reverse --batch -p1 -d "$TARGET" < "$COSMOS_LOCK_PATCH" >/dev/null 2>&1; then
  echo "==> Cosmos 全屏锁屏补丁已包含，跳过"
else
  echo "!! Cosmos 全屏锁屏补丁与新底座不匹配，请检查后再重启" >&2
  exit 1
fi
# Nexus lock-style selector page (kept in the addon; the registries are base files).
NEXUS_LOCK_STYLE_PATCH="$REPO_DIR/patches/lock/nexus-lock-style.patch"
if patch --dry-run --forward --batch -p1 -d "$TARGET" < "$NEXUS_LOCK_STYLE_PATCH" >/dev/null 2>&1; then
  patch --forward --batch -p1 -d "$TARGET" < "$NEXUS_LOCK_STYLE_PATCH"
elif patch --dry-run --reverse --batch -p1 -d "$TARGET" < "$NEXUS_LOCK_STYLE_PATCH" >/dev/null 2>&1; then
  echo "==> Nexus 锁屏样式设置页补丁已包含，跳过"
else
  echo "!! Nexus 锁屏样式补丁与新底座不匹配，请检查后再重启" >&2
  exit 1
fi
# Nexus Hyprland layout selector (applied after Nexus lock-style adds its registry entry).
NEXUS_HYPRLAND_LAYOUT_PATCH="$REPO_DIR/patches/layout/nexus-hyprland-layout.patch"
if patch --dry-run --forward --batch -p1 -d "$TARGET" < "$NEXUS_HYPRLAND_LAYOUT_PATCH" >/dev/null 2>&1; then
  patch --forward --batch -p1 -d "$TARGET" < "$NEXUS_HYPRLAND_LAYOUT_PATCH"
elif patch --dry-run --reverse --batch -p1 -d "$TARGET" < "$NEXUS_HYPRLAND_LAYOUT_PATCH" >/dev/null 2>&1; then
  echo "==> Nexus Hyprland 布局切换补丁已包含，跳过"
else
  echo "!! Nexus Hyprland 布局补丁与新底座不匹配，请检查后再重启" >&2
  exit 1
fi
cp -a "$REPO_DIR/modules/nexus/pages/hyprland" "$TARGET/modules/nexus/pages/"

bash "$REPO_DIR/scripts/sync-addons.sh" "$RESTART"

echo "==> 部署完成。校验建议：qs -c caelestia log | rg -i 'error|unable|failed'"
