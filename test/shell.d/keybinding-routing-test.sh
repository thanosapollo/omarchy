#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

python3 - "$ROOT" <<'PY'
from pathlib import Path
import re
import sys

root = Path(sys.argv[1]) / "shell"
cancel_paths = [
    "Ui/ConfirmDialog.qml",
    "Ui/Dropdown.qml",
    "Ui/MultiSelect.qml",
    "Ui/PanelKeyCatcher.qml",
    "Ui/SearchableDropdown.qml",
    "Ui/SpeedTestOverlay.qml",
    "plugins/clipboard/Clipboard.qml",
    "plugins/dev-gallery/GalleryPanel.qml",
    "plugins/emojis/Emojis.qml",
    "plugins/image-picker/ImagePicker.qml",
    "plugins/lock/LockView.qml",
    "plugins/menu/Menu.qml",
    "plugins/polkit/PolkitAgent.qml",
    "plugins/reminders/ReminderFlow.qml",
    "plugins/panels/clock/Panel.qml",
    "plugins/panels/network/Panel.qml",
    "plugins/panels/tailscale/Panel.qml",
    "plugins/panels/weather/Panel.qml",
    "plugins/panels/wifiqr/Panel.qml",
]
for relative in cancel_paths:
    text = (root / relative).read_text()
    if "Keybindings.isCancel(event" not in text:
        raise SystemExit(f"cancel action is not routed through the preset in {relative}")
    if "event.key === Qt.Key_Escape" in text or "Keys.onEscapePressed" in text:
        raise SystemExit(f"raw Escape handling remains in {relative}")
print("ok - shell cancel paths use the active preset")

routes = {
    "Ui/ButtonGroup.qml": ["isBack", "isForward"],
    "Ui/ConfirmDialog.qml": ["isBack", "isForward"],
    "Ui/Dropdown.qml": ["isNext", "isPrevious", "isForward", "isSearch"],
    "Ui/MultiSelect.qml": ["isNext", "isPrevious", "isSearch"],
    "Ui/PanelKeyCatcher.qml": ["isNext", "isPrevious", "isBack", "isForward"],
    "Ui/SearchableDropdown.qml": ["isNext", "isPrevious", "isSearch"],
    "plugins/clipboard/Clipboard.qml": ["isNext", "isPrevious", "isSearch"],
    "plugins/emojis/Emojis.qml": ["isNext", "isPrevious", "isBack", "isForward", "isSearch"],
    "plugins/image-picker/ImagePicker.qml": ["isBack", "isForward", "isSearch"],
    "plugins/menu/Menu.qml": ["isNext", "isPrevious", "isBack", "isForward", "isSearch"],
    "plugins/panels/tailscale/Panel.qml": ["isNext", "isPrevious"],
    "plugins/panels/weather/Panel.qml": ["isNext", "isPrevious"],
}
for relative, actions in routes.items():
    text = (root / relative).read_text()
    for action in actions:
        if f"Keybindings.{action}(event" not in text:
            raise SystemExit(f"{action} is not routed through the preset in {relative}")
print("ok - shell navigation paths use the active preset")

# Ctrl+Up/Down and Ctrl+k/j are upstream's separate item-reordering API,
# not cursor navigation. Preserve that guarded block; everything else routes.
reorder = '''    if (reorderable && (event.modifiers & Qt.ControlModifier)) {
      var up = event.key === Qt.Key_Up || event.key === Qt.Key_K
      var down = event.key === Qt.Key_Down || event.key === Qt.Key_J
      if (up || down) {
        reorderRequested(down ? 1 : -1); event.accepted = true; return
      }
    }
'''
raw_direction = re.compile(r"event\.key\s*===\s*Qt\.Key_(Down|Up|Left|Right)")
for path in root.rglob("*.qml"):
    text = path.read_text()
    if path.relative_to(root).as_posix() == "Ui/PanelKeyCatcher.qml":
        if text.count(reorder) != 1:
            raise SystemExit("upstream's guarded item-reordering contract changed")
        text = text.replace(reorder, "", 1)
    if raw_direction.search(text):
        raise SystemExit(f"raw arrow-key handling bypasses presets in {path.relative_to(root)}")
print("ok - cursor arrows use presets while guarded item reordering is preserved")

text_safe_routes = {
    "Ui/MultiSelect.qml": ["isCancel(event, false)", "isNext(event, false)"],
    "Ui/SearchableDropdown.qml": ["isCancel(event, false)", "isNext(event, false)"],
    "plugins/clipboard/Clipboard.qml": [
        "isCancel(event, false)", "isSearch(event, false)",
        "isNext(event, false)", "isPrevious(event, false)",
    ],
    "plugins/emojis/Emojis.qml": [
        "isCancel(event, false)", "isSearch(event, false)",
        "isNext(event, false)", "isPrevious(event, false)",
        "isBack(event, false)", "isForward(event, false)",
    ],
    "plugins/image-picker/ImagePicker.qml": [
        "isCancel(event, false)", "isSearch(event, false)",
        "isBack(event, false)", "isForward(event, false)",
    ],
    "plugins/menu/Menu.qml": [
        "isCancel(event, false)", "isSearch(event, false)",
        "isNext(event, false)", "isPrevious(event, false)",
        "isBack(event, false)", "isForward(event, false)",
    ],
    "plugins/panels/tailscale/Panel.qml": [
        "isCancel(event, false)", "isNext(event, false)", "isPrevious(event, false)",
    ],
    "plugins/panels/weather/Panel.qml": [
        "isCancel(event, false)", "isNext(event, false)", "isPrevious(event, false)",
    ],
}
for relative, calls in text_safe_routes.items():
    text = (root / relative).read_text()
    for call in calls:
        if f"Keybindings.{call}" not in text:
            raise SystemExit(f"plain custom binding is not suppressed while typing in {relative}: {call}")

text_safe_cancel_counts = {
    "plugins/dev-gallery/GalleryPanel.qml": 2,
    "plugins/lock/LockView.qml": 1,
    "plugins/panels/clock/Panel.qml": 1,
    "plugins/panels/network/Panel.qml": 2,
    "plugins/polkit/PolkitAgent.qml": 1,
    "plugins/reminders/ReminderFlow.qml": 1,
}
for relative, expected in text_safe_cancel_counts.items():
    actual = (root / relative).read_text().count("Keybindings.isCancel(event, false)")
    if actual < expected:
        raise SystemExit(f"plain custom cancel is not suppressed in every text field in {relative}")
print("ok - filter fields keep plain custom bindings available for typing")

tailscale = (root / "plugins/panels/tailscale/Panel.qml").read_text()
if "blocked: root.copyMenuOpen || root.mullvadPickerOpen" not in tailscale:
    raise SystemExit("Tailscale panel key catcher is active while the Mullvad filter owns focus")
if "function restoreKeyboardFocus()" not in tailscale:
    raise SystemExit("Tailscale has no single owner for restoring keyboard focus")
if "onMullvadPickerOpenChanged: root.restoreKeyboardFocus()" not in tailscale:
    raise SystemExit("Mullvad picker lifecycle does not restore focus on every open/close path")
if tailscale.count("root.restoreKeyboardFocus()") < 3:
    raise SystemExit("a Tailscale focus restoration bypasses its keyboard-focus owner")
print("ok - Mullvad filtering owns focus across Tailscale close and reopen")

for relative in [
    "Ui/Dropdown.qml", "Ui/MultiSelect.qml", "Ui/SearchableDropdown.qml",
    "plugins/panels/tailscale/Panel.qml",
]:
    text = (root / relative).read_text()
    if "CloseOnEscape" in text:
        raise SystemExit(f"implicit Escape popup policy bypasses the preset in {relative}")
    if "CloseOnPressOutside" not in text:
        raise SystemExit(f"outside-click popup policy is not explicit in {relative}")
print("ok - popup close policies do not bypass the cancel preset")

panel_keys = (root / "Ui/PanelKeyCatcher.qml").read_text()
if "Keybindings.isSearch(event" in panel_keys or "signal searchRequested()" in panel_keys:
    raise SystemExit("generic panel key handling swallows search without a filter owner")
print("ok - generic panels leave search keys to filter owners")
PY

require_command python3
python3 "$SHELL_TEST_DIR/fixtures/keybinding-presets/panel-keys.py" "$ROOT"
