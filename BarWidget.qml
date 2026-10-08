import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Key-frequency analyzer for QMK layout tuning.
//
// The counting happens in a bundled evdev engine (engine/omakeylog), a separate
// process so the keyboard is read with the user's own input-group access and
// recording survives a shell reload. The engine only ever stores aggregate
// counts (per key, and per adjacent key-pair) - never the text that was typed.
//
// This widget shows how many keypresses are on record, starts and stops the
// engine, and hosts a panel that renders the ranked keys, hand and finger load,
// same-finger bigrams and QMK suggestions the engine computes.
BarWidget {
  id: root
  moduleName: "io.github.cesarfilho.omakeylog"

  property bool recording: false
  property int total: 0
  property int distinct: 0
  property string errorMsg: ""
  property var report: Model.EMPTY_REPORT
  property bool refreshQueued: false

  readonly property string engine: decodeURIComponent(
    String(Qt.resolvedUrl("engine/omakeylog")).replace(/^file:\/\//, ""))

  readonly property bool showLabel: !vertical && setting("showLabel", false) === true
  readonly property string labelMode: String(setting("labelMode", "Total"))
  readonly property int refreshMs: Math.max(1, Number(setting("refreshIntervalSec", 3))) * 1000

  readonly property var panelItem: panelLoader.item
  readonly property bool panelOpen: panelItem ? panelItem.opened === true : false

  readonly property string glyph: "\u{F032C}"  // nf-md-keyboard
  readonly property string topKey: report.top_keys && report.top_keys.length > 0
    ? Model.keyName(report.top_keys[0].label) : "-"
  readonly property string labelText: {
    if (labelMode === "Top key") return topKey
    return Model.grouped(total)
  }

  // ---- data ---------------------------------------------------------------

  function applyStatus(text) {
    var s = Model.parseStatus(text)
    recording = s.recording === true
    total = Number(s.total) || 0
    distinct = Number(s.distinct) || 0
    errorMsg = (!recording && s.error) ? String(s.error) : ""
  }

  function applyReport(text) {
    report = Model.parseReport(text)
    total = Number(report.total) || total
    distinct = Number(report.distinct) || distinct
  }

  function refresh() {
    if (statusProc.running) { refreshQueued = true; return }
    statusProc.running = true
    if (panelOpen) reportProc.running = true
  }

  // ---- actions ------------------------------------------------------------

  function startRecording() {
    if (startProc.running) return
    errorMsg = ""
    startProc.running = true
  }
  function stopRecording() {
    if (stopProc.running) return
    stopProc.running = true
  }
  function toggleRecording() { recording ? stopRecording() : startRecording() }
  function resetCounts() {
    if (resetProc.running) return
    resetProc.running = true
  }

  // ---- panel contract (see the sibling plugin's notes) --------------------

  readonly property bool opened: panelOpen
  readonly property bool popoutSwitchClosing: panelItem ? panelItem.popoutSwitchClosing === true : false
  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }
  function togglePanel() { if (panelLoader.item && panelLoader.item.toggle) panelLoader.item.toggle() }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: root.injectPanel()
  }

  Process {
    id: statusProc
    command: ["/usr/bin/python3", root.engine, "status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.applyStatus(text)
        if (root.refreshQueued) { root.refreshQueued = false; root.refresh() }
      }
    }
  }

  Process {
    id: reportProc
    command: ["/usr/bin/python3", root.engine, "report", "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyReport(text)
    }
  }

  Process {
    id: startProc
    command: ["/usr/bin/python3", root.engine, "record"]
    onExited: function(code) {
      if (code !== 0) root.errorMsg = "Could not start recording (exit " + code + ")."
      root.refresh()
    }
  }

  Process {
    id: stopProc
    command: ["/usr/bin/python3", root.engine, "stop"]
    onExited: root.refresh()
  }

  Process {
    id: resetProc
    command: ["/usr/bin/python3", root.engine, "reset"]
    onExited: {
      root.report = Model.EMPTY_REPORT
      root.total = 0
      root.distinct = 0
      root.refresh()
    }
  }

  // Poll: lively while the panel is open, a gentle heartbeat otherwise so the
  // bar still reflects whether the engine is recording.
  Timer {
    interval: root.panelOpen ? root.refreshMs : 8000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.showLabel ? root.glyph + "  " + root.labelText : root.glyph
    fontSize: root.vertical ? Style.bar.iconFont : Style.font.body
    hasVisualContent: true
    active: root.recording
    useActiveColor: true
    dimmed: !root.recording && root.total === 0
    tooltipText: root.recording
      ? "omakeylog - recording (" + Model.grouped(root.total) + " keys)"
      : (root.total > 0 ? "omakeylog - " + Model.grouped(root.total) + " keys recorded"
                        : "omakeylog - click to record")
    onPressed: function(b) {
      if (b === Qt.MiddleButton) root.toggleRecording()
      else root.togglePanel()
    }
  }
}
