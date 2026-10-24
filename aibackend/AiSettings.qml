pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root
    title: "AI 服务"
    objectName: "aiSettings"
    readonly property var activeProfile: Ai.activeProfile
    readonly property string stateText: !Ai.state.profiles.length ? "尚未配置" : Ai.state.enabled ? "已启用" : "已停用"

    function formatLabel(value: string): string {
        if (value === "gemini") return "Gemini 原生";
        if (value === "anthropic") return "Anthropic 原生";
        return "OpenAI 兼容";
    }
    function openEditor(profile: var): void {
        AiUiState.editingId = profile?.id || "";
        root.nState.openSubPage(1);
    }
    function run(action: string, payload: var): void { Ai.request(action, payload); }

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        SectionHeader { first: true; text: "当前连接" }
        ToggleRow {
            first: true
            text: "启用 AI 服务"
            subtext: root.activeProfile ? root.activeProfile.name + " · " + root.formatLabel(root.activeProfile.format) : "添加服务后即可启用"
            checked: Ai.state.enabled
            disabled: !Ai.state.profiles.length
            onToggled: {
                if (checked === Ai.state.enabled) return;
                if (checked) root.run("configure", {enabled:true});
                else Ai.pause();
            }
        }
        InfoRow {
            label: "默认模型"
            value: root.activeProfile?.model || "未选择"
        }
        NavRow {
            last: true
            icon: "data_usage"
            text: "用量与限额"
            subtext: "今日 " + Ai.state.todayRequests + " 次" + (Ai.state.limits.enabled ? " · 上限 " + Ai.state.limits.daily + " 次" : " · 未限制次数")
            onClicked: root.nState.openSubPage(2)
        }

        SectionHeader { text: "服务连接" }
        Repeater {
            model: Ai.state.profiles
            NavRow {
                required property var modelData
                required property int index
                first: index === 0
                icon: "cloud"
                text: modelData.name + (modelData.id === Ai.state.active ? " · 默认" : "")
                subtext: root.formatLabel(modelData.format) + (modelData.hasKey ? " · 密钥已保存" : "")
                onClicked: root.openEditor(modelData)
            }
        }
        NavRow {
            first: !Ai.state.profiles.length
            last: true
            icon: "add"
            text: "添加服务"
            subtext: "配置供应商与接口"
            onClicked: root.openEditor(null)
        }

        SectionHeader { text: "接入功能" }
        ToggleRow {
            first: true; last: true
            text: "软件描述翻译"
            subtext: "控制台 · 软件管理"
            checked: Ai.state.translation
            onToggled: {
                if (checked !== Ai.state.translation) root.run("configure", {translation:checked});
            }
        }

    }
}
