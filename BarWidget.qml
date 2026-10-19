import QtQuick
import qs.Commons
import qs.Ui
import "TimechainModel.js" as Model

// Bar pill: the BTC/USD price, `$81,754`, stacked like the clock in a vertical
// bar; it still pulses on each new block. Reads the
// service through a binding, never a cached reference: it is null under a
// replacement bar, before the service loads and during reloads (DESIGN.md §3.2).
BarWidget {
  id: root
  moduleName: Model.PLUGIN_ID

  readonly property var svc: bar && bar.shell ? bar.shell.serviceFor(moduleName) : null
  readonly property int blockHeight: svc ? svc.blockHeight : 0
  readonly property bool stale: svc ? svc.stale : false
  readonly property real priceUsd: svc ? svc.priceUsd : 0
  readonly property string chain: svc ? svc.chain : "btc"
  readonly property var lines: Model.barLines(priceUsd, chain)

  readonly property color barForeground: bar ? bar.barForeground : Color.foreground
  readonly property color lavender: "#b9a7ff"
  readonly property color pink: "#f0a6d8"

  // ---- new-block pulse: lavender → pink → bar foreground over 1.2 s
  property bool pulsing: false
  property color pulseColor: barForeground
  readonly property color textColor: pulsing ? pulseColor : barForeground

  readonly property int serial: svc ? svc.newBlockSerial : 0
  property int _seenSerial: -1

  onSerialChanged: {
    // The first value after (re)binding is not a new block.
    if (_seenSerial >= 0 && serial > _seenSerial) pulse.restart()
    _seenSerial = serial
  }
  onSvcChanged: {
    _seenSerial = svc ? svc.newBlockSerial : -1
    injectPanel()
  }

  SequentialAnimation {
    id: pulse
    ScriptAction { script: { root.pulseColor = root.lavender; root.pulsing = true } }
    ColorAnimation { target: root; property: "pulseColor"; to: root.pink; duration: 400; easing.type: Easing.OutCubic }
    ColorAnimation { target: root; property: "pulseColor"; to: root.barForeground; duration: 800; easing.type: Easing.InOutCubic }
    ScriptAction { script: root.pulsing = false }
  }

  // ---- popup (weather pattern): the panel is loaded eagerly so the bar's
  // popout coordinator can find it; its dial is only built while open.
  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    target.bar = root.bar
    target.settings = root.settings
    target.anchorItem = button
    target.hostWidget = root
    target.svc = root.svc
  }

  function togglePanel() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  // Shape contract for bar panel navigation (Bar.qml:627-644). summon/toggle
  // IPC goes to the overlay instead, because the manifest declares one.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }

  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.vertical ? "" : Model.barLabel(root.priceUsd, root.chain)
    labelVisible: !root.vertical
    hasVisualContent: true
    fixedHeight: root.vertical ? root.lines.length * Style.bar.iconSlot : -1
    horizontalMargin: 8.75
    verticalPadding: 8.75
    foreground: root.textColor
    dimmed: root.stale || !root.svc
    tooltipText: !root.svc ? "Block Clock · service unavailable"
      : Model.tooltipText({
          height: root.svc.blockHeight,
          sinceLastBlockSec: root.svc.sinceLastBlockSec,
          tip: root.svc.tip,
          priceUsd: root.svc.priceUsd,
          chain: root.chain,
          stale: root.svc.stale,
          staleSec: root.svc.staleSec
        })

    onPressed: function(b) {
      if (b === Qt.LeftButton) root.togglePanel()
      else if (!root.svc) return
      else if (b === Qt.RightButton) root.svc.desktopAction("toggle")
      else root.svc.refresh()
    }

    Column {
      visible: root.vertical
      anchors.fill: parent

      Repeater {
        model: root.lines

        OpticalGlyph {
          required property string modelData
          width: button.width
          height: Style.bar.iconSlot
          text: modelData
          fontFamily: button.fontFamily
          fontSize: button.fontSize * 0.9
          color: root.textColor
        }
      }
    }
  }
}
