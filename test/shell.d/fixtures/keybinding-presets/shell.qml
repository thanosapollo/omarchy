import QtQuick
import Quickshell
import qs.Commons

ShellRoot {
  id: root

  function fail(message) {
    console.log("RESULT fail " + message)
    Qt.quit()
  }

  function keyEvent(key, modifiers) {
    return { key: key, modifiers: modifiers || Qt.NoModifier }
  }

  function runChecks() {
    Keybindings.configure({ preset: "default" })
    if (!Keybindings.isNext(keyEvent(Qt.Key_Down))) {
      fail("default did not accept Down")
      return
    }
    if (Keybindings.isNext(keyEvent(Qt.Key_N, Qt.ControlModifier))) {
      fail("default accepted Ctrl+N")
      return
    }

    Keybindings.configure({
      preset: "reader",
      presets: {
        reader: {
          extends: "default",
          bindings: {
            cancel: ["Q"],
            next: ["Ctrl+N"],
            search: ["S"]
          }
        }
      }
    })
    if (!Keybindings.isNext(keyEvent(Qt.Key_N, Qt.ControlModifier))) {
      fail("custom preset did not accept Ctrl+N")
      return
    }
    if (Keybindings.isNext(keyEvent(Qt.Key_Down))) {
      fail("custom replacement retained Down")
      return
    }
    if (!Keybindings.isPrevious(keyEvent(Qt.Key_Up))) {
      fail("custom preset lost inherited Up")
      return
    }
    if (!Keybindings.isCancel(keyEvent(Qt.Key_Q))
        || Keybindings.isCancel(keyEvent(Qt.Key_Q), false)) {
      fail("plain custom cancel was not suppressed for text input")
      return
    }
    if (!Keybindings.isSearch(keyEvent(Qt.Key_S))
        || Keybindings.isSearch(keyEvent(Qt.Key_S), false)) {
      fail("plain custom search was not suppressed for text input")
      return
    }

    Keybindings.configure({ preset: "emacs" })
    if (!Keybindings.isCancel(keyEvent(Qt.Key_G, Qt.ControlModifier))) {
      fail("same-process reconfiguration did not enable Ctrl+G")
      return
    }

    console.log("RESULT pass")
    Qt.quit()
  }

  Component.onCompleted: Qt.callLater(runChecks)
}
