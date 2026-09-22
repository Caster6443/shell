pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

// mihomo 无头内核的快速面板：VPN 按钮右键后接管 utilities 面板。
// 两个选项卡（节点 / 订阅）+ 策略组胶囊；节点切换走 mihomo REST API，订阅切换走 mihomo-sub。
//
// 布局刻意用固定行高 + 显式定位（不用 Row/RowLayout + anchors 混搭、不用可伸缩 delegate），
// 避免 QML 布局循环把 shell 拖死（第一版就栽在这儿）。
Item {
	id: root

	required property var screenState

	readonly property real pad: Tokens.padding.large
	readonly property real rowH: 34

	implicitWidth: Tokens.sizes.utilities.width
	implicitHeight: 372

	// ---- 入场动画（对齐 shell 其它列表的观感）----
	property real enterY: 14
	property string displayTab: MihomoState.tab

	opacity: 0
	transform: Translate {
		y: root.enterY
	}

	Behavior on opacity {
		Anim {
			type: Anim.DefaultEffects
		}
	}

	Behavior on enterY {
		Anim {
			type: Anim.FastSpatial
		}
	}

	Component.onCompleted: {
		root.opacity = 1;
		root.enterY = 0;
	}

	// 切页：淡出 → 换模型 → 淡入（与 launcher ContentList 的 animState 同款做法）
	Connections {
		target: MihomoState

		function onTabChanged() {
			switchAnim.restart();
		}
	}

	SequentialAnimation {
		id: switchAnim

		NumberAnimation {
			target: list
			property: "opacity"
			to: 0
			duration: 90
			easing: Tokens.anim.standardAccel
		}

		ScriptAction {
			script: root.displayTab = MihomoState.tab
		}

		NumberAnimation {
			target: list
			property: "opacity"
			to: 1
			duration: 170
			easing: Tokens.anim.standardDecel
		}
	}

	// 面板收起（鼠标移开 utilities 区）时复位，下次展开回到普通卡片
	Connections {
		target: root.screenState

		function onUtilitiesChanged() {
			if (!root.screenState.utilities && MihomoState.panelOpen)
				MihomoState.closePanel();
		}
	}

	// ---- 顶部：选项卡胶囊 ----
	Item {
		id: tabBar

		x: root.pad
		y: root.pad
		width: 196
		height: root.rowH

		readonly property real halfW: (width - 4) / 2
		readonly property int tabIndex: MihomoState.tab === "nodes" ? 0 : 1

		Rectangle {
			anchors.fill: parent
			radius: height / 2
			color: Colours.layer(Colours.palette.m3surfaceContainerHighest, 2)
		}

		Rectangle {
			id: tabPill

			x: 2 + tabBar.tabIndex * tabBar.halfW
			y: 2
			width: tabBar.halfW
			height: parent.height - 4
			radius: height / 2
			color: Colours.palette.m3secondaryContainer

			Behavior on x {
				Anim {
					type: Anim.DefaultEffects
				}
			}
		}

		Repeater {
			model: [{
					"id": "nodes",
					"label": "节点"
				}, {
					"id": "subs",
					"label": "订阅"
				}]

			Item {
				required property var modelData
				required property int index

				x: 2 + index * tabBar.halfW
				y: 2
				width: tabBar.halfW
				height: tabBar.height - 4

				StateLayer {
					anchors.fill: parent
					radius: height / 2
					onClicked: MihomoState.setTab(parent.modelData.id)
				}

				StyledText {
					anchors.centerIn: parent
					text: parent.modelData.label
					color: MihomoState.tab === parent.modelData.id ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurfaceVariant
					font: Tokens.font.label.medium
				}
			}
		}
	}

	// ---- 右上：操作按钮 ----
	Item {
		id: actions

		anchors.right: parent.right
		anchors.rightMargin: root.pad
		anchors.top: parent.top
		anchors.topMargin: root.pad - (rowH - 22) / 2
		width: 96
		height: rowH

		IconButton {
			x: 0
			anchors.verticalCenter: parent.verticalCenter
			icon: MihomoState.tab === "nodes" ? "speed" : "cloud_sync"
			type: IconButton.Text
			onClicked: MihomoState.tab === "nodes" ? MihomoState.testDelay() : MihomoState.syncSubs()
		}

		IconButton {
			id: refreshBtn

			x: 32
			anchors.verticalCenter: parent.verticalCenter
			icon: "refresh"
			type: IconButton.Text
			visible: !(MihomoState.busy || MihomoState.testing)
			onClicked: MihomoState.refresh()
		}

		// 忙碌/测速时：换成 shell 原生加载动画（与其它模块同款）
		Item {
			x: 32
			anchors.verticalCenter: parent.verticalCenter
			width: refreshBtn.width
			height: refreshBtn.height
			visible: MihomoState.busy || MihomoState.testing

			LoadingIndicator {
				anchors.centerIn: parent
				implicitSize: Math.round(Tokens.font.icon.medium.pointSize * 1.3)
			}
		}

		IconButton {
			x: 64
			anchors.verticalCenter: parent.verticalCenter
			icon: "close"
			type: IconButton.Text
			onClicked: MihomoState.closePanel()
		}
	}

	// ---- 策略组胶囊（横向滚动）----
	ListView {
		id: groupList

		x: root.pad
		y: root.pad + rowH + Tokens.spacing.medium
		width: root.width - root.pad * 2
		height: MihomoState.tab === "nodes" ? 30 : 0
		visible: height > 0
		orientation: ListView.Horizontal
		spacing: Tokens.spacing.small
		clip: true
		model: MihomoState.groups

		delegate: Item {
			id: groupPill

			required property var modelData

			readonly property bool active: modelData.name === MihomoState.group
			readonly property real labelW: groupMetrics.advanceWidth

			width: Math.max(64, labelW + Tokens.padding.largeIncreased)
			height: groupList.height

			TextMetrics {
				id: groupMetrics

				text: groupPill.modelData.name
				font: Tokens.font.label.medium
			}

			Rectangle {
				anchors.fill: parent
				radius: height / 2
				color: groupPill.active ? Colours.palette.m3primaryContainer : Colours.layer(Colours.palette.m3surfaceContainerHighest, 2)
			}

			StateLayer {
				anchors.fill: parent
				radius: height / 2
				onClicked: MihomoState.setGroup(parent.modelData.name)
			}

			StyledText {
				anchors.centerIn: parent
				text: groupPill.modelData.name
				color: groupPill.active ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurfaceVariant
				font: Tokens.font.label.medium
			}
		}
	}

	// ---- 列表（节点 / 订阅）----
	ListView {
		id: list

		x: root.pad
		y: root.pad + rowH + Tokens.spacing.medium + (groupList.visible ? groupList.height + Tokens.spacing.small : 0)
		width: root.width - root.pad * 2
		height: (root.implicitHeight - root.pad * 3) - (y - root.pad) - 24
		clip: true
		spacing: 2
		model: root.displayTab === "nodes" ? MihomoState.nodes : MihomoState.subs

		delegate: Item {
			id: listRow

			required property var modelData

			readonly property bool isNodes: root.displayTab === "nodes"
			readonly property bool current: isNodes ? modelData.active : modelData.current

			width: list.width
			height: root.rowH

			Rectangle {
				anchors.fill: parent
				radius: Tokens.rounding.small
				color: listRow.current ? Colours.layer(Colours.palette.m3secondaryContainer, 1) : "transparent"
			}

			StateLayer {
				anchors.fill: parent
				radius: Tokens.rounding.small
				onClicked: listRow.isNodes ? MihomoState.selectNode(listRow.modelData.name) : MihomoState.switchSub(listRow.modelData.id)
			}

			MaterialIcon {
				id: rowIcon

				anchors.left: parent.left
				anchors.leftMargin: Tokens.padding.medium
				anchors.verticalCenter: parent.verticalCenter
				text: listRow.isNodes ? (listRow.current ? "radio_button_checked" : "radio_button_unchecked") : (listRow.current ? "check_circle" : "cloud")
				color: listRow.current ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
				fontStyle: Tokens.font.icon.medium
			}

			StyledText {
				id: rowDelay

				anchors.right: parent.right
				anchors.rightMargin: Tokens.padding.medium
				anchors.verticalCenter: parent.verticalCenter
				visible: listRow.isNodes
				text: {
					if (!listRow.isNodes)
						return "";
					if (MihomoState.testing)
						return "…";
					return listRow.modelData.delay >= 0 ? `${listRow.modelData.delay} ms` : "超时";
				}
				color: {
					if (MihomoState.testing || listRow.modelData.delay < 0)
						return Colours.palette.m3onSurfaceVariant;
					if (listRow.modelData.delay <= 200)
						return Colours.palette.m3primary;
					return listRow.modelData.delay <= 500 ? Colours.palette.m3tertiary : Colours.palette.m3error;
				}
				font: Tokens.font.label.small
			}

			StyledText {
				anchors.left: rowIcon.right
				anchors.leftMargin: Tokens.padding.medium
				anchors.right: rowDelay.visible ? rowDelay.left : parent.right
				anchors.rightMargin: Tokens.padding.medium
				anchors.verticalCenter: parent.verticalCenter
				text: listRow.isNodes ? listRow.modelData.name : `${listRow.modelData.name}（${listRow.modelData.count} 节点）`
				color: listRow.current ? Colours.palette.m3primary : Colours.palette.m3onSurface
				font: Tokens.font.body.small
				elide: Text.ElideRight
			}
		}
	}

	// ---- 底部状态 ----
	StyledText {
		anchors.left: parent.left
		anchors.leftMargin: root.pad
		anchors.right: parent.right
		anchors.rightMargin: root.pad
		anchors.bottom: parent.bottom
		anchors.bottomMargin: root.pad
		text: {
			if (MihomoState.message !== "")
				return MihomoState.message;
			if (MihomoState.tab === "nodes")
				return `策略组 ${MihomoState.group} · ${MihomoState.nodes.length} 个节点`;
			return "订阅来自 mihomo-party 本地缓存，切换后自动重启内核";
		}
		color: Colours.palette.m3onSurfaceVariant
		font: Tokens.font.label.small
		elide: Text.ElideRight
	}
}
