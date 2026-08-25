#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

model="$ROOT/shell/Commons/Keybindings.js"
[[ -f $model ]] || fail "keybinding preset model exists"

run_node_test <<'JS'
const keybindings = requireFromRoot('shell/Commons/Keybindings.js')

const standard = keybindings.resolvePreset({ preset: 'default' })
assert(keybindings.matches(standard, 'cancel', 'Escape'), 'default preset cancels with Escape')
assert(keybindings.matches(standard, 'next', 'Down'), 'default preset moves down with the arrow key')
assert(keybindings.matches(standard, 'previous', 'Up'), 'default preset moves up with the arrow key')
assert(keybindings.matches(standard, 'back', 'Left'), 'default preset moves back with the arrow key')
assert(keybindings.matches(standard, 'forward', 'Right'), 'default preset moves forward with the arrow key')
assert(keybindings.matches(standard, 'search', 'Slash'), 'default preset starts search with slash')
assert(!keybindings.matches(standard, 'next', 'J'), 'default preset does not claim plain letters')

const emacs = keybindings.resolvePreset({ preset: 'emacs' })
assert(keybindings.matches(emacs, 'cancel', 'Ctrl+G'), 'emacs preset cancels with Ctrl+G')
assert(keybindings.matches(emacs, 'next', 'Ctrl+N'), 'emacs preset moves down with Ctrl+N')
assert(keybindings.matches(emacs, 'previous', 'Ctrl+P'), 'emacs preset moves up with Ctrl+P')
assert(keybindings.matches(emacs, 'back', 'Ctrl+B'), 'emacs preset moves back with Ctrl+B')
assert(keybindings.matches(emacs, 'forward', 'Ctrl+F'), 'emacs preset moves forward with Ctrl+F')
assert(keybindings.matches(emacs, 'search', 'Ctrl+S'), 'emacs preset starts search with Ctrl+S')
assert(keybindings.matches(emacs, 'next', 'Down'), 'emacs preset preserves arrow navigation')

const custom = keybindings.resolvePreset({
  preset: 'reader',
  presets: {
    reader: {
      extends: 'emacs',
      bindings: {
        cancel: ['Ctrl+Q'],
        next: [' Alt+J '],
        search: []
      }
    }
  }
})
assert(keybindings.matches(custom, 'cancel', 'Ctrl+Q'), 'custom preset replaces an inherited action')
assert(!keybindings.matches(custom, 'cancel', 'Escape'), 'custom replacement removes inherited keys')
assert(keybindings.matches(custom, 'next', 'alt+j'), 'custom bindings are normalized')
assert(keybindings.matches(custom, 'previous', 'Ctrl+P'), 'custom preset inherits unchanged actions')
assert(!keybindings.matches(custom, 'search', 'Slash'), 'an empty custom action unbinds it')

for (const name of ['missing', '__proto__']) {
  const fallback = keybindings.resolvePreset({ preset: name })
  assert(keybindings.matches(fallback, 'next', 'Down'), `${name} falls back to default`)
  assert(!keybindings.matches(fallback, 'next', 'J'), `${name} cannot claim plain letters`)
}
JS

python3 - "$ROOT" <<'PY'
import json
from pathlib import Path
import sys

root = Path(sys.argv[1])
config = json.loads((root / "config/omarchy/shell.json").read_text())
if config.get("keybindings") != {"preset": "default"}:
    raise SystemExit("default shell config does not select the non-modal default preset")

manual = (root / "manual/34-keyboard-mouse-trackpad.md").read_text()
for expected in ['"preset": "emacs"', '"presets"', '"extends": "default"']:
    if expected not in manual:
        raise SystemExit(f"manual does not document user-defined presets: {expected}")
if "`vim` preset" in manual.lower():
    raise SystemExit("manual still advertises the deferred Vim preset")

shell_docs = (root / "docs/omarchy-shell.md").read_text()
if "keybindings.preset" not in shell_docs or "keybindings.presets" not in shell_docs:
    raise SystemExit("shell contract does not document built-in and named presets")
print("ok - shell config and docs expose user-defined presets")
PY

require_compositor "keybinding preset runtime test"

if ! command -v quickshell >/dev/null 2>&1; then
  pass "quickshell not installed; skipping keybinding preset runtime test"
  exit 0
fi

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

cp "$SHELL_TEST_DIR/fixtures/keybinding-presets/shell.qml" "$test_tmp/shell.qml"
ln -s "$ROOT/shell/Commons" "$test_tmp/Commons"

output=$(timeout 15 quickshell -p "$test_tmp" --no-color 2>&1) || {
  printf '%s\n' "$output" >&2
  fail "keybinding preset runtime fixture exits cleanly"
}

if ! grep -q "RESULT pass" <<<"$output"; then
  printf '%s\n' "$output" >&2
  fail "keybinding presets reconfigure in one process"
fi

pass "keybinding presets reconfigure in one process"
