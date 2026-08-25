pragma Singleton
import QtQuick
import "Keybindings.js" as Model

QtObject {
  id: root

  property var preset: Model.resolvePreset({})

  function configure(config) {
    preset = Model.resolvePreset(config)
  }

  function keyName(key) {
    if (key >= Qt.Key_A && key <= Qt.Key_Z) return String.fromCharCode(key)
    if (key >= Qt.Key_0 && key <= Qt.Key_9) return String.fromCharCode(key)

    switch (key) {
    case Qt.Key_Escape: return "Escape"
    case Qt.Key_Down: return "Down"
    case Qt.Key_Up: return "Up"
    case Qt.Key_Left: return "Left"
    case Qt.Key_Right: return "Right"
    case Qt.Key_Slash: return "Slash"
    case Qt.Key_Space: return "Space"
    case Qt.Key_Tab: return "Tab"
    case Qt.Key_Backtab: return "Backtab"
    case Qt.Key_Enter: return "Enter"
    case Qt.Key_Return: return "Return"
    case Qt.Key_Backspace: return "Backspace"
    case Qt.Key_Delete: return "Delete"
    case Qt.Key_Home: return "Home"
    case Qt.Key_End: return "End"
    case Qt.Key_PageUp: return "PageUp"
    case Qt.Key_PageDown: return "PageDown"
    default: return ""
    }
  }

  function stroke(event) {
    var key = keyName(event.key)
    if (!key) return ""
    var parts = []
    if (event.modifiers & Qt.ControlModifier) parts.push("Ctrl")
    if (event.modifiers & Qt.AltModifier) parts.push("Alt")
    if (event.modifiers & Qt.ShiftModifier) parts.push("Shift")
    if (event.modifiers & Qt.MetaModifier) parts.push("Meta")
    parts.push(key)
    return parts.join("+")
  }

  function matches(action, event, allowPlainLetters) {
    if (allowPlainLetters === false
        && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))
        && event.key >= Qt.Key_A && event.key <= Qt.Key_Z)
      return false
    return Model.matches(preset, action, stroke(event))
  }

  function isCancel(event) { return matches("cancel", event) }
  function isNext(event, allowPlainLetters) { return matches("next", event, allowPlainLetters) }
  function isPrevious(event, allowPlainLetters) { return matches("previous", event, allowPlainLetters) }
  function isBack(event, allowPlainLetters) { return matches("back", event, allowPlainLetters) }
  function isForward(event, allowPlainLetters) { return matches("forward", event, allowPlainLetters) }
  function isSearch(event) { return matches("search", event) }
}
