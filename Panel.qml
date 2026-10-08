import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Popup view for omakeylog. The bar widget (hostWidget) owns the data and the
// actions; this file only renders what the engine computed into report.json:
// ranked keys, hand and finger load, same-finger bigrams and QMK suggestions.
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
  readonly property int total: hostWidget ? hostWidget.total : 0
  readonly property int distinct: hostWidget ? hostWidget.distinct : 0
  readonly property string errorMsg: hostWidget ? hostWidget.errorMsg : ""
  readonly property var report: hostWidget ? hostWidget.report : Model.EMPTY_REPORT

  readonly property int topKeys: hostWidget ? Math.max(5, Number(hostWidget.setting("topKeys", 12))) : 12
  readonly property int topBigrams: hostWidget ? Math.max(5, Number(hostWidget.setting("topBigrams", 10))) : 10

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property color accent: Color.accent

  property bool confirmReset: false

  readonly property string heroMeta: {
    if (errorMsg !== "") return "Not recording"
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
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(600))

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
          height: Math.min(body.implicitHeight, Style.space(430))
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
      width: Style.space(78)
      horizontalAlignment: Text.AlignRight
      textFormat: Text.PlainText
      text: meter.hideValue ? (meter.pct + "%")
                            : (Model.grouped(meter.value) + "  " + meter.pct + "%")
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
