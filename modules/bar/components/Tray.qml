pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import Caelestia.Config
import qs.components
import qs.services

StyledRect {
    id: root

    readonly property alias layout: layout
    readonly property alias items: items
    readonly property alias expandIcon: expandIcon

    readonly property int padding: Config.bar.tray.background ? Tokens.padding.medium : Tokens.padding.extraSmall
    readonly property int spacing: Config.bar.tray.background ? Tokens.spacing.medium : Tokens.spacing.extraSmall

    property bool expanded

    // 常驻显示的托盘图标：即使 compact=true 也一直显示在收纳区外（本地 fork 补丁，见
    // ~/Github_repos/shell/patches/tray/tray-pinned-wechat.patch 与 DEVELOPMENT_LOG.md）
    readonly property list<string> pinnedIds: ["wechat"]

    readonly property bool hasCollapsible: Config.bar.tray.compact && items.count - pinnedItems.count > 0

    readonly property real nonAnimHeight: {
        if (!Config.bar.tray.compact)
            return layout.implicitHeight + padding * 2;
        const pad = (Config.bar.tray.background ? Tokens.padding.extraSmall : 0) + padding;
        if (expanded)
            return expandIcon.implicitHeight + layout.implicitHeight + spacing + pad;
        const pinnedH = pinnedCol.visible ? pinnedCol.implicitHeight + spacing : 0;
        const arrowH = hasCollapsible ? expandIcon.implicitHeight : 0;
        return Math.max(Config.bar.tray.background ? width : 0, pinnedH + arrowH + pad);
    }

    clip: true
    visible: height > 0

    implicitWidth: Tokens.sizes.bar.innerWidth
    implicitHeight: nonAnimHeight

    color: Qt.alpha(Colours.tPalette.m3surfaceContainer, (Config.bar.tray.background && items.count > 0) ? Colours.tPalette.m3surfaceContainer.a : 0)
    radius: Tokens.rounding.full

    Column {
        id: layout

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: root.padding
        spacing: Tokens.spacing.small

        opacity: root.expanded || !Config.bar.tray.compact ? 1 : 0

        add: Transition {
            Anim {
                properties: "scale"
                from: 0
                to: 1
                easing: Tokens.anim.standardDecel
            }
        }

        move: Transition {
            Anim {
                properties: "scale"
                to: 1
                easing: Tokens.anim.standardDecel
            }
            Anim {
                properties: "x,y"
            }
        }

        Repeater {
            id: items

            model: ScriptModel {
                values: SystemTray.items.values.filter(i => i.status !== Status.Passive && !GlobalConfig.bar.tray.hiddenIcons.includes(i.id))
            }

            TrayItem {}
        }

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }
    }

    Column {
        id: pinnedCol

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: root.padding
        spacing: root.spacing

        visible: Config.bar.tray.compact && !root.expanded && pinnedItems.count > 0

        Repeater {
            id: pinnedItems

            model: ScriptModel {
                values: SystemTray.items.values.filter(i => !GlobalConfig.bar.tray.hiddenIcons.includes(i.id) && root.pinnedIds.includes(i.id))
            }

            TrayItem {}
        }
    }

    Loader {
        id: expandIcon

        asynchronous: true

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom

        active: Config.bar.tray.compact && root.hasCollapsible

        sourceComponent: Item {
            implicitWidth: expandIconInner.implicitWidth
            implicitHeight: expandIconInner.implicitHeight - Tokens.padding.small

            MaterialIcon {
                id: expandIconInner

                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Config.bar.tray.background ? Tokens.padding.extraSmall : -Tokens.padding.small
                text: "expand_less"
                color: Colours.palette.m3onSurfaceVariant
                fontStyle: Tokens.font.icon.medium
                rotation: root.expanded ? 180 : 0

                Behavior on rotation {
                    Anim {}
                }

                Behavior on anchors.bottomMargin {
                    Anim {}
                }
            }
        }
    }

    Behavior on implicitHeight {
        Anim {}
    }
}
