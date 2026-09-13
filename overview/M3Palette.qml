pragma Singleton

import QtQuick
import Quickshell
import qs.services

// 配色代理：跟随 caelestia 运行时调色板（qs.services.Colours），不再自己读 scheme.json。
//
// 历史坑（2026-09-11 修，用户反馈「切换明暗主题后启动器部分配色不变、要重启 shell」）：
// 这里原本是 `FileView { path: scheme.json; watchChanges: true; onLoaded: scheme = ... }`，
// 缺了 `onFileChanged: reload()`。Quickshell 的 FileView 在 watchChanges 下**只发
// fileChanged、不自动重读**（源码 `src/io/fileview.cpp`：`onWatchedFileChanged()` 里补挂
// watch 后 `emit fileChanged()`，重读要 QML 侧显式调 `reload()`），所以本单例永远停在
// 首次读到的配色。上游 `services/Colours.qml` 正是靠 `onFileChanged: reload()` 才跟得上，
// 而 launcher 面板背景用的是 `Colours.tPalette`（会更新）→ 内外配色不一致，看着发花/发糊。
//
// 现在直接代理 `Colours.palette`（上游面板同源）：主题切换、配色预览、壁纸取色都会实时跟随。
Singleton {
	id: root

	readonly property bool light: Colours.light

	readonly property color m3surface: Colours.palette.m3surface
	readonly property color m3surfaceBright: Colours.palette.m3surfaceBright
	readonly property color m3surfaceContainer: Colours.palette.m3surfaceContainer
	readonly property color m3surfaceContainerHigh: Colours.palette.m3surfaceContainerHigh
	readonly property color m3surfaceContainerHighest: Colours.palette.m3surfaceContainerHighest
	readonly property color m3surfaceVariant: Colours.palette.m3surfaceVariant
	readonly property color m3onSurface: Colours.palette.m3onSurface
	readonly property color m3onSurfaceVariant: Colours.palette.m3onSurfaceVariant
	readonly property color m3outline: Colours.palette.m3outline
	readonly property color m3outlineVariant: Colours.palette.m3outlineVariant
	readonly property color m3primary: Colours.palette.m3primary
	readonly property color m3primaryContainer: Colours.palette.m3primaryContainer
	readonly property color m3onPrimaryContainer: Colours.palette.m3onPrimaryContainer
	readonly property color m3secondary: Colours.palette.m3secondary
	readonly property color m3tertiary: Colours.palette.m3tertiary
	readonly property color m3onTertiaryContainer: Colours.palette.m3onTertiaryContainer
}
