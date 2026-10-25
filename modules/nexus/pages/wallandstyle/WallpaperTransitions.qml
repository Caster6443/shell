pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia
import Caelestia.Config
import Caelestia.Shaders
import qs.components
import qs.components.controls
import qs.modules.nexus.common
import "../../../../components/widgets/WallpaperTransitionPolicy.js" as Policy

ColumnLayout {
    id: root
    Layout.fillWidth: true
    spacing: Tokens.spacing.extraSmall / 2
    property bool effectsOpen: false
    property bool rangeOpen: false
    readonly property var available: Policy.names(Shaders)
    readonly property var chosen: Policy.allowed(available, Config.background.wallpaperTransitionRandomEffects)
    readonly property string selectedKey: {
        CUtils.dependency(Config.background.wallpaperTransition);
        const name = CUtils.enumToString(Config.background, "wallpaperTransition");
        return name ? name[0].toLowerCase() + name.slice(1) : "crossfade";
    }
    readonly property var labels: ({
        random: "随机", chromaticBloom: "色散光晕", colourDistance: "色彩溶解",
        crossfade: "淡入淡出", crosshatch: "交叉网纹", crosswarp: "交叉扭曲",
        directional: "方向推移", directionalWipe: "方向擦除", fadeColour: "纯色淡出",
        glitch: "故障", glitchDisplace: "故障位移", heatMelt: "热浪融化",
        inkSplash: "墨水飞溅", inkwellDrop: "墨滴晕染", iris: "圆形展开",
        morph: "形态变换", parametricGlitch: "参数故障", perlin: "噪声溶解",
        pixelate: "像素化", pixelfadeWave: "像素波纹", plasmaFlow: "等离子流动",
        polkaDotsCurtain: "圆点幕帘", puzzleRight: "拼图滑移", randomSquares: "随机方块",
        smoke: "烟雾", softWarpFade: "柔和扭曲", voronoiShatter: "晶格碎裂",
        zoomBlurPull: "缩放模糊"
    })

    function labelFor(key: string): string { return labels[key] || key; }
    function selectEffect(key: string): void {
        const name = key[0].toUpperCase() + key.slice(1);
        GlobalConfig.background.wallpaperTransition = WallpaperTransition[name];
        effectsOpen = false;
    }
    function toggleEffect(key: string): void {
        const present = chosen.indexOf(key) >= 0;
        if (present && chosen.length === 1) return;
        GlobalConfig.background.wallpaperTransitionRandomEffects = present
            ? chosen.filter(name => name !== key) : chosen.concat([key]);
    }
    onSelectedKeyChanged: { if (selectedKey !== "random") rangeOpen = false; }

    RowButton {
        objectName: "wallpaperTransitionSelector"
        text: "过渡动画"
        icon: "animation"
        subtext: root.labelFor(root.selectedKey)
        trailingIcon: root.effectsOpen ? "expand_less" : "expand_more"
        onClicked: root.effectsOpen = !root.effectsOpen
    }
    ConnectedRect {
        Layout.fillWidth: true
        visible: root.effectsOpen
        implicitHeight: effectGrid.implicitHeight + Tokens.padding.medium * 2
        GridLayout {
            id: effectGrid
            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
            anchors.margins: Tokens.padding.medium
            columns: width >= 640 ? 3 : 2
            rowSpacing: Tokens.spacing.small
            columnSpacing: Tokens.spacing.small
            Repeater {
                model: ["random"].concat(root.available)
                IconTextButton {
                    required property string modelData
                    objectName: "wallpaperEffect_" + modelData
                    Layout.fillWidth: true
                    text: root.labelFor(modelData)
                    icon: root.selectedKey === modelData ? "radio_button_checked" : "radio_button_unchecked"
                    checked: root.selectedKey === modelData
                    type: IconTextButton.Tonal
                    font: Tokens.font.body.small
                    onClicked: root.selectEffect(modelData)
                }
            }
        }
    }
    RowButton {
        objectName: "wallpaperRandomRangeSelector"
        visible: root.selectedKey === "random"
        text: "随机效果范围"
        icon: "shuffle"
        subtext: "已选 " + root.chosen.length + " / " + root.available.length + " 种效果"
        trailingIcon: root.rangeOpen ? "expand_less" : "expand_more"
        onClicked: root.rangeOpen = !root.rangeOpen
    }
    ConnectedRect {
        Layout.fillWidth: true
        visible: root.selectedKey === "random" && root.rangeOpen
        implicitHeight: rangeContent.implicitHeight + Tokens.padding.medium * 2
        ColumnLayout {
            id: rangeContent
            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
            anchors.margins: Tokens.padding.medium
            spacing: Tokens.spacing.small
            RowLayout {
                Layout.fillWidth: true
                StyledText {
                    Layout.fillWidth: true
                    text: root.chosen.length === 1 ? "仅选一种时将始终使用该效果" : "至少保留一种；两种以上时避免连续重复"
                    font: Tokens.font.label.small
                    wrapMode: Text.Wrap
                }
                IconTextButton {
                    objectName: "wallpaperRandomSelectAll"
                    text: "全选"; icon: "select_all"
                    type: IconTextButton.Text
                    onClicked: GlobalConfig.background.wallpaperTransitionRandomEffects = []
                }
            }
            GridLayout {
                Layout.fillWidth: true
                columns: width >= 640 ? 3 : 2
                rowSpacing: Tokens.spacing.small
                columnSpacing: Tokens.spacing.small
                Repeater {
                    model: root.available
                    IconTextButton {
                        required property string modelData
                        readonly property bool included: root.chosen.indexOf(modelData) >= 0
                        objectName: "wallpaperRandomEffect_" + modelData
                        Layout.fillWidth: true
                        text: root.labelFor(modelData)
                        icon: included ? "check_box" : "check_box_outline_blank"
                        checked: included
                        disabled: included && root.chosen.length === 1
                        type: IconTextButton.Tonal
                        font: Tokens.font.body.small
                        onClicked: root.toggleEffect(modelData)
                    }
                }
            }
        }
    }
}
