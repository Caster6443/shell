# Overview 外挂模块维护手册

## 背景与需求

用户（caster6443）使用 Caelestia（基于 Quickshell 的 shell）。早年 fork 分支里有 overview（工作区总览）模块，因上游 caelestia 破坏性变更停止维护。2026-08-18 重新移植，明确要求：

1. **与 caelestia 同一个 quickshell 实例**（`qs -c caelestia`），不单独起进程；
2. **低耦合、高模块化**：overview 自包含，不依赖 caelestia 内部组件/服务，上游更新不易破坏；
3. 对 caelestia 本体改动尽可能小（实际只动 `shell.qml` 两行钩子）。

## 部署模型

- 系统包 `caelestia-shell` 的配置位于 `/etc/xdg/quickshell/caelestia/`，由 `caelestia shell`（即 `qs -c caelestia`）加载。
- Quickshell 按 XDG 目录顺序查找 `<xdg>/quickshell/<名字>/shell.qml`，因此用户级目录 `~/.config/quickshell/caelestia/` **整体遮蔽系统包配置**——这是"本地复制一份、不碰系统包"的机制。
- 部署脚本将本仓库 `overview/` 同步到 `~/.config/quickshell/caelestia/overview/`，并在用户配置的 `shell.qml` 里写入两行钩子。

## 模块结构（`overview/`）

| 文件 | 职责 |
|---|---|
| `Overview.qml` | 模块入口：`OverviewWindow` + `HotCorner` + `IpcHandler(target "overview")` |
| `OverviewWindow.qml` | 左侧滑出面板（贴 bar 右侧，宽度 0→内容宽度动画） |
| `OverviewContent.qml` | 内容：hyprctl 窗口同步、线性布局、拖拽、滚轮、壁纸背景 |
| `HotCorner.qml` | 左上角 2×2 热区（150ms 悬停触发） |
| `WorkspaceCard.qml` | 工作区卡片（壁纸背景 + 窗口预览层 + DropArea） |
| `WindowPreview.qml` | 窗口缩略图（ScreencopyView，clip 圆角，支持拖拽/中键关闭） |
| `M3Palette.qml` | 单例 M3 色板，读 `~/.local/state/caelestia/scheme.json` |
| `OverviewState.qml` | 单例 active 状态 |
| `HyprDispatch.qml` | 统一 dispatch（兼容旧命令与 lua 版 `hl.dsp`） |
| `HyprlandData.qml` | `hyprctl clients/workspaces` 数据 |

模块只依赖 Quickshell 公共 API（`PanelWindow`、`WlrLayershell`、`HyprlandFocusGrab`、`ScreencopyView`、`Quickshell.Io`）与 caelestia 的 `qs.services.ShellState`（仅用于取 bar 宽度）。

## 输入安全设计（历史事故教训）

早期版本是**全屏透明 overlay**，一旦可见，Wayland 把所有指针事件路由给它，`forceActiveFocus()` 又拿走键盘焦点；ESC 关闭逻辑还放在内容 Loader 内部，内容未加载时无出口 → 只能强制重启。

现设计：

- 窗口只占左侧一列（anchors top/bottom/left + 宽度动画），不拦截其余屏幕；
- 仅 `OverviewState.active` 时窗口可见/收键盘焦点（`OnDemand`）；
- ESC 在窗口层直接处理，不依赖内容加载；
- `HyprlandFocusGrab.onCleared` 兜底复位；
- Hyprland 侧救援：`SUPER + Tab`（IPC toggle）与 `CTRL + SUPER + SHIFT + R`（`qs -c caelestia kill`）。

## IPC 与键位

- IPC 目标：`overview`，方法 `toggle/open/close/setVisible`。
- Hyprland 键位（`~/.config/hypr/hyprland/keybinds.lua`）：`SUPER + Tab` → `qs -c caelestia ipc call overview toggle`。
- 自启动：由 caelestia 本体负责（`execs.lua` 里 `caelestia shell -d`），overview 无需独立自启动。

## 已踩的坑（务必遵守）

1. **`Palette` 撞名**：QtQuick 自带 `Palette` 类型，自定义 `Palette.qml` 注册会被抢占，所有 `Palette.m3xxx` 解析为 undefined（日志出现 `Property 'colour' of object QtQuick/Palette is not a function`）。→ 改名 `M3Palette`。
2. **Quickshell 顶层目录单例**：pragma Singleton 只在配置根目录的**顶层子目录**自动注册（如 `qs.services`）。嵌套目录（如 `overview/services/`）不生效；相对导入 + qmldir 也不可靠。→ 服务文件平铺在 `overview/`，`import qs.overview`。
3. **函数返回类型注解**：QML 函数若没有返回类型注解，Qt 会把返回值当 void 丢弃（`should be coerced to void...`）。`M3Palette.colour()` 必须保留 `: color`。
4. **ScreencopyView 遮罩**：给 `ScreencopyView` 叠加 `MultiEffect` 遮罩时，maskSource 矩形必须有不透明颜色，否则画面被整体 mask 成透明（缩略图空白）。当前实现干脆不用 layer 遮罩，改用根 Rectangle `clip: true` 圆角裁剪（与 caelestia windowinfo 一致）。
5. **全屏层抢输入**：见上文输入安全设计。
6. **`qmllint` 不可靠**：对含 Quickshell 类型的文件退出 255 且无输出，不能作为验证依据。
7. **`caelestia shell -k` 路径不一致**：实例按配置路径注册；复制配置后必须杀掉旧路径实例并清空 `/run/user/1000/quickshell/by-*` 残留，否则 `-k` 报 `No running instances` 且 `-n` 误判已在运行。

## 维护流程

### 部署/更新

```bash
bash scripts/deploy-overview.sh -r
```

脚本行为：用户配置缺失时从 `/etc/xdg/quickshell/caelestia` 整体复制 → 同步 `overview/` → 幂等写入 shell.qml 钩子 → 可选重启。

### 测试

1. `qs -c caelestia log` 确认 `Configuration Loaded` 且无 error/warning；
2. `qs -c caelestia ipc call overview toggle` 开关一次，再查日志；
3. 目视：面板从左滑出、贴 bar 右侧、卡片有壁纸背景、窗口有画面、ESC/SUPER+Tab 可关。

### 上游同步

```bash
git fetch upstream && git merge upstream/main
```

同步后重点检查：部署脚本的钩子插入位置是否仍适用（`import "modules/lock"`、`ConfigToasts/Shortcuts/BatteryMonitor` 行），以及模块用到的 Quickshell API（`Hyprland.toplevels`、`ScreencopyView.captureSource`、`HyprlandFocusGrab`）是否变化。

### 回滚

```bash
rm -rf ~/.config/quickshell/caelestia   # 回到系统包配置
```

## 已知限制

- 内容按单屏逻辑（`Hyprland.focusedMonitor`）编写，多显示器下窗口预览尺寸计算待适配。
- 非当前工作区的窗口可能没有 wayland surface（Hyprland 不提交离屏 surface），缩略图为空属预期。
