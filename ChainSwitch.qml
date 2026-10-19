import QtQuick
import "TimechainModel.js" as Model

// BTC | XBT segmented switch (DESIGN.md §10.10): click a side, or press c.
Item {
  id: sw

  required property TimechainPalette pal
  property var svc: null
  property real fontSize: 11

  readonly property string current: svc ? svc.chain : "btc"

  implicitWidth: row.implicitWidth
  implicitHeight: row.implicitHeight

  Rectangle {
    anchors.fill: row
    radius: height / 2
    color: Qt.alpha(sw.pal.bgElevated, 0.9)
    border.color: Qt.alpha(sw.pal.muted, 0.35)
    border.width: 1
  }

  Row {
    id: row
    padding: 2

    Repeater {
      model: ["btc", "xbt"]

      Rectangle {
        id: seg
        required property string modelData
        readonly property bool active: sw.current === modelData
        width: label.implicitWidth + sw.fontSize * 1.6
        height: sw.fontSize * 2
        radius: height / 2
        color: active ? (modelData === "btc" ? sw.pal.bitcoinOrange : sw.pal.teal) : "transparent"
        Behavior on color { ColorAnimation { duration: 150 } }

        Text {
          id: label
          anchors.centerIn: parent
          text: Model.chainInfo(seg.modelData).ticker
          color: seg.active ? sw.pal.bg : (area.containsMouse ? sw.pal.text : sw.pal.muted)
          font.family: sw.pal.heightFont
          font.pixelSize: sw.fontSize
          font.bold: true
          font.letterSpacing: sw.fontSize * 0.1
        }

        MouseArea {
          id: area
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: if (sw.svc) sw.svc.chainAction(seg.modelData)
        }
      }
    }
  }
}
