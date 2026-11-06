#!/usr/bin/env python3
"""Extract production navigation, menu and dispatch code for Qt input tests."""
from pathlib import Path
import re
import sys

repo = Path(__file__).resolve().parents[2]
panel = (repo / "console/ConsolePanel.qml").read_text()
overview = (repo / "overview/OverviewContent.qml").read_text()


def block(source, marker):
    start = source.index(marker)
    brace = source.index("{", start)
    depth, end = 1, brace + 1
    while depth:
        if source[end] == "{":
            depth += 1
        elif source[end] == "}":
            depth -= 1
        end += 1
    return source[start:end]


out = Path(sys.argv[1])
out.mkdir(parents=True, exist_ok=True)
menu = (repo / "console/WindowContextMenu.qml").read_text()
menu = menu.replace("import qs.overview", "").replace("import qs.components", "").replace("import qs.services", "").replace("import Caelestia.Config", "")
menu = menu.replace("Colours.palette.m3error", "root.testPalette.m3error").replace("Tokens.font.body.large.family", '"Sans Serif"').replace("Tokens.font.icon.medium", "({})")
(out / "MaterialIcon.qml").write_text('import QtQuick\nText {property var fontStyle: ({}); font.family: "Material Symbols Rounded"; font.pixelSize:20}\n')
menu = menu.replace("M3Palette.", "root.testPalette.").replace("id: root", """id: root
    property var testPalette: ({m3surfaceContainerHigh:'#eeeeee', m3surfaceContainerHighest:'#e6e6e6', m3onSurface:'#111111', m3onSurfaceVariant:'#444444', m3outline:'#777777', m3outlineVariant:'#bbbbbb', m3tertiary:'#775588', m3primary:'#5555aa', m3error:'#ba1a1a'})""", 1)
(out / "WindowContextMenu.qml").write_text(menu)

functions = "\n".join(block(panel, "function " + name + "(") for name in
    ["toggleNavigationLayer", "navigateHorizontal", "cycleEmojiCategory", "cycleMode", "cycleAppCategory", "cycleWallView", "setAppCategory", "executeWindowMenuAction"])
functions = functions.replace("EmojiData.categories", "root.emojiCategories").replace("AppCategories.categories", "root.appCategories").replace("HyprDispatch.", "dispatch.")
keys = "\n".join(block(panel, "Keys.on" + name + "Pressed:") for name in ["Left", "Right", "Tab", "Backtab"])
reset = panel.split("\tonVisibleChanged: {", 1)[1].split("\t\tif (visible) {", 1)[0]
mode_reset = re.search(r'root.navigationLayer = "tabs";', block(panel, "onModeChanged:"))[0]
star_start = panel.rfind("Text {", 0, panel.index('visible: root.appCategory !== "favorite" &&'))
star = block(panel[star_start:], "Text {").replace("Text {", "Text { id: star", 1)
star = star.replace('textRole: \"body\"', 'font.pixelSize: 14').replace('root.appCategory !== "favorite" && AppCategories.isFavorite(appCell.modelData)', 'true').replace("M3Palette.m3tertiary", '"blue"').replace("appList.currentIndex === appCell.index ? PanelColours.selectedText : M3Palette.m3primary", '"blue"')
fixture = """import QtQuick
import QtQuick.Controls
import QtTest
Item {
 id: root; width: 600; height: 500
 property string mode: "apps"
 property string navigationLayer: "tabs"
 readonly property bool commandMode: input.text.replace(/^\\s+/, "").startsWith(">")
 property bool softwareInteractionBusy:false
 property bool enteredSoftwareByCommand:false
 property int appViewEpoch:0
 property bool appSelectionRestorePending:false
 property string appSelectionRestoreId:""
 property int appSelectionRestoreIndex:0
 Timer{id:appResultsCommitTimer;interval:1}

 property string appCategory: "favorite"
 property string wallView:"strip"
 property string emojiCategory:"全部"
 property var emojiCategories:["全部","表情","人物"]
 function resetEmojiSelection() {}
 property var appCategories: [{id:'favorite'}, {id:'all'}, {id:'tools'}]
 readonly property var modeOrder: ['apps','wallpaper','clipboard','emoji','software']
 property bool appMenuVisible: false
 readonly property bool windowMenuVisible: windowContextMenu.visible
 property bool tiledPresentation: false
 property int backgroundClicks: 0
 property int backgroundWheels: 0
 onModeChanged: { @@MODE_RESET@@ }
 onVisibleChanged: { @@RESET@@ }
 function closeAppMenu() {root.appMenuVisible=false}
 function refreshAppResults() {}
 function resetAppSelection() {}
 function ensureAppCategoryVisible() {}
 @@FUNCTIONS@@
 QtObject {id:dispatch; property var calls:[]
  function addressArg(address) {return address.startsWith('0x')?address:'0x'+address}
  function call(legacy,lua) {calls=calls.concat([{legacy:legacy,lua:lua,protectedFocus:false}])}
  function callKeepingConsoleFocus(legacy,lua) {calls=calls.concat([{legacy:legacy,lua:lua,protectedFocus:true}])}
 }
 MouseArea {anchors.fill:parent; onClicked:root.backgroundClicks++; onWheel:root.backgroundWheels++}
 TextField {id:input; width:200; height:40; @@KEYS@@ }
 Item {x:300; width:100; height:50; @@STAR@@ }
 Item {id:previewAnchor; x:40; y:160; width:120; height:140}
 OverviewFixture {id:overviewContent}
 WindowContextMenu {id:windowContextMenu; parent:root
  targetWindow:overviewContent.windowForAddress(address)
  workspaces:overviewContent.windowMenuWorkspaces()
  onActionRequested:(action,workspace)=>root.executeWindowMenuAction(action,workspace)
  onClosed:input.forceActiveFocus()
 }
 TestCase {
  name:'ConsoleNavigationAndWindowMenu'; when:windowShown
  function init() {windowContextMenu.close();tryVerify(()=>!windowContextMenu.visible);windowContextMenu.targetPreview=null;root.visible=true;root.mode='apps';root.navigationLayer='tabs';root.appCategory='favorite';root.appMenuVisible=false;root.tiledPresentation=false;input.text='';input.forceActiveFocus();dispatch.calls=[];root.backgroundClicks=0;root.backgroundWheels=0;overviewContent.restore();wait(10)}
  function test_default_arrows_cycle_all_tabs() {keyClick(Qt.Key_Right);compare(root.mode,'wallpaper');keyClick(Qt.Key_Right);compare(root.mode,'clipboard');keyClick(Qt.Key_Right);compare(root.mode,'emoji');keyClick(Qt.Key_Right);compare(root.mode,'software');keyClick(Qt.Key_Right);compare(root.mode,'software');root.mode='apps';keyClick(Qt.Key_Left);compare(root.mode,'software')}
  function test_tab_categories_and_back() {keyClick(Qt.Key_Tab);compare(root.navigationLayer,'categories');verify(input.activeFocus);keyClick(Qt.Key_Right);compare(root.appCategory,'all');compare(root.mode,'apps');keyClick(Qt.Key_Left);compare(root.appCategory,'favorite');keyClick(Qt.Key_Left);compare(root.appCategory,'tools');keyClick(Qt.Key_Tab);compare(root.navigationLayer,'tabs');keyClick(Qt.Key_Right);compare(root.mode,'wallpaper')}
  function test_other_tabs_have_no_category_layer() {root.mode='clipboard';keyClick(Qt.Key_Tab);compare(root.navigationLayer,'tabs');keyClick(Qt.Key_Right);compare(root.mode,'emoji')}
  function test_shift_tab_and_reopen_reset() {keyClick(Qt.Key_Tab,Qt.ShiftModifier);compare(root.navigationLayer,'categories');root.visible=false;root.visible=true;compare(root.navigationLayer,'tabs')}
  function test_wallpaper_views_layer() {root.mode='wallpaper';root.wallView='strip';keyClick(Qt.Key_Tab);compare(root.navigationLayer,'views');keyClick(Qt.Key_Right);compare(root.wallView,'online');compare(root.mode,'wallpaper');keyClick(Qt.Key_Right);compare(root.wallView,'carousel');keyClick(Qt.Key_Left);compare(root.wallView,'online');keyClick(Qt.Key_Tab);compare(root.navigationLayer,'tabs');keyClick(Qt.Key_Right);compare(root.mode,'clipboard')}
  function test_mode_change_resets_layer() {keyClick(Qt.Key_Tab);root.mode='wallpaper';compare(root.navigationLayer,'tabs');keyClick(Qt.Key_Tab);compare(root.navigationLayer,'views');root.mode='apps';compare(root.navigationLayer,'tabs')}
  function test_menu_colour_and_render() {windowContextMenu.showFor('0xaaa',Qt.point(200,100));tryVerify(()=>windowContextMenu.opened);compare(windowContextMenu.destructiveColour.toString(),'#ba1a1a');grabImage(windowContextMenu.contentItem.parent).save('/tmp/console-menu-light.png');windowContextMenu.testPalette=({m3surfaceContainerHigh:'#241f21',m3surfaceContainerHighest:'#2b2527',m3onSurface:'#f1dee3',m3onSurfaceVariant:'#d5c2c7',m3outline:'#9e8c92',m3outlineVariant:'#514348',m3tertiary:'#efb8df',m3primary:'#ffb0ca',m3error:'#ffb4ab'});compare(windowContextMenu.destructiveColour.toString(),'#ffb4ab');wait(20);grabImage(windowContextMenu.contentItem.parent).save('/tmp/console-menu-dark.png')}
  function test_search_stays_editable() {keyClick(Qt.Key_K);keyClick(Qt.Key_I);keyClick(Qt.Key_T);keyClick(Qt.Key_T);keyClick(Qt.Key_Y);keyClick(Qt.Key_Tab);keyClick(Qt.Key_Right);compare(input.text,'kitty');verify(input.activeFocus);keyClick(Qt.Key_X);compare(input.text,'kittyx')}
  function test_menu_blocks_navigation() {root.appMenuVisible=true;keyClick(Qt.Key_Tab);keyClick(Qt.Key_Right);compare(root.navigationLayer,'tabs');compare(root.mode,'apps')}
  function test_star_center() {compare(star.y+star.height/2,25);root.tiledPresentation=true;compare(star.y,8)}
  function test_popup_outside_click_consumed() {windowContextMenu.showFor('0xaaa',Qt.point(200,100));tryVerify(()=>windowContextMenu.opened);mouseClick(root,570,470);tryVerify(()=>!windowContextMenu.visible);compare(root.backgroundClicks,0);compare(dispatch.calls.length,0);verify(input.activeFocus)}
  function test_popup_keyboard_isolated() {windowContextMenu.showFor('0xaaa',Qt.point(200,100));tryVerify(()=>windowContextMenu.opened);keyClick(Qt.Key_Right);keyClick(Qt.Key_Tab);keyClick(Qt.Key_Down);compare(root.mode,'apps');compare(root.navigationLayer,'tabs');keyClick(Qt.Key_Escape);tryVerify(()=>!windowContextMenu.visible);compare(dispatch.calls.length,0)}
  function test_popup_background_wheel_blocked() {windowContextMenu.showFor('0xaaa',Qt.point(200,100));tryVerify(()=>windowContextMenu.opened);mouseWheel(root,570,470,0,-120);compare(root.backgroundWheels,0);verify(windowContextMenu.visible)}
  function test_emoji_category_keyboard() {root.mode="emoji";root.emojiCategory="全部";input.forceActiveFocus();keyClick(Qt.Key_Tab);compare(root.navigationLayer,"emojiCategories");keyClick(Qt.Key_Right);compare(root.emojiCategory,"表情");keyClick(Qt.Key_Left);compare(root.emojiCategory,"全部");keyClick(Qt.Key_Left);compare(root.emojiCategory,"人物");keyClick(Qt.Key_Backtab);compare(root.navigationLayer,"tabs")}
  function test_float_targets_selected_address() {windowContextMenu.showFor('0xaaa',Qt.point(200,100));tryVerify(()=>windowContextMenu.opened);windowContextMenu.activate(1);compare(dispatch.calls.length,1);verify(dispatch.calls[0].lua.includes('address:0xaaa'));verify(dispatch.calls[0].lua.includes('window.float'));verify(dispatch.calls[0].protectedFocus);tryVerify(()=>!windowContextMenu.visible)}
  function test_move_special_and_current_disabled() {windowContextMenu.showFor('0xaaa',Qt.point(200,100));windowContextMenu.activate(0);compare(windowContextMenu.choosingWorkspace,true);windowContextMenu.activate(1);compare(dispatch.calls.length,0);verify(windowContextMenu.visible);windowContextMenu.activate(11);compare(dispatch.calls.length,1);verify(dispatch.calls[0].lua.includes('special:special'));verify(dispatch.calls[0].lua.includes('follow = false'))}
  function test_close_window_by_address() {windowContextMenu.showFor('0xaaa',Qt.point(200,100));windowContextMenu.activate(2);compare(dispatch.calls.length,1);verify(dispatch.calls[0].lua.includes('window.close'));verify(dispatch.calls[0].lua.includes('address:0xaaa'))}
  function test_disappeared_target_closes_without_action() {windowContextMenu.showFor('0xaaa',Qt.point(200,100));overviewContent.removeTarget();tryVerify(()=>!windowContextMenu.visible);root.executeWindowMenuAction('close','');compare(dispatch.calls.length,0)}
  function test_workspace_page_escape_returns_then_closes() {windowContextMenu.showFor('0xaaa',Qt.point(200,100));tryVerify(()=>windowContextMenu.opened);keyClick(Qt.Key_Return);compare(windowContextMenu.choosingWorkspace,true);keyClick(Qt.Key_Escape);compare(windowContextMenu.choosingWorkspace,false);verify(windowContextMenu.visible);keyClick(Qt.Key_Escape);tryVerify(()=>!windowContextMenu.visible)}
  function test_attached_right_and_tracks_scale() {previewAnchor.x=40;previewAnchor.y=160;previewAnchor.width=120;previewAnchor.height=140;previewAnchor.scale=1;windowContextMenu.targetPreview=previewAnchor;windowContextMenu.showFor('0xaaa',Qt.point(500,400));tryVerify(()=>windowContextMenu.opened);compare(windowContextMenu.attachmentSide,'right');compare(windowContextMenu.x,168);previewAnchor.scale=1.18;compare(windowContextMenu.x,178.8);verify(windowContextMenu.y>=6);verify(windowContextMenu.y+windowContextMenu.height<=494)}
  function test_attached_left() {previewAnchor.scale=1;previewAnchor.x=430;previewAnchor.width=120;windowContextMenu.targetPreview=previewAnchor;windowContextMenu.showFor('0xaaa',Qt.point(500,400));compare(windowContextMenu.attachmentSide,'left');compare(windowContextMenu.x,158)}
  function test_attached_above_and_workspace_page_fits() {previewAnchor.scale=1;previewAnchor.x=20;previewAnchor.y=300;previewAnchor.width=560;previewAnchor.height=140;windowContextMenu.targetPreview=previewAnchor;windowContextMenu.showFor('0xaaa',Qt.point(500,400));compare(windowContextMenu.attachmentSide,'above');compare(windowContextMenu.y,102);windowContextMenu.activate(0);verify(windowContextMenu.x>=6);verify(windowContextMenu.x+windowContextMenu.width<=594);verify(windowContextMenu.y>=6);verify(windowContextMenu.y+windowContextMenu.height<=494)}
  function test_invalid_destination_rejected() {windowContextMenu.address='0xaaa';root.executeWindowMenuAction('move','special:missing');compare(dispatch.calls.length,0)}
 }
}
"""
for token, value in {"FUNCTIONS": functions, "KEYS": keys, "RESET": reset, "MODE_RESET": mode_reset, "STAR": star}.items():
    fixture = fixture.replace("@@" + token + "@@", value)
(out / "tst_navigation.qml").write_text(fixture)

model_functions = "\n".join(block(overview, "function " + name + "(") for name in ["windowForAddress", "windowMenuWorkspaces"])
(out / "OverviewFixture.qml").write_text("""import QtQuick
Item {id:root
 property int windowRevision:0
 readonly property string defaultSpecialName:'special:special'
 function specialSectionNames() {return ['special:special']}
 ListModel {id:windowModel}
 ListModel {id:specialWindowModel}
 function restore() {windowModel.clear();windowModel.append({m_address:'0xaaa',m_title:'Test Window',m_floating:false,m_wsId:1,m_wsName:'1'});root.windowRevision++}
 function removeTarget() {windowModel.clear();root.windowRevision++}
 function restartSyncTimer() {}
""" + model_functions + "\n}\n")

preview = (repo / "overview/WindowPreview.qml").read_text()
handlers = "\n".join(block(preview, name + ":") for name in ["onEntered", "onExited", "onPressed", "onReleased"])
handlers = handlers.replace("HyprDispatch.", "dispatch.").replace("Hyprland.", "hyprStub.")
# Inline fixtures do not have the production component's required-property scope.
for name in ["overviewRoot", "m_wsId", "m_wsName", "m_address", "windowAddress", "currentWsId", "scaleRatio", "m_floating", "wsWindowCount", "m_atX", "m_atY", "clampedX", "clampedY"]:
    handlers = re.sub(r"(?<![.\w])" + name + r"\b", "windowItem." + name, handlers)
drag_target = re.search(r"drag.target: ([^\n]+)", preview)[0]
(out / "tst_preview.qml").write_text("""import QtQuick
import QtTest
Item {
 id:root; width:400; height:200
 property bool hasActiveDrag:false
 property int drops:0
 DropArea {z:200;x:250;y:0;width:150;height:200;keys:["window"];onDropped:drop=>{root.drops++;drop.accept(Qt.MoveAction)}}
 Item {id:context; property bool interactionBlocked:false; property string hoveredWindowAddress:''; property bool dragFromSpecialSection:false; property int requests:0
  property Item menuPreview: null
  signal windowMenuRequested(string address, point position)
  onWindowMenuRequested:(address,position)=> {requests++;}
  function selectWorkspace(workspace) {}
  function restartSyncTimer() {}
 }
 QtObject {id:hyprStub; property var focusedMonitor:null}
 QtObject {id:dispatch; property int calls:0; property string lastLua:""; function addressArg(address) {return address} function call(a,b) {calls++;lastLua=b}}
 Item {id:previewLayer; anchors.fill:parent
 Rectangle {
  id:windowItem; x:20; y:20; width:100; height:100
  property var overviewRoot:context
  property int m_wsId:1
  property string m_wsName:'1'
  property string m_address:'0xaaa'
  property string windowAddress:m_address
  property bool isHovered:context.hoveredWindowAddress===m_address
  property int currentWsId:1
  property real scaleRatio:1
  property bool m_floating:false
  property int wsWindowCount:1
  property real m_atX:200
  property real m_atY:150
  property real clampedX:20
  property real clampedY:20
  z:isHovered?30:20
  Drag.keys:["window"]; Drag.active:mouseArea.drag.active; Drag.source:windowItem; Drag.hotSpot.x:width/2; Drag.hotSpot.y:height/2
  MouseArea {id:mouseArea; anchors.fill:parent; hoverEnabled:true
   acceptedButtons:Qt.LeftButton|Qt.MiddleButton|Qt.RightButton
   @@DRAG@@
   @@HANDLERS@@
  }
 }
 }
 TestCase {
  name:'OverviewPreviewRightClick'; when:windowShown
  function init() {context.interactionBlocked=false;context.requests=0;context.hoveredWindowAddress='';context.dragFromSpecialSection=false;root.hasActiveDrag=false;dispatch.calls=0;root.drops=0;hyprStub.focusedMonitor=null;windowItem.wsWindowCount=1;windowItem.m_floating=false;windowItem.x=20;windowItem.y=20;mouseMove(root,300,150)}
  function test_right_click_opens_without_drag_or_dispatch() {mouseClick(windowItem,50,50,Qt.RightButton);compare(context.requests,1);compare(dispatch.calls,0);verify(!root.hasActiveDrag);compare(windowItem.z,30)}
  function test_right_button_motion_does_not_drag() {mousePress(windowItem,50,50,Qt.RightButton);mouseMove(windowItem,80,50);verify(!mouseArea.drag.active);compare(windowItem.x,20);mouseRelease(windowItem,80,50,Qt.RightButton);compare(dispatch.calls,0);verify(!root.hasActiveDrag)}
  function test_left_drag_state_preserved() {mousePress(windowItem,50,50,Qt.LeftButton);verify(root.hasActiveDrag);compare(windowItem.z,100);mouseRelease(windowItem,50,50,Qt.LeftButton);verify(!root.hasActiveDrag);compare(context.requests,0)}
  function test_left_drag_drop_preserved() {mousePress(windowItem,50,50,Qt.LeftButton);mouseMove(root,100,80);mouseMove(root,320,80);verify(mouseArea.drag.active);wait(20);mouseRelease(root,320,80,Qt.LeftButton);compare(root.drops,1);verify(!root.hasActiveDrag)}
  function test_single_floating_release_keeps_position() {hyprStub.focusedMonitor=({activeWorkspace:{id:1},x:0,y:0});windowItem.m_floating=true;mouseClick(windowItem,50,50,Qt.LeftButton);compare(dispatch.calls,1);verify(dispatch.lastLua.includes('x = 200'));verify(dispatch.lastLua.includes('y = 150'))}
  function test_multi_floating_release_keeps_position() {hyprStub.focusedMonitor=({activeWorkspace:{id:1},x:0,y:0});windowItem.wsWindowCount=3;windowItem.m_floating=true;mouseClick(windowItem,50,50,Qt.LeftButton);compare(dispatch.calls,1);verify(dispatch.lastLua.includes('x = 200'));verify(dispatch.lastLua.includes('y = 150'))}
  function test_hover_handoff_keeps_new_target() {mouseArea.entered();context.hoveredWindowAddress='0xbbb';mouseArea.exited();compare(context.hoveredWindowAddress,'0xbbb')}
  function test_menu_freezes_hover() {context.hoveredWindowAddress='0xbbb';context.interactionBlocked=true;mouseMove(windowItem,50,50);compare(context.hoveredWindowAddress,'0xbbb');mouseMove(root,300,150);compare(context.hoveredWindowAddress,'0xbbb')}
 }
}
""".replace("@@DRAG@@",drag_target).replace("@@HANDLERS@@",handlers))

card = (repo / "overview/WorkspaceCard.qml").read_text()
card_props = "\n".join(block(card, marker) for marker in ["function rowMatches(", "readonly property int matchingCount:", "property real contentMaxWidth:", "readonly property var spatialBounds:", "readonly property var linearLayout:"])
card_props += "\n" + "\n".join(re.findall(r"readonly property real (?:contentTop|singleWindowRatio):[^\n]+", card))
start = card.index("\treadonly property real scaleRatio:")
end = card.index("\n\twidth: workspaceW", start)
card_props += "\n" + card[start:end]
card_props = card_props.replace("Hyprland.", "hyprStub.")
(out / "WorkspaceSizingFixture.qml").write_text("""import QtQuick
Item {
 id:workspaceContainer
 property real workspaceW:500
 property real workspaceH:220
 property bool isSpecial:false
 property string specialWsName:'special:special'
 property int wsId:1
 property ListModel windowModel:rows
 property var overviewRoot:layout
 property alias spatial:layout.spatialWindows
 QtObject {id:layout;property bool spatialWindows:false}
 QtObject {id:hyprStub;property var focusedMonitor:({width:1920,height:1080})}
 ListModel {id:rows}
 function setWindow(w,h) {rows.clear();rows.append({m_address:'a',m_wsId:1,m_wsName:'1',m_sizeW:w,m_sizeH:h,m_atX:100,m_atY:80})}
 function setRows(values) {rows.clear();for(const row of values) rows.append(row)}
""" + card_props + "\n}\n")
(out / "tst_sizing.qml").write_text("""import QtQuick
import QtTest
Item {
 WorkspaceSizingFixture {id:card}
 TestCase {
  name:'OverviewSingleWindowSizing'
  function test_fit_data() {return [
   {tag:'scrolling-tall',spatial:false,w:900,h:4000},
   {tag:'scrolling-wide',spatial:false,w:4000,h:600},
   {tag:'scrolling-monitor',spatial:false,w:1920,h:1080},
   {tag:'scrolling-fallback',spatial:false,w:0,h:0},
   {tag:'spatial-tall',spatial:true,w:900,h:4000},
   {tag:'spatial-wide',spatial:true,w:4000,h:600},
   {tag:'spatial-monitor',spatial:true,w:1920,h:1080},
   {tag:'spatial-fallback',spatial:true,w:0,h:0}
  ]}
  function test_fit(data) {
   card.spatial=data.spatial;card.setWindow(data.w,data.h)
   const w=(data.w>0?data.w:960)*card.scaleRatio
   const h=(data.h>0?data.h:1080)*card.scaleRatio
   // 1.07 exceeds the 1.06 hover target and its OutBack animation overshoot.
   verify(w*1.07<=card.workspaceW-24+0.001)
   verify(h*1.07<=card.workspaceH-card.contentTop-12+0.001)
   const x=data.spatial?card.spatialOffsetX:(card.workspaceW-w)/2
   const y=data.spatial?card.spatialOffsetY:card.contentTop+(card.workspaceH-card.contentTop-12-h)/2
   verify(x-w*0.07/2>=0)
   verify(x+w+w*0.07/2<=card.workspaceW)
   verify(y-h*0.07/2>=card.contentTop-0.001)
   verify(y+h+h*0.07/2<=card.workspaceH-12)
  }
 }
}
""")

# Palette/font are mocked here; actual font and focus use the shared-editor regression.
(out / 'ConsoleText.qml').write_text('import QtQuick\nText { property string textRole: \"body\"; property bool strong:false; font.pixelSize:textRole===\"caption\"?12:textRole===\"title\"?19:15; font.bold:strong }\n')

(out / "tst_group.qml").write_text("""import QtQuick
import QtTest
Item {
 WorkspaceSizingFixture {id:card}
 TestCase {
  name:"OverviewWindowGroups"
  function test_groups_data() {return [
    {tag:"two-same", widths:[1234,1234], heights:[1410,1410]},
    {tag:"three-same", widths:[1234,1229,1234], heights:[1410,1410,1410]},
    {tag:"unequal-ends", widths:[500,1800,900], heights:[900,700,1100]},
    {tag:"height-limited", widths:[700,700], heights:[4000,4000]},
    {tag:"wide-card", widths:[2000,400], heights:[400,900]},
    {tag:"single", widths:[1200], heights:[900]}
  ]}
  function test_groups(data) {
    card.spatial=false;
    const rows=data.widths.map((w,i)=>({m_address:String(i),m_wsId:1,m_wsName:"1",m_sizeW:w,m_sizeH:data.heights[i],m_atX:i*1300,m_atY:15}));
    card.setRows(rows);
    const scale=card.scaleRatio;
    const slots=card.linearLayout.slots;
    const n=rows.length, peak=n===1?1.07:1.198;
    const first=slots["0"].x;
    const last=slots[String(n-1)].x+data.widths[n-1]*scale;
    fuzzyCompare((first+last)/2,card.workspaceW/2,0.001);
    for(let i=0;i<n;i++) {
      const w=data.widths[i]*scale,h=data.heights[i]*scale,p=slots[String(i)];
      verify(p.x-(peak-1)*w/2>=12-0.01);
      verify(p.x+w+(peak-1)*w/2<=card.workspaceW-12+0.01);
      verify(p.y-(peak-1)*h/2>=card.contentTop-0.01);
      verify(p.y+h+(peak-1)*h/2<=card.workspaceH-12+0.01);
      if(i+1<n) {
        const next=slots[String(i+1)],nw=data.widths[i+1]*scale;
        verify(next.x-(peak-1)*nw/2-(p.x+w+(peak-1)*w/2)>=10-0.01);
      }
    }
  }
 }
}
""")

# Real modal overlay + production leave policy; no compositor or window actions.
leave_policy = '\n'.join([
    block(panel, 'HoverHandler {\n\t\tid: panelHover'),
    block(panel, 'Timer {\n\t\tid: pointerLeaveTimer')])
inside = panel.split('readonly property bool pointerInsideConsole:', 1)[1].split('\n\n', 1)[0]
(out / 'tst_menu_leave.qml').write_text('''import QtQuick
import QtQuick.Controls
import QtTest
Item {
 id: stage; width: 800; height: 650
 Item {
  id: root; x:40; y:40; width:600; height:500
  property bool pointerHasEntered:false
  property bool appMenuVisible:false
  property bool ghostVisible:false
  property bool softwareInteractionBusy:false
  property int closeCount:0
  readonly property bool windowMenuVisible:windowContextMenu.visible
  readonly property bool pointerInsideConsole: @@INSIDE@@
  function closeRequested() {closeCount++;windowContextMenu.close();root.visible=false}
  @@POLICY@@
  WindowContextMenu {id:windowContextMenu;parent:root
   targetWindow:({title:'Probe',floating:false,workspace:'1'})
   workspaces:[{workspace:'1',label:'工作区1'},{workspace:'2',label:'工作区2'}]
  }
 }
 TestCase {
  name:'WindowMenuAnimationAndLeave';when:windowShown
  function init() {windowContextMenu.close();tryVerify(()=>!windowContextMenu.visible);root.visible=false;mouseMove(stage,760,600);wait(20);root.pointerHasEntered=false;root.closeCount=0;root.visible=true;wait(20)}
  function openMenu() {mouseMove(root,300,250);tryVerify(()=>root.pointerHasEntered);windowContextMenu.showFor('0xaaa',Qt.point(200,100));tryVerify(()=>windowContextMenu.opened)}
  function test_menu_and_overlay_keep_console_open() {openMenu();mouseMove(root,250,150);wait(380);compare(root.closeCount,0);mouseMove(root,10,440);wait(380);compare(root.closeCount,0);verify(windowContextMenu.pointerInsideHost)}
  function test_leave_closes_menu_and_console() {openMenu();mouseMove(stage,760,600);wait(150);compare(root.closeCount,0);tryCompare(root,'closeCount',1,700);tryVerify(()=>!windowContextMenu.visible)}
  function test_return_cancels_close() {openMenu();mouseMove(stage,760,600);wait(120);mouseMove(root,10,440);wait(380);compare(root.closeCount,0)}
  function test_page_transition_has_intermediate_state_and_reverses() {openMenu();windowContextMenu.activate(0);wait(60);verify(windowContextMenu.height>190&&windowContextMenu.height<380);verify(windowContextMenu.pageOffset>0);verify(windowContextMenu.pageOpacity>0&&windowContextMenu.pageOpacity<1);wait(250);compare(windowContextMenu.height,380);compare(windowContextMenu.pageOffset,0);windowContextMenu.activate(0);wait(60);verify(windowContextMenu.pageOffset<0);verify(windowContextMenu.height>190&&windowContextMenu.height<380);wait(250);compare(windowContextMenu.height,190);compare(windowContextMenu.pageOpacity,1)}
 }
}
'''.replace('@@INSIDE@@', inside).replace('@@POLICY@@', leave_policy))
