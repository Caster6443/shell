import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Mpris
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services

Item {
    id: root

    required property ScreenState screenState

    ColumnLayout {
        id: layout

        anchors.fill: parent
        anchors.leftMargin: Tokens.padding.medium
        spacing: Tokens.spacing.medium

        RowLayout {
            Layout.bottomMargin: -Tokens.spacing.medium
            spacing: Tokens.spacing.medium
            z: 1

            MaterialIcon {
                Layout.topMargin: Math.round(fontInfo.pointSize * 0.12)
                text: "lyrics"
                fontStyle: Tokens.font.icon.medium
            }

            StyledText {
                Layout.fillWidth: true
                text: Tr.tr("Lyrics")
                font: Tokens.font.title.medium
            }

            LyricsInfo {}
        }

        LyricList {
            Layout.fillWidth: true
            Layout.fillHeight: true
        }

        RowLayout {
            id: playerControls

            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: Tokens.spacing.small

            SplitButton {
                id: backendSelector

                Layout.fillWidth: true
                Layout.minimumWidth: 0

                type: SplitButton.Tonal
                disabled: !Players.list.length
                active: menuItems.find(m => m.modelData === Players.active) ?? menuItems[0] ?? null
                menu.onItemSelected: item => Players.manualActive = (item as PlayerItem).modelData

                menuItems: playerList.instances
                fallbackIcon: "music_off"
                fallbackText: Tr.trCtx("No players", "no media players active")

                minLeftWidth: Math.max(0, width - expandBtn.implicitWidth - spacing)
                label.Layout.maximumWidth: Math.max(0, minLeftWidth - iconLabel.implicitWidth - textRow.spacing - textRow.anchors.horizontalCenterOffset / 2 - horizontalPadding * 2)
                label.elide: Text.ElideRight

                stateLayer.disabled: true
                menuOnTop: true

                Variants {
                    id: playerList

                    model: Players.list

                    PlayerItem {}
                }
            }

            AudioImport {
                id: audioImport
                screenState: root.screenState
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: visible ? implicitWidth : 0
                Layout.minimumWidth: 0
                Layout.maximumWidth: visible ? implicitWidth : 0
            }
        }
    }

    component PlayerItem: MenuItem {
        required property MprisPlayer modelData

        icon: modelData === Players.active ? "check" : ""
        text: Players.getIdentity(modelData)
        activeIcon: "animated_images"
    }
}
