#!/usr/bin/env bash
# 扫出所有可见 .desktop 的分类和搜索字段，输出：
#   `id<TAB>Categories<TAB>searchText`
# searchText 同时收集默认及所有本地化版本的 Name / GenericName / Keywords / Comment，
# 因而中文界面的应用也能用英文名搜索，反之亦然。
#
# 为什么不用 QML 对象上的 categories 属性（2026-09-14 用户实测"影音分类是空的"）：
# caelestia 的 AppDb 把应用包装成 AppEntry（内部 DesktopEntry 是 QObject*），运行期从 QML 读
# `entry.categories` 拿到的是空值，导致所有应用都落到「其他」。自己扫 .desktop 文件最稳。
#
# 输出顺序即优先级（先出现的胜出）：XDG_DATA_HOME → XDG_DATA_DIRS → flatpak exports。
set -u

dirs="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
for d in $(printf '%s' "${XDG_DATA_DIRS:-/usr/local/share:/usr/share}" | tr ':' ' '); do
	dirs="$dirs $d/applications"
done
dirs="$dirs /var/lib/flatpak/exports/share/applications ${XDG_DATA_HOME:-$HOME/.local/share}/flatpak/exports/share/applications"

for d in $dirs; do
	[ -d "$d" ] || continue
	for f in "$d"/*.desktop; do
		[ -f "$f" ] || continue
		awk -v id="$(basename "$f" .desktop)" '
			BEGIN { inDesktop = 0 }
			/^\[Desktop Entry\]$/ { inDesktop = 1; next }
			/^\[/ { if (inDesktop) inDesktop = 0; next }
			!inDesktop { next }
			{
				pos = index($0, "=")
				if (pos == 0) next
				key = substr($0, 1, pos - 1)
				value = substr($0, pos + 1)
				if (key == "NoDisplay") nd = value
				else if (key == "Categories") c = value
				else if (key ~ /^(Name|GenericName|X-GNOME-FullName|Keywords|Comment)(\[[^]]+\])?$/)
					search = search " " value
			}
			END {
				if (nd != "true") {
					gsub(/[\t\r\n]+/, " ", search)
					printf "%s\t%s\t%s\n", id, c, search
				}
			}
		' "$f"
	done
done | awk -F'\t' '!seen[$1]++ {print}'
