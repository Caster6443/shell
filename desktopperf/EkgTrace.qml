import QtQuick
import QtQuick.Shapes
import qs.services

Item {
    id: trace

    property var samples: []
    property color traceColour: "white"
    property real scaleFactor: 1
    readonly property var points: {
        const result = [];
        if (width <= 0 || height <= 0 || samples.length < 2)
            return result;
        const inset = 4 * scaleFactor;
        for (let i = 0; i < samples.length; ++i) {
            const x = i * width / (samples.length - 1);
            const value = Math.max(0, Math.min(100, Number(samples[i]) || 0)) / 100;
            const y = height - inset - value * (height - 2 * inset);
            result.push(Qt.point(x, y));
        }
        return result;
    }

    Rectangle {
        anchors.fill: parent
        radius: 5 * trace.scaleFactor
        color: Qt.alpha(Colours.palette.m3surfaceVariant, 0.24)
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: Qt.alpha(Colours.palette.m3outlineVariant, 0.22)
            strokeWidth: 1
            fillColor: "transparent"
            PathPolyline {
                path: [Qt.point(0, trace.height / 2), Qt.point(trace.width, trace.height / 2)]
            }
        }

        ShapePath {
            strokeColor: trace.traceColour
            strokeWidth: 1.8 * trace.scaleFactor
            capStyle: ShapePath.SquareCap
            joinStyle: ShapePath.MiterJoin
            fillColor: "transparent"
            PathPolyline { path: trace.points }
        }
    }
}
