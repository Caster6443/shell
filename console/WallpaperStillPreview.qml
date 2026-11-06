pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Io

// The shell only loads images. Video decoding runs in a serialized external worker.
Item {
    id: root
    property url source
    property size sourceSize
    property int fillMode: Image.PreserveAspectCrop
    property bool asynchronous: true
    property bool cache: true
    property bool retainWhileLoading: true
    property string poster: ""
    property bool failed: false
    readonly property bool video: /\.(mp4|mkv|webm|mov|m4v|avi)$/i.test(source.toString())

    onSourceChanged: { poster = ""; failed = false; }
    Process {
        command: ["python", Qt.resolvedUrl("video_thumbnail.py").toString().replace(/^file:\/\//, ""), root.source.toString()]
        running: root.visible && root.video && !root.poster && !root.failed
        stdout: StdioCollector {
            onStreamFinished: { if (text.trim()) root.poster = text.trim(); }
        }
        onExited: (code, status) => { if (code !== 0 && root.visible) root.failed = true; }
    }
    Image {
        anchors.fill: parent
        source: root.video ? root.poster : root.source
        sourceSize: root.sourceSize
        fillMode: root.fillMode
        asynchronous: root.asynchronous
        cache: root.cache
        retainWhileLoading: root.retainWhileLoading
    }
    Text {
        anchors.centerIn: parent
        visible: root.video && !root.poster
        text: root.failed ? "缩略图生成失败" : "正在生成缩略图…"
        color: "#888888"
    }
    Rectangle {
        visible: root.video
        anchors.left: parent.left; anchors.top: parent.top; anchors.margins: 12
        width: 38; height: 22; radius: 6; color: "#99000000"
        Text { anchors.centerIn: parent; text: "视频"; color: "white"; font.pixelSize: 12 }
    }
}
