# Console 滚轮回归

从当前源码提取 isSmoothWheel/wheelStep；以本机真实鼠标与触摸板事件数值验证分类、方向及门槛。

```bash
python3 tests/console/generate_wheel_fixture.py /tmp/console-wheel-tests
QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software /usr/lib/qt6/bin/qmltestrunner -input /tmp/console-wheel-tests
```

离散鼠标日志：angleDelta.y=±120，pixelDelta.y=±15，phase=0。触摸板日志：phase=1/2/3，angleDelta 与 pixelDelta 随手势变化。测试不替代真实设备验证。此前菜单/剪贴板扩展的夹具随功能撤回，已镜像归档到 Documents/bakFiles，不再作为当前源码的测试入口。

当前另从源码提取 HoverHandler 验证450ms滚轮保护；15项行为测试通过，QtTest连同初始化/收尾共19 passed。实际鼠标/触摸板手感待用户确认。

菜单期间滚轮/方向键导航与关闭后恢复已纳入实际WheelHandler测试；当前17项行为测试，QtTest总计21 passed。

平铺展示新增网格左右/上下导航与列表左右忽略回归；当前19项行为测试，QtTest含初始化/收尾为23 passed。

2026-10-12：恢复应用 HoverHandler，新增平铺模式鼠标移动选中及原生滚轮不改索引测试；当前25 passed（含初始化/收尾）。


## 2026-10-13 标签层级导航、Overview 窗口菜单与单窗口尺寸

```bash
python3 tests/console/generate_navigation_fixture.py /tmp/console-navigation-tests
QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software /usr/lib/qt6/bin/qmltestrunner -input /tmp/console-navigation-tests
```

提取当前生产函数/按键/鼠标处理器及完整 WindowContextMenu；隔离外部应用数据库、主题和 Hyprland dispatch，不关闭/移动真实窗口。40 passed（含三组初始化/收尾）：主标签循环、Tab/Shift+Tab 换层、应用分类、壁纸视图循环、重新打开复位、输入保留、菜单外点击/滚轮/键盘隔离、按地址命令构建、目标消失、右键不拖拽、左键拖放、单浮动窗口释放保持坐标、星号垂直居中、单窗口横纵约束与尺寸回退。菜单浅/深色用 Qt 渲染图检查，主题/MaterialIcon 在夹具中提供最小替身，不能替代当前桌面实际主题和完整捕获动画验证。

原滚轮/悬停回归增加窗口菜单悬停门控，当前26 passed（含两组初始化/收尾）。


## 2026-10-18 软件管理与命令入口

```bash
python tests/console/test_package_backend.py
python tests/console/generate_software_fixture.py /tmp/console-software-tests
QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software /usr/lib/qt6/bin/qmltestrunner -input /tmp/console-software-tests
```

后端13项：配置精确编辑、通配符/组识别、独立检查DB、AUR局部失败、版本比较、预览/依赖失败、关注持久化、名称注入/未授权拦截。Qt17项（含初始化收尾）：真实命令按键处理器、大小写筛选、Enter/Esc、软件搜索编辑、关注排序、筛选、依赖导航、确认取消和预览入口。UI夹具仅替换进程/主题接口，不执行真实包事务。原导航fixture随第五个标签调整，40 passed；软件搜索左右键编辑不切标签。原滚轮26 passed。

2026-10-18补充：软件列表增加悬停选择、450ms键盘保护、确认冻结；软件/命令Qt回归20 passed（新增3项）。

2026-10-18应用滚轮更正：单列也使用原生滚动，移除滚轮逐项导航，保留悬停保护/键盘选择；单列滚动与边界、窗口菜单消费加入回归，共29 passed（含初始化/收尾）。

2026-10-18再次更正：应用滚轮不再使用450ms保护；静止指针随contentY变化同步选中。生成器同步提取实际onContentYChanged；滚轮/悬停29 passed，包含静止跟随、键盘保持/鼠标接管及菜单冻结，替代旧“必须再移动鼠标”的预期。软件页的键盘450ms保护是另一组件，不受影响。


## 2026-10-18 关闭重开状态

```bash
python tests/console/generate_reopen_fixture.py /tmp/console-reopen-tests
QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software /usr/lib/qt6/bin/qmltestrunner -input /tmp/console-reopen-tests
```

从生产代码提取完整onVisibleChanged、模型提交Timer、选择/刷新函数与HoverHandler，使用原生GridView/flick和模拟应用数据库。改前复现连续重开恢复currentIndex=40，修复后8 passed：顶部/高亮复位、取消惯性、关闭后的旧提交无效、跨次打开模型隔离、重复重开和可见期间DB刷新身份保留。导航夹具补齐新生命周期字段，40 passed；静止鼠标滚动29 passed。

2026-10-21 后台预翻译接入：SoftwarePage 合并 Translator 送来的译文（按 profile/模型作用域过滤），软件页 Qt 回归 34 passed（含新增合并与作用域用例）。


2026-10-22：导航生成器增加OverviewWindowGroups生产计算回归，覆盖两窗/三窗/不同宽高/首尾不等宽/单窗的实际组边界居中、1.198悬停包围边界和最小10px间距。浮动窗口释放增加多窗零位移用例。总计49 passed（含初始化/收尾）；实际捕获与最终卡片样式仍需桌面截图验收。

2026-10-23 剪贴板：`python tests/clipboard/check_edit_switch.py` 验证两宿主单击预览/双击粘贴/悬停不选与编辑保护；`python tests/clipboard/check_transfer.py` 验证隔离历史不重排及模拟焦点门控，不触碰用户剪贴板或发送真实按键。

2026-10-23 Emoji分类：`python tests/console/check_emoji.py`提取生产query/cycle验证完整1927条目分类与限定搜索，5 passed；navigation夹具增加Tab/左右分类回归，总计50 passed。

2026-10-25：生成器新增tst_flow.qml，使用QT_QUICK_BACKEND=rhi运行该文件，检查悬停中间进度/终态/回位/点击/禁用；截图/tmp/console-flow-{rest,mid,hover}.png为夹具配色。


### 更正（2026-10-25，用户要求撤回按钮流动）
用户认为没有配套玻璃材质，彩色流动显得突兀，明确要求回退。核对试用前快照后，恢复RaisedButtonSurface、SoftwareButton、ConsolePanel（仓库与运行三文件）到20261025-002019-button-flow备份，撤回两轮渐变/遮罩/色相派生/动画及本次新增hoverEnabled。当前文件差异仅属于本次试用，无其他变更被覆盖。回退前当前状态再次按绝对路径镜像备份，后缀rollback-flow。移除专属flow测试和生成器新增映射/入口；历史记录保留但以本更正为准。控制台Console改名、软件更新状态提示及其他已有功能保留。


## 2026-10-26 Overview快捷键目标
`QT_QUICK_BACKEND=software python3 tests/console/check_overview_actions.py` 提取生产函数，13 passed（含初始化/收尾），覆盖虚拟选择、空/消失窗口、菜单门控、按地址两种全屏、静默工作区启动与命令转义。导航组间距5项断言在本次修改前备份上同样失败，不据此宣称全套通过；详见开发日志。

2026-10-26焦点保护回归：check_overview_actions.py增四项，当前22 passed。实际Super+F同工作区最大化/恢复后等待0.8秒仍保留Console焦点；移出后0.5秒关闭。legacy只回退原操作，非完整焦点支持。

更正（2026-10-26）：焦点保护还须在目标fullscreen前pin当前Console，保持至本次面板隐藏，立即unset无效。夹具22 passed增加pin顺序及不立即unset断言；隔离真实测试4次生产Lua+2次按键、画面检查通过，重新打开pinned=false。
