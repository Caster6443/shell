import QtQuick
import Quickshell
import Quickshell.Services.Pam
import qs.modules.lock

Item {
    id: ctx
    visible: false
    width: 0
    height: 0
    required property var lock
    required property var pam
    property string phase: "ready"
    property string buffer: pam.buffer
    readonly property string message: {
        const message = pam.lockMessage || pam.passwd.message || "";
        return /^(password|密码)\s*[:：]\s*$/i.test(message.trim()) ? "" : message;
    }
    property date now: new Date()
    property double lockedAt: Date.now()
    property int cells: buffer.length
    // Keep the submitted length after PAM clears its input buffer so the
    // Enso stroke holds steady while authentication is in progress.
    property int submittedCells: 0
    // Preserve the rejected input length just long enough for the Enso theme
    // to animate its ink retreat after PAM clears the buffer.
    property int deniedCells: 0
    property int combo: buffer.length
    property int lives: 0
    property int maxLives: 0
    property int lastLife: 0
    property int lockoutLeft: 0
    property double lockoutUntil: 0
    property string lockoutClock: ""
    property double unlockTime: 0
    // Quickshell reports an attempt limit as MaxTries, but PAM modules such
    // as pam_faillock can instead return Failed and explain the account lock
    // through Pam.qml's captured lockMessage.
    readonly property bool lockedOut: {
        const text = `${pam.lockMessage || ""}\n${pam.passwd.message || ""}`;
        const messageIndicatesLock = /(account|user).{0,48}lock|lock.{0,48}(account|user)|too many (authentication|login|failed)|maximum.{0,32}(attempt|tries)|temporarily locked|账户.{0,12}锁定|尝试次数过多|暂时锁定/i.test(text);
        return pam.state === Pam.MaxTries || messageIndicatesLock;
    }
    property bool denying: pam.state === Pam.Failed || pam.state === Pam.Error
    property bool awake: true
    property bool capsLock: false
    property string userName: Quickshell.env("USER") || "user"
    property string layout: ""
    property bool multiLayout: false
    property real ambientTime: Date.now() / 1000
    property var reward: null
    property string _buffer: pam.buffer
    signal granted
    signal denied(bool costLife)
    signal typed(int index)
    signal erased(int index)
    signal previewEscape

    function setBuffer(value) { pam.buffer = value; }
    function clearInput() { pam.buffer = ""; }
    function submit() {
        if (pam.buffer.length === 0) return;
        // Pam.qml keeps its account-lock message until the session is unlocked.
        // Clear it before a fresh authentication attempt so a previous lockout
        // does not make an unrelated failure look like a new lockout.
        pam.lockMessage = "";
        pam.state = Pam.None;
        submittedCells = pam.buffer.length;
        deniedCells = 0;
        pam.passwd.start();
    }
    function poke() {}
    function skip() {}
    function refreshCaps() {}
    function begin() { lockedAt = Date.now(); }
    function resetPreview() {
        pam.reset();
        phase = "ready";
        submittedCells = 0;
        deniedCells = 0;
        lockoutLeft = 0;
        lockoutUntil = 0;
        lockoutClock = "";
        lockedAt = Date.now();
        _buffer = pam.buffer;
    }
    function poweroff() {}
    function reboot() {}
    function suspend() {}

    onBufferChanged: {
        const old = _buffer;
        if (buffer.length > old.length) {
            if (phase === "ready") deniedCells = 0;
            typed(buffer.length - 1);
        }
        else if (buffer.length < old.length) erased(old.length - 1);
        _buffer = buffer;
    }
    Connections {
        target: ctx.pam
        function onFlashMsg() { ctx.denied(false); }
    }
    Connections {
        target: ctx.pam.passwd
        function onActiveChanged() {
            if (ctx.phase !== "exiting")
                ctx.phase = ctx.pam.passwd.active ? "verifying" : "ready";
        }
        function onCompleted(result) {
            if (result === PamResult.Success) {
                ctx.phase = "exiting";
                ctx.granted();
            } else {
                ctx.deniedCells = Math.max(ctx.submittedCells, ctx.pam.buffer.length);
                ctx.submittedCells = 0;
                ctx.phase = "ready";
                ctx.denied(true);
            }
        }
    }
    Timer { interval: 1000; repeat: true; running: true; onTriggered: { ctx.now = new Date(); ctx.ambientTime = Date.now() / 1000; } }
}
