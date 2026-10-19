import QtQuick
import QtQuick.Shapes

// One progress ring (DESIGN.md §6.4): a band from 12 o'clock clockwise in
// `color` over a faint track of the same hue, with a rounded leading end and
// optionally a start tick across the band at 12 o'clock. `endDot` (px) puts
// a larger dot on the leading edge. Value pills are drawn by the dial
// (MapPin.qml), above every ring.
Item {
  id: ring

  required property TimechainPalette pal
  property real progress: 0
  property real rOuter: 100
  property real rInner: 90
  property color color: "white"
  property real trackOpacity: 0.2
  property bool startTick: false
  property real endDot: 0
  property bool animated: true

  readonly property real cx: width / 2
  readonly property real cy: height / 2
  readonly property real rMid: (rOuter + rInner) / 2
  readonly property real band: Math.max(1, rOuter - rInner)
  readonly property real target: Math.max(0, Math.min(1, isFinite(progress) ? progress : 0))
  property real shown: target
  readonly property real sweep: shown * 360

  Behavior on shown {
    enabled: ring.animated
    NumberAnimation { duration: 600; easing.type: Easing.OutCubic }
  }

  // Track, then the progress band (flat ends; the leading end gets a disc).
  Repeater {
    model: 2

    Shape {
      id: arcShape
      required property int index
      readonly property bool track: index === 0
      anchors.fill: parent
      visible: track || ring.shown > 0
      preferredRendererType: Shape.CurveRenderer
      ShapePath {
        fillColor: "transparent"
        strokeColor: arcShape.track ? Qt.alpha(ring.color, ring.trackOpacity) : ring.color
        strokeWidth: ring.band
        capStyle: ShapePath.FlatCap
        PathAngleArc {
          centerX: ring.cx; centerY: ring.cy
          radiusX: ring.rMid; radiusY: ring.rMid
          startAngle: -90
          sweepAngle: arcShape.track ? 360 : ring.sweep
        }
      }
    }
  }

  Rectangle {
    visible: ring.startTick
    width: Math.max(1.5, ring.band * 0.35)
    height: ring.band * 3.2
    x: ring.cx - width / 2
    y: ring.cy - ring.rMid - height / 2
    color: ring.color
  }

  readonly property real endRad: (sweep - 90) * Math.PI / 180

  Rectangle {
    readonly property real dia: ring.endDot > 0 ? ring.endDot : ring.band
    visible: ring.shown > 0 && ring.shown < 1
    width: dia
    height: dia
    radius: dia / 2
    color: ring.color
    x: ring.cx + ring.rMid * Math.cos(ring.endRad) - width / 2
    y: ring.cy + ring.rMid * Math.sin(ring.endRad) - height / 2
  }
}
