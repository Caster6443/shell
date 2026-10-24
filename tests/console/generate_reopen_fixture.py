#!/usr/bin/env python3
"""Extract production lifecycle/model-commit handlers into a native Qt view fixture."""
from pathlib import Path
import sys
import re
source=(Path(__file__).resolve().parents[2]/'console/ConsolePanel.qml').read_text()
def block(marker):
    start=source.index(marker); brace=source.index('{',start); depth=1; end=brace+1
    while depth:
        if source[end]=='{':depth+=1
        elif source[end]=='}':depth-=1
        end+=1
    return source[start:end]
def renamed(s):
    return re.sub(r'\bApps\.', 'apps.', s.replace('AppCategories.', 'categories.').replace('ConsoleState.', 'state.'))
functions='\n'.join(block('function '+name+'(') for name in ['syncAppResults','refreshAppResults','resetAppSelection','restoreAppSelection','moveAppSelection'])
lifecycle=block('\tonVisibleChanged:')
commit=block('Timer {\n\t\tid: appResultsCommitTimer')
hover=block('HoverHandler {\n\t\t\t\t\t\t\t\tid: appListHover')
fixture='''import QtQuick
import QtQuick.Controls
import QtTest
Item {
 id:root;width:400;height:300
 property string mode:"apps"
 property string navigationLayer:"tabs"
 property string appCategory:"favorite"
 property string appResultsKey:""
 property var appFilteredApps:[]
 property var appPendingResults:[]
 property bool appSelectionRestorePending:false
 property string appSelectionRestoreId:""
 property int appSelectionRestoreIndex:0
 property int appViewEpoch:0
 property bool appMenuVisible:false
 property bool windowMenuVisible:false
 property bool pointerHasEntered:false
 property bool ghostVisible:false
 property var launchWatch:null
 property var screenState:({consoleTextInput:false})
 property int overviewRefreshes:0
 function syncWallResults(force){}
 function primeWallStrip(){}
 function ensureAppCategoryVisible(){}
 function closeAppMenu(){appMenuVisible=false}
 function applyRequestedMode(){}
 @@FUNCTIONS@@
 @@LIFECYCLE@@
 @@COMMIT@@
 Timer{id:clipboardRefreshTimer;interval:250}
 QtObject{id:state;property bool active:false}
 QtObject{id:windowContextMenu;function close(){}}
 QtObject{id:overviewContent;function refresh(){root.overviewRefreshes++}function unlockCaptureSequence(){}function settleToActive(){}}
 QtObject{id:apps;property var items:[];function search(key){return items.slice()}}
 QtObject{id:categories;property var allApps:[];readonly property var buckets:({favorite:allApps,all:allApps});function searchIn(items,key){return items.filter(p=>p.name.includes(key))}function entryId(item){return item?item.id:""}}
 TextInput{id:input;width:1;height:1}
 GridView {
  id:appList;anchors.fill:parent;cellWidth:400;cellHeight:50;model:root.appFilteredApps
  property int columns:1
  property bool navigationOwnsSelection:false
  onContentYChanged: appListHover.updatePointerSelection(true)
  delegate:Item {required property var modelData;width:400;height:50}
  @@HOVER@@
 }
 TestCase{
  name:"ConsoleReopen";when:windowShown
  function init(){root.visible=false;mouseMove(root,399,299);apps.items=Array.from({length:60},(_,i)=>({id:"app"+i,name:"app"+i}));categories.allApps=apps.items;root.visible=true;tryCompare(appList,"count",60);wait(30);}
  function dirty(){input.text="";root.appCategory="all";appList.navigationOwnsSelection=true;appList.currentIndex=40;appList.contentY=1800;root.appSelectionRestorePending=true;root.appSelectionRestoreId="app40";root.appSelectionRestoreIndex=40;}
  function test_close_reopen_clears_selection_and_scroll(){dirty();root.visible=false;root.visible=true;tryCompare(appList,"currentIndex",0);tryCompare(appList,"contentY",appList.originY);compare(root.appCategory,"favorite");verify(!root.appSelectionRestorePending);verify(appList.navigationOwnsSelection)}
  function test_native_flick_cannot_resume_after_reopen(){appList.contentY=500;appList.flick(0,-1000);wait(30);root.visible=false;root.visible=true;wait(250);compare(appList.contentY,appList.originY);compare(appList.currentIndex,0);verify(!appList.flicking)}
  function test_close_discards_queued_commit(){root.appPendingResults=[{id:"stale",name:"stale"}];appResultsCommitTimer.triggered();root.visible=false;wait(30);verify(!root.appFilteredApps.some(item=>item.id==="stale"));}
  function test_hide_invalidates_scheduled_model_commit(){root.appPendingResults=[{id:"stale",name:"stale"}];appResultsCommitTimer.start();wait(1);root.visible=false;apps.items=[{id:"fresh",name:"fresh"}];categories.allApps=apps.items;root.visible=true;tryCompare(appList,"count",1);wait(40);compare(root.appFilteredApps[0].id,"fresh");compare(appList.currentIndex,0);}
  function test_repeated_open_with_pending_restore(){for(let i=0;i<4;i++){dirty();root.visible=false;root.visible=true;wait(30);compare(appList.currentIndex,0);compare(appList.contentY,appList.originY);verify(!root.appSelectionRestorePending)}}
  function test_visible_database_refresh_preserves_identity(){appList.currentIndex=12;root.syncAppResults(true);tryVerify(()=>!root.appSelectionRestorePending);compare(appList.currentIndex,12);}
 }
}
'''
for key,value in {'FUNCTIONS':functions,'LIFECYCLE':lifecycle,'COMMIT':commit,'HOVER':hover}.items():fixture=fixture.replace('@@'+key+'@@',renamed(value))
out=Path(sys.argv[1]);out.mkdir(parents=True,exist_ok=True);(out/'tst_reopen.qml').write_text(fixture)
