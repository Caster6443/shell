# awww 壁纸后端

个人 fork 的原生后端接入；不是上游已经支持的配置选项。

- `wallpaperbackend/Backend.qml` 是受 `sync-addons.sh` 管理的外挂 Singleton。
- `native-backend.patch` 针对运行底座的 Wallpapers 服务、Background 和 Nexus 壁纸页。
- 用户配置 `background.wallpaperEnabled=true` 表示显示 awww 壁纸；内置 QML Wallpaper Loader 在外部后端下保持关闭，时钟/背景部件继续显示。
- 删除 `cli.json` 的 `wallpaper.postHook`，避免重复请求。CLI 仍负责壁纸路径状态、缓存和动态取色；Wallpapers.actualCurrent 交给后端绘制。
- 后端保持原有 random/2s/60fps/鼠标起点/invert-y，初始化不播放过渡。awww-daemon 已运行时复用，缺失时尝试启动。
- 禁用显示会用 `awww clear` 清空壁纸，重新启用恢复当前文件；不杀共享 daemon。
- 静态设置页预览使用现有 FadeImage，不捕获 awww 过渡，也不创建虚拟输出。

重铺底座后先同步外挂，再对配置目录应用补丁：

```sh
bash scripts/sync-addons.sh -r
patch -d "$HOME/.config/quickshell/caelestia" -p1 < patches/awww/native-backend.patch
```

检查 `qs -c caelestia ipc call wallpaperbackend status` 与 `awww query`。此补丁尚不由 deploy-upgrade.sh 自动应用。

回退须同时恢复三个底座文件、旧 cli.json postHook 及 wallpaperEnabled=false；不能只恢复旧 hook，否则会重复切壁纸。


更正（2026-10-25）：合并上游原生壁纸后，当前运行配置不再应用本补丁，awww-daemon已停止；本目录保留供旧方案回退。当前播放和过渡由Caelestia.Multimedia/Shader提供。
