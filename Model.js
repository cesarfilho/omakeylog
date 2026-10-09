.pragma library

// Helpers shared by the bar widget and the panel. The Python engine
// (engine/omakeylog) does all the counting and analysis and writes report.json
// and status.json; this file only parses those and formats them for display,
// so the QML stays declarative.

var EMPTY_HISTORY = {
  session: [], hours: [], days: [], months: [], years: [],
  summary: {}, today: { keys: 0, wpm: null }
}

// The history periods, in the order the panel offers them. `value` is the
// report's series name, `setting` the name used in the widget settings.
var HISTORY_RANGES = [
  { value: "session", label: "Session", setting: "Session" },
  { value: "hours", label: "24 h", setting: "24 hours" },
  { value: "days", label: "30 days", setting: "30 days" },
  { value: "months", label: "12 months", setting: "12 months" },
  { value: "years", label: "Years", setting: "Years" }
]

function historyRange(setting) {
  for (var i = 0; i < HISTORY_RANGES.length; i++)
    if (HISTORY_RANGES[i].setting === setting) return HISTORY_RANGES[i].value
  return "days"
}

var EMPTY_REPORT = {
  total: 0,
  distinct: 0,
  top_keys: [],
  hands: { left: 0, right: 0, thumb: 0, other: 0 },
  fingers: [],
  rows: {},
  top_bigrams: [],
  sfb: { pct: 0, top: [] },
  sfs: { pct: 0, top: [] },
  trigrams: { total: 0, kinds: {}, top: [] },
  chords: { total: 0, top: [], shifted_pct: 0 },
  timing: { samples: 0, home_holds: [], hold_hist: [] },
  heatmap: [],
  layout: { name: "", source: "default" },
  compare: null,
  suggestions: [],
  history: EMPTY_HISTORY
}

var EMPTY_STATUS = {
  recording: false,
  paused: false,
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
  r.sfs = r.sfs || { pct: 0, top: [] }
  r.trigrams = r.trigrams || EMPTY_REPORT.trigrams
  r.trigrams.kinds = r.trigrams.kinds || {}
  r.chords = r.chords || EMPTY_REPORT.chords
  r.chords.top = r.chords.top || []
  r.timing = r.timing || EMPTY_REPORT.timing
  r.timing.home_holds = r.timing.home_holds || []
  r.heatmap = r.heatmap || []
  r.layout = r.layout || EMPTY_REPORT.layout
  r.compare = r.compare || null
  r.suggestions = r.suggestions || []
  r.history = r.history || EMPTY_HISTORY
  r.history.summary = r.history.summary || {}
  r.history.today = r.history.today || EMPTY_HISTORY.today
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
  if (p[1] === "thumb") return (p[0] === "L" ? "left" : "right") + " thumb"
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
    case "LEFTCTRL": return "lctrl"
    case "RIGHTCTRL": return "rctrl"
    case "LEFTALT": return "lalt"
    case "RIGHTALT": return "ralt"
    case "LEFTMETA": return "lsuper"
    case "RIGHTMETA": return "rsuper"
    case "ESC": return "esc"
    default: return label
  }
}

function pairName(pair) {
  var parts = String(pair).split(" ")
  if (parts.length === 2) return keyName(parts[0]) + " → " + keyName(parts[1])
  return pair
}

// "LEFTCTRL+LEFTSHIFT+C" -> "lctrl + ⇧ lshift + C"
function chordName(chord) {
  return String(chord).split("+").map(keyName).join(" + ")
}

// "T H E" -> "T H E" with symbols for the named keys.
function keysName(keys) {
  return String(keys).split(" ").map(keyName).join(" ")
}

// Short legend for a heatmap keycap.
function capName(label) {
  switch (label) {
    case "": return ""
    case "SPACE": return "␣"
    case "ENTER": return "⏎"
    case "BACKSPACE": return "⌫"
    case "TAB": return "⇥"
    case "CAPSLOCK": return "⇪"
    case "LEFTSHIFT": case "RIGHTSHIFT": return "⇧"
    case "LEFTCTRL": case "RIGHTCTRL": return "ctl"
    case "LEFTALT": case "RIGHTALT": return "alt"
    case "LEFTMETA": case "RIGHTMETA": return "sup"
    case "DELETE": return "del"
  }
  var k = keyName(label)
  return k.length > 3 ? k.slice(0, 3).toLowerCase() : k
}

// "L-pinky" -> "pinky": the column chart puts left and right on their own side.
function fingerShort(code) {
  var p = String(code).split("-")
  var f = p.length === 2 ? p[1] : String(code)
  return f === "middle" ? "mid" : f
}

// Largest numeric field over a list of objects (0 for an empty list).
function maxOf(list, field) {
  var most = 0
  for (var i = 0; i < (list || []).length; i++) most = Math.max(most, Number(list[i][field]) || 0)
  return most
}

// The hold-time histogram ({ms, count} in 10 ms buckets) re-bucketed for a
// chart: `step` ms per bar up to `maxMs`, everything slower in the last bar.
function holdBars(hist, maxMs, step) {
  var n = Math.floor(maxMs / step) + 1
  var bars = []
  for (var i = 0; i < n; i++) bars.push(0)
  for (var j = 0; j < (hist || []).length; j++) {
    var b = Math.min(n - 1, Math.floor((Number(hist[j].ms) || 0) / step))
    bars[b] += Number(hist[j].count) || 0
  }
  return bars
}

// Widest heatmap row, in key units.
function gridUnits(rows) {
  var most = 0
  for (var i = 0; i < (rows || []).length; i++) {
    var sum = 0
    for (var j = 0; j < rows[i].length; j++) sum += Number(rows[i][j].w) || 1
    most = Math.max(most, sum)
  }
  return most
}

// A signed percentage-point change, "" when there is nothing to compare.
function delta(d) {
  if (d === null || d === undefined) return ""
  var n = Number(d)
  if (Math.abs(n) < 0.05) return "±0"
  return (n > 0 ? "+" : "") + n.toFixed(1)
}

// Active minutes as "45 min" or "3 h 20".
function duration(min) {
  var m = Math.round(Number(min) || 0)
  if (m < 60) return m + " min"
  var h = Math.floor(m / 60)
  return h + " h" + (m % 60 ? " " + String(m % 60).padStart(2, "0") : "")
}

// Integer with thousands separators, for the big keypress total.
function grouped(n) {
  var s = String(Math.max(0, Math.floor(Number(n) || 0)))
  return s.replace(/\B(?=(\d{3})+(?!\d))/g, " ")
}
