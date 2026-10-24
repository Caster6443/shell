#!/usr/bin/env python3
"""Check production sizing/clamps with multiple windows and hover overshoot."""
from pathlib import Path
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[2]
card = (repo / 'overview/WorkspaceCard.qml').read_text()
preview = (repo / 'overview/WindowPreview.qml').read_text()

def block(source, marker):
    start = source.index(marker)
    opening = source.index('{', start)
    depth, end = 1, opening + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]

props = '\n'.join(block(card, marker) for marker in [
    'function rowMatches(', 'readonly property int matchingCount:',
    'property real contentMaxWidth:', 'readonly property var spatialBounds:',
    'readonly property real singleWindowRatio:'])
start = card.index('\treadonly property real scaleRatio:')
props += '\n' + card[start:card.index('\n\twidth: workspaceW', start)]
props = props.replace('Hyprland.', 'hyprStub.')
clamps = '\n'.join(block(preview, marker) for marker in [
    'readonly property real clampedX:', 'readonly property real clampedY:'])
with tempfile.TemporaryDirectory() as directory:
    path = Path(directory)
    (path / 'Sizing.qml').write_text('''import QtQuick
Item {
 property real workspaceW: 640
 property real workspaceH: 320
 property bool isSpecial:false
 property string specialWsName:''
 property int wsId:1
 property ListModel windowModel:rows
 property var overviewRoot:layout
 property alias spatial:layout.spatialWindows
 property alias model:rows
 QtObject {id:layout;property bool spatialWindows:false}
 QtObject {id:hyprStub;property var focusedMonitor:({width:1920,height:1080})}
 ListModel {id:rows}
''' + props + '\n}\n')
    (path / 'Preview.qml').write_text('''import QtQuick
Item {
 property real targetX:0
 property real targetY:0
 property int wsWindowCount:2
 readonly property real boundaryScale: wsWindowCount <= 1 ? 1.08 : 1.20
''' + clamps + '\n}\n')
    (path / 'tst_bounds.qml').write_text('''import QtQuick
import QtTest
Item {
 Sizing {id:card}
 Item {id:layer;width:card.workspaceW;height:card.workspaceH;Preview{id:win}}
 TestCase {
 name:'MultiWindowBounds'
 function test_fit_data(){return [
 {tag:'linear-two-tall',spatial:false,count:2,w:900,h:4000},
 {tag:'linear-two-wide',spatial:false,count:2,w:4000,h:600},
 {tag:'linear-four',spatial:false,count:4,w:1920,h:1080},
 {tag:'linear-fallback',spatial:false,count:2,w:0,h:0},
 {tag:'spatial-two',spatial:true,count:2,w:900,h:4000},
 {tag:'spatial-four',spatial:true,count:4,w:1920,h:1080}]}
 function test_fit(data){
 card.spatial=data.spatial;card.model.clear()
 for(let i=0;i<data.count;i++)card.model.append({m_wsId:1,m_wsName:'1',m_sizeW:data.w,m_sizeH:data.h,m_atX:i*1000,m_atY:i*100})
 win.wsWindowCount=data.count
 win.width=(data.w||960)*card.scaleRatio
 win.height=(data.h||1080)*card.scaleRatio
 verify(win.width*1.20<=layer.width-24+0.001)
 verify(win.height*1.20<=layer.height-40+0.001)
 for(let pos of [-10000,0,100,10000]){
 win.targetX=pos;win.targetY=pos
 // Check normal size, hover target, and the OutBack peak (~1.198).
 for(let scale of [1,1.18,1.20]){
 let left=win.clampedX-(scale-1)*win.width/2
 let top=win.clampedY-(scale-1)*win.height/2
 verify(left>=12-0.001);verify(left+win.width*scale<=layer.width-12+0.001)
 verify(top>=28-0.001);verify(top+win.height*scale<=layer.height-12+0.001)
 }
 }
 }
 }
}
''')
    result = subprocess.run(['/usr/lib/qt6/bin/qmltestrunner', '-platform', 'offscreen', '-input', str(path)], check=False)
    raise SystemExit(result.returncode)
