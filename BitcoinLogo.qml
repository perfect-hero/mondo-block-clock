import QtQuick
import QtQuick.Shapes

// The Bitcoin logo, drawn from the public-domain vector (Wikimedia Commons
// "Bitcoin.svg", 64 × 64 units), so it is sharp at any size. With `orbit`,
// three gold nodes circle it on a faint gold track: the XBT dial's "nodes
// over miners" sign (DESIGN.md §10.11). They turn once a minute while
// `spinning`; the orbit reaches half a radius past the coin on every side,
// outside this item's bounds.
Item {
  id: logo

  required property TimechainPalette pal
  property real size: 32
  property bool orbit: false
  property bool spinning: true

  width: size
  height: size

  Shape {
    width: 64
    height: 64
    scale: logo.size / 64
    transformOrigin: Item.TopLeft
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
      strokeWidth: -1
      fillColor: logo.pal.bitcoinOrange
      PathSvg { path: "m63.033,39.744c-4.274,17.143-21.637,27.576-38.782,23.301-17.138-4.274-27.571-21.638-23.295-38.78,4.272-17.145,21.635-27.579,38.775-23.305,17.144,4.274,27.576,21.64,23.302,38.784z" }
    }
    ShapePath {
      strokeWidth: -1
      fillColor: "white"
      PathSvg { path: "m46.103,27.444c0.637-4.258-2.605-6.547-7.038-8.074l1.438-5.768-3.511-0.875-1.4,5.616c-0.923-0.23-1.871-0.447-2.813-0.662l1.41-5.653-3.509-0.875-1.439,5.766c-0.764-0.174-1.514-0.346-2.242-0.527l0.004-0.018-4.842-1.209-0.934,3.75s2.605,0.597,2.55,0.634c1.422,0.355,1.679,1.296,1.636,2.042l-1.638,6.571c0.098,0.025,0.225,0.061,0.365,0.117-0.117-0.029-0.242-0.061-0.371-0.092l-2.296,9.205c-0.174,0.432-0.615,1.08-1.609,0.834,0.035,0.051-2.552-0.637-2.552-0.637l-1.743,4.019,4.569,1.139c0.85,0.213,1.683,0.436,2.503,0.646l-1.453,5.834,3.507,0.875,1.439-5.772c0.958,0.26,1.888,0.5,2.798,0.726l-1.434,5.745,3.511,0.875,1.453-5.823c5.987,1.133,10.489,0.676,12.384-4.739,1.527-4.36-0.076-6.875-3.226-8.515,2.294-0.529,4.022-2.038,4.483-5.155zm-8.022,11.249c-1.085,4.36-8.426,2.003-10.806,1.412l1.928-7.729c2.38,0.594,10.012,1.77,8.878,6.317zm1.086-11.312c-0.99,3.966-7.1,1.951-9.082,1.457l1.748-7.01c1.982,0.494,8.365,1.416,7.334,5.553z" }
    }
  }

  // Orbit: radius 1.5 coin radii, nodes 0.13 of the coin across.
  Item {
    id: orbitItem
    visible: logo.orbit
    readonly property real r: logo.size * 0.75
    x: logo.size / 2
    y: logo.size / 2

    Rectangle {
      x: -orbitItem.r
      y: -orbitItem.r
      width: orbitItem.r * 2
      height: width
      radius: width / 2
      color: "transparent"
      border.color: Qt.alpha(logo.pal.nodeGold, 0.35)
      border.width: Math.max(1, logo.size * 0.023)
    }

    Item {
      id: nodes
      Repeater {
        model: 3
        Rectangle {
          required property int index
          readonly property real a: index * 2 * Math.PI / 3 - Math.PI / 2
          width: Math.max(3, logo.size * 0.133)
          height: width
          radius: width / 2
          color: logo.pal.nodeGold
          x: orbitItem.r * Math.cos(a) - width / 2
          y: orbitItem.r * Math.sin(a) - height / 2
        }
      }

      NumberAnimation on rotation {
        from: 0
        to: 360
        duration: 60000
        loops: Animation.Infinite
        running: logo.orbit && logo.spinning && logo.visible
      }
    }
  }
}
