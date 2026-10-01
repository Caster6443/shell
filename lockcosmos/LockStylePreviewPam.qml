import QtQuick
import Quickshell.Services.Pam
import qs.modules.lock

Item {
    id: root
    property string buffer: ""
    property string lockMessage: ""
    property int state: Pam.None
    signal flashMsg

    function handleKey(event) {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            passwd.start();
        } else if (event.key === Qt.Key_Backspace) {
            buffer = buffer.slice(0, -1);
        } else if (/^[^\x00-\x1F\x7F-\x9F]+$/.test(event.text)) {
            buffer += event.text;
        }
    }

    function reset() {
        successTimer.stop();
        buffer = "";
        lockMessage = "";
        state = Pam.None;
        passwd.active = false;
        passwd.message = "";
    }

    QtObject {
        id: passwd
        property bool active: false
        property string message: ""
        signal completed(var result)
        function start() {
            if (active || root.buffer.length === 0) return;
            active = true;
            root.buffer = "";
            successTimer.restart();
        }
    }
    property alias passwd: passwd

    QtObject {
        id: fprint
        property int state: Pam.None
        property string message: ""
        property int tries: 0
        property bool canAttempt: false
        property bool available: false
    }
    property alias fprint: fprint
    QtObject {
        id: howdy
        property int state: Pam.None
        property string message: ""
        property int tries: 0
        property bool canAttempt: false
        property bool active: false
    }
    property alias howdy: howdy

    Timer {
        id: successTimer
        interval: 650
        onTriggered: {
            passwd.active = false;
            root.state = Pam.None;
            passwd.completed(PamResult.Success);
        }
    }
}
