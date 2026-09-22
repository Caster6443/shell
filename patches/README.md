# 底座文件补丁（fork 对系统包 `modules/` 的改动）

运行配置 = **系统包底座**（`/etc/xdg/quickshell/caelestia/`，`caelestia-shell-git` 已 `IgnorePkg` 锁定）
+ **fork 外挂模块**（`scripts/sync-addons.sh` 同步）+ **底座补丁**（本目录，手工维护）。

底座补丁是直接改在 `~/.config/quickshell/caelestia/` 里的本体文件（`modules/` 等），
**`sync-addons.sh` 不覆盖它们**；但一旦重新从系统包铺底座
（`sudo cp -a /etc/xdg/quickshell/caelestia/. ~/.config/quickshell/caelestia/`），补丁会丢，
需要按本目录的 `.patch` 重新应用（`patch -p1 -d ~/.config/quickshell/caelestia`）。

改补丁前先备份到 `~/Documents/bakFiles/<绝对路径镜像>`（见用户主目录 `AGENTS.md` 备份规范）。

| 补丁 | 目标文件 | 作用 |
|---|---|---|
| `launcher/wrapper-keep-alive.patch` | `modules/launcher/Wrapper.qml` | launcher 面板内容常驻 + 启动预热（修打开慢半拍/卡顿），详见 `DEVELOPMENT_LOG.md` 2026-09-11 条目 |
| `tray/tray-pinned-wechat.patch` | `modules/bar/components/Tray.qml` | 微信托盘图标常驻不收纳 |
| `utilities/vpn-right-click-mihomo-panel.patch` | `modules/utilities/cards/Toggles.qml` | VPN 快捷开关加右键 → 打开 mihomo 节点/订阅面板 |
| `utilities/utilities-mihomo-panel.patch` | `modules/utilities/Content.qml` | 面板打开时用 `MihomoPanel` 顶替三张卡片 |

另有历史遗留的两处人工改造文件（没有单独留 patch，内容在 `~/.config/quickshell/caelestia/` 与仓库对应副本中）：

- `modules/launcher/Content.qml`：launcher 面板内容改为 `SpotlightPanel`（fork 版，仓库副本一致）；
- `modules/Shortcuts.qml`：① 删除 launcherInterrupt 计数逻辑；② 2026-09-14 增加 `spotlight` IPC
  （`caelestia shell spotlight clipboard` / `spotlight open <apps|wallpaper|clipboard|emoji>`），
  由 `openSpotlight()` 打开 launcher 并预置标签页，同一标签再调一次则收回（fork 版，仓库副本一致）。
