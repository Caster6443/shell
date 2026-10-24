"""Load the real shared QML palette with isolated light/dark/hue fixtures."""
from pathlib import Path
import tempfile,subprocess,os
repo=Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix='panel-colours-') as d:
 p=Path(d);(p/'PanelColours.qml').write_text((repo/'overview/PanelColours.qml').read_text().replace('import qs.services','import "."'))
 (p/'qmldir').write_text('singleton Colours 1.0 Colours.qml\nsingleton PanelColours 1.0 PanelColours.qml\n')
 (p/'Colours.qml').write_text('''pragma Singleton
import QtQuick
QtObject {
 property bool light: false
 property var palette: ({m3surfaceContainerHigh: "#1a211c",m3surfaceContainerLow:"#111612",m3primary:"#a5d1b2",m3primaryContainer:"#335a42",m3onPrimary:"#214831",m3onPrimaryContainer:"#c2eece",m3onSurface:"#dee8de"})
}''')
 (p/'tst_palette.qml').write_text('''import QtQuick
import QtTest
import "."
TestCase {
 name: "PanelColours"
 function init() { Colours.light=false;Colours.palette=({m3surfaceContainerHigh:"#1a211c",m3surfaceContainerLow:"#111612",m3primary:"#a5d1b2",m3primaryContainer:"#335a42",m3onPrimary:"#214831",m3onPrimaryContainer:"#c2eece",m3onSurface:"#dee8de"}); }
 function test_dark_pairs() { compare(PanelColours.selection.toString(),"#335a42");compare(PanelColours.selectedText.toString(),"#c2eece");verify(PanelColours.background.g>PanelColours.background.r);verify(PanelColours.background.r>0.1);verify(PanelColours.background.a===1);verify(PanelColours.background!==PanelColours.content); }
 function test_light_pairs() { Colours.light=true;compare(PanelColours.selection.toString(),"#a5d1b2");compare(PanelColours.selectedText.toString(),"#214831"); }
 function test_hue_update() { const previous=PanelColours.background.toString();Colours.palette=Object.assign({},Colours.palette,{m3primary:"#d1a5c1"});verify(PanelColours.background.toString()!==previous); }
}
''')
 r=subprocess.run(['/usr/lib/qt6/bin/qmltestrunner','-input',d],env=dict(os.environ,QT_QPA_PLATFORM='offscreen',QT_QUICK_BACKEND='software'),capture_output=True,text=True,timeout=20);print(r.stdout,r.stderr);r.check_returncode()
