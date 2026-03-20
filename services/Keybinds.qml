pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    readonly property string homeDir: Quickshell.env("HOME")

    property var data: []
    property bool isLoaded: false

    property Process fetcher: Process {
        command: [root.homeDir + "/.config/quickshell/caelestia/utils/bin/getkeybind", root.homeDir + "/.config/hypr/hyprland/keybinds.conf", root.homeDir + "/.config/hypr/variables.conf"]
        running: true

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.data = JSON.parse(this.text);
                    root.isLoaded = true;
                    console.log("Keybinds data loaded successfully!");

                    fileWatcher.running = true;
                } catch (e) {
                    console.log("Failed to parse keybinds JSON: " + e);
                }
            }
        }
    }

    property Process fileWatcher: Process {
        command: ["inotifywait", "-e", "close_write", root.homeDir + "/.config/hypr/hyprland/keybinds.conf", root.homeDir + "/.config/hypr/variables.conf"]
        running: false

        stdout: StdioCollector {
            onStreamFinished: {
                console.log("Hyprland config changed! Hot-reloading keybinds...");
                root.reload();
                fileWatcher.running = false;
                fileWatcher.running = true;
            }
        }
    }

    function reload() {
        fetcher.running = false;
        fetcher.running = true;
    }
}
