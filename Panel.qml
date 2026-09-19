import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Bar toggle for Chrome/Chromium hardware acceleration. The setting only
// lives in the browser's Local State file and is only read at process
// start, so there is no live "flip a switch" API -- toggling always means
// a full browser restart. bin/oma-hwaccel-toggle handles that restart
// safely (quit, edit, relaunch with --restore-last-session so tabs come
// back). Because that's disruptive, the bar icon only opens this panel;
// the actual toggle requires the explicit button click below.
Panel {
  id: root
  moduleName: "whitcodes.chromehwaccel"
  ipcTarget: "whitcodes.chromehwaccel"
  manageIpc: false

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string pluginDir: home + "/.config/omarchy/plugins/whitcodes.chromehwaccel"

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  property bool hasLoaded: false
  property bool found: false
  property string browserLabel: ""
  property bool hwaccelEnabled: true
  property bool browserRunning: false

  property bool toggling: false
  property string toggleError: ""

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }
  property int pollIntervalSec: Math.max(5, Number(setting("pollIntervalSec", 20)))

  function refreshNow() {
    if (!statusProc.running) statusProc.running = true
  }

  function applyStatus(output) {
    try {
      var parsed = JSON.parse(String(output || "{}"))
      root.found = !!parsed.found
      root.browserLabel = parsed.label || ""
      root.hwaccelEnabled = parsed.enabled !== false
      root.browserRunning = !!parsed.running
    } catch (e) {
      root.found = false
    }
    root.hasLoaded = true
  }

  // Named distinctly from the base Panel type's own toggle() (open/close
  // the dropdown, used by the bar-icon click and IPC below) -- this one is
  // the actual hardware-acceleration flip-and-restart action.
  function toggleHwAccel() {
    if (toggling || !found) return
    toggling = true
    toggleError = ""
    toggleProc.running = true
  }

  function applyToggleResult(output) {
    toggling = false
    try {
      var parsed = JSON.parse(String(output || "{}"))
      if (parsed.ok) {
        root.hwaccelEnabled = !!parsed.enabled
        toggleError = ""
      } else {
        toggleError = parsed.error || "Toggle failed"
      }
    } catch (e) {
      toggleError = "Toggle failed"
    }
    // The browser (if it was running) is relaunching in the background --
    // give it a moment before polling its new state.
    settleTimer.restart()
  }

  visible: true
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Component.onCompleted: refreshNow()

  Timer {
    interval: root.pollIntervalSec * 1000
    running: true
    repeat: true
    onTriggered: root.refreshNow()
  }

  Timer {
    id: settleTimer
    interval: 4000
    repeat: false
    onTriggered: root.refreshNow()
  }

  onOpenedChanged: if (opened) refreshNow()

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { root.refreshNow(); return "ok" }
  }

  Process {
    id: statusProc
    running: false
    command: ["bash", root.pluginDir + "/bin/oma-hwaccel-status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyStatus(text)
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (text.trim() !== "") console.warn("whitcodes.chromehwaccel/status", text.trim())
    }
  }

  Process {
    id: toggleProc
    running: false
    command: ["bash", root.pluginDir + "/bin/oma-hwaccel-toggle"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyToggleResult(text)
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (text.trim() !== "") console.warn("whitcodes.chromehwaccel/toggle", text.trim())
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "GPU"
    active: root.found && root.hwaccelEnabled
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.MiddleButton) root.refreshNow()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(320))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(320))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        width: parent.width
        spacing: Style.space(14)

        Item {
          width: parent.width
          implicitHeight: heroLabels.implicitHeight

          Column {
            id: heroLabels
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: Style.space(2)

            Text {
              text: "Chrome Hardware Acceleration"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
              width: parent.width
            }

            Text {
              text: root.hasLoaded
                ? (root.found ? root.browserLabel + (root.browserRunning ? " · running" : " · not running") : "No Chrome or Chromium install found")
                : "Checking…"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              elide: Text.ElideRight
              width: parent.width
            }
          }
        }

        PanelSeparator {
          foreground: root.foreground
        }

        Item {
          visible: root.found
          width: parent.width
          implicitHeight: stateHeader.implicitHeight

          PanelSectionHeader {
            id: stateHeader
            text: "STATE"
            foreground: root.foreground
            fontFamily: root.fontFamily
            anchors.left: parent.left
          }

          Text {
            text: root.hwaccelEnabled ? "ON" : "OFF"
            color: root.hwaccelEnabled ? root.foreground : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
            anchors.right: parent.right
          }
        }

        Text {
          visible: root.found
          width: parent.width
          text: root.browserRunning
            ? "Toggling closes all " + root.browserLabel + " windows, flips the setting, and reopens with your tabs restored."
            : root.browserLabel + " isn't running -- toggling just flips the setting for next launch, no restart needed."
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        Text {
          visible: root.toggleError !== ""
          width: parent.width
          text: root.toggleError
          color: root.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        ToggleButton {
          visible: root.found
          width: parent.width
        }
      }
    }
  }

  // The one control that actually flips the setting. Deliberately a
  // second, explicit action behind the bar-icon click -- see file header.
  component ToggleButton: Item {
    id: toggleButton
    implicitHeight: toggleText.implicitHeight + Style.spacing.md * 2

    readonly property bool enabled_: !root.toggling

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: mouse.containsMouse ? Style.hoverFillFor(root.foreground, Color.accent) : Style.selectedFillFor(root.foreground, Color.accent)
    }

    Text {
      id: toggleText
      anchors.centerIn: parent
      text: root.toggling
        ? (root.browserRunning ? "Restarting…" : "Applying…")
        : (root.hwaccelEnabled ? "Turn off & restart" : "Turn on & restart")
      color: toggleButton.enabled_ ? root.foreground : root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      font.bold: true
    }

    MouseArea {
      id: mouse
      anchors.fill: parent
      hoverEnabled: true
      enabled: toggleButton.enabled_
      cursorShape: toggleButton.enabled_ ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: root.toggleHwAccel()
    }
  }
}
