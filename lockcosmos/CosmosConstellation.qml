pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes

Item {
    id: constellation

    required property string passcode
    required property real scaleFactor
    required property color starColor
    property color errorColor: "#ff8a80"
    property bool hasError: false
    property real pulse: 0

    readonly property int maxStars: 24
    readonly property int count: Math.min(passcode.length, maxStars)
    readonly property real stepX: Math.min(48 * scaleFactor, (width - 40 * scaleFactor) / Math.max(1, count))
    readonly property color tone: hasError ? errorColor : starColor

    function pointAt(i: int): point {
        const n = Math.max(1, count);
        return Qt.point(width / 2 + (i - (n - 1) / 2) * stepX,
                        height / 2 + Math.sin(i * 1.9 + 0.6) * 15 * scaleFactor + (i % 3 === 0 ? -9 : 5) * scaleFactor);
    }

    Shape {
        anchors.fill: parent
        opacity: constellation.count > 1 ? 0.55 : 0
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            fillColor: "transparent"
            strokeColor: constellation.tone
            strokeWidth: 1 * constellation.scaleFactor
            PathPolyline {
                path: {
                    const points = [];
                    for (let i = 0; i < constellation.count; i++)
                        points.push(constellation.pointAt(i));
                    return points;
                }
            }
        }
    }

    Repeater {
        model: constellation.maxStars

        Item {
            id: star
            required property int index
            readonly property bool active: index < constellation.count
            readonly property point location: constellation.pointAt(index)
            readonly property real lit: constellation.count > 0
                ? Math.max(0, 1 - Math.abs(constellation.pulse * (constellation.count + 3) - 1.5 - index) / 1.5) : 0
            width: 30 * constellation.scaleFactor
            height: width
            x: location.x - width / 2
            y: location.y - height / 2
            opacity: active ? 1 : 0
            scale: active ? 1 : 0
            visible: opacity > 0.01

            Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
            Behavior on y { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: 230; easing.type: Easing.OutBack } }
            Behavior on opacity { NumberAnimation { duration: 170 } }

            Rectangle {
                anchors.centerIn: parent
                width: parent.width * (0.6 + 0.4 * star.lit)
                height: width
                radius: width / 2
                color: Qt.alpha(constellation.tone, 0.2 + star.lit * 0.18)
            }
            Rectangle {
                anchors.centerIn: parent
                width: parent.width * 0.68
                height: 1.2 * constellation.scaleFactor
                color: Qt.alpha(constellation.tone, 0.72)
            }
            Rectangle {
                anchors.centerIn: parent
                width: 1.2 * constellation.scaleFactor
                height: parent.height * 0.68
                color: Qt.alpha(constellation.tone, 0.72)
            }
            Rectangle {
                anchors.centerIn: parent
                width: 5 * constellation.scaleFactor
                height: width
                radius: width / 2
                color: "#ffffff"
            }
        }
    }
}
