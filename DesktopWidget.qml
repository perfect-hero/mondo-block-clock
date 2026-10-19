import QtQuick
import Quickshell
import Quickshell.Wayland
import "TimechainModel.js" as Model

// The always-on desktop dial (DESIGN.md §7.3): one window on the bottom layer
// per chosen monitor, above the wallpaper and below windows. Click it to give
// it the keyboard (f/d fullscreen, esc/q hide, c chain, r refresh); double-click opens
// fullscreen. Owned by the service; with the setting off the model is empty,
// so no window exists at all.
Variants {
  id: root

  property var svc: null
  readonly property var cfg: svc ? svc.config : Model.resolveConfig(null)
  readonly property var layout: Model.desktopLayout(cfg)

  model: {
    if (!svc || cfg.desktopWidget !== true) return []
    var screens = Quickshell.screens
    var names = []
    for (var i = 0; i < screens.length; i++) names.push(screens[i].name)
    var wanted = Model.pickScreens(names, cfg.desktopScreen)
    var out = []
    for (var j = 0; j < screens.length; j++)
      if (wanted.indexOf(screens[j].name) !== -1) out.push(screens[j])
    return out
  }

  PanelWindow {
    id: win

    required property var modelData
    screen: modelData

    WlrLayershell.namespace: "mondo-block-clock"
    WlrLayershell.layer: WlrLayer.Bottom
    // Keyboard only after a click on the dial; never taken on its own.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    // Respect the bar's zone on whichever edge it is; reserve nothing.
    exclusionMode: ExclusionMode.Normal
    color: "transparent"

    // No anchors = centred on the output by the compositor.
    anchors.top: root.layout.top
    anchors.bottom: root.layout.bottom
    anchors.left: root.layout.left
    anchors.right: root.layout.right
    margins.top: root.layout.margin
    margins.bottom: root.layout.margin
    margins.left: root.layout.margin
    margins.right: root.layout.margin

    implicitWidth: root.layout.width
    implicitHeight: root.layout.height

    TimechainPalette { id: pal }

    // One layer for the whole face, so the opacity applies to it as a unit
    // instead of letting overlapping rings show through each other.
    Item {
      anchors.fill: parent
      opacity: root.layout.opacity
      layer.enabled: opacity < 1

      Rectangle {
        anchors.centerIn: parent
        readonly property bool round: !root.cfg.desktopStats
        width: round ? Math.min(parent.width, parent.height) : parent.width
        height: round ? width : parent.height
        radius: round ? width / 2 : 18
        color: pal.bg
        border.color: pal.hairline
        border.width: 1
      }

      // Under the face, so the dial's hover area (no buttons) passes clicks here.
      MouseArea {
        anchors.fill: parent
        onClicked: keys.forceActiveFocus()
        onDoubleClicked: root.svc.openFullscreen("")
      }

      TimechainFace {
        anchors.fill: parent
        svc: root.svc
        pal: pal
        dialFraction: root.layout.dialFraction
        showStats: root.cfg.desktopStats
        motion: false
        margin: Math.max(12, root.cfg.desktopSize * 0.035)
      }

      Item {
        id: keys
        anchors.fill: parent
        focus: true
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_F || event.key === Qt.Key_D) {
            root.svc.openFullscreen("")
          } else if (event.key === Qt.Key_Escape || event.key === Qt.Key_Q) {
            root.svc.desktopAction("hide")
          } else if (event.key === Qt.Key_R) {
            root.svc.refresh()
          } else if (event.key === Qt.Key_C) {
            root.svc.chainAction("toggle")
          } else {
            return
          }
          event.accepted = true
        }
      }
    }
  }
}
