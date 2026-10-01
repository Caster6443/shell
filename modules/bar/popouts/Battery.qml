pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Services.UPower
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.services

Column {
    id: root

    readonly property var fanProps: FanCurveState
    readonly property int fanMode: fanProps.powerMode === profileIndex(PowerProfiles.profile) && fanProps.fanMode >= 0 ? fanProps.fanMode : profileIndex(PowerProfiles.profile)

    function profileIndex(profile: int): int {
        if (profile === PowerProfile.PowerSaver)
            return 0;
        if (profile === PowerProfile.Performance)
            return 2;
        return 1;
    }

    function asusProfile(index: int): string {
        return ["Quiet", "Balanced", "Performance"][index];
    }

    function setFanMode(index: int): void {
        if (index < 0 || index > 2)
            return;

        profileCurveTimer.stop();
        fanProps.powerMode = profileIndex(PowerProfiles.profile);
        fanProps.fanMode = index;
        applyFanCurve(index, asusProfile(profileIndex(PowerProfiles.profile)));
    }

    function applyFanCurve(presetIndex: int, targetProfile: string): void {
        // Curves are the saved profile points exposed by asusctl 6.5.0
        // on this FA507XV. Raw PWM values (0–255) avoid percentage rounding.
        const curves = [
            {
                cpu: "60c:5,63c:22,66c:38,69c:45,72c:56,75c:63,78c:81,78c:81",
                gpu: "58c:5,60c:20,63c:38,65c:43,67c:56,70c:66,72c:84,72c:84"
            },
            {
                cpu: "45c:5,49c:22,54c:38,68c:45,74c:56,79c:63,84c:81,89c:94",
                gpu: "40c:5,42c:20,43c:38,60c:43,65c:56,69c:66,74c:84,78c:112"
            },
            {
                cpu: "20c:28,52c:45,57c:63,62c:81,67c:94,72c:109,81c:147,86c:181",
                gpu: "20c:25,39c:43,45c:66,50c:84,55c:112,60c:127,70c:173,76c:201"
            }
        ];
        const curve = curves[presetIndex];
        const commands = [
            `/usr/bin/asusctl fan-curve --mod-profile ${targetProfile} --fan cpu --data '${curve.cpu}'`,
            `/usr/bin/asusctl fan-curve --mod-profile ${targetProfile} --fan gpu --data '${curve.gpu}'`,
            `/usr/bin/asusctl fan-curve --mod-profile ${targetProfile} --fan cpu --enable-fan-curve true`,
            `/usr/bin/asusctl fan-curve --mod-profile ${targetProfile} --fan gpu --enable-fan-curve true`
        ];
        Quickshell.execDetached(["bash", "-c", commands.join(" && ")]);
    }

    function formatSeconds(s: int): string {
        const day = Math.floor(s / 86400);
        const hr = Math.floor(s / 3600) % 24;
        const min = Math.floor(s / 60) % 60;

        let comps = [];
        if (day > 0)
            comps.push(Tr.trN("%n day", "%n days", day));
        if (hr > 0)
            comps.push(Tr.trN("%n hour", "%n hours", hr));
        if (min > 0)
            comps.push(Tr.trN("%n min", "%n mins", min));

        return comps.join(Tr.trCtx(", ", "duration component separator"));
    }

    function powerProfileToString(p: int): string {
        switch (p) {
        case PowerProfile.Balanced:
            return Tr.trCtx("Balanced", "power profile");
        case PowerProfile.Performance:
            return Tr.trCtx("Performance", "power profile");
        case PowerProfile.PowerSaver:
            return Tr.trCtx("Power saver", "power profile");
        default:
            return Tr.trCtx("Unknown", "power profile");
        }
    }

    function perfDegradationToString(p: int): string {
        switch (p) {
        case PerformanceDegradationReason.HighTemperature:
            return Tr.tr("The device is too hot");
        case PerformanceDegradationReason.LapDetected:
            return Tr.tr("The device is on a lap");
        default:
            return Tr.tr("Unknown reason");
        }
    }

    spacing: Tokens.spacing.medium
    width: Tokens.sizes.bar.batteryWidth

    StyledText {
        text: UPower.displayDevice.isLaptopBattery ? Tr.trCtx("Remaining: %1%", "battery remaining").arg(Math.round(UPower.displayDevice.percentage * 100)) : Tr.tr("No battery detected")
    }

    StyledText {
        text: {
            const dev = UPower.displayDevice;
            if (!dev.isLaptopBattery)
                return Tr.tr("Power profile: %1").arg(root.powerProfileToString(PowerProfiles.profile));

            if (UPower.onBattery) {
                const time = root.formatSeconds(dev.timeToEmpty);
                if (time)
                    return Tr.tr("Time remaining: %1").arg(time);
                return Tr.tr("Calculating remaining battery life...");
            }

            if (dev.timeToFull > 0)
                return Tr.tr("Time until charged: %1").arg(root.formatSeconds(dev.timeToFull));
            if (Math.round(dev.percentage * 100) === 100)
                return Tr.tr("Fully charged!");
            return Tr.tr("Calculating time until charged...");
        }
    }

    Loader {
        asynchronous: true
        anchors.horizontalCenter: parent.horizontalCenter

        active: PowerProfiles.degradationReason !== PerformanceDegradationReason.None

        height: active ? ((item as Item)?.implicitHeight ?? 0) : 0

        sourceComponent: StyledRect {
            implicitWidth: child.implicitWidth + Tokens.padding.medium * 2
            implicitHeight: child.implicitHeight + Tokens.padding.large

            color: Colours.palette.m3error
            radius: Tokens.rounding.large

            Column {
                id: child

                anchors.centerIn: parent

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: Tokens.spacing.small

                    MaterialIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.verticalCenterOffset: -font.pointSize / 10

                        text: "warning"
                        color: Colours.palette.m3onError
                    }

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        // TRANSLATORS: charger or thermal warning: the battery cannot draw full power
                        text: Tr.tr("Performance degraded")
                        color: Colours.palette.m3onError
                        font: Tokens.font.title.small
                    }

                    MaterialIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.verticalCenterOffset: -font.pointSize / 10

                        text: "warning"
                        color: Colours.palette.m3onError
                    }
                }

                StyledText {
                    anchors.horizontalCenter: parent.horizontalCenter

                    text: root.perfDegradationToString(PowerProfiles.degradationReason)
                    color: Colours.palette.m3onError
                }
            }
        }
    }

    StyledRect {
        id: profiles

        property string current: {
            const p = PowerProfiles.profile;
            if (p === PowerProfile.PowerSaver)
                return saver.icon;
            if (p === PowerProfile.Performance)
                return perf.icon;
            return balance.icon;
        }

        anchors.horizontalCenter: parent.horizontalCenter

        implicitWidth: saver.implicitHeight + balance.implicitHeight + perf.implicitHeight + Tokens.padding.medium * 2 + Tokens.spacing.largeIncreased * 2
        implicitHeight: Math.max(saver.implicitHeight, balance.implicitHeight, perf.implicitHeight) + Tokens.padding.small

        color: Colours.tPalette.m3surfaceContainer
        radius: Tokens.rounding.full

        StyledRect {
            id: indicator

            color: Colours.palette.m3primary
            radius: Tokens.rounding.full
            state: profiles.current

            states: [
                State {
                    name: saver.icon

                    Fill {
                        item: saver
                        indicatorTarget: indicator
                    }
                },
                State {
                    name: balance.icon

                    Fill {
                        item: balance
                        indicatorTarget: indicator
                    }
                },
                State {
                    name: perf.icon

                    Fill {
                        item: perf
                        indicatorTarget: indicator
                    }
                }
            ]

            transitions: Transition {
                AnchorAnim {}
            }
        }

        Profile {
            id: saver

            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: Tokens.padding.extraSmall

            profile: PowerProfile.PowerSaver
            icon: "energy_savings_leaf"
        }

        Profile {
            id: balance

            anchors.centerIn: parent

            profile: PowerProfile.Balanced
            icon: "balance"
        }

        Profile {
            id: perf

            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            anchors.rightMargin: Tokens.padding.extraSmall

            profile: PowerProfile.Performance
            icon: "rocket_launch"
        }
    }

    StyledText {
        anchors.horizontalCenter: parent.horizontalCenter
        text: "风扇曲线"
    }

    StyledRect {
        id: fanProfiles

        property string current: ["quiet", "balanced", "performance"][root.fanMode]

        anchors.horizontalCenter: parent.horizontalCenter

        implicitWidth: quietFan.implicitWidth + balancedFan.implicitWidth + performanceFan.implicitWidth + Tokens.padding.medium * 2 + Tokens.spacing.largeIncreased * 2
        implicitHeight: Math.max(quietFan.implicitHeight, balancedFan.implicitHeight, performanceFan.implicitHeight) + Tokens.padding.small

        color: Colours.tPalette.m3surfaceContainer
        radius: Tokens.rounding.full

        StyledRect {
            id: fanIndicator

            color: Colours.palette.m3primary
            radius: Tokens.rounding.full
            state: fanProfiles.current

            states: [
                State {
                    name: "quiet"
                    FanFill { item: quietFan }
                },
                State {
                    name: "balanced"
                    FanFill { item: balancedFan }
                },
                State {
                    name: "performance"
                    FanFill { item: performanceFan }
                }
            ]

            transitions: Transition {
                AnchorAnim {}
            }
        }

        FanMode {
            id: quietFan
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: Tokens.padding.extraSmall
            index: 0
            icon: "mode_fan"
            label: "安静曲线"
        }

        FanMode {
            id: balancedFan
            anchors.centerIn: parent
            index: 1
            icon: "mode_fan"
            label: "均衡曲线"
        }

        FanMode {
            id: performanceFan
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            anchors.rightMargin: Tokens.padding.extraSmall
            index: 2
            icon: "mode_fan"
            label: "强散热曲线"
        }
    }

    Connections {
        target: PowerProfiles

        function onProfileChanged(): void {
            const nextMode = root.profileIndex(PowerProfiles.profile);
            root.fanProps.powerMode = nextMode;
            root.fanProps.fanMode = nextMode;
            profileCurveTimer.restart();
        }
    }

    Component.onCompleted: {
        const currentMode = root.profileIndex(PowerProfiles.profile);
        if (root.fanProps.powerMode < 0) {
            root.fanProps.powerMode = currentMode;
            root.fanProps.fanMode = currentMode;
        } else if (root.fanProps.powerMode !== currentMode) {
            root.fanProps.powerMode = currentMode;
            root.fanProps.fanMode = currentMode;
            profileCurveTimer.restart();
        }
    }

    Timer {
        id: profileCurveTimer
        interval: 750
        repeat: false
        onTriggered: root.applyFanCurve(root.fanMode, root.asusProfile(root.profileIndex(PowerProfiles.profile)))
    }

    component Fill: AnchorChanges {
        required property Item item
        required property Item indicatorTarget

        target: indicatorTarget
        anchors.left: item.left
        anchors.right: item.right
        anchors.top: item.top
        anchors.bottom: item.bottom
    }

    component FanFill: Fill {
        indicatorTarget: fanIndicator
    }

    component Profile: Item {
        required property string icon
        required property int profile

        implicitWidth: icon.implicitHeight + Tokens.padding.small
        implicitHeight: icon.implicitHeight + Tokens.padding.small

        StateLayer {
            radius: Tokens.rounding.full
            color: profiles.current === parent.icon ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface
            onClicked: PowerProfiles.profile = parent.profile
        }

        MaterialIcon {
            id: icon

            anchors.centerIn: parent

            text: parent.icon
            fontStyle: Tokens.font.icon.large
            color: profiles.current === text ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
            fill: profiles.current === text ? 1 : 0

            Behavior on fill {
                Anim {
                    type: Anim.DefaultEffects
                }
            }
        }
    }

    component FanMode: Item {
        required property int index
        required property string icon
        required property string label

        implicitWidth: iconItem.implicitHeight + Tokens.padding.small
        implicitHeight: iconItem.implicitHeight + Tokens.padding.small

        StateLayer {
            id: fanLayer
            radius: Tokens.rounding.full
            color: fanProfiles.current === ["quiet", "balanced", "performance"][parent.index] ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface
            onClicked: root.setFanMode(parent.index)
        }

        ToolTip.visible: fanLayer.containsMouse
        ToolTip.text: label

        MaterialIcon {
            id: iconItem

            anchors.centerIn: parent

            text: parent.icon
            fontStyle: Tokens.font.icon.large
            color: fanProfiles.current === ["quiet", "balanced", "performance"][parent.index] ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
            fill: fanProfiles.current === ["quiet", "balanced", "performance"][parent.index] ? 1 : 0

            Behavior on fill {
                Anim {
                    type: Anim.DefaultEffects
                }
            }
        }
    }
}
