pragma Singleton
import QtQuick
import Quickshell

// 软件描述后台预翻译：把已安装包的描述分批交给 AI 后端补齐，界面只读本地缓存。
// 所有请求都走 Ai 的 low 优先级，用户在现场查看时发起的翻译会先执行。
// 只负责排队与退避；包索引、缓存键、批量提示词都在 Backend.py 里，QML 不接触包列表细节。
Singleton {
    id: root

    property bool working: false
    property bool suspended: false
    property int pending: 0
    property int total: 0
    property int explicitTotal: 0
    property int done: 0
    property string lastError: ""
    property string requestId: ""
    property string requestAction: ""
    property string batchScope: ""
    property int failures: 0

    readonly property string scope: JSON.stringify([Ai.activeProfile?.id, Ai.activeProfile?.format, Ai.activeProfile?.baseUrl, Ai.activeProfile?.model])
    readonly property bool ready: Ai.loaded && Ai.translationEnabled
    readonly property bool idle: requestId === "" && !working

    // map: {包名 + "\n" + 原描述: 译文}；scope 与 SoftwarePage.translationScope 同构。
    signal translated(var translations, string scope)

    Component.onCompleted: root.refresh()

    function refresh(): void {
        if (!root.ready || root.requestId) return;
        root.requestAction = "status";
        root.requestId = Ai.request("translationStatus", {}, "low");
    }

    // 软件页可见时让路：只完成在途批次，不再开新批次，交互翻译不必排长队。
    function resume(): void {
        if (!root.suspended && root.pending > 0 && !root.requestId) root.retryLater(300);
    }

    function step(): void {
        if (!root.ready || root.requestId || root.suspended) return;
        if (root.pending <= 0) return;
        root.working = true;
        root.batchScope = root.scope;
        root.requestAction = "batch";
        root.requestId = Ai.request("translateBatch", {size: 10}, "low");
    }

    // 请求之间的间隔按每分钟上限留 20% 余量，避免把额度用满后挡住交互请求。
    function pace(): int {
        return Math.max(1500, Math.ceil(72000 / Math.max(1, Ai.state.limits.minute)));
    }

    function retryLater(delay: int): void {
        nextTimer.interval = delay;
        nextTimer.restart();
    }

    function handleError(result: var): void {
        const code = result.code || "";
        root.lastError = result.error || "预翻译失败，稍后重试";
        // 额度类错误只需静默等待，下一轮会重新查询待翻译数量。
        if (code === "daily_limit") return root.retryLater(1800000);
        if (code === "rate_limit") return root.retryLater(70000);
        if (code === "cooldown") return root.retryLater(35000);
        if (code === "busy") return root.retryLater(5000);
        if (["network", "http", "parse", "response", "timeout"].indexOf(code) >= 0) {
            root.failures += 1;
            if (root.failures < 3) return root.retryLater(30000);
            return; // 连续失败停止本轮，等下一次刷新触发
        }
        // configuration / disabled / redirect / storage：配置问题，不循环重试。
    }

    Timer { id: nextTimer; interval: 1500; onTriggered: root.step() }
    Timer { id: pollTimer; interval: 120000; repeat: true; running: true; onTriggered: root.refresh() }

    Connections {
        target: Ai
        function onLoadedChanged(): void { root.refresh(); }
        function onTranslationEnabledChanged(): void { root.failures = 0; root.refresh(); }
        function onConfigurationChanged(): void { root.failures = 0; root.refresh(); }
        function onCompleted(requestId, result): void {
            if (requestId !== root.requestId) return;
            const action = root.requestAction;
            root.requestId = "";
            root.requestAction = "";
            root.working = false;
            if (!result.ok) return root.handleError(result);
            root.failures = 0;
            root.lastError = "";
            if (action === "status") {
                root.total = result.total || 0;
                root.explicitTotal = result.explicit || 0;
                root.pending = result.pending || 0;
                if (root.pending > 0) root.retryLater(300);
                return;
            }
            const map = result.translations || {};
            const count = Object.keys(map).length;
            root.total = result.total || root.total;
            root.explicitTotal = result.explicit || root.explicitTotal;
            root.pending = result.remaining || 0;
            if (count > 0) {
                root.done += count;
                root.translated(map, root.batchScope);
            }
            if (root.pending > 0) root.retryLater(root.pace());
        }
    }
}
