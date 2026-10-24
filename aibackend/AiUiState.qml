pragma Singleton
import QtQuick
import Quickshell

// 主页面与编辑子页之间的临时约定：进入编辑页前写入要编辑的服务 id（空表示新建）。
Singleton {
    property string editingId: ""
}
