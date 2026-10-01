pragma Singleton
import QtQuick
import qs.services as CaelestiaServices
QtObject {
    function accentOf(_id) { return CaelestiaServices.Colours.palette.m3primary; }
    function accent2Of(_id) { return CaelestiaServices.Colours.palette.m3tertiary; }
}
