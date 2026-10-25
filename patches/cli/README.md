# CLI 自动明暗阈值

来源：本机 caelestia-cli-git 1.1.3.r6.g66232f7-1 的 utils/wallpaper.py。局部维护补丁，不替换整个CLI。

壁纸平均色HCT tone门槛60→50；cli.json支持 wallpaper.smartLightThreshold（0–100，默认50）。smart.json加入_lightThreshold，旧缓存或门槛变化时重算，保留动态variant选择与--no-smart语义。手动模式仍走原有scheme命令。

检查：python scripts/apply-cli-smart-threshold.py
安装：sudo python scripts/apply-cli-smart-threshold.py --apply

升级CLI包后先检查。脚本检查正反向补丁，只在匹配时应用并按原绝对路径镜像备份；不自动覆盖未知新版源码。Shell的deploy-upgrade.sh不管理系统CLI，不将本补丁混入QML部署。首次安装由用户终端sudo完成，2026-10-22核对源文件SHA256通过。


### 2026-10-25 视频壁纸支持差异
系统CLI包仍为1.1.3.r6.g66232f7，已将官方main的utils/wallpaper.py视频识别、FFmpeg首帧/分辨率处理接入，并保留本地smartLightThreshold规则；差异保存video-wallpaper.patch（基线为已有阈值补丁的旧CLI）。这属于包文件的本地维护补丁，不代表CLI包版本已经升级。FFmpeg已安装；桌面视频播放及恢复静态壁纸已实测。回退旧CLI文件见本次操作记录的before-native-video-reconstructed备份，保留该来源标记。
