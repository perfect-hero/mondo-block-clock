import QtQuick
import Quickshell
import Quickshell.Wayland
import "TimechainModel.js" as Model

// The fullscreen dial (DESIGN.md §7.4), on the Emojis pattern: the shell loads
// this on summon (keybind, `omarchy-shell shell toggle <id>`, `f` in the popup
// or on the desktop dial) and destroys it on hide, so nothing here outlives a
// close. Summoned with {"screensaver": true} (Service.qml, on idle) it is the
// screensaver: no hover or hint, and any key, click or activity closes it.
Item {
  id: root

  property var shell: null
  property bool opened: false
  property bool screensaver: false
  property real openedAt: 0

  readonly property var svc: shell && typeof shell.serviceFor === "function" ? shell.serviceFor(Model.PLUGIN_ID) : null

  function open(payloadJson) {
    var payload = {}
    try { payload = JSON.parse(payloadJson || "{}") || {} } catch (e) {}
    screensaver = payload.screensaver === true
    openedAt = Date.now()
    opened = true
    if (svc) svc.requestFreshPrice()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    opened = false
  }

  function dismiss() {
    opened = false
    if (shell && typeof shell.hide === "function") shell.hide(Model.PLUGIN_ID)
  }

  function toggle() {
    if (opened) dismiss()
    else open("")
  }

  TimechainPalette { id: pal }

  PanelWindow {
    id: win
    visible: root.opened
    // No screen: the compositor puts it on the focused monitor.
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"

    WlrLayershell.namespace: "mondo-block-clock-overlay"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: Qt.alpha(pal.bg, 0.95)
    }

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.AllButtons
      hoverEnabled: root.screensaver
      onClicked: root.dismiss()
      onPositionChanged: if (root.screensaver && Date.now() - root.openedAt > 1000) root.dismiss()
    }

    // Screensaver: the service's idle monitor reports any input, mouse
    // movement included. The grace period skips activity caused by opening.
    Connections {
      target: root.screensaver ? root.svc : null
      function onUserIdleChanged() {
        if (!root.svc.userIdle && Date.now() - root.openedAt > 1000) root.dismiss()
      }
    }

    TimechainFace {
      id: face
      anchors.fill: parent
      svc: root.svc
      pal: pal
      dialFraction: 0.78
      margin: Math.max(24, Math.min(width, height) * 0.045)
      hoverDetails: !root.screensaver
      motion: !root.screensaver
      hint: root.screensaver ? "" : "hover a ring for details · c chain · esc close · d/f desktop dial · r refresh"
    }

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true
      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        if (root.screensaver) {
          root.dismiss()
        } else if (event.key === Qt.Key_Escape || event.key === Qt.Key_Q) {
          // Close for good: no desktop dial left behind.
          if (root.svc) root.svc.desktopAction("hide")
          root.dismiss()
        } else if (event.key === Qt.Key_R) {
          if (root.svc) root.svc.refresh()
        } else if (event.key === Qt.Key_C) {
          if (root.svc) root.svc.chainAction("toggle")
        } else if (event.key === Qt.Key_D || event.key === Qt.Key_F) {
          // Back to the desktop dial.
          if (root.svc) root.svc.desktopAction("show")
          root.dismiss()
        } else {
          return
        }
        event.accepted = true
      }
    }
  }
}
