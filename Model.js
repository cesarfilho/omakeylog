.pragma library

// Helpers shared by the bar widget and the panel. The Python engine
// (engine/omakeylog) does all the counting and analysis and writes report.json
// and status.json; this file only parses those and formats them for display,
// so the QML stays declarative.

var EMPTY_REPORT = {
  total: 0,
  distinct: 0,
  top_keys: [],
  hands: { left: 0, right: 0, thumb: 0, other: 0 },
  fingers: [],
  rows: {},
  top_bigrams: [],
  sfb: { pct: 0, top: [] },
  suggestions: []
}

var EMPTY_STATUS = {
  recording: false,
  pid: 0,
  devices: [],
  error: null,
  total: 0,
  distinct: 0
}

function parse(text, fallback) {
  try {
    var v = JSON.parse(String(text))
    return (v && typeof v === "object") ? v : fallback
  } catch (e) {
    return fallback
  }
}

function parseReport(text) {
  var r = parse(text, null)
  if (!r) return EMPTY_REPORT
  // Fill any missing branch so bindings never hit undefined.
  r.top_keys = r.top_keys || []
  r.fingers = r.fingers || []
  r.top_bigrams = r.top_bigrams || []
  r.hands = r.hands || EMPTY_REPORT.hands
  r.rows = r.rows || {}
  r.sfb = r.sfb || { pct: 0, top: [] }
  r.suggestions = r.suggestions || []
  return r
}

function parseStatus(text) {
  var s = parse(text, null)
  if (!s) return EMPTY_STATUS
  s.devices = s.devices || []
  return s
}

// "L-pinky" -> "left pinky", "R-index" -> "right index", "T-thumb" -> "thumb".
function fingerName(code) {
  var p = String(code).split("-")
  if (p.length !== 2) return code
  if (p[0] === "T") return "thumb"
  var hand = p[0] === "L" ? "left" : (p[0] === "R" ? "right" : p[0])
  return hand + " " + p[1]
}

// A key label from the engine ("SEMICOLON", "SPACE", "A") shown short.
function keyName(label) {
  switch (label) {
    case "SPACE": return "␣ space"
    case "ENTER": return "⏎ enter"
    case "BACKSPACE": return "⌫ bksp"
    case "TAB": return "⇥ tab"
    case "SEMICOLON": return ";"
    case "APOSTROPHE": return "'"
    case "COMMA": return ","
    case "DOT": return "."
    case "SLASH": return "/"
    case "BACKSLASH": return "\\"
    case "MINUS": return "-"
    case "EQUAL": return "="
    case "GRAVE": return "`"
    case "LEFTBRACE": return "["
    case "RIGHTBRACE": return "]"
    case "LEFTSHIFT": return "⇧ lshift"
    case "RIGHTSHIFT": return "⇧ rshift"
    case "CAPSLOCK": return "⇪ caps"
    default: return label
  }
}

function pairName(pair) {
  var parts = String(pair).split(" ")
  if (parts.length === 2) return keyName(parts[0]) + " → " + keyName(parts[1])
  return pair
}

// Integer with thousands separators, for the big keypress total.
function grouped(n) {
  var s = String(Math.max(0, Math.floor(Number(n) || 0)))
  return s.replace(/\B(?=(\d{3})+(?!\d))/g, " ")
}
