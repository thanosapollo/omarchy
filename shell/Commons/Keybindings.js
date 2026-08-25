var ACTIONS = ["cancel", "next", "previous", "back", "forward", "search"]
var DEFAULT_PRESET = "default"

var BUILTIN_PRESETS = {
  default: {
    cancel: ["Escape"],
    next: ["Down"],
    previous: ["Up"],
    back: ["Left"],
    forward: ["Right"],
    search: ["Slash"]
  },
  emacs: {
    cancel: ["Escape", "Ctrl+G"],
    next: ["Down", "Ctrl+N"],
    previous: ["Up", "Ctrl+P"],
    back: ["Left", "Ctrl+B"],
    forward: ["Right", "Ctrl+F"],
    search: ["Slash", "Ctrl+S"]
  }
}

var MODIFIER_NAMES = {
  ctrl: "Ctrl",
  control: "Ctrl",
  alt: "Alt",
  shift: "Shift",
  meta: "Meta",
  super: "Meta"
}

var KEY_NAMES = {
  esc: "Escape",
  escape: "Escape",
  down: "Down",
  up: "Up",
  left: "Left",
  right: "Right",
  slash: "Slash",
  "/": "Slash",
  space: "Space",
  tab: "Tab",
  backtab: "Backtab",
  enter: "Enter",
  return: "Return",
  backspace: "Backspace",
  delete: "Delete",
  home: "Home",
  end: "End",
  pageup: "PageUp",
  pagedown: "PageDown"
}

function isPlainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value)
}

function hasOwn(object, key) {
  return isPlainObject(object) && Object.prototype.hasOwnProperty.call(object, key)
}

function normalizedKeyName(value) {
  var raw = String(value || "").trim()
  if (!raw) return ""
  var known = KEY_NAMES[raw.toLowerCase()]
  if (known) return known
  if (raw.length === 1) return raw.toUpperCase()
  return raw.charAt(0).toUpperCase() + raw.slice(1)
}

function normalizeStroke(value) {
  var parts = String(value || "").trim().split("+")
  if (!parts.length) return ""
  var key = normalizedKeyName(parts.pop())
  if (!key) return ""

  var modifiers = {}
  for (var i = 0; i < parts.length; i++) {
    var modifier = MODIFIER_NAMES[String(parts[i] || "").trim().toLowerCase()]
    if (!modifier) return ""
    modifiers[modifier] = true
  }

  var result = []
  var order = ["Ctrl", "Alt", "Shift", "Meta"]
  for (var j = 0; j < order.length; j++) {
    if (modifiers[order[j]]) result.push(order[j])
  }
  result.push(key)
  return result.join("+")
}

function normalizeBindings(values) {
  if (!Array.isArray(values)) return []
  var result = []
  for (var i = 0; i < values.length; i++) {
    var binding = normalizeStroke(values[i])
    if (binding && result.indexOf(binding) === -1) result.push(binding)
  }
  return result
}

function clonePreset(preset) {
  var result = {}
  for (var i = 0; i < ACTIONS.length; i++) {
    var action = ACTIONS[i]
    result[action] = normalizeBindings(preset && preset[action])
  }
  return result
}

function resolvePreset(config) {
  var source = isPlainObject(config) ? config : {}
  var name = String(source.preset || DEFAULT_PRESET)
  if (hasOwn(BUILTIN_PRESETS, name)) return clonePreset(BUILTIN_PRESETS[name])

  var custom = hasOwn(source.presets, name) && isPlainObject(source.presets[name])
    ? source.presets[name] : null
  if (!custom) return clonePreset(BUILTIN_PRESETS[DEFAULT_PRESET])

  var baseName = String(custom.extends || DEFAULT_PRESET)
  var base = hasOwn(BUILTIN_PRESETS, baseName)
    ? BUILTIN_PRESETS[baseName] : BUILTIN_PRESETS[DEFAULT_PRESET]
  var result = clonePreset(base)
  var bindings = isPlainObject(custom.bindings) ? custom.bindings : {}
  for (var i = 0; i < ACTIONS.length; i++) {
    var action = ACTIONS[i]
    if (Object.prototype.hasOwnProperty.call(bindings, action))
      result[action] = normalizeBindings(bindings[action])
  }
  return result
}

function matches(preset, action, stroke) {
  var bindings = preset && Array.isArray(preset[action]) ? preset[action] : []
  return bindings.indexOf(normalizeStroke(stroke)) !== -1
}

if (typeof module !== "undefined") {
  module.exports = {
    ACTIONS: ACTIONS,
    DEFAULT_PRESET: DEFAULT_PRESET,
    normalizeStroke: normalizeStroke,
    resolvePreset: resolvePreset,
    matches: matches
  }
}
