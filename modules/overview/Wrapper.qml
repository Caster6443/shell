pragma ComponentBehavior: Bound

import QtQuick
import qs.components
import qs.config
import qs.services

Item {
    id: root

    property var visibilities: Visibilities.getForActive()

    visible: width > 0
    implicitWidth: 0
    clip: true

    onVisibleChanged: if (visible)
        forceActiveFocus()

    Keys.onPressed: event => {
        if (content.item)
            content.item.handleKey(event);
    }

    states: State {
        name: "visible"
        when: root.visibilities.overview

        PropertyChanges {
            root.implicitWidth: content.item ? content.item.implicitWidth : 0
        }
    }

    transitions: [
        Transition {
            from: ""
            to: "visible"

            Anim {
                target: root
                property: "implicitWidth"
                type: Anim.DefaultSpatial  // <- 调用新版的空间位移预设
            }
        },
        Transition {
            from: "visible"
            to: ""

            Anim {
                target: root
                property: "implicitWidth"
                type: Anim.StandardSmall   // <- 收起时调用标准的小幅度退出动画
            }
        }
    ]

    Loader {
        id: content

        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: parent.left

        active: root.visibilities.overview || root.visible

        sourceComponent: Overview {
            visibilities: root.visibilities
        }
    }
}
