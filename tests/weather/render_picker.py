#!/usr/bin/env python3
"""Isolated offscreen UI/keyboard-focus probe; no live shell or credentials.

Usage: python tests/weather/render_picker.py [/tmp/weather-picker.png]
Uses actual deployed components and weather code, with a fixture palette and
private XDG directories/D-Bus. This checks layout, not physical geolocation.
"""
from pathlib import Path
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile


def main():
    deployed = Path.home() / ".config/quickshell/caelestia"
    destination = str(Path(sys.argv[1]).resolve()) if len(sys.argv) > 1 else ""
    with tempfile.TemporaryDirectory(prefix="caelestia-weather-ui-") as temp:
        base = Path(temp)
        app = base / "app"
        app.mkdir()
        for name in ("services", "utils", "modules"):
            (app / name).mkdir()
        for name in ("config", "cache", "data", "state", "runtime"):
            (base / name).mkdir(mode=0o700)
        (app / "components").symlink_to(deployed / "components", target_is_directory=True)
        for module in (deployed / "modules").iterdir():
            if module.is_dir():
                (app / "modules" / module.name).symlink_to(module, target_is_directory=True)
        for name in ("wallpaperbackend", "lockcosmos"):
            if (deployed / name).is_dir():
                (app / name).symlink_to(deployed / name, target_is_directory=True)
        shutil.copy2(deployed / "services/Weather.qml", app / "services/Weather.qml")
        (app / "services/Paths.qml").write_text(
            'pragma Singleton\nimport QtQuick\nQtObject { readonly property string cache: '
            + json.dumps(str(base / "cache")) + ' }\n')
        keys = set()
        for source in (deployed / "components", deployed / "modules/dashboard"):
            for path in source.rglob("*.qml"):
                keys.update(re.findall(r"\bm3\w+", path.read_text()))
        palette = {key: "#ededed" if "on" in key.lower() else "#32302a" for key in keys}
        palette.update(m3primary="#d8c688", m3onSurface="#ede5d1",
                       m3surfaceContainer="#25231b", m3onSurfaceVariant="#c0baa8",
                       m3secondaryContainer="#514831", m3onSecondaryContainer="#f0dfb4")
        (app / "services/Colours.qml").write_text(
            'pragma Singleton\nimport QtQuick\nQtObject { property var palette: ('
            + json.dumps(palette) + '); property var tPalette: palette }\n')
        (app / "utils/Icons.qml").write_text(
            'pragma Singleton\nimport QtQuick\nQtObject { function getWeatherIcon(code) { return "cloud"; } }\n')
        script = '''import QtQuick
import QtQuick.Window
import Caelestia.I18n
import Quickshell
import qs.components
import qs.modules.dashboard
ShellRoot {
 id: fixture
 Component.onCompleted: Tr.language = "zh_CN"
 property ScreenState fixtureState: ScreenState { modelData: null; dashboard: true }
 function find(object, name) {
  if (object.objectName === name) return object;
  for (const child of object.children || []) { const found = find(child, name); if (found) return found; }
  return null;
 }
 Timer { id: closingProbe; interval: 70; onTriggered: {
  if (picker.implicitHeight <= 0 || picker.opacity >= 1) { console.error("CLOSE_ANIMATION_FAILED"); Qt.exit(1); return; }
  picker.expanded = true;
  reopeningProbe.start();
 } }
 Timer { id: reopeningProbe; interval: 1000; onTriggered: {
  if (!picker.visible || !picker.enabled || picker.opacity !== 1 || picker.implicitHeight <= 0) { console.error("RAPID_REOPEN_FAILED"); Qt.exit(1); return; }
  picker.expanded = false;
  closedProbe.start();
 } }
 Timer { id: closedProbe; interval: 1000; onTriggered: {
  if (picker.visible || picker.implicitHeight !== 0 || fixture.fixtureState.dashboardTextInput) { console.error("CLOSED_STATE_FAILED"); Qt.exit(1); return; }
  console.log("ANIMATION_LIFECYCLE_PASS"); Qt.quit();
 } }
 Window {
  width: 840; height: 550; visible: true; color: "#17160f"
  WeatherLocationPicker {
   id: picker; x: 16; y: 16; width: parent.width - 32; screenState: fixture.fixtureState; expanded: true
   locations: [
    {id:"101200105",country:"中国",adm1:"湖北省",adm2:"武汉",name:"汉阳",lat:"30.55",lon:"114.22"},
    {id:"test2",country:"中国",adm1:"湖北省",adm2:"武汉",name:"武昌",lat:"30.55",lon:"114.22"},
    {id:"test3",country:"中国",adm1:"湖北省",adm2:"武汉",name:"江汉",lat:"30.55",lon:"114.22"},
    {id:"test4",country:"中国",adm1:"湖北省",adm2:"武汉",name:"洪山",lat:"30.55",lon:"114.22"}]
  }
  Timer { interval: 500; running: true; onTriggered: {
   const field = fixture.find(picker, "weatherCityField");
   field.forceActiveFocus();
   if (!fixture.fixtureState.dashboardTextInput) { console.error("FOCUS_ACQUIRE_FAILED"); Qt.exit(1); return; }
   picker.grabToImage(result => {
    if (DESTINATION && !result.saveToFile(DESTINATION)) { Qt.exit(1); return; }
    picker.expanded = false;
    if (fixture.fixtureState.dashboardTextInput) { console.error("FOCUS_RELEASE_FAILED"); Qt.exit(1); return; }
    console.log("PICKER_UI_PASS", picker.width, picker.height);
    if (picker.implicitHeight <= 0 || picker.enabled) { console.error("COLLAPSE_LIFECYCLE_FAILED"); Qt.exit(1); return; }
    closingProbe.start();
   });
  } }
 }
}
'''.replace("DESTINATION", json.dumps(destination))
        (app / "shell.qml").write_text(script)
        env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software",
                   DISPLAY="", WAYLAND_DISPLAY="", XDG_CONFIG_HOME=str(base / "config"),
                   XDG_CACHE_HOME=str(base / "cache"), XDG_DATA_HOME=str(base / "data"),
                   XDG_STATE_HOME=str(base / "state"), XDG_RUNTIME_DIR=str(base / "runtime"))
        result = subprocess.run(["dbus-run-session", "--", "qs", "-p", str(app), "--no-color"],
                                env=env, capture_output=True, text=True, timeout=12)
        output = result.stdout + result.stderr
        allowed = ("Unable to read local QWeather API host", "Unable to read local QWeather API key")
        unexpected = [line for line in output.splitlines()
                      if ("WARN" in line or "ERROR" in line) and not any(x in line for x in allowed)]
        if result.returncode or "PICKER_UI_PASS" not in output or "ANIMATION_LIFECYCLE_PASS" not in output or unexpected:
            print(output)
            return 1
        print("PASS: picker loads in Chinese; focus releases; animated collapse, rapid reopen and final hidden state pass")
        if destination:
            print(destination)
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
