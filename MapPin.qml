import QtQuick
import QtQuick.Shapes
import "TimechainModel.js" as Model

// A value pill on a ring (DESIGN.md §6.4): a band curved along the ring,
// centred on `angle` (clockwise from 12) at mid radius `radius`, as long as
// its text needs, with a small pointer on the outside like a map marker. The
// text follows the curve and turns over in the lower half. Fills its parent;
// the ring's centre is (cx, cy). The dial hit-tests it with `sweepDeg` and
// `halfHeight` (Model.arcHit).
Item {
  id: pin

  required property TimechainPalette pal
  property string text: ""
  property color accent: "white"
  property real fontSize: 11
  property real cx: width / 2
  property real cy: height / 2
  property real radius: 100
  property real angle: 0

  readonly property real halfHeight: fontSize * 0.95
  readonly property real border: Math.max(1.25, fontSize * 0.12)
  readonly property real sweepDeg: (label.textLength + fontSize * 0.5) / radius * 180 / Math.PI
  readonly property real startQt: angle - 90 - sweepDeg / 2

  // Shadow, outline, then fill: three strokes along the same arc with round caps.
  Repeater {
    model: 3

    Shape {
      id: band
      required property int index
      width: pin.width
      height: pin.height
      x: index === 0 ? pin.fontSize * 0.1 : 0
      y: index === 0 ? pin.fontSize * 0.15 : 0
      opacity: index === 0 ? 0.45 : 1
      preferredRendererType: Shape.CurveRenderer

      ShapePath {
        fillColor: "transparent"
        strokeColor: band.index === 0 ? "black" : band.index === 1 ? pin.accent : pin.pal.bgElevated
        strokeWidth: band.index === 2 ? 2 * (pin.halfHeight - pin.border) : 2 * pin.halfHeight
        capStyle: ShapePath.RoundCap
        PathAngleArc {
          centerX: pin.cx; centerY: pin.cy
          radiusX: pin.radius; radiusY: pin.radius
          startAngle: pin.startQt; sweepAngle: pin.sweepDeg
        }
      }
    }
  }

  // Pointer on the outer edge, at the pill's middle.
  Item {
    x: pin.cx
    y: pin.cy
    rotation: pin.angle

    Shape {
      y: -pin.radius - pin.halfHeight + pin.border / 2
      preferredRendererType: Shape.CurveRenderer
      ShapePath {
        fillColor: pin.accent
        strokeWidth: -1
        readonly property real w: pin.fontSize * 0.45
        startX: -w; startY: 0
        PathLine { x: 0; y: -pin.fontSize * 0.5 }
        PathLine { x: pin.fontSize * 0.45; y: 0 }
        PathLine { x: -pin.fontSize * 0.45; y: 0 }
      }
    }
  }

  ArcText {
    id: label
    anchors.fill: parent
    cx: pin.cx
    cy: pin.cy
    radius: pin.radius
    angle: pin.angle
    align: "center"
    flipped: Model.markerFlipped(pin.angle)
    text: pin.text
    color: pin.pal.text
    font.family: pin.pal.heightFont
    font.pixelSize: pin.fontSize
    font.bold: true
  }
}
