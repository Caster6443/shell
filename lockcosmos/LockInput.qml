import QtQuick

Item {
    id: li
    required property var ctx
    property bool active: true
    signal escapePressed
    signal backgroundPressed
    anchors.fill: parent
    function focusInput() { if (active) input.forceActiveFocus(); }
    Component.onCompleted: Qt.callLater(() => focusInput())
    MouseArea {
        anchors.fill: parent
        enabled: li.active
        onPressed: { li.backgroundPressed(); li.focusInput(); }
    }
    TextInput {
        id: input
        width: 1; height: 1; opacity: 0
        enabled: li.active; focus: li.active
        echoMode: TextInput.Password
        passwordMaskDelay: 0
        inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase | Qt.ImhHiddenText
        onTextChanged: li.ctx.setBuffer(text)
        onAccepted: li.ctx.submit()
        onActiveFocusChanged: {
            if (!activeFocus && li.active && li.ctx.lock.locked)
                Qt.callLater(() => li.focusInput());
        }
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) { li.escapePressed(); event.accepted = true; }
        }
        Connections {
            target: li.ctx
            function onBufferChanged() { if (input.text !== li.ctx.buffer) input.text = li.ctx.buffer; }
        }
    }
}
