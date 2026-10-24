pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

// 编辑单个 AI 服务（连接、模型、凭据）。目标由 AiUiState.editingId 指定，空表示新建。
PageBase {
    id: root
    title: root.creating ? "新建服务" : "编辑服务"
    isSubPage: true
    objectName: "aiServiceEditorPage"
    property string editingId: ""
    property bool creating: true
    property string serviceName: ""
    property string baseUrl: ""
    property string modelId: ""
    property string format: "openai"
    property string storage: "keyring"
    property string apiKeyDraft: ""
    property bool hasKey: false
    property string operationId: ""
    property string operation: ""
    property string message: ""
    property bool failed: false
    property var modelTests: ({})
    property string testingModel: ""
    property string testingScope: ""
    property double testingStartedAt: 0
    readonly property string testScope: JSON.stringify([editingId, format, baseUrl])
    readonly property color testSuccessColour: Colours.light ? "#237a44" : "#8bd49c"
    onTestScopeChanged: modelTests = ({})

    function testSelectedModel(): void {
        if (pending || !editingId || !modelId || !Ai.state.enabled) return;
        run("generate", {profileId:editingId,model:modelId,source:"settings-test",messages:[{role:"user",content:"Reply with OK."}],maxTokens:128});
    }
    function recordTestResult(result: var): void {
        if (testingScope !== testScope) return;
        modelTests = Object.assign({}, modelTests, {[testingModel]: {
            state: result.ok ? "success" : result.code === "timeout" ? "timeout" : "error",
            elapsedMs: Math.max(1, Date.now() - testingStartedAt),
            error: result.error || "测试失败"
        }});
    }
    property bool fetchAfterSave: true
    property bool modelSaveAfterTest: false
    property bool deleteArmed: false
    property bool addingModel: false
    property string draftModel: ""
    property string modelSearch: ""
    readonly property var discoveredModels: editingProfile?.models || []
    readonly property var filteredModels: discoveredModels.filter(id => id.toLowerCase().includes(modelSearch.toLowerCase()))
    readonly property bool pending: !!operationId
    readonly property var editingProfile: Ai.state.profiles.find(p => p.id === editingId) || null
    readonly property bool canSave: !!serviceName.trim() && !!baseUrl.trim()

    function formatLabel(value: string): string {
        if (value === "gemini")
            return "Gemini 原生";
        if (value === "anthropic")
            return "Anthropic 原生";
        return "OpenAI 兼容";
    }
    function load(profile: var): void {
        creating = !profile;
        editingId = profile?.id || "";
        serviceName = profile?.name || "";
        baseUrl = profile?.baseUrl || "";
        modelId = profile?.model || "";
        format = profile?.format || "openai";
        storage = profile?.storage || "keyring";
        hasKey = !!profile?.hasKey;
        apiKeyDraft = "";
        keyRow.field.clear();
        deleteArmed = false;
        modelSearch = "";
        message = "";
    }
    function run(action: string, payload: var): void {
        if (pending)
            return;
        operation = action;
        failed = false;
        message = "";
        if (action === "generate") {
            testingModel = payload.model || modelId;
            testingScope = testScope;
            testingStartedAt = Date.now();
            modelTests = Object.assign({}, modelTests, {[testingModel]: {state:"running"}});
        }
        operationId = Ai.request(action, payload);
    }
    function selectModel(model: string): void {
        if (pending)
            return;
        modelId = model.trim();
        if (!editingId || !modelId || editingProfile?.model === modelId)
            return;
        modelSaveAfterTest = false;
        run("setModel", {profileId:editingId, model:modelId});
    }
    function persistModels(models: var): void {
        if (!editingId)
            return;
        root.run("saveModels", {profileId:editingId, models:models});
    }
    function addModel(): void {
        const value = draftModel.trim();
        if (!value)
            return;
        persistModels(discoveredModels.concat([value]));
        draftModel = "";
        addingModel = false;
    }
    function removeModel(model: string): void {
        persistModels(discoveredModels.filter(id => id !== model));
    }
    function resetModels(): void {
        persistModels([]);
    }
    function save(): void {
        root.run("saveProfile", {profile:{id:editingId,name:serviceName,format:format,
            baseUrl:baseUrl,model:modelId,storage:storage},apiKey:apiKeyDraft});
        apiKeyDraft = "";
        keyRow.field.clear();
    }
    Component.onCompleted: load(Ai.state.profiles.find(p => p.id === AiUiState.editingId) || null)
    Component.onDestruction: {
        apiKeyDraft = "";
        if (operation === "generate" && operationId) Ai.cancel(operationId);
    }
    property Connections aiConnections: Connections {
        target: Ai
        function onCompleted(requestId, result): void {
            if (requestId !== root.operationId)
                return;
            const action = root.operation;
            root.operationId = "";
            if (action === "generate") root.recordTestResult(result);
            root.failed = action !== "generate" && !result.ok;
            root.message = action === "generate" || result.ok ? "" : result.error;
            if (!result.ok)
                return;
            if (action === "saveProfile") {
                root.editingId = result.profileId;
                root.creating = false;
                if (root.fetchAfterSave && Ai.state.enabled)
                    root.run("models", {profileId:root.editingId});
            } else if (action === "models") {
                root.message = result.models.length ? "" : "没有取到模型，可手动填写模型 ID";
            } else if (action === "generate") {
                if (root.modelId && root.editingProfile?.model !== root.modelId) {
                    root.modelSaveAfterTest = true;
                    root.run("setModel", {profileId:root.editingId, model:root.modelId});
                }
            } else if (action === "saveModels") {
                root.message = "";
            } else if (action === "setModel") {
                root.modelSaveAfterTest = false;
            } else if (action === "deleteProfile") {
                root.nState.closeSubPage();
            }
        }
    }

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        SectionHeader { first: true; text: "连接" }
        TextFieldRow {
            first: true
            label: "服务名称"
            field.Layout.preferredWidth: root.cappedWidth * 0.55
            field.Layout.maximumWidth: root.cappedWidth * 0.58
            placeholderText: root.creating ? "例如 DeepSeek" : ""
            value: root.serviceName
            enabled: !root.pending
            onValueEdited: value => root.serviceName = value
        }
        SelectRow {
            label: "接口类型"
            menuItems: [openaiFormat, geminiFormat, anthropicFormat]
            active: menuItems.find(i => i.value === root.format)
            enabled: !root.pending
            onSelected: item => root.format = item.value
            MenuItem { id: openaiFormat; text: "OpenAI 兼容"; value: "openai" }
            MenuItem { id: geminiFormat; text: "Gemini 原生"; value: "gemini" }
            MenuItem { id: anthropicFormat; text: "Anthropic 原生"; value: "anthropic" }
        }
        TextFieldRow {
            last: true
            label: "接口地址"
            placeholderText: root.creating ? "https://…/v1" : ""
            subtext: "Base URL"
            field.Layout.preferredWidth: root.cappedWidth * 0.55
            field.Layout.maximumWidth: root.cappedWidth * 0.58
            value: root.baseUrl
            enabled: !root.pending
            maximumLength: 2048
            onValueEdited: value => root.baseUrl = value
        }
        SectionHeader { text: "凭据" }
        SelectRow {
            first: true
            label: "存储方式"
            subtext: root.storage === "file" ? "本机明文文件" : ""
            menuItems: [keyringStorage, fileStorage]
            active: root.storage === "keyring" ? keyringStorage : fileStorage
            enabled: !root.pending
            onSelected: item => root.storage = item.value
            MenuItem { id: keyringStorage; text: "系统密钥环"; value: "keyring" }
            MenuItem { id: fileStorage; text: "本机私有文件"; value: "file" }
        }
        TextFieldRow {
            id: keyRow
            last: true
            label: "API Key"
            field.Layout.preferredWidth: root.cappedWidth * 0.55
            field.Layout.maximumWidth: root.cappedWidth * 0.58
            subtext: root.hasKey ? "已保存，留空保留" : ""
            placeholderText: root.hasKey ? "输入以替换" : "输入 API Key"
            value: ""
            maximumLength: 16384
            field.echoMode: TextInput.Password
            enabled: !root.pending
            onValueEdited: value => root.apiKeyDraft = value
        }

        SectionHeader { text: "模型" }

        // 模型池：标题行带 新建/重置/获取，行内可选中与删除
        ConnectedRect {
            Layout.fillWidth: true
            first: true
            implicitHeight: pool.implicitHeight + Tokens.padding.large * 2
            ColumnLayout {
                id: pool
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.medium

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.extraSmall
                    StyledText {
                        Layout.fillWidth: true
                        text: root.discoveredModels.length ? "可用模型 · " + root.discoveredModels.length : "可用模型"
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.body.small
                    }
                    IconButton {
                        id: addButton
                        icon: "add"
                        font: Tokens.font.icon.small
                        padding: Tokens.padding.small
                        type: IconButton.Text
                        isRound: true
                        disabled: root.pending || !root.editingId
                        onClicked: {
                            root.addingModel = !root.addingModel;
                            if (root.addingModel)
                                Qt.callLater(() => draftField.forceActiveFocus());
                        }
                        HoverHandler { id: addHover }
                        ToolTip.visible: addHover.hovered && !addButton.disabled
                        ToolTip.text: "新建模型"
                        ToolTip.delay: 300
                    }
                    IconButton {
                        id: resetButton
                        icon: "delete_sweep"
                        font: Tokens.font.icon.small
                        padding: Tokens.padding.small
                        type: IconButton.Text
                        isRound: true
                        disabled: root.pending || !root.editingId || !root.discoveredModels.length
                        onClicked: root.resetModels()
                        HoverHandler { id: resetHover }
                        ToolTip.visible: resetHover.hovered && !resetButton.disabled
                        ToolTip.text: "清空模型列表"
                        ToolTip.delay: 300
                    }
                    TextButton {
                        id: testButton
                        objectName: "testSelectedModel"
                        text: "测试模型"
                        type: TextButton.Text
                        disabled: root.pending || !root.editingId || !root.modelId || !Ai.state.enabled
                        onClicked: root.testSelectedModel()
                        HoverHandler { id: testButtonHover }
                        ToolTip.visible: testButtonHover.hovered
                        ToolTip.text: "测试当前选中的模型"
                        ToolTip.delay: 300
                    }
                    TextButton {
                        id: fetchButton
                        text: "获取模型"
                        type: TextButton.Text
                        disabled: root.pending || !root.editingId || !Ai.state.enabled
                        onClicked: root.run("models", {profileId:root.editingId})
                        HoverHandler { id: fetchHover }
                        ToolTip.visible: fetchHover.hovered && !fetchButton.disabled
                        ToolTip.text: "从服务获取模型"
                        ToolTip.delay: 300
                    }
                }
                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: Qt.alpha(Colours.palette.m3outline, 0.16)
                }
                RowLayout {
                    Layout.fillWidth: true
                    visible: root.addingModel
                    spacing: Tokens.spacing.extraSmall
                    StyledTextField {
                        id: draftField
                        Layout.fillWidth: true
                        placeholderText: "模型 ID"
                        text: root.draftModel
                        onTextEdited: root.draftModel = text
                        onAccepted: root.addModel()
                    }
                    IconButton {
                        id: draftAddButton
                        icon: "check"
                        font: Tokens.font.icon.small
                        isRound: true
                        disabled: !root.draftModel.trim()
                        onClicked: root.addModel()
                        HoverHandler { id: draftAddHover }
                        ToolTip.visible: draftAddHover.hovered && !draftAddButton.disabled
                        ToolTip.text: "添加"
                        ToolTip.delay: 300
                    }
                    IconButton {
                        id: draftCloseButton
                        icon: "close"
                        font: Tokens.font.icon.small
                        isRound: true
                        onClicked: {
                            root.addingModel = false;
                            root.draftModel = "";
                        }
                        HoverHandler { id: draftCloseHover }
                        ToolTip.visible: draftCloseHover.hovered
                        ToolTip.text: "取消"
                        ToolTip.delay: 300
                    }
                }
                StyledTextField {
                    id: modelSearchField
                    Layout.fillWidth: true
                    visible: root.discoveredModels.length > 6
                    placeholderText: "搜索模型"
                    text: root.modelSearch
                    onTextEdited: root.modelSearch = text
                }
                ListView {
                    id: modelsList
                    objectName: "aiModelsList"
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(count, 5) * 48 + Math.max(0, Math.min(count, 5) - 1) * 4
                    spacing: 4
                    visible: count > 0
                    clip: true
                    model: root.filteredModels
                    boundsBehavior: Flickable.StopAtBounds
                    delegate: Rectangle {
                        id: modelRow
                        required property string modelData
                        required property int index
                        width: modelsList.width
                        height: 48
                        radius: Tokens.rounding.medium
                        color: root.modelId === modelData ? Qt.alpha(Colours.palette.m3primary, 0.12) : "transparent"
                        border.width: root.modelId === modelData ? 1 : 0
                        border.color: Qt.alpha(Colours.palette.m3primary, 0.25)
                        StateLayer { onClicked: root.selectModel(modelRow.modelData) }
                        HoverHandler { id: modelHover }
                        ToolTip.visible: modelHover.hovered && !removeHover.hovered && !testStatusHover.hovered
                        ToolTip.text: "设为当前模型"
                        ToolTip.delay: 500
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Tokens.padding.small
                            anchors.rightMargin: Tokens.spacing.extraSmall
                            spacing: Tokens.spacing.extraSmall
                            MaterialIcon {
                                text: root.modelId === modelRow.modelData ? "radio_button_checked" : "radio_button_unchecked"
                                color: root.modelId === modelRow.modelData ? Colours.palette.m3primary : Colours.palette.m3outline
                                fontStyle: Tokens.font.icon.small
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: modelRow.modelData
                                textFormat: Text.PlainText
                                font: Tokens.font.body.small
                                color: Colours.palette.m3onSurface
                                elide: Text.ElideRight
                            }
                            RowLayout {
                                id: testStatus
                                objectName: "modelTestStatus-" + modelRow.modelData
                                readonly property var result: root.modelTests[modelRow.modelData] || null
                                readonly property string testState: result?.state || ""
                                visible: !!result
                                spacing: Tokens.spacing.extraSmall
                                Loader {
                                    active: testStatus.testState === "running"
                                    visible: active
                                    Layout.preferredWidth: 18
                                    Layout.preferredHeight: 18
                                    sourceComponent: CircularIndicator { implicitSize: 18; strokeWidth: 2; running: true }
                                }
                                MaterialIcon {
                                    visible: testStatus.testState !== "running"
                                    text: testStatus.testState === "success" ? "check_circle" : "error"
                                    color: testStatus.testState === "success" ? root.testSuccessColour : Colours.palette.m3error
                                    fontStyle: Tokens.font.icon.small
                                }
                                StyledText {
                                    visible: testStatus.testState !== "running"
                                    text: testStatus.testState === "success" ? (testStatus.result.elapsedMs / 1000).toFixed(2) + " s" : testStatus.testState === "timeout" ? "超时" : "失败"
                                    color: testStatus.testState === "success" ? root.testSuccessColour : Colours.palette.m3error
                                    font: Tokens.font.label.small
                                }
                                HoverHandler { id: testStatusHover }
                                ToolTip.visible: testStatusHover.hovered
                                ToolTip.delay: 300
                                ToolTip.text: testStatus.testState === "running" ? "正在测试模型" : testStatus.testState === "success" ? "请求成功 · 耗时包含排队与模型生成" : testStatus.result?.error || ""
                            }
                            IconButton {
                                id: removeButton
                                icon: "close"
                                padding: Tokens.padding.small
                                font: Tokens.font.icon.small
                                type: IconButton.Text
                                isRound: true
                                disabled: root.pending
                                onClicked: root.removeModel(modelRow.modelData)
                                HoverHandler { id: removeHover }
                                ToolTip.visible: removeHover.hovered && !removeButton.disabled
                                ToolTip.text: "删除该模型"
                                ToolTip.delay: 300
                            }
                        }
                    }
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: root.discoveredModels.length === 0
                    text: root.editingId ? "获取模型列表，或点 + 手动添加" : "先创建服务，再添加模型"
                    color: Colours.palette.m3outline
                    font: Tokens.font.label.small
                }
            }
        }

        ToggleRow {
            last: true
            text: "保存时刷新模型"
            subtext: "自动获取此服务的模型列表"
            checked: root.fetchAfterSave
            onToggled: root.fetchAfterSave = checked
        }
        StyledText {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.small
            visible: (root.pending && root.operation !== "generate") || !!root.message
            text: root.pending ? "处理中…" : root.message
            color: root.failed ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant
            wrapMode: Text.Wrap
            font: Tokens.font.body.small
            textFormat: Text.PlainText
        }

        RowButton {
            Layout.topMargin: Tokens.spacing.large
            first: true
            last: true
            icon: "save"
            text: root.editingId ? "保存连接设置" : "创建服务"
            subtext: root.editingId ? "" : "保存后即可获取模型"
            disabled: root.pending || !root.canSave
            onClicked: root.save()
        }
        SectionHeader { visible: !!root.editingId; text: "服务管理" }
        RowButton {
            first: true
            last: true
            visible: !!root.editingId
            icon: "delete"
            iconLabel.color: Colours.palette.m3error
            label.color: Colours.palette.m3error
            text: root.deleteArmed ? "再次点击确认删除" : "删除此服务"
            subtext: root.deleteArmed ? "再次点击后无法撤销" : "移除此连接及本机凭据"
            disabled: root.pending
            onClicked: {
                if (root.deleteArmed)
                    root.run("deleteProfile", {profileId:root.editingId});
                else
                    root.deleteArmed = true;
            }
        }
    }
}
