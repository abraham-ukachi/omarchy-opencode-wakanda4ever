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
* @name: Wakanda4Ever - AgentMemory Dashboard - Bar Widget
* @file: BarWidget.qml
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

// Qt Quick - base primitives
import QtQuick
// Quickshell - core (Quickshell.env, ...)
import Quickshell
// Quickshell - IO (Process, StdioCollector, ...)
import Quickshell.Io
// Omarchy - commons
import qs.Commons
// Omarchy - UI (the `BarWidget` & `BarIconButton` base components)
import qs.Ui


// ======<<< Wakanda4Ever - Bar Widget >>>======
BarWidget {
  id: root
  moduleName: "wakanda4ever"

  // the user's home directory (anchor for the allowlisted child environment)
  readonly property string home: Quickshell.env("HOME")
  // path to the `collect.py` status probe (same folder as this qml file)
  readonly property string collectPath: root.home + "/.config/omarchy/plugins/wakanda4ever/collect.py"
  // trusted absolute interpreter (never PATH-resolved)
  readonly property string pythonPath: "/usr/bin/python3"
  // how often (in seconds) the tiny daemon health probe re-runs
  readonly property int probeSec: 60

  // whether the dashboard is currently open (used to highlight the button)
  property bool highlighted: false
  // the latest AgentMemory daemon state (from `collect.py --status`)
  property bool statusKnown: false
  property bool memoryOnline: false
  property string memoryStatus: ""
  property string memoryVersion: ""

  // size the widget to the underlying icon button
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // refresh the highlighted state from the shell's plugin registry
  function syncState() {
    if (root.bar && root.bar.shell && root.bar.shell.isPluginOpen)
      highlighted = root.bar.shell.isPluginOpen(root.moduleName) === true
  }

  // toggle the Wakanda4Ever dashboard panel
  function toggle() {
    if (root.bar && root.bar.shell && root.bar.shell.toggle)
      root.bar.shell.toggle(root.moduleName, "{}")
    else if (root.bar && root.bar.run)
      root.bar.run("omarchy-shell shell toggle " + root.moduleName)
    Qt.callLater(root.syncState)
    Qt.callLater(root.checkStatus)
  }

  // the short label used in the tooltip
  function statusText() {
    if (!root.statusKnown) return "checking agentmemory"
    if (!root.memoryOnline) return "agentmemory offline"
    var s = String(root.memoryStatus || "").toLowerCase()
    if (s === "warn" || s === "warning") return "agentmemory needs attention"
    if (s === "error" || s === "degraded" || s === "unhealthy") return "agentmemory degraded"
    return "agentmemory healthy"
  }

  // the dot color that matches the daemon state
  function statusColor() {
    if (!root.memoryOnline) return Color.muted
    var s = String(root.memoryStatus || "").toLowerCase()
    if (s === "warn" || s === "warning" || s === "error" ||
        s === "degraded" || s === "unhealthy")
      return Color.urgent
    return Color.accent
  }

  // run the lightweight health probe (one tiny JSON line, no SQLite/disk work)
  function checkStatus() {
    if (!probe.running) probe.running = true
  }

  // parse the probe's JSON output
  function applyStatus(raw) {
    try {
      var j = JSON.parse(raw || "{}")
      root.memoryOnline = j.online === true
      root.memoryStatus = String(
        j.status || (root.memoryOnline ? "healthy" : "offline")).toLowerCase()
      root.memoryVersion = String(j.version || "")
      root.statusKnown = true
    } catch (e) {
      // NOTE: a broken probe must never take the bar down with it
      root.statusKnown = false
    }
  }

  // keep the highlight in sync while visible (cheap enough at 400ms)
  Timer {
    interval: 400
    running: root.visible
    repeat: true
    triggeredOnStart: true
    onTriggered: root.syncState()
  }

  // poll the daemon health quietly in the background
  Timer {
    interval: root.probeSec * 1000
    running: root.visible
    repeat: true
    triggeredOnStart: true
    onTriggered: root.checkStatus()
  }

  // the (tiny) health probe process
  Process {
    id: probe
    command: [root.pythonPath, root.collectPath, "--status"]
    running: false
    clearEnvironment: true
    environment: ({ HOME: root.home })
    stdout: StdioCollector {
      onStreamFinished: root.applyStatus(text)
    }
  }

  // the icon button that toggles the dashboard on click
  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\uf086"
    tooltipText: "Wakanda4Ever — " + root.statusText()
    active: root.highlighted
    useActiveColor: true
    onPressed: function(mouse) {
      root.toggle()
    }
  }

  // a tiny status dot in the button's corner (filled = online, hollow when unknown)
  Rectangle {
    readonly property int dot: Style.space(6)
    width: dot
    height: dot
    radius: dot / 2
    anchors.right: button.right
    anchors.bottom: button.bottom
    anchors.rightMargin: Style.space(3)
    anchors.bottomMargin: Style.space(3)
    visible: root.statusKnown && !root.highlighted
    color: root.memoryOnline ? root.statusColor() : "transparent"
    border.width: root.memoryOnline ? 0 : 1
    border.color: root.statusColor()
  }
}
