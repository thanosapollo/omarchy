#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

python3 - "$ROOT" <<'PY'
from pathlib import Path
import re
import sys

root = Path(sys.argv[1]) / "shell"
shared_cancel_paths = [
    "Ui/ConfirmDialog.qml",
    "Ui/Dropdown.qml",
    "Ui/MultiSelect.qml",
    "Ui/PanelKeyCatcher.qml",
    "Ui/SearchableDropdown.qml",
    "Ui/SpeedTestOverlay.qml",
]
for relative in shared_cancel_paths:
    text = (root / relative).read_text()
    if "Keybindings.isCancel(event)" not in text:
        raise SystemExit(f"cancel action is not routed through the preset in {relative}")
    if "event.key === Qt.Key_Escape" in text or "Keys.onEscapePressed" in text:
        raise SystemExit(f"raw Escape handling remains in {relative}")
print("ok - shared controls route cancel through the active preset")

shared_routes = {
    "Ui/ButtonGroup.qml": ["isBack", "isForward"],
    "Ui/ConfirmDialog.qml": ["isBack", "isForward"],
    "Ui/Dropdown.qml": ["isNext", "isPrevious", "isForward", "isSearch"],
    "Ui/MultiSelect.qml": ["isNext", "isPrevious", "isSearch"],
    "Ui/PanelKeyCatcher.qml": ["isNext", "isPrevious", "isBack", "isForward"],
    "Ui/SearchableDropdown.qml": ["isNext", "isPrevious", "isSearch"],
}
raw_direction = re.compile(r"event\.key\s*===\s*Qt\.Key_(Down|Up|Left|Right)")
for relative, actions in shared_routes.items():
    text = (root / relative).read_text()
    for action in actions:
        if f"Keybindings.{action}(event" not in text:
            raise SystemExit(f"{action} is not routed through the preset in {relative}")
    if raw_direction.search(text):
        raise SystemExit(f"raw arrow-key handling remains in {relative}")
print("ok - shared controls route navigation through the active preset")

text_safe_routes = {
    "Ui/MultiSelect.qml": ["isCancel(event, false)", "isNext(event, false)"],
    "Ui/SearchableDropdown.qml": ["isCancel(event, false)", "isNext(event, false)"],
}
for relative, calls in text_safe_routes.items():
    text = (root / relative).read_text()
    for call in calls:
        if f"Keybindings.{call}" not in text:
            raise SystemExit(f"plain custom letters can steal filter input in {relative}")
print("ok - shared filters keep plain custom bindings available for typing")

for relative in ["Ui/Dropdown.qml", "Ui/MultiSelect.qml", "Ui/SearchableDropdown.qml"]:
    text = (root / relative).read_text()
    if "CloseOnEscape" in text:
        raise SystemExit(f"implicit Escape popup policy bypasses the preset in {relative}")
    if "CloseOnPressOutside" not in text:
        raise SystemExit(f"outside-click popup policy is not explicit in {relative}")
print("ok - shared popups leave cancel ownership to the active preset")

panel_keys = (root / "Ui/PanelKeyCatcher.qml").read_text()
if "Keybindings.isSearch(event)" in panel_keys or "signal searchRequested()" in panel_keys:
    raise SystemExit("generic panel handling swallows search without a filter owner")
print("ok - generic panels leave search to filter owners")
PY
