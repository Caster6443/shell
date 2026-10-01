pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root
    visible: false
    width: 0
    height: 0
    property string lightStyle: "enso"
    property string darkStyle: "cosmos"
    property string path: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/quickshell/caelestia/lock-style.json"

    function styleFor(isLight) {
        return isLight ? lightStyle : darkStyle;
    }

    function setStyle(mode, id) {
        if (!["cosmos", "enso"].includes(id) || !["light", "dark"].includes(mode))
            return;
        if (mode === "light")
            lightStyle = id;
        else
            darkStyle = id;
        store.setText(JSON.stringify({ light: lightStyle, dark: darkStyle }, null, "\t"));
    }

    FileView {
        id: store
        path: root.path
        printErrors: false
        onLoaded: {
            try {
                const data = JSON.parse(store.text());
                root.lightStyle = ["cosmos", "enso"].includes(data.light) ? data.light : "enso";
                root.darkStyle = ["cosmos", "enso"].includes(data.dark) ? data.dark : "cosmos";
                if (data.light !== root.lightStyle || data.dark !== root.darkStyle)
                    store.setText(JSON.stringify({ light: root.lightStyle, dark: root.darkStyle }, null, "\t"));
            } catch (e) {
                store.setText(JSON.stringify({ light: root.lightStyle, dark: root.darkStyle }, null, "\t"));
            }
        }
    }
    Component.onCompleted: store.reload()
}
