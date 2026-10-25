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
| `session/qt612-gif-source-size.patch` | `modules/session/Content.qml` | 绕过本机 Qt 6.12.0 AnimatedImage 设置 sourceSize 后递归崩溃；不指定 GIF 解码尺寸，保留显示尺寸与 PreserveAspectFit |
| `layout/nexus-hyprland-layout.patch` | Nexus `PageRegistry.qml`、`PageCompRegistry.qml` 与新增 `pages/hyprland/HyprlandLayout.qml` | 设置中心增加 Hyprland 布局页，可在四种内置布局间即时切换，并同步滚动布局专属参数、Shift+滚轮快捷键和工作区动画方向（Scrolling 纵向、平铺横向）；三指横滑在 Scrolling 下滚列、其他布局下跟手切换工作区；页面打开时读取实际布局状态 |
| `lock/cosmos-lockscreen.patch` | `modules/lock/LockSurface.qml` | 当前正式锁屏按 Caelestia 实际亮暗主题分别加载 Nexus 设置中指定的样式（默认浅色 Enso、深色 Cosmos）；仍由 Caelestia PAM 认证；`deploy-upgrade.sh` 自动应用 |
| `lock/nexus-lock-style.patch` | Nexus `PageRegistry.qml`、`PageCompRegistry.qml` | 在 Caelestia 图形化设置中心新增“锁屏”页入口，设置页由 `lockcosmos/LockStylePage.qml` 提供；`deploy-upgrade.sh` 自动应用 |
| `background/desktop-clock-calendar.patch` | `modules/background/DesktopClock.qml` | 保留大号时钟与原主题风格；文字强调色使用壁纸动态生成的 `primary/secondary/tertiary`，开启反转颜色时改用对应容器色；星期/日期共用周一开始的 7 列网格，仅绘制本月日期并按需显示 4–6 周；时间顶部下方沿用原三张 96×126 卡片尺寸，改为显示未来逐小时的时间、降水概率、图标和温度，滚轮按小时浏览；待办与闹钟页使用 `Colours.palette` 壁纸动态主色（启用/未完成条目强调、已完成/停用条目弱化）；日期格用 ButtonBase 整格接收点击，点击本月日期后切换到当日待办清单，待办与闹钟界面复用桌面时钟配置的底板透明度并带淡入淡出/轻缩放转场；待办到期时整张卡片切换成提醒场景并播放由 `~/.config/quickshell/caelestia/desktop-clock.json` 的 `reminderGif` 单独指定的 GIF（默认回退到 `paths.mediaGif`，不影响 Dashboard），按比例填满原组件尺寸并尝试以圆角 Mask 裁切；左上角标题、右上角任务名、底部居中的操作按钮；发出一次桌面通知，9 秒后自动返回；点击时钟时间切换整个组件到闹钟设置页，支持名称、一次/每周与周日到周六逐日多选、启停、删除及 10 分钟稍后提醒 |
| `background/desktop-todo-keyboard-focus.patch` | `modules/background/Background.qml` | 仅待办视图显示时，将背景层 shell 的键盘焦点设为 Exclusive，确保待办控件可交互；返回日历后恢复 None |
| `drawers/drawer-clock-input-hole.patch` | `modules/drawers/Regions.qml` | 先将桌面时钟矩形 Combine 到基础 Region；由于外层使用 Xor，这会让时钟区域从 drawers 最终输入区中排除。此操作排在各面板 Region 前，使通知等可交互面板随后重新纳入输入区，避免与右上角时钟重叠时失去点击/拖动；与 Background Loader 引用 alias 配套 |
| `dashboard/dashboard-visible-intersection.patch` | `modules/dashboard/Content.qml` | Dashboard 分页仅在当前页或与视口有实际像素交集时加载；排除仅在边缘相触的相邻页，避免闲置媒体页提前启动音频可视化；deploy-upgrade.sh 自动应用 |
| `dashboard/media-audio-import.patch` | `modules/dashboard/media/LyricsAndSelector.qml`、新增 `AudioImport.qml` / `AudioImportCheck.py` | 后端选择器旁的下载胶囊（MPD 后端隐藏）、回车直接下载、MP3 音频包重复拦截、歌手标签输入、默认目录持久化；等待 MPD 音乐库扫描完成后将新音频加入当前队列；deploy-upgrade.sh 自动应用 |
| `dashboard/media-input-focus.patch` | `ContentWindow.qml`、`Media.qml`、`LyricsAndSelector.qml`、`AudioImport.qml`、`ScreenState.qml` | Shell 文本输入与 Fcitx 兼容：输入聚焦时用 layer-shell OnDemand、暂停 HyprlandFocusGrab；覆盖 Console 与媒体胶囊；deploy-upgrade.sh 自动应用 |
| `services/weather-qweather.patch` | `services/Weather.qml`、Nexus `LanguageAndRegion.qml`、Dashboard 天气页与地区选择器及 Content 传参 | 和风天气与区县名称；启动单次定位、有限重试；Dashboard 搜索城市/区县并保存精确地区 ID，选择后立即刷新三类天气；设置页手动位置与重新定位。重铺底座后在现有 Dashboard 补丁之后手动应用 |
| `utilities/synchronous-content.patch` | `modules/utilities/Wrapper.qml` | 小菜单同步创建，避免异步创建期间图标重叠；deploy-upgrade.sh 自动应用，不增加 Ready 显示门控 |
| `launcher/wrapper-keep-alive.patch` | `modules/launcher/Wrapper.qml` | launcher 面板内容常驻 + 启动预热（修打开慢半拍/卡顿），详见 `DEVELOPMENT_LOG.md` 2026-09-11 条目 |
| `tray/tray-pinned-wechat.patch` | `modules/bar/components/Tray.qml` | 微信托盘图标常驻不收纳 |
| `bar/battery-fan-curves.patch` | `modules/bar/popouts/Battery.qml` | 电池/电源弹出面板增加风扇曲线三档；默认跟随省电/平衡/性能档，手动切换仅改当前 ASUS profile 的风扇曲线 |
| `bar/fan-curve-state.patch` | `services/FanCurveState.qml` | 用常驻服务单例保存手动风扇档，弹出面板 Loader 关闭后状态仍保留 |
| `bar/fan-curve-state.patch` | `services/FanCurveState.qml` | 全局 Singleton 保存风扇档选择，避免 Battery 弹出面板 Loader 销毁后丢失覆盖状态 |

另有历史遗留的两处人工改造文件（没有单独留 patch，内容在 `~/.config/quickshell/caelestia/` 与仓库对应副本中）：

- `modules/launcher/Content.qml`：已恢复为 Caelestia 原版启动器内容；Console 不再嵌入 launcher。
- `modules/Shortcuts.qml`：删除 launcherInterrupt 计数逻辑；Console IPC 由顶层 `Console.qml` 注册，改为打开独立浮窗。

| `ai/nexus-ai-settings.patch` | Nexus `PageRegistry.qml`、`PageCompRegistry.qml` | 共用 AI 服务设置入口，页面与后端由 `aibackend/` 外挂提供；升级脚本在锁屏/布局补丁之后应用，凭据不入仓库 |


### CLI自动明暗阈值（2026-10-22）
系统CLI的壁纸smart-mode局部补丁见[cli/README.md](cli/README.md)，检查入口`python scripts/apply-cli-smart-threshold.py`，不属于QML底座部署。

### Bar移动存储（2026-10-23）
`bar/removable-devices.patch`连接Bar与popout到`removable/`外挂；插入设备时托盘旁显示USB图标。普通sync只同步外挂，重铺底座由deploy-upgrade恢复两个连接点。后端与测试范围见`removable/README.md`。


### 2026-10-25 原生壁纸试用部署
上游已合并至2e1c51fa，当前正式用户配置使用新Visual/Shader底座及~/.local/lib/caelestia-shell-native/qml插件（shell.qml的Env pragma指定），系统caelestia-shell-git包仍为旧版。当前不应用awww补丁，旧wallpaperbackend源码仅保留供回退。不要直接用旧系统包重铺当前用户目录；将来正式打包安装新底座后再切换部署来源。桌面时钟GIF补丁已重基并移除AnimatedImage.sourceSize，部署后必须运行 `python tests/background/check_gif_source_size.py`，以防Qt 6.12已知递归崩溃复发。当前维护patch已按新底座调整，尚未把旧deploy-upgrade脚本当作本次用户级插件试用的一键重建入口。
