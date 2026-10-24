# AI 后端回归

- `python tests/ai/test_backend.py`：31项隔离测试，凭据隔离/权限、地址绑定、三种适配器、缓存失效、限额原子预占与错误脱敏。网络/密钥环为桩。预翻译相关：批量缓存与队列推进、新增/描述变化重排、卸载清理、解析失败三次后跳过、输出预算约束、状态查询不接触网络与凭据、模型变化重新排队。
- `python tests/ai/check_transport.py`：临时XDG、合成密钥、回环HTTP服务，真实子进程调用。验证默认禁用、模型发现、认证头、翻译缓存、跨进程计数/限额和重定向不转发认证。需要本机socket权限。
- `python tests/ai/check_translator.py`：真实 `qs -p` 进程 + 私有XDG/D-Bus + 临时pacman库（`CAELESTIA_PACMAN_DB`）+ 回环模拟服务，验证 Translator 单例随 Shell 启动、索引5个包、一次批量全部翻译并写入缓存、无网络外请求、无告警。不接触真实密钥/API/包管理。
- `python tests/ai/check_ui.py [截图路径]`：实际Ai.qml/AiSettings.qml、Python后端及主题组件，私有XDG/D-Bus，回环模拟服务。验证设置保存、默认不发请求、模型发现、生成、翻译缓存、取消后队列继续。使用模拟Colours及drawers窗口类型；软件渲染关闭Flickable遮罩，容许宿主初始化时现有Menu空窗口告警和offscreen mask提示。不能替代真实桌面视觉或密钥环/付费服务验证。
- 软件页翻译回归在 `tests/console/generate_software_fixture.py`，34 passed（含初始化/收尾），包含后台预翻译结果合并、作用域过滤、默认关闭、失败不循环、过期结果隔离、本地缓存和隐藏不请求。

这些测试不读取用户真实API Key；“测试密钥”均无效合成值。接口适配器测试通过不代表每家服务的所有参数/模型均兼容。

2026-10-21：新增setModel不接触凭据/不发网络且持久保存模型；实际UI集成从空模型起步，选择后验证配置持久化再执行模拟生成/翻译。软件页新增缺模型提示回归。

2026-10-21 后台预翻译：后端扫描 pacman 本地库建索引，按批（默认8条）翻译并在 SQLite 记录 cache_key；Translator 单例以 low 优先级推进，交互请求优先。`check_translator.py` 用真实 Quickshell 进程验证该链路。推理模型需把单次输出上限调到 1024–2048，否则整批可能返回空正文（表现为 `response` 错误而不是静默失败）。

- `python tests/ai/shot_ai_settings.py [输出.png] [--edit]`：离屏渲染真实 AiSettings 整页（模拟配色、私有 XDG、模拟服务配置，无网络/无真实密钥），用于检查信息层级与排版。`--edit` 展开编辑表单。截图不能替代实机主题观感。

- 设置页拆分（2026-10-21）：`AiSettings` 是主页（概览、服务列表、功能开关、用量入口）；`AiServiceEditorPage` 编辑单个服务（新建与编辑共用，id 由 `AiUiState.editingId` 传入），`AiUsagePage` 放今日请求与限额。`check_ui.py` 用编辑页跑保存/模型/翻译流程，并额外实例化 `AiSettings` 确认主页可加载。

2026-10-21：新增限额开关（关闭后不限次数、单次输出上限放开到 16384，显式 maxTokens 仍生效）；`check_ui.py` 增加“获取模型后列表自动展开”的断言。

样式检查：shot_ai_settings.py 支持 --theme / --native / --compact；分别渲染主页、编辑、新建、用量与限额关闭状态。均为私有配置/模拟服务，可选读取当前scheme色板，不读取真实密钥；check_ui保留原交互验证。
