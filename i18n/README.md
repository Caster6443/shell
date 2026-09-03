# caelestia fork i18n（个人汉化，非硬编码）

目标：上游 QML 保持英文 qsTr 原文（合并零冲突），翻译以 `.ts/.qm` 形式放在本目录，
由插件加载器按系统 locale 自动加载；未翻译条目自动回退英文（常见术语可保持不翻）。

## 结构

- `plugin-translations.patch`：给 `caelestia-shell-git` 插件加的翻译加载器
  （`plugin/src/Caelestia/translations.cpp`），模块被 QML import 时按
  `~/.config/quickshell/caelestia/translations/` 加载 `caelestia_zh_CN.qm`。
- `translations/caelestia_zh_CN.ts`：lupdate 抽取的原文 + 中文翻译（未翻译=回退英文）。
- `update-translations.sh`：lupdate/lrelease + 部署 .qm 到用户配置目录。

## 使用

1. 翻译：用 Linguist（`linguist6`）或直接编辑 `.ts`，只翻想要的条目。
2. 编译并部署：`bash i18n/update-translations.sh`。
3. 重新编译插件（使加载器生效）：
   ```bash
   cd ~/.cache/yay/caelestia-shell-git
   git apply ~/Github_repos/shell/i18n/plugin-translations.patch
   makepkg -efi
   ```
   之后重启 caelestia（`caelestia shell -k && caelestia shell -d`）。

## 注意

- IgnorePkg 已锁 `caelestia-shell-git`，本流程即"手动更新"路径的一部分。
- 系统 locale 需为 `zh_CN`（加载器用 `QLocale::system().name()` 匹配）。
