"""Exercise production category filtering and cycling with the complete shipped dataset."""
from pathlib import Path
import json, os, subprocess, tempfile
repo = Path(__file__).resolve().parents[2]
data = (repo / 'console/EmojiData.qml').read_text()
panel = (repo / 'console/ConsolePanel.qml').read_text()
def block(source, marker):
    start=source.index(marker); end=source.index('{',start)+1; depth=1
    while depth:
        depth += (source[end]=='{')-(source[end]=='}'); end+=1
    return source[start:end]
items=[]
for line in (repo/'console/data/emoji.tsv').read_text().splitlines():
    if not line or line.startswith('#'): continue
    emoji,category,keywords=line.split('\t'); items.append(dict(emoji=emoji,category=category,keywords=keywords.lower()))
categories=['全部','表情','人物','动物','食物','出行','活动','物品','符号','旗帜','其他']
assert len(items)==1927, len(items)
assert all(it['category'] in categories[1:] for it in items)
fixture='''import QtQuick
import QtTest
Item {
 id: root
 property var items: ITEMS
 readonly property int maxResults: 400
 property string emojiCategory: "全部"
 property int resets: 0
 function resetEmojiSelection() { resets++ }
 QtObject { id: emojiData; property var categories: CATEGORIES }
 FUNCTIONS
 TestCase {
  name: "EmojiCategories"; when: true
  function test_partition() {
   let total=0;
   for (const c of emojiData.categories.slice(1)) {
    const entries=root.query("",c); verify(entries.length>0,c);
    verify(entries.every(e=>e.category===c),c); total+=entries.length;
   }
   compare(total,root.items.length); compare(root.query("","全部").length,total);
  }
  function test_search_within_category() {
   verify(root.query("cat","动物").length>0);
   verify(root.query("cat","动物").every(e=>e.category==="动物"));
   compare(root.query("grinning face","旗帜").length,0);
   compare(root.query("😀","表情")[0].emoji,"😀");
   compare(root.query(" FACE ","表情").length,root.query("face","表情").length);
  }
  function test_cycle_wrap() {
   root.emojiCategory="全部"; root.cycleEmojiCategory(-1); compare(root.emojiCategory,"其他");
   root.cycleEmojiCategory(1); compare(root.emojiCategory,"全部");
   root.cycleEmojiCategory(1); compare(root.emojiCategory,"表情");
   tryVerify(()=>root.resets>0);
  }
 }
}'''
fixture=fixture.replace('ITEMS',json.dumps(items,ensure_ascii=False)).replace('CATEGORIES',json.dumps(categories,ensure_ascii=False)).replace('FUNCTIONS',block(data,'function query(')+'\n'+block(panel,'function cycleEmojiCategory(').replace('EmojiData.categories','emojiData.categories'))
with tempfile.TemporaryDirectory() as d:
    Path(d,'tst_emoji.qml').write_text(fixture)
    subprocess.run(['/usr/lib/qt6/bin/qmltestrunner','-input',d],env=dict(os.environ,QT_QPA_PLATFORM='offscreen',QT_QUICK_BACKEND='software'),check=True)
