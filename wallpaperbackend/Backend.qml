pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia.Config

Singleton {
    id: root
    readonly property bool external: true
    readonly property bool enabled: GlobalConfig.background.wallpaperEnabled
    property string source: ""
    property string appliedSource: ""
    property string requestedSource: ""
    property bool initialised: false
    property bool pending: false
    property bool animateNext: false
    property string transitionPosition: "0.5,0.5"
    property int recoveryAttempts: 0

    function setSource(path: string): void {
        if (!path || source === path) return;
        source = path;
        pending = true;
        animateNext = initialised;
        initialised = true;
        if (enabled) readiness.running = true;
    }
    function apply(): void {
        if (!enabled || !source || render.running) return;
        pending = false;
        requestedSource = source;
        render.command = ["awww", "img", source, "--resize", "crop", "--transition-type", animateNext ? "random" : "none", "--transition-duration", "2", "--transition-fps", "60", "--transition-pos", transitionPosition, "--invert-y"];
        render.running = true;
    }
    onEnabledChanged: {
        if (enabled) { pending = true; animateNext = false; readiness.running = true; }
        else clear.running = true;
    }
    // 只保留一个 daemon：先杀掉同名进程再拉起，避免残留实例继续绘制旧壁纸。
    function recover(): void {
        if (root.recoveryAttempts >= 5) {
            console.warn("awww: recovery failed after", root.recoveryAttempts, "attempts");
            return;
        }
        root.recoveryAttempts += 1;
        Quickshell.execDetached(["sh", "-c", "pkill -x awww-daemon; sleep 0.3; exec awww-daemon"]);
        retry.restart();
    }
    Component.onCompleted: dedupe.running = true
    Process {
        id: readiness
        command: ["awww", "query"]
        onExited: (code, status) => {
            if (!root.enabled) return;
            if (code === 0) {
                root.recoveryAttempts = 0;
                if (root.animateNext) cursor.running = true;
                else root.apply();
            } else root.recover();
        }
    }
    // 每次 Shell 启动检查一次：存在多个 daemon 时清掉重开。
    Process {
        id: dedupe
        command: ["sh", "-c", "pgrep -x awww-daemon | wc -l"]
        stdout: StdioCollector { id: dedupeOut }
        onExited: (code, status) => {
            if (!root.enabled) return;
            const count = parseInt(dedupeOut.text.trim(), 10);
            if (count > 1) {
                console.warn("awww: found", count, "daemons, restarting one");
                root.recover();
            }
        }
    }
    Timer { id: retry; interval: 800; onTriggered: readiness.running = true }
    Process {
        id: cursor
        command: ["hyprctl", "cursorpos"]
        stdout: StdioCollector { onStreamFinished: root.transitionPosition = text.trim().replace(/\s/g, "") || "0.5,0.5" }
        onExited: root.apply()
    }
    Process {
        id: render
        onExited: (code, status) => {
            if (code === 0) root.appliedSource = root.requestedSource;
            else console.warn("awww wallpaper request failed:", code);
            if (root.pending) readiness.running = true;
            if (!root.enabled) clear.running = true;
        }
    }
    Process { id: clear; command: ["awww", "clear"] }
    IpcHandler {
        target: "wallpaperbackend"
        function status(): string {
            return JSON.stringify({ backend: "awww", enabled: root.enabled, source: root.source, appliedSource: root.appliedSource, running: render.running });
        }
    }
}
