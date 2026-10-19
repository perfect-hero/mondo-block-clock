import QtQuick
import "TimechainModel.js" as Model

// Text laid along a circle (DESIGN.md §6.6): one Text per glyph, capitals
// centred on `radius`. Starts at `angle` (clockwise from 12), or is centred on
// it with align "center". `flipped` reads counter-clockwise, tops inward.
// Fills its parent; the circle's centre is (cx, cy).
Item {
  id: arc

  property string text: ""
  property font font
  property real spacing: 0
  property color color: "white"
  property real cx: width / 2
  property real cy: height / 2
  property real radius: 100
  property real angle: 0
  property string align: "start"
  property bool flipped: false

  // Arc length of the whole text in px, for sizing a pill around it.
  readonly property real textLength: {
    var t = 0
    for (var i = 0; i < glyphs.length; i++) t += widths[i]
    return t
  }

  FontMetrics { id: fm }

  readonly property var glyphs: Array.from(text)
  // Name the font in each binding: advanceWidth() is a call, so these would
  // not otherwise re-run when the font changes.
  readonly property var widths: {
    fm.font = arc.font
    return glyphs.map(function(g) { return fm.advanceWidth(g) + arc.spacing })
  }
  readonly property var angles: Model.arcGlyphs(widths, radius, angle, align, flipped)
  readonly property real capHeight: { fm.font = arc.font; return fm.tightBoundingRect("H").height }

  Repeater {
    model: arc.glyphs.length

    // A zero-size pivot at the dial centre, swung to the glyph's angle; the
    // glyph sits on the circle and turns over when flipped.
    Item {
      required property int index
      x: arc.cx
      y: arc.cy
      rotation: arc.angles[index] || 0

      Item {
        y: -arc.radius
        rotation: arc.flipped ? 180 : 0

        Text {
          x: -implicitWidth / 2
          y: arc.capHeight / 2 - baselineOffset
          text: arc.glyphs[index]
          color: arc.color
          font: arc.font
        }
      }
    }
  }
}
