# AGENTS.md

本仓库是 Caelestia Shell 的个人 fork（上游：`caelestia-dots/shell`），由 Codex 负责维护。

## 仓库职责

- `main`：个人维护分支，包含 overview 外挂模块与维护文档；其余文件尽量与上游保持同步。
- `overview/`：**自包含的 overview 外挂模块**（同 `qs -c caelestia` 实例，低耦合），部署到 `~/.config/quickshell/caelestia/overview/`。
- `scripts/deploy-overview.sh`：一键部署/更新外挂到用户配置。
- `docs/overview-addon.md`：架构、踩坑记录与维护手册（**动代码前先读**）。
- `fix/storage-disk-rounding`：给上游的 PR 工作分支，与 overview 无关，不要混入。

## 快速上手

```bash
# 部署/更新 overview（-r 表示部署后重启 caelestia）
bash scripts/deploy-overview.sh -r

# 查看运行日志 / 手动开关
qs -c caelestia log
qs -c caelestia ipc call overview toggle

# 回滚到系统包配置
rm -rf ~/.config/quickshell/caelestia
```

## 关键约定（详见 docs/overview-addon.md）

- 对 caelestia 本体**零修改**：`shell.qml` 的两行钩子（`import "overview"` + `Overview {}`）由部署脚本写入用户配置，仓库内 shell.qml 保持上游原样。
- Quickshell 只自动注册**顶层目录**的 pragma Singleton：overview 的服务文件必须平铺在 `overview/` 下，通过 `import qs.overview` 使用。
- 自定义 QML 类型**避开 Qt 内置名**：`Palette` 会与 QtQuick/Palette 撞车，已改名 `M3Palette`。
- 全屏 overlay layer 会抢占所有输入（历史事故）：overview 必须保持左侧面板形态 + 输入安全设计。
- `qmllint` 对含 Quickshell 类型的文件会静默崩溃（退出 255 无输出），**不可靠**；验证以 `qs -c caelestia log` 实际运行日志为准。

## 上游同步

```bash
git fetch upstream
git merge upstream/main
```

`overview/`、`scripts/deploy-overview.sh`、`docs/`、`AGENTS.md` 与上游无路径冲突；若上游改动了 `shell.qml` 或相关 API，检查部署脚本的钩子逻辑与模块对 Quickshell API 的使用。
