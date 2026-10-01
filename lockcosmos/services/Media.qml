pragma Singleton
import QtQuick
import qs.services as CaelestiaServices
QtObject {
    readonly property var activePlayer: CaelestiaServices.Players.active
    readonly property string title: activePlayer?.trackTitle || ""
    readonly property string artist: activePlayer?.trackArtist || ""
    readonly property bool isPlaying: activePlayer?.isPlaying || false
    function playPause() { if (activePlayer?.canTogglePlaying) activePlayer.togglePlaying(); }
    function previous() { if (activePlayer?.canGoPrevious) activePlayer.previous(); }
    function next() { if (activePlayer?.canGoNext) activePlayer.next(); }
}
