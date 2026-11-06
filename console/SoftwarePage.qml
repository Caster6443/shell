pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Caelestia.Config
import qs.overview
import qs.aibackend

Item {
    id: root
    property var wheelStep: null
    property string query: ""
    property string filter: "explicit"
    property var packages: []
    property string selectedName: ""
    property var details: ({})
    property string detailTab: "overview"
    property var history: []
    property bool loaded: false
    property double checkedAt: 0
    property string notice: ""
    property string error: ""
    property string detailError: ""
    property string pendingAction: ""
    property string pendingName: ""
    property var removalPlan: ({})
    property string confirmationText: ""
    property var result: ({})
    readonly property bool busy: queryProcess.running || !!cacheLookupRequest || pendingPackageResult !== null
    readonly property bool interactionBusy: confirm.visible || privileged.running
    readonly property string backend: Quickshell.shellDir + "/console/PackageBackend.py"
    readonly property var selected: packages.find(p => p.name === selectedName) || null
    readonly property int explicitCount: packages.filter(p => p.explicit).length
    function versionStatus(pkg: var): var {
        if (!pkg || !pkg.available) return {label:"可用版本", value:"暂未查询到"};
        if (pkg.available === pkg.version) {
            const development = /-(git|svn|hg|bzr|cvs|darcs|fossil)$/.test(pkg.name);
            return {label:"更新状态", value:development ? "已是最新发布版本" : "已是最新版"};
        }
        return {label:"可用版本", value:pkg.available};
    }
    function matchesQuery(pkg: var): bool {
        return query.trim().toLowerCase().split(/\s+/).every(word => (pkg.name + " " + pkg.description).toLowerCase().includes(word));
    }
    function matchesScope(pkg: var, scope: string): bool {
        if (scope === "all") return true;
        if (scope === "explicit") return pkg.explicit;
        if (scope === "deps") return !pkg.explicit;
        if (scope === "watched") return pkg.watched;
        if (scope === "updates") return pkg.update;
        if (scope === "ignored") return pkg.ignored;
        if (scope === "orphans") return pkg.orphan;
        return true;
    }
    function sortedRows(list: var): var {
        return list.sort((a, b) => Number(b.watched) - Number(a.watched) || a.name.localeCompare(b.name));
    }
    readonly property var scopedRows: sortedRows(packages.filter(p => matchesQuery(p) && matchesScope(p, filter)))
    // 默认只看显式安装；显式范围内搜不到时自动扩到全部已安装，避免“明明装了却搜不到”。
    readonly property bool searchFallback: scopedRows.length === 0 && !!query.trim() && filter === "explicit"
    readonly property var rows: searchFallback ? sortedRows(packages.filter(p => matchesQuery(p) && matchesScope(p, "all"))) : scopedRows
    property string cacheLookupRequest: ""
    property var pendingPackageResult: null
    readonly property string translationScope: JSON.stringify([Ai.activeProfile?.id, Ai.activeProfile?.format, Ai.activeProfile?.baseUrl, Ai.activeProfile?.model])
    onTranslationScopeChanged: { translationCache = ({}); translationAttempts = ({}); resetTranslation(); }
    function applyPackageResult(data: var): void {
        packages = data.packages || [];
        checkedAt = data.checkedAt || 0;
        notice = (data.warnings || []).join("\n");
        loaded = true;
    }
    function preparePackageResult(data: var): void {
        pendingPackageResult = data;
        if (!Ai.loaded) return;
        if (Ai.translationEnabled) {
            cacheLookupRequest = Ai.request("cachedTranslations", {items:(data.packages || []).map(p => ({name:p.name,description:p.description}))});
        } else {
            pendingPackageResult = null;
            applyPackageResult(data);
        }
    }
    property string translatedDescription: ""
    property string translationRequest: ""
    property string translationRequestIdentity: ""
    property var translationCache: ({})
    property string translationError: ""
    readonly property string translationBlockReason: Ai.loaded && Ai.state.enabled && Ai.state.translation && !Ai.activeProfile?.model ? "请在 AI 服务中选择默认服务和模型后再翻译" : ""
    property bool translationFailed: false
    property var translationAttempts: ({})
    readonly property string descriptionIdentity: selectedName + "\n" + (selected?.description || "")
    onDescriptionIdentityChanged: resetTranslation()
    onDetailTabChanged: { if (detailTab === "overview") translationTimer.restart(); }
    function resetTranslation(): void {
        const previous = translationRequest;
        translationRequest = "";
        if (previous) {
            const attempts = Object.assign({}, translationAttempts);
            delete attempts[translationRequestIdentity];
            translationAttempts = attempts;
            Ai.cancel(previous);
        }
        translatedDescription = Ai.translationEnabled ? translationCache[descriptionIdentity] || "" : "";
        translationFailed = false;
        translationError = "";
        if (translatedDescription) translationTimer.stop();
        else translationTimer.restart();
    }
    function translateDescription(retry: bool): void {
        if (!visible || detailTab !== "overview" || !Ai.translationEnabled || !selected?.description) return;
        if (!retry && translationCache[descriptionIdentity]) { translatedDescription = translationCache[descriptionIdentity]; return; }
        if (!retry && translationAttempts[descriptionIdentity]) return;
        translationAttempts = Object.assign({}, translationAttempts, {[descriptionIdentity]:true});
        translationFailed = false;
        translationRequestIdentity = descriptionIdentity;
        translationRequest = Ai.request("translate", {name:selectedName,description:selected.description});
    }
    Timer { id: translationTimer; interval: 600; onTriggered: root.translateDescription(false) }
    Connections {
        target: Ai
        function onTranslationEnabledChanged(): void { root.translationAttempts = ({}); root.resetTranslation(); }
        function onConfigurationChanged(): void { root.translationAttempts = ({}); root.resetTranslation(); }
        function onLoadedChanged(): void { if (Ai.loaded && root.pendingPackageResult && !root.cacheLookupRequest) root.preparePackageResult(root.pendingPackageResult); }
        function onCompleted(requestId, result): void {
            if (requestId === root.cacheLookupRequest) {
                root.cacheLookupRequest = "";
                if (result.ok) root.translationCache = Object.assign({}, root.translationCache, result.translations || {});
                const data = root.pendingPackageResult;
                root.pendingPackageResult = null;
                if (data) root.applyPackageResult(data);
                root.resetTranslation();
                return;
            }
            if (requestId !== root.translationRequest) return;
            root.translationRequest = "";
            root.translationFailed = !result.ok;
            root.translationError = result.ok ? "" : (result.error || "暂未取得译文，显示原文");
            if (result.ok) {
                root.translatedDescription = result.text;
                root.translationCache = Object.assign({}, root.translationCache, {[root.translationRequestIdentity]:result.text});
            }
        }
    }
    // 后台预翻译按 profile/地址/模型划分作用域；只接受当前作用域的结果，避免切换服务后显示旧译文。
    Connections {
        target: Translator
        function onTranslated(translations, scope): void {
            if (scope !== root.translationScope) return;
            root.translationCache = Object.assign({}, root.translationCache, translations);
            if (!root.translatedDescription && root.translationCache[root.descriptionIdentity]) {
                root.translatedDescription = root.translationCache[root.descriptionIdentity];
                translationTimer.stop();
            }
        }
    }
    signal focusSearchRequested()
    signal revealPackage(string name)

    onVisibleChanged: {
        // 用户正在浏览软件页时，后台预翻译只收尾在途批次，不再开新批次。
        Translator.suspended = visible;
        if (visible) { resetTranslation(); if (!busy) refresh(); }
        else { resetTranslation(); translationTimer.stop(); Translator.resume(); }
    }
    Component.onDestruction: Translator.suspended = false
    onRowsChanged: {
        if (!rows.some(p => p.name === selectedName)) selectedName = rows.length ? rows[0].name : "";
        Qt.callLater(() => {
            const index = root.rows.findIndex(p => p.name === root.selectedName);
            if (index >= 0) packageList.positionViewAtIndex(index, ListView.Contain);
        });
    }
    onSelectedNameChanged: { details = ({}); detailError = ""; detailTimer.restart(); }
    Timer { id: navigationGuard; objectName: "softwareNavigationGuard"; interval: 450 }
    function hoverSelect(name: string): void {
        if (!root.interactionBusy && !navigationGuard.running && !packageList.moving)
            root.selectedName = name;
    }
    function moveSelection(step: int): void {
        if (!rows.length) return;
        navigationGuard.restart();
        const index = Math.max(0, Math.min(rows.length - 1, rows.findIndex(p => p.name === selectedName) + step));
        selectedName = rows[index].name;
        packageList.positionViewAtIndex(index, ListView.Contain);
    }
    function cycleSection(section: string, wheel: var): void {
        if (interactionBusy || !wheelStep) return;
        const step = wheelStep("software-" + section, wheel, true);
        if (!step) return;
        const order = section === "filter" ? ["explicit", "deps", "watched", "updates", "ignored", "orphans"] : ["overview", "dependencies", "actions"];
        const current = section === "filter" ? filter : detailTab;
        const index = Math.max(0, order.indexOf(current));
        const next = order[(index - step + order.length) % order.length];
        if (section === "filter") filter = next;
        else detailTab = next;
    }
    function showSelected(): void { if (selected) detailTab = "overview"; }
    function refresh(): void { invoke("list", "", ""); }
    function invoke(action: string, name: string, argument: string): void {
        if (busy || privileged.running) return;
        error = "";
        result = ({});
        queryProcess.action = action;
        queryProcess.command = ["python", backend, action, name, argument];
        queryProcess.running = true;
    }
    function navigatePackage(name: string): void {
        if (!name) return;
        if (selectedName) history = history.concat([selectedName]);
        filter = "all";
        revealPackage(name);
        selectedName = name;
        detailTab = "dependencies";
    }
    function goBack(): void {
        if (!history.length) return;
        const name = history[history.length - 1];
        history = history.slice(0, -1);
        filter = "all";
        revealPackage(name);
        selectedName = name;
    }
    function requestAction(action: string): void {
        if (!selected || busy || privileged.running) return;
        pendingName = selected.name;
        pendingAction = action;
        if (action === "remove") { invoke("preview", pendingName, ""); return; }
        if (action === "ignore") {
            confirmationText = selected.ignored
                ? "恢复 " + pendingName + " 的正常升级？\n当前忽略规则：" + selected.ignoreReason
                : "将 " + pendingName + " 加入 IgnorePkg？\n以后系统升级会跳过它，仍可在这里查看可用版本。长期锁定版本可能导致依赖不兼容。\n此操作将请求系统授权，并备份 pacman.conf。";
        } else {
            confirmationText = "将 " + pendingName + " 标为显式安装？\n这会防止它被作为孤儿依赖清理，不会阻止系统升级。终端中仍需确认。";
        }
        confirm.open();
    }
    function startTerminal(action: string, name: string): void {
        Quickshell.execDetached([...GlobalConfig.general.apps.terminal, "python", backend, "terminal", action, name]);
        notice = "操作已交给终端；完成后点击“刷新列表”。";
    }
    function acceptAction(): void {
        const p = packages.find(p => p.name === pendingName);
        if (!p) { error = "软件包已不在列表中，请刷新"; return; }
        if (pendingAction === "ignore") {
            privileged.command = ["pkexec", "/usr/bin/python", "-I", backend, "ignore", pendingName, p.ignored ? "0" : "1"];
            privileged.running = true;
        } else startTerminal(pendingAction, pendingName);
    }
    function sizeText(bytes: real): string { return (bytes / 1048576).toFixed(1) + " MiB"; }
    Timer { id: detailTimer; interval: 90; onTriggered: {
        if (detailProcess.running) return;
        if (!root.selectedName) return;
        detailProcess.requestedName = root.selectedName;
        detailProcess.command = ["python", root.backend, "detail", root.selectedName];
        detailProcess.running = true;
    } }
    Process {
        id: queryProcess
        property string action: "list"
        stdout: StdioCollector { onStreamFinished: { try { root.result = JSON.parse(text); } catch (e) { root.result = ({error: "无法解析软件包查询结果"}); } } }
        stderr: StdioCollector {}
        onExited: (code, status) => {
            const data = root.result;
            if (code !== 0 || data.error) { root.error = data.error || "查询失败，请重试"; return; }
            if (action === "preview") {
                root.removalPlan = data;
                root.confirmationText = "将卸载 " + root.pendingName + " 及下列不再需要的依赖：\n\n" + data.names.join("、") + "\n\n预计释放 " + root.sizeText(data.bytes) + "。保留可生成 .pacsave 的配置备份。\n终端会重新计算依赖，并要求最终确认。";
                confirm.open();
            } else {
                root.preparePackageResult(data);
            }
        }
    }
    Process {
        id: detailProcess
        property string requestedName: ""
        property var response: ({})
        stdout: StdioCollector { onStreamFinished: { try { detailProcess.response = JSON.parse(text); } catch (e) { detailProcess.response = ({error: "详情解析失败"}); } } }
        onExited: (code, status) => {
            if (requestedName === root.selectedName) {
                root.details = response;
                root.detailError = response.error || (code ? "详情读取失败" : "");
            } else detailTimer.restart();
        }
    }
    Process {
        id: privileged
        property string output: ""
        stdout: StdioCollector { onStreamFinished: privileged.output = text }
        stderr: StdioCollector { id: privilegeErrors }
        onExited: (code, status) => {
            let data = ({});
            try { data = JSON.parse(output); } catch (e) {}
            if (code !== 0 || data.error) root.error = data.error || "授权已取消或修改失败。";
            else { root.notice = "忽略升级设置已更新。"; root.refresh(); }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 10
        RowLayout {
            Layout.fillWidth: true
            ConsoleText { text: "软件管理"; textRole: "title"; strong: true; color: M3Palette.m3onSurface }
            ConsoleText { text: root.packages.length ? root.explicitCount + " 个显式安装 · 共 " + root.packages.length + " 个已安装" : ""; color: M3Palette.m3onSurfaceVariant; textRole: "caption"}
            Item { Layout.fillWidth: true }
            SoftwareButton { text: "刷新列表"; enabled: !root.busy && !privileged.running; onClicked: root.refresh() }
            SoftwareButton { text: queryProcess.running && queryProcess.action === "check" ? "检查中…" : "检查更新"; enabled: !root.busy && !privileged.running; onClicked: root.invoke("check", "", "") }
            SoftwareButton { text: "系统升级 ↗"; accent: true; enabled: !root.busy; onClicked: root.startTerminal("upgrade", "") }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 5
            WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: event => { root.cycleSection("filter", event); event.accepted = true; }
            }
            Repeater {
                model: [{key:"explicit", label:"显式"}, {key:"deps", label:"依赖"}, {key:"watched", label:"关注"}, {key:"updates", label:"可更新"}, {key:"ignored", label:"已忽略"}, {key:"orphans", label:"孤儿"}]
                SoftwareButton {
                    required property var modelData
                    text: modelData.label
                    accent: root.filter === modelData.key
                    onClicked: { root.filter = modelData.key; root.focusSearchRequested(); }
                }
            }
            Item { Layout.fillWidth: true }
            ConsoleText { text: root.searchFallback ? root.rows.length + " 项（含依赖）" : root.rows.length + " 项"; color: M3Palette.m3onSurfaceVariant; textRole: "caption"}
        }
        ConsoleText {
            Layout.fillWidth: true
            text: root.error || (root.busy ? (queryProcess.action === "check" ? "正在检查仓库与 AUR；已忽略的软件包也会比较版本…" : "正在读取软件包…") : root.notice || (root.checkedAt ? "上次联网检查：" + new Date(root.checkedAt * 1000).toLocaleString(Qt.locale(), "MM-dd HH:mm") : "当前版本来自本机仓库数据库；点击“检查更新”获取最新版本。"))
            color: root.error ? M3Palette.m3tertiary : M3Palette.m3onSurfaceVariant
            textRole: "caption"
            wrapMode: Text.Wrap
            maximumLineCount: 3
            elide: Text.ElideRight
        }
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 14
            Rectangle {
                Layout.preferredWidth: Math.round(root.width * 0.41)
                Layout.fillHeight: true
                radius: 20
                color: ConsoleMaterialStyle.content
                border.width: 0
                border.color: Qt.alpha(M3Palette.m3onSurface, 0.08)
                ListView {
                    id: packageList
                    objectName: "softwarePackages"
                    anchors.fill: parent
                    anchors.margins: 5
                    clip: true
                    spacing: 3
                    model: root.rows
                    ScrollBar.vertical: ScrollBar {}
                    delegate: Rectangle {
                        id: packageRow
                        required property var modelData
                        required property int index
                        width: packageList.width
                        height: 66
                        radius: 9
                        color: root.selectedName === modelData.name ? M3Palette.m3primaryContainer : modelData.watched ? Qt.alpha(M3Palette.m3tertiary, 0.10) : "transparent"
                        Column {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.margins: 12
                            anchors.rightMargin: updateIndicator.visible ? 42 : 12
                            spacing: 5
                            ConsoleText {
                                width: parent.width
                                text: (packageRow.modelData.watched ? "★  " : "") + packageRow.modelData.name + (packageRow.modelData.ignored ? "  · 已忽略" : "")
                                color: root.selectedName === packageRow.modelData.name ? M3Palette.m3onPrimaryContainer : M3Palette.m3onSurface
                                textRole: "body"
                                strong: packageRow.modelData.watched || root.selectedName === packageRow.modelData.name
                                elide: Text.ElideRight
                            }
                            ConsoleText {
                                width: parent.width
                                text: packageRow.modelData.version + (packageRow.modelData.update ? " → " + packageRow.modelData.available : "")
                                color: root.selectedName === packageRow.modelData.name ? Qt.alpha(M3Palette.m3onPrimaryContainer, 0.8) : M3Palette.m3onSurfaceVariant
                                textRole: "caption"
                                elide: Text.ElideMiddle
                            }
                        }
                        ConsoleText {
                            id: updateIndicator
                            objectName: "softwareUpdate-" + packageRow.modelData.name
                            visible: !!packageRow.modelData.update && root.filter !== "updates"
                            anchors.right: parent.right
                            anchors.rightMargin: 14
                            anchors.verticalCenter: parent.verticalCenter
                            text: "keyboard_double_arrow_up"
                            font.family: "Material Symbols Rounded"
                            font.pixelSize: 24
                            color: root.selectedName === packageRow.modelData.name ? M3Palette.m3onPrimaryContainer : M3Palette.m3tertiary
                        }
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            ToolTip.text: "有可用更新"
                            ToolTip.delay: 500
                            ToolTip.visible: containsMouse && updateIndicator.visible
                                && mouseX >= updateIndicator.x && mouseX <= updateIndicator.x + updateIndicator.width
                                && mouseY >= updateIndicator.y && mouseY <= updateIndicator.y + updateIndicator.height
                            onEntered: root.hoverSelect(packageRow.modelData.name)
                            onPositionChanged: root.hoverSelect(packageRow.modelData.name)
                            onClicked: { root.selectedName = packageRow.modelData.name; root.focusSearchRequested(); }
                        }
                    }
                    ConsoleText { anchors.centerIn: parent; text: root.busy && !root.loaded ? "正在读取…" : "没有匹配的软件包"; visible: packageList.count === 0; color: M3Palette.m3onSurfaceVariant; textRole: "body"}
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 10
                visible: !!root.selected
                RowLayout {
                    Layout.fillWidth: true
                    SoftwareButton { text: "‹"; visible: root.history.length > 0; onClicked: root.goBack() }
                    ConsoleText { Layout.fillWidth: true; text: root.selectedName; color: M3Palette.m3onSurface; textRole: "title"; strong: true; elide: Text.ElideRight }
                    SoftwareButton { text: root.selected?.watched ? "★ 已关注" : "☆ 关注"; accent: !!root.selected?.watched; enabled: !root.busy; onClicked: root.invoke("watch", root.selectedName, root.selected.watched ? "0" : "1") }
                }
                RowLayout {
                    WheelHandler {
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                        onWheel: event => { root.cycleSection("detail", event); event.accepted = true; }
                    }
                    Repeater {
                        model: [{key:"overview", label:"概览"}, {key:"dependencies", label:"依赖关系"}, {key:"actions", label:"管理"}]
                        SoftwareButton { required property var modelData; text: modelData.label; accent: root.detailTab === modelData.key; onClicked: root.detailTab = modelData.key }
                    }
                }
                ScrollView {
                    id: detailScroll
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    contentWidth: availableWidth
                    ColumnLayout {
                        width: detailScroll.availableWidth
                        spacing: 12
                        ConsoleText { Layout.fillWidth: true; visible: !!root.detailError; text: root.detailError; color: M3Palette.m3tertiary; wrapMode: Text.Wrap; textRole: "caption"}
                        ColumnLayout {
                            visible: root.detailTab === "overview"
                            Layout.fillWidth: true
                            spacing: 13
                            ConsoleText {
                                Layout.fillWidth: true
                                text: root.translatedDescription || root.selected?.description || ""
                                color: M3Palette.m3onSurface
                                wrapMode: Text.Wrap
                                textFormat: Text.PlainText
                                textRole: "body"
                                HoverHandler { id: descriptionHover }
                                ToolTip.text: root.selected?.description || ""
                                ToolTip.visible: descriptionHover.hovered && !!root.translatedDescription
                                ToolTip.delay: 500
                            }
                            RowLayout {
                                visible: !!root.translationRequest || root.translationFailed || !!root.translationBlockReason
                                Layout.fillWidth: true
                                ConsoleText { Layout.fillWidth: true; text: root.translationRequest ? "正在翻译…" : root.translationError || root.translationBlockReason; color: M3Palette.m3onSurfaceVariant; textRole: "caption"; wrapMode: Text.Wrap }
                                SoftwareButton { visible: root.translationFailed && Ai.translationEnabled; text: "重试翻译"; onClicked: root.translateDescription(true) }
                            }
                            Rectangle { Layout.fillWidth: true; height: 1; color: Qt.alpha(M3Palette.m3onSurface, 0.12) }
                            Repeater {
                                model: root.selected ? [
                                    {label:"已安装", value:root.selected.version},
                                    root.versionStatus(root.selected),
                                    {label:"来源", value:root.selected.source},
                                    {label:"安装大小", value:root.sizeText(root.selected.size)},
                                    {label:"安装原因", value:root.selected.explicit ? "显式安装" : "作为依赖安装"},
                                    {label:"升级策略", value:root.selected.ignored ? "已忽略 · " + root.selected.ignoreReason : "随系统正常升级"},
                                    {label:"许可证", value:(root.details.licenses || []).join(" · ") || "—"}
                                ] : []
                                RowLayout {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    spacing: 12
                                    ConsoleText { Layout.preferredWidth: 74; text: modelData.label; color: M3Palette.m3onSurfaceVariant; textRole: "caption"}
                                    ConsoleText { Layout.fillWidth: true; text: modelData.value; color: M3Palette.m3onSurface; textRole: "body"; wrapMode: Text.WrapAnywhere }
                                }
                            }
                            ConsoleText { Layout.fillWidth: true; text: root.details.url || ""; color: M3Palette.m3tertiary; textRole: "caption"; wrapMode: Text.WrapAnywhere }
                        }
                        ColumnLayout {
                            visible: root.detailTab === "dependencies"
                            Layout.fillWidth: true
                            spacing: 12
                            ConsoleText { Layout.fillWidth: true; text: "点击依赖可查看对应的已安装包；未安装的可选依赖仅作展示。"; color: M3Palette.m3onSurfaceVariant; wrapMode: Text.Wrap; textRole: "caption"}
                            Repeater {
                                model: [ {label:"它需要", items:root.details.dependencies || []}, {label:"被谁依赖", items:root.details.requiredBy || []}, {label:"可选依赖", items:root.details.optional || []}, {label:"作为谁的可选依赖", items:root.details.optionalFor || []} ]
                                ColumnLayout {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    spacing: 4
                                    ConsoleText { text: modelData.label + " · " + modelData.items.length; color: M3Palette.m3onSurface; strong: true; textRole: "body"}
                                    Repeater {
                                        model: modelData.items
                                        delegate: Item {
                                            id: depRow
                                            required property var modelData
                                            Layout.fillWidth: true
                                            implicitHeight: depText.implicitHeight + 12
                                            ConsoleText { id: depText; anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; anchors.margins: 8; text: depRow.modelData.label + (depRow.modelData.target ? "  ›" : ""); color: depRow.modelData.target ? M3Palette.m3tertiary : M3Palette.m3onSurfaceVariant; textRole: "caption"; wrapMode: Text.WrapAnywhere }
                                            MouseArea { anchors.fill: parent; enabled: !!depRow.modelData.target; cursorShape: Qt.PointingHandCursor; onClicked: root.navigatePackage(depRow.modelData.target) }
                                        }
                                    }
                                    ConsoleText { visible: modelData.items.length === 0; text: "无"; color: M3Palette.m3onSurfaceVariant; textRole: "caption"}
                                }
                            }
                        }
                        ColumnLayout {
                            visible: root.detailTab === "actions"
                            Layout.fillWidth: true
                            spacing: 13
                            SoftwareButton { text: root.selected?.ignored ? "恢复正常升级…" : "忽略升级…"; enabled: !root.busy && !privileged.running; onClicked: root.requestAction("ignore") }
                            SoftwareButton { text: "标为显式安装…"; enabled: !!root.selected && !root.selected.explicit && !root.busy; onClicked: root.requestAction("explicit") }
                            Rectangle { Layout.fillWidth: true; height: 1; color: Qt.alpha(M3Palette.m3onSurface, 0.1) }
                            SoftwareButton { text: "预览卸载…"; danger: true; enabled: !root.busy; onClicked: root.requestAction("remove") }
                        }
                    }
                }
            }
        }
        ConsoleText { Layout.fillWidth: true; text: "pacman / AUR · 不含 Flatpak、AppImage · 开发包仅比较已发布版本"; color: Qt.alpha(M3Palette.m3onSurface, 0.5); textRole: "caption"; elide: Text.ElideRight }
    }
    Popup {
        id: confirm
        parent: root
        anchors.centerIn: parent
        width: Math.min(520, root.width - 30)
        height: Math.min(implicitHeight, root.height - 20)
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape
        padding: 20
        onClosed: root.focusSearchRequested()
        background: Rectangle { radius: 16; color: ConsoleMaterialStyle.content; border.width: 1; border.color: M3Palette.m3outlineVariant }
        contentItem: ColumnLayout {
            spacing: 16
            ConsoleText { Layout.fillWidth: true; text: "确认操作"; color: M3Palette.m3onSurface; textRole: "body"; strong: true }
            ScrollView {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(confirmBody.implicitHeight + 8, root.height - 190)
                clip: true
                ConsoleText { id: confirmBody; width: confirm.availableWidth; text: root.confirmationText; color: M3Palette.m3onSurface; textRole: "body"; wrapMode: Text.WrapAnywhere }
            }
            RowLayout {
                Layout.alignment: Qt.AlignRight
                SoftwareButton { text: "取消"; onClicked: confirm.close() }
                SoftwareButton { text: root.pendingAction === "ignore" ? "授权并修改" : "在终端中继续"; accent: true; onClicked: { confirm.close(); root.acceptAction(); } }
            }
        }
    }
}
