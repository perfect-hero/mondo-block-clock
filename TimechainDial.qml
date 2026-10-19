import QtQuick
import QtQuick.Shapes
import "TimechainModel.js" as Model

// The dial, size-agnostic: rings outer → inner (supply, halving, difficulty,
// 24 h ticks, block timer), each named by curved text starting at 12 o'clock;
// curved value pills with the halving and difficulty counts; the block height
// in the centre (DESIGN.md §2, §6). Hovering a ring or a pill swaps the centre
// for that ring's details. Reads everything from `svc`, which may be null; it
// then shows the loading state.
Item {
  id: dial

  property var svc: null
  property TimechainPalette pal: TimechainPalette {}
  property bool animated: true
  property bool hoverDetails: true
  // Ambient motion (the XBT orbit); off on the desktop dial and screensaver.
  property bool motion: true

  readonly property real size: Math.min(width, height)
  // Rings use 90 % of the box; the supply label and pill pointers stand out past it.
  readonly property real d: size * 0.9
  readonly property real cx: width / 2
  readonly property real cy: height / 2

  readonly property int h: svc ? svc.blockHeight : 0
  readonly property string chainId: svc ? svc.chain : "btc"
  readonly property bool loading: h <= 0
  readonly property bool stale: svc ? svc.stale : false
  readonly property real nowSec: svc ? svc.nowMs / 1000 : 0
  readonly property bool showTimer: svc && svc.config ? svc.config.showTimerRing !== false : true
  readonly property var timer: Model.timerState(svc ? svc.sinceLastBlockSec : 0)
  readonly property color timerColor: timer.cycle === 0 ? pal.teal : timer.cycle === 1 ? pal.amber : pal.red

  readonly property real ringsOpacity: stale ? 0.4 : 1
  readonly property real captionSize: Math.max(9, d * 0.022)
  readonly property real pinSize: Math.max(9, d * 0.019)
  readonly property real labelSize: Math.max(8, d * 0.0125)

  // ---- geometry (DESIGN.md §6.3, relative to d)
  readonly property real r1: d * 0.500
  readonly property real r2: d * 0.478
  readonly property real r3: d * 0.425
  readonly property real r4: d * 0.375
  readonly property real r5: d * 0.322
  readonly property real ringBand: d * 0.008
  readonly property real tickWidth: Math.max(2, d * 0.0055)

  readonly property real halvingP: loading ? 0 : Model.halvingProgress(h)
  readonly property real retargetP: loading ? 0 : Model.retargetProgress(h, svc ? svc.difficulty : null)

  // ---- hover: which ring the centre describes ("" = block height)
  property string ringHover: ""
  readonly property string activeRing: ringHover === "timer" && !showTimer ? "" : ringHover
  readonly property var info: activeRing === "" || loading ? null : Model.ringInfo(activeRing, {
    height: h,
    nowMs: svc ? svc.nowMs : 0,
    difficulty: svc ? svc.difficulty : null,
    blocks: svc ? svc.recentBlocks : [],
    blocksLast24h: svc ? svc.blocksLast24h : 0,
    sinceLastBlockSec: svc ? svc.sinceLastBlockSec : 0,
    tip: svc ? svc.tip : null,
    chain: chainId
  })

  // ---- new-block bump on the height
  readonly property int serial: svc ? svc.newBlockSerial : 0
  property int _seenSerial: -1
  onSerialChanged: {
    if (_seenSerial >= 0 && serial > _seenSerial && animated) bump.restart()
    _seenSerial = serial
  }
  onSvcChanged: _seenSerial = svc ? svc.newBlockSerial : -1

  // Faint light behind the dial so it does not sit on a flat plane.
  Shape {
    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer
    ShapePath {
      strokeWidth: -1
      fillGradient: RadialGradient {
        centerX: dial.cx; centerY: dial.cy; centerRadius: dial.r1 * 1.05
        focalX: dial.cx; focalY: dial.cy
        GradientStop { position: 0; color: Qt.alpha(dial.pal.lavender, 0.07) }
        GradientStop { position: 0.7; color: Qt.alpha(dial.pal.lavender, 0.025) }
        GradientStop { position: 1; color: "transparent" }
      }
      PathAngleArc {
        centerX: dial.cx; centerY: dial.cy
        radiusX: dial.r1 * 1.05; radiusY: dial.r1 * 1.05
        startAngle: 0; sweepAngle: 360
      }
    }
  }

  Item {
    id: rings
    anchors.fill: parent
    opacity: dial.ringsOpacity

    Behavior on opacity { NumberAnimation { duration: 300 } }

    // Supply: a fine line, with a tick at each halving's share of the 21 M
    // (50 %, 75 %, 87.5 %, …) and a dot at 12 o'clock.
    DialRing {
      anchors.fill: parent
      pal: dial.pal
      animated: dial.animated
      color: dial.pal.ringSupply
      trackOpacity: 0.3
      rOuter: dial.r1 + Math.max(0.5, dial.d * 0.0009)
      rInner: dial.r1 - Math.max(0.5, dial.d * 0.0009)
      progress: dial.loading ? 0 : Model.supplyPercent(dial.h) / 100
    }

    Repeater {
      model: Model.supplyHalvingMarks(3)

      Item {
        required property real modelData
        x: dial.cx
        y: dial.cy
        rotation: modelData * 360
        Rectangle {
          width: Math.max(1, dial.d * 0.002)
          height: dial.d * 0.014
          x: -width / 2
          y: -dial.r1 - height / 2
          color: dial.pal.ringSupply
        }
      }
    }

    Rectangle {
      width: Math.max(4, dial.d * 0.008)
      height: width
      radius: width / 2
      x: dial.cx - width / 2
      y: dial.cy - dial.r1 - height / 2
      color: dial.pal.ringSupply
    }

    DialRing {
      id: halvingRing
      anchors.fill: parent
      pal: dial.pal
      animated: dial.animated
      color: dial.pal.ringHalving
      startTick: true
      rOuter: dial.r2 + dial.ringBand / 2
      rInner: dial.r2 - dial.ringBand / 2
      progress: dial.halvingP
    }

    DialRing {
      id: retargetRing
      anchors.fill: parent
      pal: dial.pal
      animated: dial.animated
      color: dial.pal.ringDifficulty
      startTick: true
      rOuter: dial.r3 + dial.ringBand / 2
      rInner: dial.r3 - dial.ringBand / 2
      progress: dial.retargetP
    }

    BlockTickRing {
      anchors.fill: parent
      pal: dial.pal
      blocks: dial.svc ? dial.svc.recentBlocks : []
      // Ticks drift once a minute, not every second.
      nowSec: Math.floor(dial.nowSec / 60) * 60
      radius: dial.r4
      tickLength: dial.d * 0.011
      tickWidth: dial.tickWidth
    }

    DialRing {
      visible: dial.showTimer
      anchors.fill: parent
      pal: dial.pal
      // The timer wraps every ten minutes; animating the wrap would sweep backwards.
      animated: false
      color: dial.timerColor
      trackOpacity: 0.12
      endDot: Math.max(5, dial.d * 0.012)
      rOuter: dial.r5 + Math.max(0.75, dial.d * 0.0015)
      rInner: dial.r5 - Math.max(0.75, dial.d * 0.0015)
      progress: dial.loading ? 0 : dial.timer.progress
    }
  }

  // ---- legend: each ring's name along it, from just after 12 o'clock.
  Repeater {
    model: [
      { text: "SUPPLY %", r: dial.r1 + dial.labelSize * 0.95 },
      { text: "BLOCKS TO HALVING", r: dial.r2 - dial.ringBand / 2 - dial.labelSize * 0.95 },
      { text: "BLOCKS TO DIFFICULTY ADJUST", r: dial.r3 - dial.ringBand / 2 - dial.labelSize * 0.95 },
      { text: "LAST 24 HOURS BLOCKS", r: dial.r4 - dial.tickWidth / 2 - dial.labelSize * 0.95 }
    ]

    ArcText {
      required property var modelData
      anchors.fill: parent
      opacity: dial.ringsOpacity
      text: modelData.text + "  \u203A"
      radius: modelData.r
      angle: dial.labelSize * 0.9 / modelData.r * 180 / Math.PI
      color: dial.pal.muted
      spacing: dial.labelSize * 0.1
      font.family: dial.pal.valueFont
      font.pixelSize: dial.labelSize
    }
  }

  // Hover over the rings (no buttons: clicks fall through, e.g. to the
  // overlay's click-to-close).
  MouseArea {
    anchors.fill: parent
    enabled: dial.hoverDetails
    hoverEnabled: true
    acceptedButtons: Qt.NoButton
    onPositionChanged: function(mouse) {
      var lp = logo.mapFromItem(dial, mouse.x, mouse.y)
      dial.ringHover = logo.visible && logo.contains(lp) ? "chain"
        : dial.pillHit(halvingPin, mouse) ? "halving"
        : dial.pillHit(retargetPin, mouse) ? "difficulty"
        : Model.ringAt(Math.hypot(mouse.x - dial.cx, mouse.y - dial.cy), dial.d)
    }
    onExited: dial.ringHover = ""
    onEnabledChanged: dial.ringHover = ""
  }

  function pillHit(pin, mouse) {
    return pin.visible && Model.arcHit(mouse.x, mouse.y, dial.cx, dial.cy, pin.radius,
                                       pin.angle, pin.sweepDeg, pin.halfHeight)
  }

  // ---- value pills, above every ring, on each ring's leading edge.
  MapPin {
    id: halvingPin
    anchors.fill: parent
    visible: !dial.loading
    opacity: dial.ringsOpacity
    pal: dial.pal
    text: Model.groupThousands(Model.blocksToHalving(dial.h))
    fontSize: dial.pinSize
    accent: dial.pal.ringHalving
    radius: dial.r2
    angle: halvingRing.shown * 360
  }

  MapPin {
    id: retargetPin
    anchors.fill: parent
    visible: !dial.loading
    opacity: dial.ringsOpacity
    pal: dial.pal
    text: Model.groupThousands(Model.blocksToRetarget(dial.h, dial.svc ? dial.svc.difficulty : null))
    fontSize: dial.pinSize
    accent: dial.pal.ringDifficulty
    radius: dial.r3
    angle: retargetRing.shown * 360
  }

  // ---- centre
  Column {
    anchors.centerIn: parent
    spacing: dial.d * 0.012

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: dial.chainId === "xbt" ? "BLOCK CLOCK · XBT" : "BLOCK CLOCK"
      color: dial.pal.muted
      font.pixelSize: dial.d * 0.028
      font.letterSpacing: dial.d * 0.028 * 0.25
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      visible: dial.stale
      text: "stale · " + Model.formatElapsed(dial.svc ? dial.svc.staleSec : 0)
      color: dial.pal.muted
      font.pixelSize: dial.captionSize
    }

    Item { width: 1; height: dial.d * 0.03 }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: dial.info ? dial.info.caption : "BLOCK HEIGHT"
      color: dial.info ? dial.pal.text : dial.pal.muted
      font.pixelSize: dial.captionSize
      font.letterSpacing: dial.captionSize * 0.2
    }

    GradientText {
      id: heightText
      anchors.horizontalCenter: parent.horizontalCenter
      readonly property string shownText: dial.info ? dial.info.value : dial.loading ? "······" : String(dial.h)
      text: shownText
      from: dial.pal.lavender
      to: dial.pal.pink
      font.family: dial.pal.heightFont
      // Long values shrink to stay inside the timer ring.
      font.pixelSize: Math.min(dial.d * 0.15, dial.d * 0.54 / Math.max(1, shownText.length * 0.62))
      font.bold: true
      font.features: { "tnum": 1 }

      SequentialAnimation {
        id: bump
        NumberAnimation { target: heightText; property: "scale"; to: 1.04; duration: 160; easing.type: Easing.OutCubic }
        NumberAnimation { target: heightText; property: "scale"; to: 1.0; duration: 240; easing.type: Easing.InOutCubic }
      }
    }

    // Below the value: the hovered ring's detail line, else the Bitcoin logo
    // (with the gold node orbit on XBT; hovering it explains the chain). The time
    // since the last block is on the timer ring's hover.
    Item {
      anchors.horizontalCenter: parent.horizontalCenter
      // Room for the XBT orbit on both chains, so switching does not shift the layout.
      width: Math.max(detail.implicitWidth, logo.width * 1.5)
      height: logo.height * 1.5

      Text {
        id: detail
        anchors.centerIn: parent
        visible: dial.info !== null && dial.activeRing !== "chain"
        text: dial.info ? dial.info.detail : ""
        color: dial.pal.muted
        font.family: dial.pal.valueFont
        font.pixelSize: dial.d * 0.026
      }

      // Stays in place (only hidden) while hovered, so hovering it holds.
      BitcoinLogo {
        id: logo
        anchors.centerIn: parent
        opacity: !dial.info || dial.activeRing === "chain" ? 1 : 0
        visible: !dial.loading
        pal: dial.pal
        size: dial.d * 0.075
        orbit: dial.chainId === "xbt"
        spinning: dial.motion
      }
    }
  }
}
