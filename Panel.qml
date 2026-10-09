import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Popup view for omakeylog. The bar widget (hostWidget) owns the data and the
// actions; this file only renders what the engine computed into report.json:
// a keyboard heatmap, ranked keys, hand and finger load, same-finger pairs,
// trigram patterns, shortcuts, typing timing and QMK suggestions.
//
// Five tabs keep each view on one screen: Overview (summary numbers, the
// heatmap, top keys, hand balance), Layout (finger load, trigram patterns,
// key pairs, shortcuts), Timing (hold times, TAPPING_TERM), History
// (keypresses and words per minute over a chosen period) and Tips (the QMK
// suggestions).
//
// Keys: 1-5 switch tabs, S start/stop recording, R refresh, X reset (twice to
// confirm), Esc close.
Panel {
  id: root
  moduleName: "io.github.cesarfilho.omakeylog"
  ipcTarget: "io.github.cesarfilho.omakeylog"

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property bool recording: hostWidget ? hostWidget.recording : false
  readonly property bool paused: hostWidget ? hostWidget.paused : false
  readonly property int total: hostWidget ? hostWidget.total : 0
  readonly property int distinct: hostWidget ? hostWidget.distinct : 0
  readonly property string errorMsg: hostWidget ? hostWidget.errorMsg : ""
  readonly property var report: hostWidget ? hostWidget.report : Model.EMPTY_REPORT

  readonly property int topKeys: hostWidget ? Math.max(5, Number(hostWidget.setting("topKeys", 12))) : 12
  readonly property int topBigrams: hostWidget ? Math.max(5, Number(hostWidget.setting("topBigrams", 10))) : 10
  // Layout tab rows per list; more than 7 would push it past one screen.
  readonly property int pairRows: Math.min(7, topBigrams)
  readonly property bool showHeatmap: hostWidget ? hostWidget.setting("showHeatmap", true) !== false : true
  readonly property var compare: report.compare

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property color accent: Color.accent

  property bool confirmReset: false
  // Height the content column may use: the panel's 720 cap or the screen,
  // whichever is smaller, less the panel's own padding.
  readonly property real maxHeight: Math.min(Style.space(720),
      panel.availableCardHeight > 0 ? panel.availableCardHeight : Style.space(720))
    - panel.verticalContentInset

  readonly property var tabs: [
    { value: "overview", label: "Overview" },
    { value: "layout", label: "Layout" },
    { value: "timing", label: "Timing" },
    { value: "history", label: "History" },
    { value: "tips", label: "Tips" }
  ]
  property string tab: "overview"

  // History period: the widget setting until the user picks one in the panel.
  property string pickedRange: ""
  readonly property string range: pickedRange !== "" ? pickedRange
    : Model.historyRange(hostWidget ? String(hostWidget.setting("historyRange", "30 days")) : "30 days")
  readonly property var series: report.history[range] || []
  readonly property var rangeSummary: report.history.summary[range] || ({})
  // Counts recorded before 1.2 have no dates, so the history can be empty
  // while the counts are not.
  readonly property bool hasHistory: ((report.history.summary.years || {}).keys || 0) > 0

  readonly property string heroMeta: {
    if (errorMsg !== "") return "Not recording"
    if (paused) return "Paused - session locked or not active"
    if (recording) return "Recording - " + Model.grouped(total) + " keys"
    if (total > 0) return Model.grouped(total) + " keys on record"
    return "Not recording yet"
  }

  // ---- lifecycle ----------------------------------------------------------

  function open() {
    confirmReset = false
    root.controller.show()
    if (hostWidget) hostWidget.refresh()
  }
  function close() { root.controller.hide() }
  function toggle() { root.opened ? root.close() : root.open() }

  function doReset() {
    if (!hostWidget) return
    if (confirmReset) { confirmReset = false; hostWidget.resetCounts() }
    else { confirmReset = true; confirmTimer.restart() }
  }

  Timer { id: confirmTimer; interval: 4000; onTriggered: root.confirmReset = false }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(720))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTextKey: function(t) {
        var k = t.toLowerCase()
        if (k === "s" && root.hostWidget) root.hostWidget.toggleRecording()
        else if (k === "r" && root.hostWidget) root.hostWidget.refresh()
        else if (k === "x") root.doReset()
        else if (k >= "1" && k <= "5") root.tab = root.tabs[Number(k) - 1].value
      }

      Column {
        id: column
        anchors.fill: parent
        spacing: Style.space(14)

        // ---------- Hero ----------
        PanelHero {
          foreground: root.foreground
          fontFamily: root.fontFamily
          title: "Key frequency"
          meta: root.heroMeta
          detail: root.recording ? "REC" : ""
          iconComponent: Component {
            Text {
              textFormat: Text.PlainText
              text: "\u{F032C}"
              color: root.recording ? root.accent : root.foreground
              opacity: root.recording || root.total > 0 ? 1.0 : 0.5
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
            }
          }
        }

        // ---------- Controls ----------
        Row {
          width: parent.width
          spacing: Style.space(8)

          PillButton {
            label: root.recording ? "Stop" : "Start recording"
            glyph: root.recording ? "\u{F0666}" : "\u{F044A}"  // stop / record
            emphasised: true
            onActivated: if (root.hostWidget) root.hostWidget.toggleRecording()
          }
          PillButton {
            label: "Refresh"
            glyph: "\u{F0450}"
            onActivated: if (root.hostWidget) root.hostWidget.refresh()
          }
          PillButton {
            label: root.confirmReset ? "Confirm reset" : "Reset"
            glyph: "\u{F0A7A}"
            danger: root.confirmReset
            onActivated: root.doReset()
          }
        }

        // ---------- Input-access error ----------
        Rectangle {
          visible: root.errorMsg !== ""
          width: parent.width
          height: visible ? errCol.implicitHeight + Style.space(16) : 0
          radius: Style.cornerRadius
          color: Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, 0.16)
          border.width: 1
          border.color: Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, 0.5)

          Column {
            id: errCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Style.space(8)
            spacing: Style.space(4)

            Text {
              width: parent.width
              textFormat: Text.PlainText
              wrapMode: Text.Wrap
              text: root.errorMsg
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }
            Text {
              width: parent.width
              visible: root.errorMsg.indexOf("input") !== -1
              textFormat: Text.PlainText
              wrapMode: Text.Wrap
              text: "Fix:  sudo usermod -aG input \"$USER\"   then log out and back in."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }

        // ---------- Tabs ----------
        ButtonGroup {
          visible: root.total > 0
          focusable: false
          foreground: root.foreground
          accent: root.accent
          fontFamily: root.fontFamily
          fontSize: Style.font.caption
          options: root.tabs
          value: root.tab
          onChanged: function(v) { root.tab = v }
        }

        PanelSeparator { foreground: root.foreground }

        // ---------- Analysis ----------
        // Each tab is sized to fit without scrolling; the Flickable is only a
        // fallback for a very small screen or many suggestions. It gets
        // whatever the panel's height limit leaves after the header and footer.
        Flickable {
          id: flick
          readonly property real chrome: {
            var h = 0, n = 0
            for (var i = 0; i < column.children.length; i++) {
              var c = column.children[i]
              if (!c.visible) continue
              n++
              if (c !== flick) h += c.height
            }
            return h + column.spacing * Math.max(0, n - 1)
          }
          width: parent.width
          height: Math.min(body.implicitHeight, Math.max(Style.space(200), root.maxHeight - chrome))
          contentWidth: width
          contentHeight: body.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          interactive: contentHeight > height
          ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

          Column {
            id: body
            width: parent.width
            spacing: Style.space(12)
            readonly property real half: (width - Style.space(16)) / 2

            Text {
              visible: root.total === 0
              width: parent.width
              textFormat: Text.PlainText
              wrapMode: Text.Wrap
              text: "No keypresses recorded yet. Click Start and type for a while - "
                    + "the more you type, the better the layout suggestions."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }

            // ================= OVERVIEW =================
            Column {
              visible: root.total > 0 && root.tab === "overview"
              width: parent.width
              spacing: Style.space(12)

              Row {
                width: parent.width
                Kpi {
                  width: parent.width / 4
                  value: Model.grouped(root.hasHistory ? root.report.history.today.keys : root.total)
                  caption: root.hasHistory ? "keys today" : "keys"
                }
                Kpi { width: parent.width / 4; value: root.report.sfb.pct + "%"; caption: "same-finger"; warn: root.report.sfb.pct >= 3 }
                Kpi {
                  width: parent.width / 4
                  value: root.report.history.today.wpm !== null && root.report.history.today.wpm !== undefined
                         ? Math.round(root.report.history.today.wpm) : "-"
                  caption: "wpm today"
                }
                Kpi {
                  width: parent.width / 4
                  value: root.report.timing.tapping_term ? root.report.timing.tapping_term + " ms"
                         : (root.report.timing.hold_median ? root.report.timing.hold_median + " ms" : "-")
                  caption: root.report.timing.tapping_term ? "tapping term" : "median tap"
                }
              }

              // Words per minute over the last two weeks; click for the History tab
              Item {
                readonly property var days: root.report.history.days.slice(-14)
                visible: Model.maxOf(days, "wpm") > 0
                width: parent.width
                height: visible ? Style.space(30) : 0
                SeriesBars {
                  id: spark
                  anchors.left: parent.left
                  anchors.right: sparkLabel.left
                  anchors.rightMargin: Style.space(10)
                  height: parent.height
                  rows: parent.days
                  field: "wpm"
                  hoverable: false
                }
                Text {
                  id: sparkLabel
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: "wpm, 14 days  ›"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: { root.pickedRange = "days"; root.tab = "history" }
                }
              }

              // Comparison with the recording before the last reset
              Rectangle {
                visible: root.compare !== null
                width: parent.width
                height: visible ? cmpText.implicitHeight + Style.space(12) : 0
                radius: Style.cornerRadius
                color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.10)
                border.width: 1
                border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.35)
                Text {
                  id: cmpText
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.margins: Style.space(8)
                  textFormat: Text.PlainText
                  wrapMode: Text.Wrap
                  text: root.compare === null ? "" :
                    "vs previous recording (" + Model.grouped(root.compare.total) + " keys):  "
                    + "same-finger pairs " + root.compare.sfb_pct + "% → " + root.report.sfb.pct
                    + "%  (" + Model.delta(root.compare.sfb_delta) + ")"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }

              // Heatmap: the strongest colour on the keys you press most
              Column {
                id: heat
                visible: root.showHeatmap && root.report.heatmap.length > 0
                width: parent.width
                spacing: Style.space(4)
                readonly property real units: Math.max(1, Model.gridUnits(root.report.heatmap))
                readonly property real unit: width / units

                Column {
                  width: parent.width
                  Repeater {
                    model: heat.visible ? root.report.heatmap : []
                    delegate: Row {
                      id: heatRow
                      required property var modelData
                      Repeater {
                        model: heatRow.modelData
                        delegate: Item {
                          id: cap
                          required property var modelData
                          width: (Number(cap.modelData.w) || 1) * heat.unit
                          height: Style.space(26)
                          Rectangle {
                            anchors.fill: parent
                            anchors.margins: 1.5
                            visible: cap.modelData.label !== ""
                            radius: 4
                            color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b,
                                           0.05 + 0.80 * Number(cap.modelData.heat))
                            border.width: 1
                            border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
                            HoverHandler { id: capHover }
                            Text {
                              anchors.centerIn: parent
                              textFormat: Text.PlainText
                              text: capHover.hovered ? Model.grouped(cap.modelData.count)
                                                     : Model.capName(cap.modelData.label)
                              color: root.foreground
                              font.family: root.fontFamily
                              font.pixelSize: Math.max(8, Style.font.caption - 2)
                              font.bold: Number(cap.modelData.heat) > 0.5
                            }
                          }
                        }
                      }
                    }
                  }
                }
                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  elide: Text.ElideRight
                  text: "Layout: " + root.report.layout.name
                        + (root.report.layout.source === "default" ? "  ·  import yours with 'layout import-vil'" : "")
                        + "  ·  hover a key for its count"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }

              SectionLabel { text: "MOST-PRESSED KEYS" }
              Grid {
                readonly property var keys: root.report.top_keys.slice(0, Math.min(8, root.topKeys))
                width: parent.width
                columns: 2
                rows: Math.ceil(keys.length / 2)
                flow: Grid.TopToBottom
                columnSpacing: Style.space(16)
                rowSpacing: Style.space(2)
                Repeater {
                  model: parent.keys
                  delegate: MeterRow {
                    required property var modelData
                    width: body.half
                    labelWidth: Style.space(64)
                    name: Model.keyName(modelData.label)
                    pct: modelData.pct
                    hideValue: true
                  }
                }
              }

              SectionLabel { text: "HAND BALANCE" }
              StackBar {
                width: parent.width
                parts: [
                  { name: "left",  pct: root.report.hands.left,  color: root.accent },
                  { name: "thumb", pct: root.report.hands.thumb, color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.45) },
                  { name: "right", pct: root.report.hands.right, color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.55) },
                  { name: "other", pct: root.report.hands.other || 0, color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18) }
                ]
              }
            }

            // ================= LAYOUT =================
            Column {
              visible: root.total > 0 && root.tab === "layout"
              width: parent.width
              spacing: Style.space(12)

              SectionLabel { text: "FINGER LOAD" }
              Row {
                id: fingerChart
                readonly property real most: Math.max(1, Model.maxOf(root.report.fingers, "pct"))
                width: parent.width
                Repeater {
                  model: root.report.fingers
                  delegate: Column {
                    id: fcol
                    required property var modelData
                    width: fingerChart.width / Math.max(1, root.report.fingers.length)
                    spacing: Style.space(2)
                    Text {
                      anchors.horizontalCenter: parent.horizontalCenter
                      textFormat: Text.PlainText
                      text: Math.round(fcol.modelData.pct) + "%"
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Math.max(8, Style.font.caption - 1)
                    }
                    Item {
                      width: parent.width
                      height: Style.space(56)
                      Rectangle {
                        anchors.bottom: parent.bottom
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width * 0.6
                        height: Math.max(2, parent.height * fcol.modelData.pct / fingerChart.most)
                        radius: 3
                        color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b,
                                       0.35 + 0.65 * fcol.modelData.pct / fingerChart.most)
                      }
                    }
                    Text {
                      anchors.horizontalCenter: parent.horizontalCenter
                      textFormat: Text.PlainText
                      text: Model.fingerShort(fcol.modelData.finger)
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Math.max(8, Style.font.caption - 1)
                    }
                    Text {
                      visible: fcol.modelData.delta !== null && fcol.modelData.delta !== undefined
                      anchors.horizontalCenter: parent.horizontalCenter
                      textFormat: Text.PlainText
                      text: Model.delta(fcol.modelData.delta)
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Math.max(8, Style.font.caption - 2)
                    }
                  }
                }
              }

              SectionLabel { text: "TRIGRAM PATTERNS"; visible: root.report.trigrams.total > 0 }
              StackBar {
                visible: root.report.trigrams.total > 0
                width: parent.width
                parts: [
                  { name: "roll",      pct: root.report.trigrams.kinds.roll || 0,      color: root.accent },
                  { name: "alternate", pct: root.report.trigrams.kinds.alternate || 0, color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.45) },
                  { name: "one-hand",  pct: root.report.trigrams.kinds.onehand || 0,   color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.35) },
                  { name: "redirect",  pct: root.report.trigrams.kinds.redirect || 0,  color: Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, 0.45) },
                  { name: "same-finger", pct: root.report.trigrams.kinds.sfb || 0,     color: Color.urgent }
                ]
              }

              Row {
                width: parent.width
                spacing: Style.space(16)
                Column {
                  width: body.half
                  spacing: Style.space(2)
                  SectionLabel { text: "TOP KEY-PAIRS" }
                  Repeater {
                    model: root.report.top_bigrams.slice(0, root.pairRows)
                    delegate: PairRow {
                      required property var modelData
                      width: body.half
                      name: Model.pairName(modelData.pair)
                      value: modelData.count
                    }
                  }
                }
                Column {
                  width: body.half
                  spacing: Style.space(2)
                  SectionLabel { text: "SAME-FINGER  " + root.report.sfb.pct + "%" }
                  Repeater {
                    model: root.report.sfb.top.slice(0, root.pairRows)
                    delegate: PairRow {
                      required property var modelData
                      width: body.half
                      name: Model.pairName(modelData.pair)
                      value: modelData.count
                      warn: true
                    }
                  }
                }
              }

              Text {
                visible: root.report.sfs.top.length > 0
                width: parent.width
                textFormat: Text.PlainText
                elide: Text.ElideRight
                text: "Same finger, one key between: " + root.report.sfs.pct + "%"
                      + "  ·  " + root.report.sfs.top.slice(0, 3).map(function(r) {
                          return Model.pairName(r.pair) }).join(", ")
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              SectionLabel { text: "TOP SHORTCUTS"; visible: root.report.chords.top.length > 0 }
              Grid {
                readonly property var chords: root.report.chords.top.slice(0, 4)
                visible: chords.length > 0
                width: parent.width
                columns: 2
                rows: Math.ceil(chords.length / 2)
                flow: Grid.TopToBottom
                columnSpacing: Style.space(16)
                rowSpacing: Style.space(2)
                Repeater {
                  model: parent.chords
                  delegate: PairRow {
                    required property var modelData
                    width: body.half
                    name: Model.chordName(modelData.chord)
                    value: modelData.count
                  }
                }
              }
            }

            // ================= TIMING =================
            Column {
              visible: root.total > 0 && root.tab === "timing"
              width: parent.width
              spacing: Style.space(12)

              Text {
                visible: root.report.timing.samples === 0
                width: parent.width
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                text: "No timing yet - it fills in as you type."
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }

              Row {
                visible: root.report.timing.samples > 0
                width: parent.width
                Kpi { width: parent.width / 4; value: root.report.timing.hold_median + " ms"; caption: "median tap" }
                Kpi { width: parent.width / 4; value: root.report.timing.hold_p95 + " ms"; caption: "95% under" }
                Kpi { width: parent.width / 4; value: root.report.timing.roll_pct + "%"; caption: "rolled" }
                Kpi {
                  width: parent.width / 4
                  value: root.report.timing.tapping_term ? root.report.timing.tapping_term + " ms" : "-"
                  caption: root.report.timing.tapping_term ? "tapping term" : "term: type more"
                  strong: !!root.report.timing.tapping_term
                }
              }

              SectionLabel {
                visible: root.report.timing.samples > 0
                text: "HOW LONG YOU HOLD A KEY  (" + Model.grouped(root.report.timing.samples) + " taps)"
              }
              Column {
                id: holdChart
                visible: root.report.timing.samples > 0
                width: parent.width
                spacing: Style.space(2)
                readonly property int maxMs: 400
                readonly property int step: 10
                readonly property var bars: Model.holdBars(root.report.timing.hold_hist, maxMs, step)
                readonly property real most: Math.max(1, Math.max.apply(null, bars))
                readonly property real barW: width / bars.length

                Item {
                  width: parent.width
                  height: Style.space(64)
                  Row {
                    anchors.bottom: parent.bottom
                    Repeater {
                      model: holdChart.bars
                      delegate: Item {
                        id: hbar
                        required property var modelData
                        required property int index
                        width: holdChart.barW
                        height: Style.space(64)
                        Rectangle {
                          anchors.bottom: parent.bottom
                          anchors.horizontalCenter: parent.horizontalCenter
                          width: Math.max(1, parent.width - 1)
                          height: hbar.modelData > 0 ? Math.max(2, parent.height * hbar.modelData / holdChart.most) : 0
                          radius: 1
                          color: root.report.timing.tapping_term
                                 && hbar.index * holdChart.step >= root.report.timing.tapping_term
                                 ? Color.urgent : root.accent
                        }
                      }
                    }
                  }
                  // TAPPING_TERM marker: a tap slower than this turns into a hold
                  Rectangle {
                    visible: !!root.report.timing.tapping_term
                    x: Math.min(parent.width - 1, holdChart.barW * (root.report.timing.tapping_term || 0) / holdChart.step)
                    width: 1
                    height: parent.height
                    color: root.foreground
                    opacity: 0.6
                  }
                }
                Item {
                  width: parent.width
                  height: axisL.implicitHeight
                  Text { id: axisL; text: "0"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
                  Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: (holdChart.maxMs / 2) + " ms"
                    color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption
                  }
                  Text {
                    anchors.right: parent.right
                    text: holdChart.maxMs + "+ ms"
                    color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption
                  }
                }
              }

              Text {
                visible: !!root.report.timing.overlap_median
                width: parent.width
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                text: "When you roll, both keys are down for " + root.report.timing.overlap_median
                      + " ms (median)" + (root.report.timing.tapping_term
                      ? ".  The line marks the suggested TAPPING_TERM." : ".")
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              SectionLabel { text: "HOME-ROW HOLDS (slowest first)"; visible: root.report.timing.home_holds.length > 0 }
              Flow {
                visible: root.report.timing.home_holds.length > 0
                width: parent.width
                spacing: Style.space(6)
                Repeater {
                  model: root.report.timing.home_holds
                  delegate: Rectangle {
                    id: chip
                    required property var modelData
                    width: chipText.implicitWidth + Style.space(12)
                    height: chipText.implicitHeight + Style.space(6)
                    radius: Style.cornerRadius
                    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
                    Text {
                      id: chipText
                      anchors.centerIn: parent
                      textFormat: Text.PlainText
                      text: Model.keyName(chip.modelData.label) + "  " + chip.modelData.ms + " ms"
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }
                }
              }
            }

            // ================= TIPS =================
            Column {
              visible: root.total > 0 && root.tab === "tips"
              width: parent.width
              spacing: Style.space(10)

              Text {
                visible: root.report.suggestions.length === 0
                width: parent.width
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                text: "No suggestions yet - they appear once there is enough typing to judge."
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }

              SectionLabel { text: "QMK SUGGESTIONS"; visible: root.report.suggestions.length > 0 }
              Repeater {
                model: root.report.suggestions
                delegate: Row {
                  required property var modelData
                  width: body.width
                  spacing: Style.space(6)
                  Text {
                    text: "•"
                    color: root.accent
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                  }
                  Text {
                    width: body.width - Style.space(16)
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                    text: modelData
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }
              }
            }

            // ================= HISTORY =================
            Column {
              id: historyTab
              visible: root.total > 0 && root.tab === "history"
              width: parent.width
              spacing: Style.space(12)
              property int hovered: -1
              readonly property real mostWpm: Math.max(1, Model.maxOf(root.series, "wpm"))
              readonly property real mostKeys: Math.max(1, Model.maxOf(root.series, "keys"))
              readonly property var shown: hovered >= 0 && hovered < root.series.length
                                           ? root.series[hovered] : null

              ButtonGroup {
                focusable: false
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                fontSize: Style.font.caption
                options: Model.HISTORY_RANGES
                value: root.range
                onChanged: function(v) { root.pickedRange = v; historyTab.hovered = -1 }
              }

              Row {
                width: parent.width
                Kpi { width: parent.width / 4; value: Model.grouped(root.rangeSummary.keys || 0); caption: "keys" }
                Kpi { width: parent.width / 4; value: Model.duration(root.rangeSummary.active_min); caption: "typing" }
                Kpi {
                  width: parent.width / 4
                  value: root.rangeSummary.wpm ? Math.round(root.rangeSummary.wpm) : "-"
                  caption: "avg wpm"
                }
                Kpi {
                  width: parent.width / 4
                  value: root.rangeSummary.peak_wpm ? Math.round(root.rangeSummary.peak_wpm) : "-"
                  caption: "best wpm"
                  strong: !!root.rangeSummary.peak_wpm
                }
              }

              Text {
                visible: (root.rangeSummary.keys || 0) === 0
                width: parent.width
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                text: !root.hasHistory
                      ? "History starts with version 1.2 - "
                        + (root.recording ? "it fills in as you type." : "press Start to begin recording it.")
                      : root.range === "session" && !root.recording
                      ? "Not recording - the session starts when you press Start."
                      : "No typing recorded in this period yet."
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }

              Column {
                visible: (root.rangeSummary.keys || 0) > 0
                width: parent.width
                spacing: Style.space(4)

                SectionLabel { text: "WORDS PER MINUTE" }
                SeriesBars {
                  width: parent.width
                  height: Style.space(72)
                  field: "wpm"
                  most: historyTab.mostWpm
                  barColor: root.accent
                }

                SectionLabel { text: "KEYPRESSES" }
                SeriesBars {
                  width: parent.width
                  height: Style.space(40)
                  field: "keys"
                  most: historyTab.mostKeys
                  barColor: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.45)
                }

                Item {
                  width: parent.width
                  height: axisFirst.implicitHeight
                  Text {
                    id: axisFirst
                    text: root.series.length ? root.series[0].label : ""
                    color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption
                  }
                  Text {
                    visible: root.series.length > 2
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.series.length > 2 ? root.series[Math.floor(root.series.length / 2)].label : ""
                    color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption
                  }
                  Text {
                    visible: root.series.length > 1
                    anchors.right: parent.right
                    text: root.series.length > 1 ? root.series[root.series.length - 1].label : ""
                    color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption
                  }
                }

                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  elide: Text.ElideRight
                  text: historyTab.shown === null
                        ? "Hover a bar for details  ·  pauses over 1.5 s don't count"
                        : historyTab.shown.label + ":  " + Model.grouped(historyTab.shown.keys) + " keys  ·  "
                          + Model.duration(historyTab.shown.active_min) + " typing  ·  "
                          + (historyTab.shown.wpm !== null ? Math.round(historyTab.shown.wpm) + " wpm" : "too little to measure")
                  color: historyTab.shown === null ? root.dim : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
            }
          }
        }

        PanelSeparator { foreground: root.foreground }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          horizontalAlignment: Text.AlignHCenter
          text: "1-5 tabs   S " + (root.recording ? "stop" : "record") + "   R refresh   X reset   Esc close"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }

  // ---- small reusable pieces ----------------------------------------------

  component SectionLabel: Text {
    width: parent ? parent.width : 0
    textFormat: Text.PlainText
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    font.bold: true
    font.letterSpacing: 1.2
    topPadding: Style.space(2)
  }

  // A labelled meter: name on the left, a proportional bar, and the count/pct.
  component MeterRow: Item {
    id: meter
    property string name: ""
    property real pct: 0
    property int value: 0
    property bool hideValue: false
    property string extra: ""
    property real labelWidth: Style.space(96)
    implicitHeight: Math.max(label.implicitHeight, Style.space(18))

    Text {
      id: label
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: meter.labelWidth
      elide: Text.ElideRight
      textFormat: Text.PlainText
      text: meter.name
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
    Rectangle {
      id: track
      anchors.left: label.right
      anchors.right: amount.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      height: Style.space(8)
      radius: height / 2
      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
      Rectangle {
        height: parent.height
        radius: parent.radius
        width: Math.max(2, parent.width * Math.min(1, meter.pct / 100.0))
        color: root.accent
      }
    }
    Text {
      id: amount
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      width: meter.extra !== "" ? Style.space(116) : (meter.hideValue ? Style.space(44) : Style.space(78))
      horizontalAlignment: Text.AlignRight
      textFormat: Text.PlainText
      text: (meter.hideValue ? (meter.pct + "%")
                             : (Model.grouped(meter.value) + "  " + meter.pct + "%"))
            + (meter.extra !== "" ? "  (" + meter.extra + ")" : "")
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  // A key-pair line: the transition on the left, its count on the right.
  component PairRow: Item {
    id: pr
    property string name: ""
    property int value: 0
    property bool warn: false
    implicitHeight: Math.max(pairLabel.implicitHeight, Style.space(18))

    Text {
      id: pairLabel
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: pr.name
      color: pr.warn ? Color.urgent : root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
    Text {
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: Model.grouped(pr.value)
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  // A name on the left and a value on the right.
  component StatRow: Item {
    id: stat
    property string name: ""
    property string value: ""
    property bool strong: false
    width: parent ? parent.width : 0
    implicitHeight: visible ? Math.max(statName.implicitHeight, Style.space(18)) : 0

    Text {
      id: statName
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: stat.name
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
    Text {
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: stat.value
      color: stat.strong ? root.accent : root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: stat.strong
    }
  }

  // A big number over a small caption, for the summary row.
  component Kpi: Column {
    id: kpi
    property string value: ""
    property string caption: ""
    property bool warn: false
    property bool strong: false
    spacing: 0
    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      textFormat: Text.PlainText
      text: kpi.value
      color: kpi.warn ? Color.urgent : (kpi.strong ? root.accent : root.foreground)
      font.family: root.fontFamily
      font.pixelSize: Style.font.title
      font.bold: true
    }
    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      elide: Text.ElideRight
      textFormat: Text.PlainText
      text: kpi.caption
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  // One bar split into coloured parts ({name, pct, color}) with a legend.
  component StackBar: Column {
    id: stack
    property var parts: []
    readonly property real sum: {
      var t = 0
      for (var i = 0; i < parts.length; i++) t += Math.max(0, Number(parts[i].pct) || 0)
      return Math.max(1, t)
    }
    spacing: Style.space(4)
    Rectangle {
      width: parent.width
      height: Style.space(10)
      radius: height / 2
      clip: true
      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
      Row {
        anchors.fill: parent
        Repeater {
          model: stack.parts
          delegate: Rectangle {
            required property var modelData
            width: stack.width * Math.max(0, Number(modelData.pct) || 0) / stack.sum
            height: parent.height
            color: modelData.color
          }
        }
      }
    }
    Flow {
      width: parent.width
      spacing: Style.space(10)
      Repeater {
        model: stack.parts
        delegate: Row {
          required property var modelData
          visible: Number(modelData.pct) > 0
          spacing: Style.space(4)
          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(8); height: width; radius: 2
            color: modelData.color
          }
          Text {
            textFormat: Text.PlainText
            text: modelData.name + " " + modelData.pct + "%"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }

  // One bar per history bucket, scaled to `most`. In the History tab hovering
  // a bar shows its numbers under the charts.
  component SeriesBars: Item {
    id: sb
    property var rows: root.series
    property string field: "keys"
    property real most: Math.max(1, Model.maxOf(rows, field))
    property color barColor: root.accent
    property bool hoverable: true
    Row {
      anchors.fill: parent
      Repeater {
        model: sb.rows
        delegate: Item {
          id: sbar
          required property var modelData
          required property int index
          readonly property real v: Number(modelData[sb.field]) || 0
          width: sb.width / Math.max(1, sb.rows.length)
          height: sb.height
          Rectangle {
            anchors.fill: parent
            anchors.leftMargin: 0.5
            anchors.rightMargin: 0.5
            visible: sb.hoverable && historyTab.hovered === sbar.index
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
          }
          Rectangle {
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.max(1, Math.min(parent.width - 2, Style.space(18)))
            height: sbar.v > 0 ? Math.max(2, parent.height * sbar.v / sb.most) : 1
            radius: 2
            color: sbar.v > 0 ? sb.barColor
                              : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
          }
          HoverHandler {
            enabled: sb.hoverable
            onHoveredChanged: {
              if (hovered) historyTab.hovered = sbar.index
              else if (historyTab.hovered === sbar.index) historyTab.hovered = -1
            }
          }
        }
      }
    }
  }

  // A compact pill button (no PanelActionButton dependency for labelled ones).
  component PillButton: Rectangle {
    id: pill
    property string label: ""
    property string glyph: ""
    property bool emphasised: false
    property bool danger: false
    signal activated()

    implicitWidth: pillRow.implicitWidth + Style.space(20)
    implicitHeight: pillRow.implicitHeight + Style.space(12)
    radius: Style.cornerRadius
    readonly property color base: danger ? Color.urgent : (emphasised ? root.accent : root.foreground)
    color: Qt.rgba(base.r, base.g, base.b, pillHover.hovered ? 0.26 : 0.14)
    border.width: 1
    border.color: Qt.rgba(base.r, base.g, base.b, 0.5)

    HoverHandler { id: pillHover }
    Row {
      id: pillRow
      anchors.centerIn: parent
      spacing: Style.space(6)
      Text {
        visible: pill.glyph !== ""
        text: pill.glyph
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }
      Text {
        text: pill.label
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: pill.activated()
    }
  }
}
