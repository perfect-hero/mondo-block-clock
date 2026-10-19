import QtQuick
import qs.Commons
import qs.Ui
import "TimechainModel.js" as Model

// Popup anchored to the bar widget (DESIGN.md §7.2). Same open/close/toggle
// contract as the weather panel, so the bar's one-popup rule and panel
// navigation work. The dial is only built while open: every monitor's bar
// widget owns one of these, and N hidden dials would each tick once a second.
Panel {
  id: root
  moduleName: Model.PLUGIN_ID
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var svc: null
  readonly property var barIdentity: hostWidget || root

  readonly property TimechainPalette pal: TimechainPalette {}

  function open() {
    root.controller.show()
    if (svc) svc.requestFreshPrice()
  }

  function close() { root.controller.hide() }

  function toggle() { root.opened ? root.close() : root.open() }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function openOverlay() {
    root.close()
    if (root.bar && root.bar.shell && typeof root.bar.shell.summon === "function")
      root.bar.shell.summon(Model.PLUGIN_ID, "")
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    // The face draws its own dark surface edge to edge inside the themed border.
    padding: 0
    contentWidth: panel.fittedContentWidth(Style.space(640))
    contentHeight: panel.fittedContentHeight(Style.space(580))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        var k = String(text).toLowerCase()
        if (k === "q") root.close()
        else if (k === "c" && root.svc) root.svc.chainAction("toggle")
        else if (k === "r" && root.svc) root.svc.refresh()
        else if (k === "d" && root.svc) { root.svc.desktopAction("show"); root.close() }
        else if (k === "f") root.openOverlay()
      }

      Rectangle {
        anchors.fill: parent
        color: root.pal ? root.pal.bg : "#0f1116"
        radius: Math.max(0, Style.cornerRadius - 2)

        Loader {
          anchors.fill: parent
          active: root.opened
          sourceComponent: TimechainFace {
            svc: root.svc
            pal: root.pal
            dialFraction: 0.74
            margin: Style.space(18)
            hint: "hover a ring for details"
          }
        }
      }
    }
  }
}
