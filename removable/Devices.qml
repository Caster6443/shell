pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    property var devices: []
    property string busyPath: ""
    property string message: ""
    property string error: ""
    readonly property bool busy: action.running
    readonly property string backend: Qt.resolvedUrl("Devices.py").toString().replace(/^file:\/\//, "")
    function remove(device: var): void {
        if (root.busy || !device) return;
        root.busyPath = device.path;
        root.message = "";
        root.error = "";
        action.command = ["python", root.backend, "remove", device.path, device.identity];
        action.running = true;
    }
    function sizeText(bytes: real): string {
        return bytes >= 1099511627776 ? (bytes / 1099511627776).toFixed(1) + " TiB" : (bytes / 1073741824).toFixed(1) + " GiB";
    }
    Process {
        id: monitor
        command: ["python", root.backend, "watch"]
        running: true
        stdout: SplitParser {
            onRead: line => {
                try {
                    const data = JSON.parse(line);
                    if (data.devices !== undefined) root.devices = data.devices;
                    if (data.error) root.error = data.error;
                } catch (e) { root.error = "读取移动设备状态失败"; }
            }
        }
        onExited: (code, status) => { root.error = "移动设备服务已停止，正在重连"; retry.restart(); }
    }
    Timer { id: retry; interval: 5000; onTriggered: monitor.running = true }
    Process {
        id: action
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    root.message = data.message || "";
                    root.error = data.error || "";
                    if (data.ok && data.message)
                        Quickshell.execDetached(["notify-send", "移动存储", data.message]);
                } catch (e) { root.error = "安全弹出失败，请重试"; }
            }
        }
        onExited: (code, status) => {
            root.busyPath = "";
            if (code !== 0 && !root.error) root.error = "安全弹出失败，设备可能正在使用";
        }
    }
}
