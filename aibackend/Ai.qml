pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    property var state: ({enabled:false, translation:false, active:"", profiles:[], limits:{daily:100,minute:10,outputTokens:512}, usage:[], todayRequests:0})
    property bool loaded: false
    property var queue: []
    property var current: null
    property int serial: 0
    readonly property bool busy: current !== null
    readonly property var activeProfile: state.profiles.find(p => p.id === state.active) || null
    readonly property bool translationEnabled: loaded && state.enabled && state.translation && !!activeProfile?.model
    signal completed(string requestId, var result)
    signal configurationChanged()

    function request(action: string, options: var, priority: string): string {
        const id = "ai-" + (++serial);
        if (queue.length >= 16) {
            Qt.callLater(() => root.completed(id, {ok:false, code:"busy", error:"AI 请求队列已满"}));
            return id;
        }
        const job = {id:id, action:action, payload:Object.assign({}, options || {}, {action:action}), low:priority === "low"};
        // Low-priority work (background pretranslation) must never delay an interactive request.
        const index = job.low ? queue.length : queue.findIndex(entry => entry.low);
        queue = index < 0 ? queue.concat([job]) : queue.slice(0, index).concat([job], queue.slice(index));
        Qt.callLater(root.pump);
        return id;
    }
    function pump(): void {
        if (current || !queue.length || worker.running) return;
        current = queue[0];
        queue = queue.slice(1);
        worker.output = "";
        worker.failure = "";
        worker.stdinEnabled = true;
        worker.running = true;
        watchdog.restart();
    }
    function cancel(requestId: string): void {
        const queued = queue.find(job => job.id === requestId);
        if (queued) {
            queue = queue.filter(job => job.id !== requestId);
            completed(requestId, {ok:false, code:"cancelled", error:"请求已取消"});
        }
        if (current?.id === requestId && (current.action === "generate" || current.action === "translate" || current.action === "models")) {
            worker.failure = "cancelled";
            worker.running = false;
        }
    }
    function pause(): string {
        for (const job of queue.slice()) {
            if (["generate","translate","models"].includes(job.action)) cancel(job.id);
        }
        if (current) cancel(current.id);
        return request("configure", {enabled:false});
    }
    Component.onCompleted: request("status", {})
    Timer {
        id: watchdog
        interval: 45000
        onTriggered: { worker.failure = "timeout"; worker.running = false; }
    }
    Process {
        id: worker
        property string output: ""
        property string failure: ""
        command: ["python3", Quickshell.shellDir + "/aibackend/Backend.py"]
        onStarted: {
            worker.write(JSON.stringify(root.current.payload) + "\n");
            // Do not retain the submitted credential in the request queue or result.
            root.current.payload = ({});
            worker.stdinEnabled = false;
        }
        stdout: StdioCollector { onStreamFinished: worker.output = text }
        onExited: (exitCode, exitStatus) => {
            watchdog.stop();
            const job = root.current;
            if (!job) return;
            let result = {ok:false, code:"backend", error:"AI 后端未返回有效结果"};
            if (worker.failure) result = {ok:false, code:worker.failure, error:worker.failure === "cancelled" ? "请求已取消" : "请求超时，未自动重试"};
            else if (exitCode === 0) {
                try { result = JSON.parse(worker.output); } catch (e) {}
            }
            worker.output = "";
            root.current = null;
            if (result.status) { root.state = result.status; root.loaded = true; }
            if (result.ok && ["configure","saveProfile","deleteProfile","setModel"].includes(job.action)) root.configurationChanged();
            root.completed(job.id, result);
            if (worker.failure && ["generate","translate","models"].includes(job.action)) root.request("status", {});
            Qt.callLater(root.pump);
        }
    }
}
