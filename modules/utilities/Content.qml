pragma ComponentBehavior: Bound

import "cards"
import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.mihomo
import qs.modules.bar.popouts as BarPopouts

Item {
    id: root

    required property var props
    required property ScreenState screenState
    required property BarPopouts.Wrapper popouts
    required property matrix4x4 deformMatrix

    readonly property int enabledCards: (idleInhibit.active ? 1 : 0) + (record.active ? 1 : 0) + (toggles.active ? 1 : 0) + (mihomoPanel.active ? 1 : 0)
    readonly property real nonAnimHeight: ((idleInhibit.item as IdleInhibit)?.nonAnimHeight ?? 0) + ((record.item as Record)?.nonAnimHeight ?? 0) + ((toggles.item as Toggles)?.implicitHeight ?? 0) + ((mihomoPanel.item as MihomoPanel)?.implicitHeight ?? 0) + layout.spacing * Math.max(0, enabledCards - 1)

    implicitWidth: layout.implicitWidth
    implicitHeight: layout.implicitHeight

    // 本地 fork 补丁（2026-09-11）：普通卡片 ↔ mihomo 面板切换时高度平滑过渡
    Behavior on implicitHeight {
        Anim {}
    }

    ColumnLayout {
        id: layout

        anchors.fill: parent
        spacing: Tokens.spacing.medium

        Loader {
            id: idleInhibit

            Layout.fillWidth: true
            active: Config.utilities.cards.keepAwake
            visible: active

            sourceComponent: IdleInhibit {
                objectName: "utilitiesKeepAwake"
            }
        }

        Loader {
            id: record

            Layout.fillWidth: true
            active: Config.utilities.cards.recorder
            visible: active
            z: 1

            sourceComponent: Record {
                objectName: "utilitiesScreenRecorder"

                props: root.props
                screenState: root.screenState
            }
        }

        Loader {
            id: toggles

            Layout.fillWidth: true
            // 本地 fork 补丁（2026-09-11）：右键 VPN 按钮后，面板整体让位给 mihomo 面板
            active: Config.utilities.cards.quickToggles && !MihomoState.panelOpen
            visible: active

            sourceComponent: Toggles {
                objectName: "utilitiesQuickToggles"

                screenState: root.screenState
                popouts: root.popouts
            }
        }

        Loader {
            id: mihomoPanel

            Layout.fillWidth: true
            active: MihomoState.panelOpen
            visible: active

            sourceComponent: MihomoPanel {
                screenState: root.screenState
            }
        }
    }

    RecordingDeleteModal {
        props: root.props
        deformMatrix: root.deformMatrix
    }
}
