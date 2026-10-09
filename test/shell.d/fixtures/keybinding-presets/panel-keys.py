"""Run the actual panel key handler against the real Keybindings singleton."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

root = Path(sys.argv[1])
if not shutil.which("quickshell"):
    print("ok - panel key runtime # SKIP")
    sys.exit(0)

source = (root / "shell/Ui/PanelKeyCatcher.qml").read_text()
start = source.index("Keys.onPressed: function(event) {")
opening = source.index("{", start)
depth = 1
end = opening + 1
while depth:
    depth += (source[end] == "{") - (source[end] == "}")
    end += 1
handler = "function handle(event) " + source[opening:end]

with tempfile.TemporaryDirectory(prefix="panel-keys-", dir=os.environ.get("TMPDIR")) as directory:
    path = Path(directory)
    (path / "Commons").symlink_to(root / "shell/Commons")
    qml = '''import QtQuick
import Quickshell
import qs.Commons
ShellRoot {
  id: root
  property bool blocked: false
  property bool reorderable: true
  property string action: ""
  function moveRequested(dx, dy) { action = "move:" + dx + ":" + dy }
  function reorderRequested(dy) { action = "reorder:" + dy }
  function closeRequested() { action = "close" }
  function tabRequested(direction) { action = "tab:" + direction }
  function returnRequested() { action = "return" }
  function activateRequested() { action = "activate" }
  function deleteRequested() { action = "delete" }
  function textKey(text, modifiers) { action = "text:" + text }
''' + handler + '''
  function check(key, modifiers, expected) {
    action = ""
    handle({key: key, modifiers: modifiers, text: "", accepted: false})
    if (action !== expected) throw new Error("key " + key + ": " + action + " != " + expected)
  }
  Component.onCompleted: Qt.callLater(function() {
    try {
      Keybindings.configure({preset: "default"})
      check(Qt.Key_Down, Qt.NoModifier, "move:0:1")
      check(Qt.Key_Down, Qt.ControlModifier, "reorder:1")
      check(Qt.Key_K, Qt.ControlModifier, "reorder:-1")
      Keybindings.configure({preset: "emacs"})
      check(Qt.Key_N, Qt.ControlModifier, "move:0:1")
      check(Qt.Key_P, Qt.ControlModifier, "move:0:-1")
      check(Qt.Key_G, Qt.ControlModifier, "close")
      check(Qt.Key_Up, Qt.ControlModifier, "reorder:-1")
      Keybindings.configure({preset: "reader", presets: {reader: {
        extends: "default", bindings: {next: ["Ctrl+N"]}
      }}})
      check(Qt.Key_Down, Qt.NoModifier, "")
      check(Qt.Key_N, Qt.ControlModifier, "move:0:1")
      check(Qt.Key_Down, Qt.ControlModifier, "reorder:1")
      blocked = true
      check(Qt.Key_Down, Qt.ControlModifier, "")
      check(Qt.Key_N, Qt.ControlModifier, "")
      console.log("NATIVE_PASS panel cursor/reorder/custom/blocked")
    } catch (error) { console.log("NATIVE_FAIL", error) }
    Qt.quit()
  })
}'''
    (path / "shell.qml").write_text(qml)
    env = dict(os.environ)
    for key in ("DISPLAY", "WAYLAND_DISPLAY", "DBUS_SESSION_BUS_ADDRESS", "HYPRLAND_INSTANCE_SIGNATURE"):
        env.pop(key, None)
    env.update(HOME=str(path), QT_QPA_PLATFORM="offscreen", QT_QPA_PLATFORMTHEME="",
               QT_STYLE_OVERRIDE="Basic", OMARCHY_PATH=str(root))
    for key in ("XDG_CONFIG_HOME", "XDG_CACHE_HOME", "XDG_DATA_HOME", "XDG_STATE_HOME", "XDG_RUNTIME_DIR"):
        destination = path / key.lower()
        destination.mkdir(mode=0o700)
        env[key] = str(destination)
    result = subprocess.run(["quickshell", "-p", str(path)], env=env, text=True,
                            capture_output=True, timeout=15)
    output = result.stdout + result.stderr
    if result.returncode or "NATIVE_PASS" not in output or "NATIVE_FAIL" in output:
        raise SystemExit(output)
    print("ok - native panel cursor presets preserve item reordering and blocked editors")
