"""Exercise the real setter and extracted panel dispatch with native Qt IO."""
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(sys.argv.pop(1)).resolve()


def block(source, start):
    """Extract a balanced QML block, keeping its actual handlers/functions."""
    offset = source.index(start)
    opening = source.index("{", offset)
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[offset:end]


class DisplayTextSizeTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="dt-", dir=os.environ.get("TMPDIR"))
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name)
        self.home = self.path / "home"
        self.config = self.home / ".config/omarchy/shell.toml"
        self.config.parent.mkdir(parents=True)
        self.bin = self.path / "bin"
        self.bin.mkdir()
        self.env = dict(os.environ)
        for key in ("DISPLAY", "WAYLAND_DISPLAY", "DBUS_SESSION_BUS_ADDRESS", "HYPRLAND_INSTANCE_SIGNATURE"):
            self.env.pop(key, None)
        self.env.update(HOME=str(self.home), PATH=f"{self.bin}:/usr/bin:/bin",
                        QT_QPA_PLATFORM="offscreen", QT_QPA_PLATFORMTHEME="", QT_STYLE_OVERRIDE="Basic",
                        OMARCHY_PATH=str(ROOT))
        for key in ("XDG_CONFIG_HOME", "XDG_CACHE_HOME", "XDG_DATA_HOME", "XDG_STATE_HOME", "XDG_RUNTIME_DIR"):
            directory = self.path / key.lower()
            directory.mkdir(mode=0o700)
            self.env[key] = str(directory)
        self.executable("gsettings", "#!/bin/bash\n[[ $1 == get ]] && printf \"'Sans 11'\\n\"\nexit 0\n")
        self.executable("pkill", "#!/bin/bash\nexit 0\n")
        self.executable("pgrep", "#!/bin/bash\nexit 1\n")

    def executable(self, name, contents):
        file = self.bin / name
        file.write_text(contents)
        file.chmod(0o755)

    def setter(self, size):
        return subprocess.run([str(ROOT / "bin/omarchy-display-text-size"), str(size)],
                              env=self.env, text=True, capture_output=True, timeout=10)

    def test_cli_range(self):
        for size in range(9, 31):
            with self.subTest(size=size):
                result = self.setter(size)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn(f"base-size = {size}\n", self.config.read_text())
        previous = self.config.read_bytes()
        for size in (8, 31, "12.5", "nope"):
            self.assertNotEqual(self.setter(size).returncode, 0)
            self.assertEqual(self.config.read_bytes(), previous)

    def test_gtk_interface_uses_requested_pixel_size(self):
        factor_file = self.path / "gtk-factor"
        self.executable("gsettings", f'''#!/bin/bash
case "$1" in
  get) printf "'Sans 11'\\n" ;;
  set) printf '%s\\n' "$4" > '{factor_file}' ;;
esac
''')
        # GTK rounds to whole points to avoid fractional menu clipping.
        for size, points in ((12, 9), (20, 15), (22, 17), (30, 23)):
            with self.subTest(size=size):
                result = self.setter(size)
                self.assertEqual(result.returncode, 0, result.stderr)
                factor = float(factor_file.read_text())
                self.assertAlmostEqual(factor, points / 11, delta=0.00005)
                self.assertLessEqual(abs(11 * factor * 96 / 72 - size), 0.6675)

    def linked_config(self):
        target = self.home / "dotfiles/.config/omarchy/shell.toml"
        target.parent.mkdir(parents=True)
        target.write_text("# custom\n[font]\nfamily = 'Iosevka'\nbase-size = 18\n[bar]\nheight = 24\n")
        target.chmod(0o640)
        self.config.symlink_to(os.path.relpath(target, self.config.parent))
        return target

    def test_symlink_atomic_set_and_reset(self):
        target = self.linked_config()
        link = os.readlink(self.config)
        # A hostile/unusable global TMPDIR must not be used for config staging.
        self.env["TMPDIR"] = str(self.path / "absent-global-temp")
        for size in (16, 20, "reset"):
            result = self.setter(size)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue(self.config.is_symlink(), "setter replaced the Stow link")
            self.assertEqual(os.readlink(self.config), link)
            self.assertEqual(target.stat().st_mode & 0o777, 0o640)
            expected = "" if size == "reset" else f"base-size = {size}\n"
            self.assertEqual(target.read_text(), "# custom\n[font]\nfamily = 'Iosevka'\n" + expected + "[bar]\nheight = 24\n")
            self.assertEqual(list(target.parent.glob(".shell.toml.*")), [])

    def test_write_failure_is_reported_without_downstream_updates(self):
        self.config.write_text("[font]\nbase-size = 18\n")
        self.executable("gsettings", f"#!/bin/bash\nprintf called >> '{self.path}/downstream'\n")
        for command in ("mktemp", "chmod", "awk", "mv"):
            self.executable(command, "#!/bin/bash\nexit 1\n")
            for size in (20, "reset"):
                with self.subTest(command=command, size=size):
                    self.assertNotEqual(self.setter(size).returncode, 0)
                    self.assertEqual(self.config.read_text(), "[font]\nbase-size = 18\n")
                    self.assertFalse((self.path / "downstream").exists())
                    self.assertEqual(list(self.config.parent.glob(".shell.toml.*")), [])
            (self.bin / command).unlink()

    def native(self, qml):
        if not shutil.which("quickshell"):
            self.skipTest("quickshell unavailable; native IO requires Quickshell")
        (self.path / "shell.qml").write_text(qml)
        result = subprocess.run(["quickshell", "-p", str(self.path / "shell.qml")],
                                env=self.env, capture_output=True, text=True, timeout=12)
        output = result.stdout + result.stderr
        self.assertEqual(result.returncode, 0, output)
        self.assertIn("NATIVE_PASS", output, output)
        self.assertNotIn("NATIVE_FAIL", output, output)

    def test_native_fileview_symlink_referent_rewrites(self):
        self.linked_config()
        self.native('''import QtQuick
import Quickshell
import Quickshell.Io
ShellRoot {
  id: root
  property int stage: 0
  property int seen: 0
  FileView {
    id: view
    path: Quickshell.env("HOME") + "/.config/omarchy/shell.toml"
    watchChanges: true
    onFileChanged: reload()
    onLoaded: root.seen = parseInt(text().match(/base-size = (\\d+)/)[1])
  }
  Process { id: setter }
  Timer {
    interval: 200; repeat: true; running: true
    onTriggered: {
      if (setter.running) return
      if (root.stage === 0 && root.seen === 18) {
        setter.command = [Quickshell.env("OMARCHY_PATH") + "/bin/omarchy-display-text-size", "20"]
        setter.running = true
        root.stage++
      } else if (root.stage === 1 && root.seen === 20) {
        setter.command = [Quickshell.env("OMARCHY_PATH") + "/bin/omarchy-display-text-size", "16"]
        setter.running = true
        root.stage++
      } else if (root.stage === 2 && root.seen === 16) {
        console.log("NATIVE_PASS symlink automatic reload 18→20→16")
        Qt.quit()
      }
    }
  }
  Timer { interval: 3000; running: true; onTriggered: { console.log("NATIVE_FAIL automatic reload", root.stage, root.seen); Qt.quit() } }
}''')

    def test_native_slider_release_and_cancel(self):
        runner = "/usr/lib/qt6/bin/qmltestrunner"
        if not Path(runner).is_file():
            self.skipTest("Qt6 qmltestrunner unavailable; native gestures require QtTest")
        imports = self.path / "imports/qs/Commons"
        imports.mkdir(parents=True)
        (imports / "qmldir").write_text("module qs.Commons\nsingleton Style 1.0 Style.qml\nsingleton Color 1.0 Color.qml\nsingleton Border 1.0 Border.qml\n")
        (imports / "Style.qml").write_text('''pragma Singleton
import QtQuick
QtObject {
  property var spacing: ({controlHeight:36, md:8})
  function space(px) { return px }
  function selectedFillFor(fg, accent) { return accent }
}''')
        (imports / "Color.qml").write_text('''pragma Singleton
import QtQuick
QtObject { property color accent: "white"; property color foreground: "white"; property color background: "black" }
''')
        (imports / "Border.qml").write_text('''pragma Singleton
import QtQuick
QtObject { function flat(color, width) { return {} } }
''')
        shutil.copyfile(ROOT / "shell/Ui/PanelSlider.qml", self.path / "PanelSlider.qml")
        (self.path / "BorderSurface.qml").write_text("import QtQuick\nRectangle { property var borderSpec }\n")
        (self.path / "tst_slider.qml").write_text('''import QtQuick
import QtTest
Item {
  width: 400; height: 240
  property int boundValue: 2
  property int releases: 0
  Flickable {
    id: flick; anchors.fill: parent; contentHeight: 1500
    PanelSlider {
      id: slider; x: 30; y: 80; width: 300; height: 40
      minimum: 0; maximum: 18; integer: true; step: 1
      value: boundValue
      onReleased: function(v) { boundValue = v; releases++ }
    }
  }
  TestCase {
    name: "TextSizeSliderGestures"; when: windowShown
    function init() { flick.contentY = 0; boundValue = 2; releases = 0; wait(50) }
    function test_release_retains_pending_choice() {
      mousePress(slider, 250, 20)
      compare(slider.dragging, true)
      mouseRelease(slider, 250, 20)
      compare(releases, 1)
      compare(boundValue, 15)
      compare(slider.liveValue, 15)
      compare(slider.dragging, false)
      // Failed async owner resets the bound value, including the thumb.
      boundValue = 2
      compare(slider.liveValue, 2)
    }
    function test_cancel_restores_bound_value_without_release() {
      mousePress(slider, 250, 20)
      compare(slider.dragging, true)
      mouseMove(slider, 250, -30, 30)
      mouseMove(slider, 250, -80, 30)
      wait(50)
      compare(slider.dragging, false)
      compare(slider.liveValue, boundValue)
      compare(releases, 0)
      mouseRelease(slider, 250, -80)
    }
  }
}''')
        result = subprocess.run([runner, "-input", str(self.path / "tst_slider.qml"),
                                 "-import", str(self.path / "imports"), "-o", "-,txt"], env=self.env,
                                text=True, capture_output=True, timeout=12)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("4 passed, 0 failed", result.stdout)

    def test_native_dispatch_and_preview(self):
        source = (ROOT / "shell/plugins/panels/monitor/Panel.qml").read_text()
        module = self.path / "Commons"
        module.mkdir()
        (module / "qmldir").write_text("module Commons\nsingleton Style 1.0 Style.qml\n")
        (module / "Style.qml").write_text('''pragma Singleton
import QtQuick
QtObject {
  property var font: ({ baseSize: 18 })
  signal fontBaseSizeChanged()
}''')
        # Only replace the unrelated stdout collector. Dispatch and completion
        # handlers remain byte-for-byte from the panel under test.
        process = block(source, "Process {\n    id: textScaleProc")
        process = process.replace("stdout: StdioCollector { waitForEnd: true }", "")
        properties = "\n".join(line for line in source.splitlines()
                               if re.match(r"  (readonly )?property .*textSize", line))
        functions = []
        for match in re.finditer(r"  function (\w+)\(", source):
            if "Text" in match[1] or match[1] in ("markReflowing", "startTextSize", "finishTextSize", "settleTextSize"):
                functions.append(block(source, match[0]))
        timers = "\n".join(block(source, "Timer {\n    id: " + name)
                            for name in ("reflowSettle", "textSizeSettle") if f"id: {name}" in source)
        connections = block(source, "Connections {\n    target: Style")
        self.executable("omarchy-display-text-size", '''#!/bin/bash
sleep 0.18
printf '%s\\n' "$1" >> "$HOME/requests"
[[ $1 == 24 ]] && exit 1
[[ $1 == 30 ]] && rm -- "$0"
exit 0
''')
        qml = '''import QtQuick
import Quickshell
import Quickshell.Io
import "Commons"
ShellRoot {
  id: root
  property bool reflowingText: false
  property int stage: 0
  function check(ok, message) { if (!ok) { console.log("NATIVE_FAIL", message); Qt.quit() } }
''' + properties + "\n" + "\n".join(functions) + "\n" + process + "\n" + timers + "\n" + connections + '''
  FileView { id: requests; path: Quickshell.env("HOME") + "/requests" }
  Timer { interval: 20; running: true; onTriggered: {
    root.setTextSize(16)
  } }
  Timer { interval: 70; running: true; onTriggered: {
    root.setTextSize(19)
    root.setTextSize(20)
  } }
  Timer {
    interval: 600; repeat: true; running: true
    onTriggered: {
      if (root.stage === 0) {
        requests.reload()
        root.stage++
      } else if (root.stage === 1) {
        root.check(requests.text().trim() === "16\\n20", "busy requests coalesce to final20: " + requests.text())
        root.check(JSON.stringify(root.textSizeStops) === JSON.stringify(Array.from({length:19}, (_,i) => i+12)), "all integer stops 12–30")
        root.check(root.displayedTextPx() === 20, "successful request waits for Style")
        Style.font = {baseSize:20}; Style.fontBaseSizeChanged()
        root.check(root.textSizePreviewIndex === -1, "Style acknowledgement clears preview")
        root.setTextSize(24)
        root.stage++
      } else if (root.stage === 2) {
        root.check(root.textSizePreviewIndex === -1 && root.displayedTextPx() === 20, "failed write resets preview")
        root.setTextSize(22)
        root.stage++
      } else if (root.stage === 3) {
        root.check(root.displayedTextPx() === 22, "missing Style acknowledgement holds preview briefly")
        root.stage++
      } else if (root.stage === 6) {
        root.check(root.textSizePreviewIndex === -1, "missing Style acknowledgement times out")
        root.setTextSize(30)
        Style.font = {baseSize:30}; Style.fontBaseSizeChanged()
        root.check(root.displayedTextPx() === 30, "early acknowledgement survives running command")
        root.stage++
      } else if (root.stage === 7) {
        root.check(root.textSizePreviewIndex === -1, "early acknowledgement settles after exit")
        root.setTextSize(28)
        root.stage++
      } else if (root.stage === 8) {
        root.check(root.textSizePreviewIndex === -1 && !root.textSizeInFlight, "failed spawn resets preview and busy state")
        console.log("NATIVE_PASS dispatch/preview/failure/timeout/early acknowledgement/spawn failure")
        Qt.quit()
      } else { root.stage++ }
    }
  }
  Timer { interval: 7000; running: true; onTriggered: { console.log("NATIVE_FAIL timeout"); Qt.quit() } }
}'''
        self.native(qml)


if __name__ == "__main__":
    unittest.main(verbosity=2)
