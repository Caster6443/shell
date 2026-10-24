# 移动存储

托盘旁的按需 bar 入口；悬停展开原生 popout。菜单每个设备一行：名称、容量、弹出图标。失败时才追加错误；完成后桌面通知。未挂载设备也可断电。

- Devices.py：Gio 读取 UDisks2 ObjectManager，信号驱动刷新（150ms合并），无周期轮询。
- Devices.qml：单例只运行一个观察进程；操作进程独立于菜单Loader，关闭菜单不终止卸载。
- 安全弹出：重新核验外部设备身份、非系统盘、无活动swap及多槽读卡器关系；依次非强制 Unmount，重新核验后 PowerOff，缺少该能力时 Eject 或仅卸载。不挂载、不格式化、不强制卸载、不申请root/认证弹窗。中途失败时可能已有部分分区卸载，错误会显示。
- 多槽读卡器有其他介质时保守拒绝断电，避免影响其他盘；加密已解锁映射通过 CryptoBackingDevice 归组，锁定/复杂RAID的忙碌状态交由UDisks拒绝。
- 依赖：python、python-gobject、udisks2、notify-send（本机已有）。

部署：scripts/sync-addons.sh同步removable数据模块；底座连接点为patches/bar/removable-devices.patch（Bar.qml、popouts/Content.qml）。重铺底座由deploy-upgrade.sh恢复补丁；普通sync不修改本体。禁止把运行Bar整文件反灌到仓库modules。

测试：python tests/removable/test_devices.py（11项，桩操作，不弹出用户设备）。2026-10-23在实际Hyprland/Caelestia已核对USB图标和面板，29.3GiB真机只读识别；实际弹出尚未验证。

回退：先按备份规范保存当前两底座文件，再对runtime执行patch --dry-run --reverse检查后反向应用上述补丁；不必删除外挂目录。保留其他任务的改动。


补充（2026-10-23）：用户要求名称用硬件型号标识，替代泛化SCSI DISK。后端优先Drive.Model（具体型号，配厂商），SCSI模型泛化时从块设备sysfs向上查USB product；仍泛化则以USB存储 · VID:PID区分，卷标仅保留为附加数据。实查当前U盘：SCSI Vendor=SCSI/Model=DISK，USB manufacturer=USB/product=DISK，VID:PID=23a9:ef18，未提供真实品牌型号，不能臆造。现回退USB存储 · 23A9:EF18。测试fixture明确验证型号优先、卷标不取代型号，11项通过。菜单进一步收为无标题/无说明/无挂载路径的44px单行（名称、容量、eject图标），错误才展开文字。
