pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import "../../services" as Services
import QtQuick.Window
import "../../config"

FloatingWindow {
    id: root
    readonly property string homeDir: Quickshell.env("HOME")
    title: "cheatsheet"
    implicitWidth: Screen.width * 0.75
    implicitHeight: Screen.height * 0.75
    visible: false
    color: "transparent"

    Shortcut {
        sequence: "Escape"
        onActivated: root.visible = false
    }

    Shortcut {
        sequence: "q"
        onActivated: root.visible = false
    }

    Process {
        id: toggleWatcher
        command: ["bash", "-c", "touch /tmp/cheatsheet_toggle && inotifywait -e close_write /tmp/cheatsheet_toggle"]
        running: true

        stdout: StdioCollector {
            onStreamFinished: {
                root.visible = !root.visible;
                toggleWatcher.running = false;
                toggleWatcher.running = true;
            }
        }
    }
    property var themeColours: ({})

    property var keybindsData: []

    Process {
        id: fetchTheme
        command: ["cat", root.homeDir + "/.local/state/caelestia/scheme.json"]
        running: true

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var scheme = JSON.parse(this.text);
                    root.themeColours = scheme.colours;
                    console.log("Color scheme loaded successfully! Primary color: #" + root.themeColours.primary);
                    themeWatcher.running = true;
                } catch (e) {
                    console.log("Failed to parse color scheme JSON: " + e);
                }
            }
        }
    }

    Process {
        id: themeWatcher
        command: ["inotifywait", "-e", "close_write", root.homeDir + "/.local/state/caelestia/scheme.json"]
        running: false

        stdout: StdioCollector {
            onStreamFinished: {
                console.log("Wallpaper/color scheme change detected, preparing to reload");
                fetchTheme.running = false;
                fetchTheme.running = true;
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: root.themeColours.surface ? ("#" + root.themeColours.surface) : '#1e1e2e'
        opacity: 0.5
        radius: 18

        Column {
            anchors.fill: parent
            anchors.margins: 40
            spacing: 30

            Text {
                text: "Caelestia Cheatsheet"
                font.family: Appearance.font.family.sans
                font.pixelSize: 32
                font.bold: true
                color: root.themeColours.primary ? ("#" + root.themeColours.primary) : "#cdd6f4"
                anchors.horizontalCenter: parent.horizontalCenter
            }

            Grid {
                width: parent.width
                columns: Math.max(1, Math.floor(parent.width / 420))
                columnSpacing: 40
                rowSpacing: 35

                Repeater {
                    model: Services.Keybinds.data
                    delegate: Column {
                        required property var modelData
                        width: 400
                        spacing: 15
                        visible: modelData && modelData.keybinds && modelData.keybinds.length > 0

                        Text {
                            text: (modelData ? modelData.category : "").charAt(0).toUpperCase() + (modelData ? modelData.category : "").slice(1)
                            font.family: Appearance.font.family.sans
                            font.pixelSize: 22
                            font.bold: true
                            color: root.themeColours.primary ? ("#" + root.themeColours.primary) : "#cdd6f4"
                        }

                        Column {
                            spacing: 10

                            Repeater {
                                model: modelData && modelData.keybinds ? modelData.keybinds : []
                                delegate: Row {
                                    required property var modelData
                                    property var kb: modelData
                                    width: 400
                                    spacing: 15

                                    Row {
                                        spacing: 6
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 220

                                        Repeater {
                                            model: kb.key ? kb.key.split(" ") : []
                                            delegate: Row {
                                                required property string modelData
                                                required property int index
                                                spacing: 6
                                                anchors.verticalCenter: parent.verticalCenter

                                                Rectangle {
                                                    color: root.themeColours.primary ? ("#" + root.themeColours.primary) : "#cdd6f4"
                                                    radius: 5
                                                    width: innerBg.width + 4
                                                    height: innerBg.height + 6

                                                    Rectangle {
                                                        id: innerBg
                                                        color: root.themeColours.surface ? ("#" + root.themeColours.surface) : "#1e1e2e"
                                                        radius: 4
                                                        width: keyText.implicitWidth + 14
                                                        height: keyText.implicitHeight + 8
                                                        anchors.horizontalCenter: parent.horizontalCenter
                                                        anchors.top: parent.top
                                                        anchors.topMargin: 1

                                                        Text {
                                                            id: keyText
                                                            text: modelData
                                                            anchors.centerIn: parent
                                                            font.family: Appearance.font.family.sans
                                                            font.pixelSize: 12
                                                            font.bold: true
                                                            color: root.themeColours.primary ? ("#" + root.themeColours.primary) : "#cdd6f4"
                                                        }
                                                    }
                                                }
                                                Text {
                                                    text: "+"
                                                    visible: index < (kb.key.split(" ").length - 1)
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    font.pixelSize: 14
                                                    color: root.themeColours.primary ? ("#" + root.themeColours.primary) : "#cdd6f4"
                                                    opacity: 0.7
                                                }
                                            }
                                        }
                                    }

                                    Text {
                                        text: kb.desc
                                        anchors.verticalCenter: parent.verticalCenter
                                        font.family: Appearance.font.family.sans
                                        font.pixelSize: 13
                                        color: root.themeColours.onSurface ? ("#" + root.themeColours.onSurface) : (root.themeColours.text ? ("#" + root.themeColours.text) : "#cdd6f4")
                                        width: parent.width - 220 - parent.spacing
                                        wrapMode: Text.WordWrap
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
