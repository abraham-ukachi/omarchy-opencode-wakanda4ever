/* 
* @license MIT
* ~~~~~~~~~~~~
* omarchy-opencode-wakanda4ever
* ~~~~~~~~~~~~
* Copyright (c) 2026 Abraham Ukachi. The Wakanda4Ever Project.
*
* Permission is hereby granted, free of charge, to any person obtaining a copy
* of this software and associated documentation files (the 'Software'), to deal
* in the Software without restriction, including without limitation the rights
* to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
* copies of the Software, and to permit persons to whom the Software is
* furnished to do so, subject to the following conditions:
*
* The above copyright notice and this permission notice shall be included in all
* copies or substantial portions of the Software.
*
* THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
* IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
* FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
* AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
* LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
* OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
* SOFTWARE.
*
* @project: omarchy-opencode-wakanda4ever
* @name: Wakanda4Ever - Conversation Dashboard - Panel
* @file: Main.qml
* @type: QML
* @authors: Abraham Ukachi <abrahamukachi@gmail.com>
*
* Example usage:
*   1+|> omarchy plugin add https://github.com/abraham-ukachi/omarchy-opencode-wakanda4ever --enable
*    -|>
*
*/


/*
* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
* MOTTO: We'll always do more 😜!!!
* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
*/


// ======<<< QML IMPORTS >>>======

// Qt Quick - base primitives (Rectangle, Text, MouseArea, ...)
import QtQuick
// Qt Quick - Layouts (RowLayout, ColumnLayout, ...)
import QtQuick.Layouts
// Quickshell - core (Panel, Process, env, ...)
import Quickshell
// Quickshell - IO (StdioCollector, ...)
import Quickshell.Io
// Quickshell - Wayland (WlrLayer, WlrLayershell, WlrKeyboardFocus, ...)
import Quickshell.Wayland
// Omarchy - commons (Color, Style, ...)
import qs.Commons
// Omarchy - UI (Panel, PanelWindow, ...)
import qs.Ui


// ======<<< Wakanda4Ever - Panel >>>======
Panel {
  id: root
  moduleName: "Wakanda4Ever"
  ipcTarget: "Wakanda4Ever"

  // path to the `collect.py` python script (same folder as this qml file)
  readonly property string collectPath: Quickshell.env("HOME") + "/.config/omarchy/plugins/wakanda4ever/collect.py"
  // how often (in seconds) the dashboard refreshes its live data
  readonly property int refreshSec: 60

  // Define the dashboard palette colors (borrowed from the omarchy `Color` & `Style` singletons)
  readonly property color fg: Color.popups.text
  readonly property color muted: Color.muted
  readonly property color accent: Color.accent
  readonly property color urgent: Color.urgent
  readonly property color surface: Color.popups.background
  readonly property color chrome: Color.popups.border
  // reference to the omarchy default font family
  readonly property string fontFamily: Style.font.family

  // Define the live dashboard data (filled in by `applyData`)
  property int daily: 0
  property int weekly: 0
  property int monthly: 0
  property int total: 0
  property var sessions: []
  property var files: []
  property var diskInfo: ({})


  // ======<<< UTILITY HELPERS >>>======

  // clamp a value between `lo` and `hi`
  function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }
  // tint a color with an alpha (opacity) factor
  function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

  // turn a number into a compact `1k / 1M / 1B` style string
  function compact(n) {
    n = Number(n) || 0
    var abs = Math.abs(n)
    var s
    if (abs >= 1e9) s = (n / 1e9).toFixed(1).replace(/\.0$/, "") + "B"
    else if (abs >= 1e6) s = (n / 1e6).toFixed(1).replace(/\.0$/, "") + "M"
    else if (abs >= 1e3) s = (n / 1e3).toFixed(1).replace(/\.0$/, "") + "k"
    else s = String(Math.round(abs))
    return n < 0 ? "-" + s : s
  }

  // turn a raw byte count into a human readable `KB / MB / GB` string
  function humanBytes(raw) {
    var n = Number(raw)
    if (!isFinite(n) || n < 0) return "–"
    var units = ["B", "KB", "MB", "GB", "TB"]
    var i = 0
    while (n >= 1024 && i < units.length - 1) { n /= 1024; i++ }
    return (i === 0 ? String(n) : n.toFixed(1)) + " " + units[i]
  }

  // get the session object at index `i` (or `null` when out of range)
  function sessionAt(i) { return root.sessions.length > i ? root.sessions[i] : null }
  // get the file (meter) object at index `i` (or `null` when out of range)
  function fileAt(i) { return root.files.length > i ? root.files[i] : null }

  // compute a log-scaled fill ratio (0..1) for a file's memory meter
  function fileMeterFill(f) {
    var b = Number(f && f.bytes) || 0
    var l = Number(f && f.limit) || 0
    if (l <= 0) return 0
    var fb = Math.log(1 + b) / Math.LN10
    var fl = Math.log(1 + l) / Math.LN10
    return clamp(fl > 0 ? fb / fl : 0, 0, 1)
  }

  // compute a percentage text (e.g. `42%`, `<1%`) for a file's memory meter
  function filePctText(f) {
    var l = Number(f && f.limit) || 0
    if (l <= 0) return "0%"
    var p = (Number(f && f.bytes) || 0) / l * 100
    if (p >= 10) return Math.round(p) + "%"
    if (p >= 1) return p.toFixed(1) + "%"
    if (p > 0) return "<1%"
    return "0%"
  }

  // close the dashboard (only when it's currently open)
  function ensureClosed() {
    if (root.opened) root.close()
  }


  // ======<<< LIVE DATA COLLECTION >>>======

  // refresh the dashboard data every `refreshSec` seconds while it's open
  Timer {
    id: refreshTimer
    interval: root.refreshSec * 1000
    running: root.opened
    repeat: true
    triggeredOnStart: true
    onTriggered: root.run()
  }

  // spawn `collect.py` to gather the opencode conversation data as JSON
  Process {
    id: collect
    command: ["python3", root.collectPath]
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyData(text)
    }
  }

  // start a collection run (only when one isn't already running)
  function run() {
    if (!collect.running) collect.running = true
  }

  // parse the JSON payload coming from `collect.py` & store it on the root
  function applyData(raw) {
    try {
      var j = JSON.parse(raw || "{}")
      var s = j.stats || {}
      daily = Number(s.daily) || 0
      weekly = Number(s.weekly) || 0
      monthly = Number(s.monthly) || 0
      total = Number(s.total) || 0
      sessions = Array.isArray(j.sessions) ? j.sessions : []
      files = Array.isArray(j.files) ? j.files : []
      diskInfo = j.disk || {}
    } catch (e) {
      // NOTE: log a warning (without crashing the dashboard) when the JSON is unexpected
      console.warn("Wakanda4Ever: bad collector output", e)
    }
  }


  // ======<<< SESSION ROW - COMPONENT >>>======
  // A single row in the `RECENT SESSIONS` list: rank + title + timestamp
  component SessionRow: RowLayout {
    required property var modelData
    required property int position
    spacing: Style.space(10)

    // `01`, `02`, `03` - rank badge (accent colored for the newest session)
    Text {
      text: ("0" + (position + 1)).slice(-2)
      width: Style.space(24)
      color: position === 0 ? root.accent : root.alpha(root.muted, 0.55)
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.weight: Font.DemiBold
      Layout.alignment: Qt.AlignVCenter
    }

    // session content: title line + timestamp line
    Column {
      Layout.fillWidth: true
      spacing: Style.space(3)

      // -------- Title line (the session title) --------
      Text {
        width: parent.width
        text: modelData && modelData.title ? modelData.title : "—"
        color: root.fg
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.weight: Font.Medium
        elide: Text.ElideRight
      }

      // -------- Timestamp line (date + time) --------
      Text {
        width: parent.width
        text: modelData && modelData.date ? modelData.date : ""
        color: root.muted
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }
  }


  // ======<<< METER ROW - COMPONENT >>>======
  // A single row in the `MEMORY FOOTPRINT` list: label + size + animated meter
  component MeterRow: Column {
    required property var modelData
    spacing: Style.space(5)
    Layout.fillWidth: true

    // the log-scaled fill ratio of this meter
    readonly property real fill: root.fileMeterFill(modelData)

    // -------- Label + size + percentage --------
    RowLayout {
      width: parent.width
      spacing: Style.space(8)

      // meter label (e.g. `conversation log`)
      Text {
        text: modelData && modelData.label ? modelData.label : "—"
        color: root.fg
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        Layout.alignment: Qt.AlignVCenter
      }
      // current size vs. bounding limit
      Text {
        text: modelData ? root.humanBytes(modelData.bytes) + " of " + root.humanBytes(modelData.limit) : ""
        color: root.muted
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter
      }
      // the percentage text (accent when something is stored)
      Text {
        text: root.filePctText(modelData)
        color: modelData && Number(modelData.bytes) > 0 ? root.fg : root.muted
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.weight: Font.DemiBold
        Layout.alignment: Qt.AlignVCenter
      }
    }

    // -------- The animated meter track --------
    Item {
      width: parent.width
      height: Style.space(5)

      // the (empty) track
      Rectangle {
        anchors.fill: parent
        radius: parent.height / 2
        color: root.alpha(root.fg, 0.08)
      }

      // the accent fill (only appears when there's something stored)
      Rectangle {
        readonly property bool hasBytes: modelData && Number(modelData.bytes) > 0
        width: hasBytes ? Math.max(parent.width * fill, Style.space(4)) : 0
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        radius: parent.height / 2
        color: modelData && Number(modelData.bytes) > 0 ? root.accent : root.alpha(root.fg, 0.08)
        Behavior on width {
          NumberAnimation { duration: 450; easing.type: Easing.OutCubic }
        }
      }
    }
  }


  // ======<<< THE DASHBOARD OVERLAY WINDOW >>>======

  PanelWindow {
    id: window
    visible: root.opened
    // stretch the overlay across the entire screen
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "wakanda4ever-dashboard"
    WlrLayershell.layer: WlrLayer.Overlay
    // NOTE: do not steal keyboard focus from the bar/apps
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    // auto-close the dashboard whenever the window gets hidden
    onVisibleChanged: {
      if (!visible) Qt.callLater(root.ensureClosed)
    }

    // -------- Click-outside catcher (closes the dashboard) --------
    MouseArea {
      id: outsideCatcher
      anchors.fill: parent
      onClicked: root.ensureClosed()
    }

    // -------- The dashboard card (top-right, below the bar) --------
    Rectangle {
      id: card
      width: 500
      height: 560
      radius: Math.max(Style.cornerRadius, 10)
      color: root.surface
      border.color: root.alpha(root.chrome, 0.5)
      border.width: 1
      clip: true
      anchors.top: parent.top
      anchors.right: parent.right
      anchors.topMargin: Style.bar.sizeHorizontal + Style.space(14)
      anchors.rightMargin: Style.space(12)

      // swallow clicks inside the card (so it doesn't close while interacting)
      MouseArea {
        anchors.fill: parent
        onClicked: { }
      }

      // a thin accent strip along the top of the card
      Rectangle {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: Style.space(4)
        color: root.accent
      }

      // -------- Card content column --------
      ColumnLayout {
        id: body
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.topMargin: Style.space(20)
        anchors.bottomMargin: Style.space(18)
        anchors.leftMargin: Style.space(20)
        anchors.rightMargin: Style.space(20)
        spacing: Style.space(12)

        // WAKANDA4EVER - letter-spaced brand title
        Text {
          text: "W A K A N D A 4 E V E R"
          color: root.fg
          font.family: root.fontFamily
          font.pixelSize: Style.font.subtitle
          font.weight: Font.DemiBold
          font.letterSpacing: Style.space(3)
        }
        // brand subtitle
        Text {
          text: "persistent conversation dashboard"
          color: root.muted
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.letterSpacing: Style.space(1)
        }

        // -------- A little breathing room --------
        Item { width: 1; height: Style.space(14) }

        // -------- HERO - total prompt count (big & centered) --------
        Column {
          Layout.fillWidth: true
          spacing: Style.space(4)

          // the big compact number (e.g. `1.2k`)
          Text {
            text: root.total > 0 ? root.compact(root.total) : "0"
            anchors.horizontalCenter: parent.horizontalCenter
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.displayLarge
            font.weight: Font.DemiBold
          }
          // `PROMPT` / `PROMPTS` caption below the count (singular when it's 1)
          Text {
            text: root.total === 1 ? "PROMPT" : "PROMPTS"
            anchors.horizontalCenter: parent.horizontalCenter
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.weight: Font.DemiBold
            font.letterSpacing: Style.space(2)
          }
        }

        // -------- Flexible spacer --------
        Item {
          width: 1
          Layout.fillHeight: true
        }

        // -------- Chapter divider --------
        Rectangle {
          Layout.fillWidth: true
          height: 1
          color: root.alpha(root.chrome, 0.35)
        }

        // -------- RECENT SESSIONS - section header --------
        RowLayout {
          Layout.fillWidth: true
          Text {
            text: "RECENT SESSIONS"
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.weight: Font.DemiBold
            font.letterSpacing: Style.space(2)
          }
          Item { Layout.fillWidth: true }
          Text {
            text: "latest 3"
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        // the latest 3 sessions (sorted by most recent activity)
        SessionRow {
          Layout.fillWidth: true
          position: 0
          modelData: root.sessionAt(0)
          visible: !!modelData
        }
        SessionRow {
          Layout.fillWidth: true
          position: 1
          modelData: root.sessionAt(1)
          visible: !!modelData
        }
        SessionRow {
          Layout.fillWidth: true
          position: 2
          modelData: root.sessionAt(2)
          visible: !!modelData
        }

        // friendly empty-state placeholder (when there are no sessions yet)
        ColumnLayout {
          visible: root.sessions.length === 0
          Layout.fillWidth: true
          Text {
            text: "Your latest sessions will appear here."
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }

        // -------- Flexible spacer --------
        Item {
          width: 1
          Layout.fillHeight: true
        }

        // -------- Chapter divider --------
        Rectangle {
          Layout.fillWidth: true
          height: 1
          color: root.alpha(root.chrome, 0.35)
        }

        // -------- MEMORY FOOTPRINT - section header --------
        RowLayout {
          Layout.fillWidth: true
          Text {
            text: "MEMORY FOOTPRINT"
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.weight: Font.DemiBold
            font.letterSpacing: Style.space(2)
          }
          Item { Layout.fillWidth: true }
          Text {
            text: "log-scaled · bounded by free space"
            color: root.alpha(root.muted, 0.7)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        // the memory meter rows (conversation log, user memory, opencode database)
        MeterRow {
          Layout.fillWidth: true
          modelData: root.fileAt(0)
          visible: !!modelData
        }
        MeterRow {
          Layout.fillWidth: true
          modelData: root.fileAt(1)
          visible: !!modelData
        }
        MeterRow {
          Layout.fillWidth: true
          modelData: root.fileAt(2)
          visible: !!modelData
        }

        // -------- DISK - section header --------
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(8)

          Text {
            text: "DISK"
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.weight: Font.DemiBold
            font.letterSpacing: Style.space(2)
            Layout.alignment: Qt.AlignVCenter
          }
          Item { Layout.fillWidth: true }
          // free space (accent-colored, right aligned)
          Text {
            text: root.diskInfo && root.diskInfo.free ? root.humanBytes(root.diskInfo.free) + " free" : "—"
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            Layout.alignment: Qt.AlignVCenter
          }
          // total space (muted)
          Text {
            text: root.diskInfo && root.diskInfo.total ? "of " + root.humanBytes(root.diskInfo.total) : ""
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            Layout.alignment: Qt.AlignVCenter
          }
        }

        // -------- Footer --------
        RowLayout {
          Layout.fillWidth: true
          Text {
            text: "updated live · click outside to close"
            color: root.alpha(root.muted, 0.7)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
          Item { Layout.fillWidth: true }
          Text {
            text: "forever."
            color: root.alpha(root.accent, 0.7)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.weight: Font.DemiBold
          }
        }
      }

      // -------- Refresh button (top-right of the card) --------
      // Re-runs the collector on click, so the prompt total, the recent
      // sessions and the memory footprint are always current & displayed.
      Item {
        id: refreshButton
        width: Style.space(28)
        height: Style.space(28)
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: Style.space(10)
        anchors.rightMargin: Style.space(12)

        // the (accent tinted) hover/press pill behind the glyph
        Rectangle {
          anchors.fill: parent
          radius: parent.height / 2
          color: refreshMouse.hovered || refreshMouse.pressed || collect.running
            ? root.alpha(root.accent, 0.14)
            : root.alpha(root.fg, 0.06)
          Behavior on color {
            ColorAnimation { duration: 150; easing.type: Easing.OutCubic }
          }
        }

        // the refresh glyph (spins while a refresh is in flight)
        Text {
          id: refreshGlyph
          anchors.centerIn: parent
          text: "\uF021"
          color: refreshMouse.hovered || refreshMouse.pressed || collect.running
            ? root.accent : root.muted
          font.family: root.fontFamily
          font.pixelSize: Style.font.icon
          font.weight: Font.DemiBold
          renderType: Text.NativeRendering
          transformOrigin: Item.Center

          // keep the glyph spinning for as long as the collector runs
          property bool spinning: collect.running
          onSpinningChanged: {
            if (spinning) { rotation = 0; spin.restart() }
            else { spin.stop(); rotation = 0 }
          }
        }

        // the infinite right-turn animation (restarted by `refreshGlyph`)
        NumberAnimation {
          id: spin
          target: refreshGlyph
          property: "rotation"
          from: 0
          to: 360
          duration: 900
          easing.type: Easing.Linear
          loops: Animation.Infinite
        }

        MouseArea {
          id: refreshMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          // NOTE: re-runs the collector (a no-op while one is already running)
          onClicked: root.run()
        }
      }
    }
  }
}