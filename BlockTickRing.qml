import QtQuick
import "TimechainModel.js" as Model

// Last-24-hours ring (DESIGN.md §6.5): one tick per block at its age, 12
// o'clock = now, older blocks clockwise. Ticks are short dashes along the
// circle; the newest is pink and larger, and they fade with age.
Item {
  id: ring

  required property TimechainPalette pal
  property var blocks: []
  property real nowSec: 0
  property real radius: 100
  property real tickLength: 8
  property real tickWidth: 1.5

  readonly property real cx: width / 2
  readonly property real cy: height / 2

  Repeater {
    model: ring.blocks

    // Each tick is a centred rectangle swung about the dial centre.
    Item {
      required property var modelData
      required property int index
      readonly property real age: ring.nowSec - modelData.timestamp
      readonly property bool newest: index === 0
      visible: age <= Model.DAY_SEC
      x: ring.cx
      y: ring.cy
      width: 0
      height: 0
      rotation: Model.tickAngleDeg(age)

      // A short dash along the circle: tickLength around, tickWidth across.
      Rectangle {
        width: ring.tickLength * (parent.newest ? 1.4 : 1)
        height: ring.tickWidth * (parent.newest ? 1.4 : 1)
        x: -width / 2
        y: -ring.radius - height / 2
        radius: height * 0.25
        color: parent.newest ? ring.pal.pink : ring.pal.tick
        opacity: parent.newest ? 1 : Model.tickOpacity(parent.age)
      }
    }
  }
}
