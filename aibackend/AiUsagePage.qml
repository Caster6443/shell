pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

// AI 服务子页：今日用量与请求限额。限额可整体关闭，关闭后不限次数、不限单次输出。
PageBase {
    id: root
    title: "用量与限额"
    isSubPage: true
    objectName: "aiUsagePage"

    function run(action: string, payload: var): void {
        Ai.request(action, payload);
    }

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        SectionHeader { first: true; text: "今日用量" }
        InfoRow {
            first: true; last: true
            label: "请求次数"
            value: Ai.state.todayRequests + (Ai.state.limits.enabled ? " / " + Ai.state.limits.daily : "")
            subtext: Ai.state.limits.enabled ? "含失败请求" : "未限制次数"
        }

        SectionHeader { text: "请求保护" }
        ToggleRow {
            first: true
            last: !Ai.state.limits.enabled
            text: "启用请求限额"
            subtext: Ai.state.limits.enabled ? "达到上限后暂停请求" : "不限次数与单次输出"
            checked: Ai.state.limits.enabled
            // 绑定更新也会触发 toggled，只有和当前配置不一致才是用户操作。
            onToggled: {
                if (checked !== Ai.state.limits.enabled)
                    root.run("configure", {limits:{enabled:checked}});
            }
        }
        StepperRow {
            visible: Ai.state.limits.enabled
            label: "每日请求"
            value: Ai.state.limits.daily
            from: 1; to: 10000; stepSize: 10
            onMoved: value => root.run("configure", {limits:{daily:value}})
        }
        StepperRow {
            visible: Ai.state.limits.enabled
            label: "每分钟请求"
            value: Ai.state.limits.minute
            from: 1; to: 60
            onMoved: value => root.run("configure", {limits:{minute:value}})
        }
        StepperRow {
            last: true
            visible: Ai.state.limits.enabled
            label: "单次输出上限"
            subtext: "token"
            value: Ai.state.limits.outputTokens
            from: 64; to: 16384; stepSize: 64
            onMoved: value => root.run("configure", {limits:{outputTokens:value}})
        }
    }
}
