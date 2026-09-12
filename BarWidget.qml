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
* @name: Wakanda4Ever - Conversation Dashboard - Bar Widget
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
// Omarchy - commons
import qs.Commons
// Omarchy - UI (the `BarWidget` & `BarIconButton` base components)
import qs.Ui


// ======<<< Wakanda4Ever - Bar Widget >>>======
BarWidget {
  id: root
  moduleName: "Wakanda4Ever"

  // whether the dashboard is currently open (used to highlight the button)
  property bool highlighted: false
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
      root.bar.shell.toggle(root.moduleName)
    else if (root.bar && root.bar.run)
      root.bar.run("omarchy-shell shell toggle Wakanda4Ever")
    Qt.callLater(root.syncState)
  }

  // keep the highlight in sync while visible (cheap enough at 400ms)
  Timer {
    interval: 400
    running: root.visible
    repeat: true
    triggeredOnStart: true
    onTriggered: root.syncState()
  }

  // the icon button that toggles the dashboard on click
  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\uf086"
    tooltipText: "Wakanda4Ever — conversation dashboard"
    active: root.highlighted
    useActiveColor: true
    onPressed: function(mouse) {
      root.toggle()
    }
  }
}