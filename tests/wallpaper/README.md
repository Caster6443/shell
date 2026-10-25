# 原生壁纸过渡

本地扩展：27个编译效果之外追加`WallpaperTransition.Random`（原有枚举值不变）；`background.wallpaperTransitionRandomEffects`为效果key字符串列表，空列表表示全部，未知项过滤，全部无效时回退全部。UI至少保留一项；单项会重复，两项以上排除上一种。固定模式忽略随机范围，并保留范围配置。

- `QML_IMPORT_PATH=<本次编译的QML目录> QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software /usr/lib/qt6/bin/qmltestrunner -input tests/wallpaper/tst_transition_policy.qml`：真实编译shader枚举、固定效果、2700次无连续重复、指定范围及边界回退。
- `QML_IMPORT_PATH=<含新Config插件的QML目录> python tests/wallpaper/check_settings.py [截图.png]`：生产UI/后端QML、真实新Config，私有XDG与模拟配色；验证模式切换、条件显示、保留子集、最后一项保护、全选、落盘，以及生产后端100次从指定子集取值且不连续重复。UI信号调用不等同于真实指针事件；offscreen截图不替代正式桌面主题验收。

运行Config插件必须包含Random及randomEffects字段。当前本机使用`~/.local/lib/caelestia-shell-native/qml`；仅同步QML到旧系统插件会失败。设置页的入口是“壁纸与样式→过渡动画/随机效果范围”。效果选择使用页内可滚动网格，避免28项原生菜单超出窗口。

过渡生命周期：活动shader保持到上一帧捕获完成后才更换；配置修改在下一次壁纸切换时应用，不改变正在播放的过渡。
