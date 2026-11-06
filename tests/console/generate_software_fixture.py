#!/usr/bin/env python3
"""Exercise production UI with isolated process stubs; no system transactions."""
from pathlib import Path
import sys
base = Path(__file__).resolve().parents[2]
out = Path(sys.argv[1]); out.mkdir(parents=True, exist_ok=True)
palette = """pragma Singleton
import QtQuick
QtObject {
 property color m3surface:"#f9f5f0"
 property color m3surfaceContainerHigh:"#f0ebe4"
 property color m3onSurface:"#222222"
 property color m3onSurfaceVariant:"#555555"
 property color m3primaryContainer:"#dce8c8"
 property color m3onPrimaryContainer:"#182500"
 property color m3tertiary:"#596342"
 property color m3outlineVariant:"#aaaaaa"
}
"""
(out / 'M3Palette.qml').write_text(palette)
(out / 'qmldir').write_text('singleton M3Palette 1.0 M3Palette.qml\n')
for name in ['CommandPage.qml', 'SoftwareButton.qml', 'SoftwarePage.qml', 'RaisedButtonSurface.qml']:
    s = (base / 'console' / name).read_text().replace('import qs.overview', 'import "."').replace('import qs.aibackend', 'import "."')
    s = s.replace('ConsoleMaterialStyle.', 'ConsoleStyle.')
    s = s.replace('ConsoleStyle.accent', 'M3Palette.m3tertiary').replace('ConsoleStyle.onAccent', 'M3Palette.m3onPrimaryContainer')
    s = s.replace('ConsoleStyle.selection', 'M3Palette.m3primaryContainer').replace('ConsoleStyle.selectedText', 'M3Palette.m3onPrimaryContainer')
    s = s.replace('ConsoleStyle.content', 'M3Palette.m3surface').replace('import qs.services', '').replace('Colours.light', 'true').replace('Colours.palette.m3surfaceContainerHigh', 'M3Palette.m3surface')
    if name == 'SoftwarePage.qml':
        s = s.replace('import Quickshell\n', '').replace('import Quickshell.Io\n', '').replace('import Caelestia.Config\n', '')
        s = s.replace('Quickshell.shellDir + "/console/PackageBackend.py"', '\"/unused/backend.py\"')
        s = s.replace('    property string query: \"\"', '    property var recordedCalls: []\n    property string query: \"\"')
        a = s.index('    function invoke('); b = s.index('    function navigatePackage', a)
        s = s[:a] + '    function invoke(action: string, name: string, argument: string): void { recordedCalls = recordedCalls.concat([{action:action, name:name, argument:argument}]); }\n' + s[b:]
        a = s.index('    function startTerminal('); b = s.index('    function acceptAction()', a)
        s = s[:a] + '    function startTerminal(action: string, name: string): void { recordedCalls=recordedCalls.concat([{action:"terminal-"+action,name:name}]); }\n' + s[b:]
        a = s.index('    Timer { id: detailTimer;'); b = s.index('    Process {', a)
        s = s[:a] + '    Timer { id: detailTimer; interval: 90 }\n' + s[b:]
    (out / name).write_text(s)
(out / 'Process.qml').write_text('import QtQuick\nItem {property bool running:false;property var command:[];property var stdout;property var stderr;signal exited(int code,int status)}\n')
(out / 'StdioCollector.qml').write_text('import QtQuick\nQtObject {property string text:"";signal streamFinished()}\n')
(out / 'tst_software.qml').write_text(Path(__file__).with_name('software.qml.in').read_text())

# Extract the real command entry handlers into a Qt keyboard fixture.
panel = (base/'console/ConsolePanel.qml').read_text()
def block(marker):
    start=panel.index(marker); brace=panel.index('{',start); depth=1; end=brace+1
    while depth:
        if panel[end]=='{': depth+=1
        elif panel[end]=='}': depth-=1
        end+=1
    return panel[start:end]
functions='\n'.join(block('function '+name+'(') for name in ['openSoftwareCommand','escapeSoftware'])
handlers='\n'.join(block('Keys.on'+key+'Pressed:') for key in ['Escape','Up','Down','Left','Right'])+'\n'+block('onAccepted:')
fixture = """import QtQuick
import QtQuick.Controls
import QtTest
Item {
 id:root; width:800;height:500
 property string mode:"apps"
 property string navigationLayer:"tabs"
 property bool enteredSoftwareByCommand:false
 property string commandReturnText:">"
 property bool appMenuVisible:false
 property int closes:0
 readonly property bool commandMode:input.text.replace(/^\\s+/, "").startsWith(">")
 onModeChanged:{enteredSoftwareByCommand=false;if(mode==="software")input.text=""}
 function closeRequested(){closes++}
 @@FUNCTIONS@@
 CommandPage{id:commandPage;visible:root.commandMode;anchors.top:input.bottom;width:800;height:400;query:input.text.replace(/^\\s+/, "").slice(1).trim();onPackagesRequested:root.openSoftwareCommand()}
 QtObject{id:softwarePage;property string filter:"all";property string detailTab:"overview";property int selection:0;function moveSelection(step){selection+=step} function showSelected(){}}
 TextField{id:input;width:400;height:40;@@HANDLERS@@}
 TestCase{
  name:"SoftwareCommandEntry";when:windowShown
  function init(){root.mode="apps";root.enteredSoftwareByCommand=false;root.closes=0;input.text="";input.forceActiveFocus()}
  function test_prefix_filter_enter_escape(){input.text="> PKG";verify(root.commandMode);compare(commandPage.results.length,1);keyClick(Qt.Key_Return);compare(root.mode,"software");compare(input.text,"");verify(root.enteredSoftwareByCommand);keyClick(Qt.Key_Escape);compare(input.text,"> PKG");verify(root.commandMode);compare(root.closes,0);keyClick(Qt.Key_Escape);compare(input.text,"");verify(!root.commandMode)}
  function test_uppercase_and_unknown(){input.text="> PACKAGES";keyClick(Qt.Key_Return);compare(root.mode,"software");input.text="> nomatch";keyClick(Qt.Key_Return);compare(input.text,"> nomatch");verify(root.commandMode)}
  function test_command_arrows_do_not_switch_tabs(){input.text="> pkg";keyClick(Qt.Key_Left);compare(root.mode,"apps");keyClick(Qt.Key_Right);compare(root.mode,"apps");keyClick(Qt.Key_Down);keyClick(Qt.Key_Up);compare(root.mode,"apps")}
  function test_software_arrows_select_and_edit(){root.mode="software";input.text="pacman";input.cursorPosition=6;keyClick(Qt.Key_Left);compare(input.cursorPosition,5);compare(root.mode,"software");keyClick(Qt.Key_Right);compare(input.cursorPosition,6);softwarePage.selection=0;keyClick(Qt.Key_Down);compare(softwarePage.selection,1);keyClick(Qt.Key_Up);compare(softwarePage.selection,0);keyClick(Qt.Key_Escape);compare(root.closes,1)}
 }
}
"""
(out/'tst_command_entry.qml').write_text(fixture.replace('@@FUNCTIONS@@',functions).replace('@@HANDLERS@@',handlers))

(out/'Ai.qml').write_text("""pragma Singleton
import QtQuick
QtObject {
 property bool loaded:true
 property var state:({enabled:false,translation:false})
 property var activeProfile:({model:"fixture-model"})
 property bool translationEnabled:false
 property var requests:[]
 property var cancelled:[]
 property int serial:0
 signal completed(string requestId,var result)
 signal configurationChanged()
 function request(action,options){const id="test-"+(++serial);requests=requests.concat([{id:id,action:action,options:options}]);return id;}
 function cancel(id){cancelled=cancelled.concat([id]);}
}
""")
with (out/'qmldir').open('a') as stream:stream.write('singleton Ai 1.0 Ai.qml\n')
(out/'Translator.qml').write_text("""pragma Singleton
import QtQuick
QtObject {
 property int pending:0
 property bool suspended:false
 property int total:0
 property int done:0
 property string lastError:""
 function resume(){}
 signal translated(var translations,string scope)
}
""")
with (out/'qmldir').open('a') as stream:stream.write('singleton Translator 1.0 Translator.qml\n')

# Palette/font are mocked here; actual font and focus use the shared-editor regression.
(out / 'ConsoleText.qml').write_text('import QtQuick\nText { property string textRole: \"body\"; property bool strong:false; font.pixelSize:textRole===\"caption\"?12:textRole===\"title\"?19:15; font.bold:strong }\n')
