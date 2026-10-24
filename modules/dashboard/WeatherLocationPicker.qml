pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services

StyledRect {
    id: root
    objectName: "weatherLocationPicker"

    required property ScreenState screenState
    property bool expanded: false
    property bool searching: false
    property int searchEpoch: 0
    property var locations: []
    property string message: ""

    function updateTextInputFocus(): void {
        if (!screenState)
            return;
        screenState.dashboardTextInput = expanded && (cityField.activeFocus || districtField.activeFocus);
    }

    Component.onDestruction: {
        if (screenState)
            screenState.dashboardTextInput = false;
    }
    Connections {
        target: root.screenState
        function onDashboardChanged(): void {
            if (!root.screenState.dashboard)
                root.expanded = false;
        }
        function onDashboardTabChanged(): void { root.expanded = false; }
    }

    function invalidateSearch(): void {
        searchEpoch++;
        searching = false;
        locations = [];
        message = "";
        searchTimeout.stop();
    }

    function search(): void {
        if (searching)
            return;
        const city = cityField.text.trim();
        const district = districtField.text.trim();
        if (!city && !district) {
            message = Tr.tr("Enter a city or district first");
            return;
        }
        const epoch = ++searchEpoch;
        locations = [];
        searching = true;
        message = Tr.tr("Searching...");
        searchTimeout.restart();
        Weather.searchLocations(city, district, result => {
            if (!root || epoch !== root.searchEpoch || !root.expanded)
                return;
            searchTimeout.stop();
            root.searching = false;
            root.locations = result.locations || [];
            root.message = result.error === "network" || result.error === "unavailable"
                ? Tr.tr("Search failed. Try again.")
                : root.locations.length ? ""
                : Tr.tr("No matching places");
        });
    }

    visible: expanded || implicitHeight > 0
    enabled: expanded
    clip: true
    opacity: expanded ? 1 : 0
    Behavior on opacity { Anim { type: Anim.FastEffects } }
    Behavior on implicitHeight { Anim { type: Anim.DefaultSpatial } }
    implicitHeight: expanded ? body.implicitHeight + Tokens.padding.medium * 2 : 0
    radius: Tokens.rounding.large
    color: Colours.tPalette.m3surfaceContainer
    Keys.onEscapePressed: expanded = false

    onExpandedChanged: {
        if (!expanded) {
            invalidateSearch();
            searchTimeout.stop();
            cityField.focus = false;
            districtField.focus = false;
            if (root.screenState)
                root.screenState.dashboardTextInput = false;
        }
    }

    Timer {
        id: searchTimeout
        interval: 15000
        onTriggered: {
            root.searchEpoch++;
            root.searching = false;
            root.message = Tr.tr("Search failed. Try again.");
        }
    }

    ColumnLayout {
        id: body
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Tokens.padding.medium
        spacing: Tokens.spacing.small

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            StyledText {
                Layout.fillWidth: true
                text: Tr.tr("Choose location")
                font: Tokens.font.body.medium
                elide: Text.ElideRight
            }

            IconTextButton {
                type: ButtonBase.Text
                icon: "my_location"
                text: Tr.tr("Auto locate")
                disabled: Weather.ipApiRequestPending
                onClicked: {
                    root.invalidateSearch();
                    if (GlobalConfig.services.weatherLocation)
                        GlobalConfig.services.weatherLocation = "";
                    else
                        Weather.refreshLocation();
                    root.expanded = false;
                }
            }

            IconButton {
                icon: "close"
                type: ButtonBase.Text
                onClicked: root.expanded = false
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            StyledTextField {
                id: cityField
                objectName: "weatherCityField"
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                verticalPadding: Tokens.padding.small
                placeholderText: Tr.tr("City")
                onActiveFocusChanged: root.updateTextInputFocus()
                onTextEdited: root.invalidateSearch()
                onAccepted: root.search()
            }

            StyledTextField {
                id: districtField
                objectName: "weatherDistrictField"
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                verticalPadding: Tokens.padding.small
                placeholderText: Tr.tr("District (optional)")
                onActiveFocusChanged: root.updateTextInputFocus()
                onTextEdited: root.invalidateSearch()
                onAccepted: root.search()
            }

            IconTextButton {
                icon: "search"
                type: ButtonBase.Tonal
                text: Tr.tr("Search")
                disabled: root.searching
                onClicked: root.search()
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: !!root.message
            text: root.message
            wrapMode: Text.WordWrap
            font: Tokens.font.label.small
            color: Colours.palette.m3onSurfaceVariant
        }

        ListView {
            id: results
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(count, 3) * 56
            Behavior on Layout.preferredHeight { Anim { type: Anim.DefaultSpatial } }
            visible: count > 0
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: root.locations

            delegate: ButtonBase {
                id: resultButton
                required property var modelData
                implicitWidth: results.width
                implicitHeight: 56
                width: results.width
                height: 56
                type: ButtonBase.Text
                activeOnColour: Colours.palette.m3primary
                inactiveOnColour: Colours.palette.m3onSurface
                radius: Tokens.rounding.small
                internalChecked: GlobalConfig.services.weatherLocation === String(modelData.id)

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Tokens.padding.small
                    anchors.rightMargin: Tokens.padding.small
                    spacing: Tokens.spacing.small

                    MaterialIcon {
                        text: resultButton.internalChecked ? "check_circle" : "location_on"
                        color: Colours.palette.m3primary
                        fontStyle: Tokens.font.icon.medium
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        StyledText {
                            Layout.fillWidth: true
                            text: resultButton.modelData.name
                            elide: Text.ElideRight
                            font: Tokens.font.body.medium
                            color: resultButton.onColour
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: [...new Set([resultButton.modelData.country, resultButton.modelData.adm1,
                                resultButton.modelData.adm2].filter(v => v && v !== resultButton.modelData.name))].join(" · ")
                            elide: Text.ElideRight
                            font: Tokens.font.label.small
                            color: Colours.palette.m3onSurfaceVariant
                        }
                    }
                }

                onClicked: {
                    if (Weather.selectLocation(modelData))
                        root.expanded = false;
                }
            }
        }
    }
}
