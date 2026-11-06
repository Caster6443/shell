pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.overview

Item {
    id: root
    property string query: ""
    readonly property var commands: [{name: "packages", title: "软件管理", description: "已安装软件、依赖关系、更新与卸载", keywords: "pkg package packages software apps 软件 应用管理 包管理 更新 update"}]
    readonly property var results: commands.filter(c => query.trim().toLowerCase().split(/\s+/).every(word => (c.name + " " + c.title + " " + c.keywords).toLowerCase().includes(word)))
    property int currentIndex: 0
    signal packagesRequested()
    onResultsChanged: currentIndex = 0
    function moveSelection(step: int): void { currentIndex = Math.max(0, Math.min(results.length - 1, currentIndex + step)); }
    function activate(): void { if (results.length && results[currentIndex]) packagesRequested(); }
    ColumnLayout {
        anchors.fill: parent
        spacing: 14
        ConsoleText { text: "命令"; color: M3Palette.m3onSurface; textRole: "title"; strong: true }
        ConsoleText { text: "继续输入筛选 · ↑ ↓ 选择 · Enter 打开 · Esc 返回搜索"; color: M3Palette.m3onSurfaceVariant; textRole: "caption"}
        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 6
            clip: true
            model: root.results
            delegate: Rectangle {
                id: row
                required property var modelData
                required property int index
                width: list.width
                height: 76
                radius: 12
                color: row.index === root.currentIndex ? ConsoleMaterialStyle.selection : Qt.alpha(M3Palette.m3onSurface, 0.04)
                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 15
                    spacing: 14
                    ConsoleText { text: ">_"; color: ConsoleMaterialStyle.selectedText; textRole: "title"; strong: true }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 5
                        ConsoleText { text: row.modelData.title; color: M3Palette.m3onSurface; textRole: "body"; strong: true }
                        ConsoleText { text: row.modelData.description; color: M3Palette.m3onSurfaceVariant; textRole: "caption"}
                    }
                    ConsoleText { text: row.modelData.name + "  ↵"; color: M3Palette.m3onSurfaceVariant; textRole: "body"}
                }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { root.currentIndex = row.index; root.activate(); } }
            }
            ConsoleText { anchors.centerIn: parent; visible: list.count === 0; text: "没有匹配的命令"; color: M3Palette.m3onSurfaceVariant; textRole: "body"}
        }
    }
}
