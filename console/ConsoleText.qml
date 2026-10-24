import QtQuick
import Caelestia.Config
import qs.services
Text {
    property string textRole: "body"
    property bool strong: false
    font: textRole === "title"
        ? Tokens.font.title.builders.small.weight(strong ? Font.DemiBold : Font.Normal).build()
        : textRole === "caption"
            ? Tokens.font.label.builders.medium.weight(strong ? Font.DemiBold : Font.Normal).build()
            : Tokens.font.body.builders.small.weight(strong ? Font.Medium : Font.Normal).build()
    renderType: Text.NativeRendering
    textFormat: Text.PlainText
    color: Colours.palette.m3onSurface
}
