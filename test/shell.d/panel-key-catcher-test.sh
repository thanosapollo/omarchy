#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# /usr/bin/qmltestrunner is the Qt 5 binary, which exits 0 having run nothing.
qml_test_runner=""
for candidate in /usr/lib/qt6/bin/qmltestrunner /usr/lib/qt6/qmltestrunner; do
  if [[ -x $candidate ]]; then
    qml_test_runner=$candidate
    break
  fi
done

if [[ -z $qml_test_runner ]]; then
  skip "qt6 qmltestrunner not found; skipping panel key catcher tests"
  exit 0
fi

# qmltestrunner does not register Quickshell's qs import namespace. Expose only
# the real keybinding singleton needed by this otherwise plain QtQuick control.
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
mkdir -p "$test_tmp/qs/Commons"
printf 'module qs.Commons\nsingleton Keybindings 1.0 Keybindings.qml\n' > "$test_tmp/qs/Commons/qmldir"
ln -s "$ROOT/shell/Commons/Keybindings.qml" "$test_tmp/qs/Commons/Keybindings.qml"
ln -s "$ROOT/shell/Commons/Keybindings.js" "$test_tmp/qs/Commons/Keybindings.js"

output=$(QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software "$qml_test_runner" -import "$test_tmp" -input "$SHELL_TEST_DIR/panel-key-catcher/qml" -o -,txt 2>&1) ||
  fail "panel key catcher passes modifiers with text keys" "$output"
pass "panel key catcher passes modifiers with text keys"
