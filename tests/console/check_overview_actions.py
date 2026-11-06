#!/usr/bin/env python3
"""Extract production overview action routing and verify dispatch targets."""
from pathlib import Path
import subprocess, tempfile
repo = Path(__file__).resolve().parents[2]
def block(source, marker):
    start = source.index(marker); opening = source.index('{', start); end = opening + 1; depth = 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}'); end += 1
    return source[start:end]
overview = (repo/'overview/OverviewContent.qml').read_text()
panel = (repo/'console/ConsolePanel.qml').read_text()
dispatch_source = (repo/'overview/HyprDispatch.qml').read_text()
functions = '\n'.join([block(dispatch_source, 'function callKeepingConsoleFocus('), block(overview, 'function closeSelected('), block(overview, 'function selectWorkspace('), block(overview, 'function fullscreenSelected('), block(panel, 'function launchShortcut('), block(panel, 'function executeWindowMenuAction(')]).replace('HyprDispatch.', 'dispatch.').replace('Hyprland.', 'hyprStub.').replace('Quickshell.', 'qsStub.')
with tempfile.TemporaryDirectory() as tmp:
    Path(tmp, 'tst_actions.qml').write_text('''import QtQuick
import QtTest
Item {
 id: root; width:200; height:200
 property bool preserveConsoleFocus:false
 property bool interactionBlocked:false
 property string selectedWorkspace:""
 property string hoveredWindowAddress:""
 property string mode:"apps"
 property bool commandMode:false
 function windowForAddress(address) {return address==="0xabc" ? {address:address} : null}
 QtObject {id:overviewContent;property string selectedWorkspace:root.selectedWorkspace;property bool interactionBlocked:root.interactionBlocked
 function windowForAddress(address){return root.windowForAddress(address)}
 function windowMenuWorkspaces(){return [{workspace:"2"}]}
 function restartSyncTimer(){}
 }
 QtObject {id:windowContextMenu;property string address:"0xabc"}
 QtObject {id:hyprStub;property bool usingLua:true}
 QtObject {id:qsStub;property var argv:[];function execDetached(args){argv=args}}
 QtObject {id:dispatch;function callKeepingConsoleFocus(a,b){root.callKeepingConsoleFocus(a,b)} property var calls:[];function addressArg(a){return a} function call(a,b){calls=calls.concat([b])}}
''' + functions + '''
 TestCase {
 name:"OverviewActions";when:windowShown
 function init(){windowContextMenu.address="0xabc";root.preserveConsoleFocus=false;hyprStub.usingLua=true;qsStub.argv=[];root.visible=true;root.mode="apps";root.commandMode=false;root.interactionBlocked=false;root.selectedWorkspace="";root.hoveredWindowAddress="";dispatch.calls=[]}
 function test_select_does_not_dispatch(){root.selectWorkspace("5");compare(root.selectedWorkspace,"5");compare(dispatch.calls.length,0)}
 function test_blocked_selection(){root.interactionBlocked=true;root.selectWorkspace("5");compare(root.selectedWorkspace,"")}
 function test_preserve_focus_batch(){root.preserveConsoleFocus=true;root.hoveredWindowAddress="0xabc";root.fullscreenSelected("maximized");compare(dispatch.calls.length,0);compare(qsStub.argv[0],"hyprctl");compare(qsStub.argv[1],"eval");const code=qsStub.argv[2];verify(code.indexOf('local owner = hl.get_active_window()')<code.indexOf('hl.dsp.window.fullscreen'));verify(code.includes('owner.title == "caelestia-console"'));verify(code.indexOf('hl.dsp.window.fullscreen')<code.indexOf('hl.dsp.focus'));verify(code.indexOf('hl.dsp.focus')<code.indexOf('hl.dsp.window.alter_zorder'));verify(code.includes('mode = "top"'));verify(code.indexOf('hl.dsp.window.pin')<code.indexOf('hl.dsp.window.fullscreen'));verify(code.includes('local wasPinned = owner.pinned'));verify(!code.includes('action = "unset"'))}
 function test_focus_route_empty_noop(){root.preserveConsoleFocus=true;root.fullscreenSelected("maximized");compare(qsStub.argv.length,0)}
 function test_focus_route_blocked_noop(){root.preserveConsoleFocus=true;root.hoveredWindowAddress="0xabc";root.interactionBlocked=true;root.fullscreenSelected("maximized");compare(qsStub.argv.length,0)}
 function test_float_preserves_console_focus(){root.executeWindowMenuAction("float","");compare(dispatch.calls.length,0);compare(qsStub.argv[0],"hyprctl");const code=qsStub.argv[2];verify(code.includes('owner.title == "caelestia-console"'));verify(code.includes('hl.dsp.window.float({ window = "address:0xabc", action = "toggle" })'));verify(code.indexOf('hl.dsp.window.pin')<code.indexOf('hl.dsp.window.float'));verify(code.indexOf('hl.dsp.window.float')<code.indexOf('hl.dsp.focus'));verify(code.indexOf('hl.dsp.focus')<code.indexOf('hl.dsp.window.alter_zorder'));verify(!code.includes('action = "unset"'))}
 function test_float_stale_target_noop(){windowContextMenu.address="0xgone";root.executeWindowMenuAction("float","");compare(qsStub.argv.length,0);compare(dispatch.calls.length,0)}
 function test_float_legacy_fallback(){hyprStub.usingLua=false;root.executeWindowMenuAction("float","");compare(dispatch.calls.length,1);verify(dispatch.calls[0].includes('window.float'));compare(qsStub.argv.length,0)}
 function test_focus_legacy_fallback(){hyprStub.usingLua=false;root.callKeepingConsoleFocus("legacy","lua");compare(dispatch.calls.length,1);compare(qsStub.argv.length,0)}
 function test_close_selected(){root.hoveredWindowAddress="0xabc";root.closeSelected();compare(dispatch.calls.length,1);compare(dispatch.calls[0],'hl.dsp.window.close({ window = "address:0xabc" })')}
 function test_close_empty(){root.closeSelected();compare(dispatch.calls.length,0)}
 function test_close_stale(){root.hoveredWindowAddress="0xgone";root.closeSelected();compare(dispatch.calls.length,0)}
 function test_close_blocked(){root.hoveredWindowAddress="0xabc";root.interactionBlocked=true;root.closeSelected();compare(dispatch.calls.length,0)}
 function test_close_hidden(){root.hoveredWindowAddress="0xabc";root.visible=false;root.closeSelected();compare(dispatch.calls.length,0)}
 function test_empty_target(){root.fullscreenSelected("maximized");compare(dispatch.calls.length,0)}
 function test_stale_target(){root.hoveredWindowAddress="0xgone";root.fullscreenSelected("maximized");compare(dispatch.calls.length,0)}
 function test_maximize_address(){root.hoveredWindowAddress="0xabc";root.fullscreenSelected("maximized");compare(dispatch.calls.length,1);verify(dispatch.calls[0].includes('window = "address:0xabc"'));verify(dispatch.calls[0].includes('mode = "maximized"'))}
 function test_fullscreen_address(){root.hoveredWindowAddress="0xabc";root.fullscreenSelected("fullscreen");verify(dispatch.calls[0].includes('mode = "fullscreen"'))}
 function test_launch_silent(){root.selectedWorkspace="5";root.launchShortcut("foot");verify(dispatch.calls[0].includes('workspace = "5 silent"'))}
 function test_special_launch(){root.selectedWorkspace="special:slot1";root.launchShortcut("foot");verify(dispatch.calls[0].includes('workspace = "special:slot1 silent"'))}
 function test_other_tab_ignores_selection(){root.mode="emoji";root.selectedWorkspace="5";root.launchShortcut("foot");verify(!dispatch.calls[0].includes('workspace'))}
 function test_menu_blocks_launch(){root.interactionBlocked=true;root.selectedWorkspace="5";root.launchShortcut("foot");compare(dispatch.calls.length,0)}
 function test_command_escaping(){root.selectedWorkspace="5";root.launchShortcut('foot --title="a b"');verify(dispatch.calls[0].includes(JSON.stringify('foot --title="a b"')))}
 }
}
''')
    raise SystemExit(subprocess.run(['/usr/lib/qt6/bin/qmltestrunner','-platform','offscreen','-input',tmp]).returncode)
