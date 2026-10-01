pragma Singleton
import QtQuick
QtObject {
    readonly property int xp: 0
    readonly property int level: 1
    readonly property int liveStreak: 0
    readonly property var achievements: []
    readonly property var achievementDefs: []
    function levelFor(xp) { return Math.floor(Math.max(0, xp) / 100) + 1; }
    function xpForLevel(level) { return Math.max(0, level - 1) * 100; }
    function rankFor(level) { return level > 1 ? "Wayfarer" : "Newcomer"; }
}
