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
// Keys: S start/stop recording, R refresh, X reset (twice to confirm),
// Esc close.
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
  readonly property bool showHeatmap: hostWidget ? hostWidget.setting("showHeatmap", true) !== false : true
  readonly property var compare: report.compare

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property color accent: Color.accent

  property bool confirmReset: false

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

        PanelSeparator { foreground: root.foreground }

        // ---------- Scrollable analysis ----------
        Flickable {
          id: flick
          width: parent.width
          height: Math.min(body.implicitHeight, Style.space(560))
          contentWidth: width
          contentHeight: body.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          interactive: contentHeight > height
          ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

          Column {
            id: body
            width: parent.width
            spacing: Style.space(14)

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

            // Comparison with the recording before the last reset
            Rectangle {
              visible: root.total > 0 && root.compare !== null
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

            // Heatmap
            SectionLabel { text: "HEATMAP"; visible: root.total > 0 && root.showHeatmap }
            Column {
              id: heat
              visible: root.total > 0 && root.showHeatmap && root.report.heatmap.length > 0
              width: parent.width
              readonly property real units: Math.max(1, Model.gridUnits(root.report.heatmap))
              readonly property real unit: width / units

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
                      height: Style.space(24)
                      Rectangle {
                        anchors.fill: parent
                        anchors.margins: 1.5
                        visible: cap.modelData.label !== ""
                        radius: 4
                        color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b,
                                       0.05 + 0.75 * Number(cap.modelData.heat))
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
              visible: heat.visible
              width: parent.width
              textFormat: Text.PlainText
              elide: Text.ElideRight
              text: "Layout: " + root.report.layout.name
                    + (root.report.layout.source === "default" ? "  ·  import yours with 'layout import-vil'" : "")
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            // Top keys
            SectionLabel { text: "MOST-PRESSED KEYS"; visible: root.total > 0 }
            Repeater {
              model: root.total > 0 ? root.report.top_keys.slice(0, root.topKeys) : []
              delegate: MeterRow {
                required property var modelData
                width: body.width
                name: Model.keyName(modelData.label)
                value: modelData.count
                pct: modelData.pct
              }
            }

            // Hand balance
            SectionLabel { text: "HAND BALANCE"; visible: root.total > 0 }
            Column {
              visible: root.total > 0
              width: parent.width
              spacing: Style.space(2)
              MeterRow { width: body.width; name: "left";  pct: root.report.hands.left;  hideValue: true }
              MeterRow { width: body.width; name: "right"; pct: root.report.hands.right; hideValue: true }
              MeterRow { width: body.width; name: "thumb"; pct: root.report.hands.thumb; hideValue: true }
            }

            // Finger load
            SectionLabel { text: "FINGER LOAD"; visible: root.total > 0 }
            Repeater {
              model: root.total > 0 ? root.report.fingers : []
              delegate: MeterRow {
                required property var modelData
                width: body.width
                name: Model.fingerName(modelData.finger)
                pct: modelData.pct
                hideValue: true
                extra: Model.delta(modelData.delta)
              }
            }

            // Top bigrams
            SectionLabel { text: "TOP KEY-PAIRS"; visible: root.report.top_bigrams.length > 0 }
            Repeater {
              model: root.report.top_bigrams.slice(0, root.topBigrams)
              delegate: PairRow {
                required property var modelData
                width: body.width
                name: Model.pairName(modelData.pair)
                value: modelData.count
              }
            }

            // Same-finger bigrams
            SectionLabel {
              text: "SAME-FINGER BIGRAMS  (" + root.report.sfb.pct + "% of pairs)"
              visible: root.report.sfb.top.length > 0
            }
            Text {
              visible: root.report.sfb.top.length > 0
              width: parent.width
              textFormat: Text.PlainText
              wrapMode: Text.Wrap
              text: "Pairs typed with one finger twice - the main thing a good layout reduces."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
            Repeater {
              model: root.report.sfb.top
              delegate: PairRow {
                required property var modelData
                width: body.width
                name: Model.pairName(modelData.pair)
                value: modelData.count
                warn: true
              }
            }

            // Same-finger skipgrams
            Text {
              visible: root.total > 0 && root.report.sfs.top.length > 0
              width: parent.width
              textFormat: Text.PlainText
              wrapMode: Text.Wrap
              text: "Same-finger skipgrams (one key in between): " + root.report.sfs.pct + "%"
                    + (root.report.sfs.top.length > 0
                       ? "  ·  worst: " + root.report.sfs.top.slice(0, 3).map(function(r) {
                           return Model.pairName(r.pair) }).join(", ")
                       : "")
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            // Trigram patterns
            SectionLabel { text: "TRIGRAM PATTERNS"; visible: root.report.trigrams.total > 0 }
            Column {
              visible: root.report.trigrams.total > 0
              width: parent.width
              spacing: Style.space(2)
              MeterRow { width: body.width; name: "alternate"; pct: root.report.trigrams.kinds.alternate || 0; hideValue: true }
              MeterRow { width: body.width; name: "roll";      pct: root.report.trigrams.kinds.roll || 0;      hideValue: true }
              MeterRow { width: body.width; name: "one-hand";  pct: root.report.trigrams.kinds.onehand || 0;   hideValue: true }
              MeterRow { width: body.width; name: "redirect";  pct: root.report.trigrams.kinds.redirect || 0;  hideValue: true }
              MeterRow { width: body.width; name: "same-finger"; pct: root.report.trigrams.kinds.sfb || 0;     hideValue: true }
            }

            // Shortcuts
            SectionLabel { text: "TOP SHORTCUTS"; visible: root.report.chords.top.length > 0 }
            Repeater {
              model: root.report.chords.top.slice(0, 6)
              delegate: PairRow {
                required property var modelData
                width: body.width
                name: Model.chordName(modelData.chord)
                value: modelData.count
              }
            }

            // Timing, for home-row mods
            SectionLabel { text: "TIMING (HOME-ROW MODS)"; visible: root.report.timing.samples > 0 }
            Column {
              visible: root.report.timing.samples > 0
              width: parent.width
              spacing: Style.space(2)
              StatRow { name: "median tap";   value: root.report.timing.hold_median + " ms" }
              StatRow { name: "95% of taps under"; value: root.report.timing.hold_p95 + " ms" }
              StatRow { name: "rolled keypresses"; value: root.report.timing.roll_pct + "%" }
              StatRow {
                visible: !!root.report.timing.overlap_median
                name: "median roll overlap"; value: root.report.timing.overlap_median + " ms"
              }
              StatRow {
                name: "suggested TAPPING_TERM"
                value: root.report.timing.tapping_term
                       ? root.report.timing.tapping_term + " ms"
                       : "needs more typing"
                strong: !!root.report.timing.tapping_term
              }
            }

            // Suggestions
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
        }

        PanelSeparator { foreground: root.foreground }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          horizontalAlignment: Text.AlignHCenter
          text: "S " + (root.recording ? "stop" : "record") + "   R refresh   X reset   Esc close"
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
    implicitHeight: Math.max(label.implicitHeight, Style.space(18))

    Text {
      id: label
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(96)
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
      width: meter.extra !== "" ? Style.space(116) : Style.space(78)
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
