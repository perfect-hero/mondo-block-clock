import QtQuick
import "TimechainModel.js" as Model

// A whole surface: the dial centred, corner stats in the corners of the box
// (DESIGN.md §2, §6.3). Popup, overlay and desktop widget all host this.
Item {
  id: face

  property var svc: null
  property TimechainPalette pal: TimechainPalette {}
  // Dial diameter as a fraction of the shorter side.
  property real dialFraction: 0.8
  property real margin: 16
  property bool showStats: true
  property bool animated: true
  // Hover details on the rings (off for the screensaver).
  property bool hoverDetails: true
  // Ambient motion such as the XBT orbit.
  property bool motion: true
  // Optional muted line at the bottom centre, e.g. "hover a ring for details".
  property string hint: ""

  readonly property real d: Math.min(width, height) * dialFraction
  readonly property real valueSize: Math.max(11, d * 0.042)
  readonly property real captionSize: Math.max(9, d * 0.022)
  readonly property var locale: Qt.locale("en_US")

  readonly property int h: svc ? svc.blockHeight : 0
  readonly property real price: svc ? svc.priceUsd : 0
  readonly property var now: new Date(svc ? svc.nowMs : Date.now())
  readonly property string timeFormat: svc && svc.config ? svc.config.timeFormat : "h:mm AP"
  readonly property bool showHashrate: svc && svc.config ? svc.config.showHashrate === true : false
  readonly property string ticker: svc ? svc.chainInfo.ticker : "BTC"

  TimechainDial {
    anchors.centerIn: parent
    width: face.d / 0.9
    height: width
    svc: face.svc
    pal: face.pal
    animated: face.animated
    hoverDetails: face.hoverDetails
    motion: face.motion
  }

  // 6 o'clock, above the hint line when there is one.
  ChainSwitch {
    visible: face.showStats
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: hintText.visible ? hintText.top : parent.bottom
    anchors.bottomMargin: hintText.visible ? face.captionSize * 0.8 : face.margin
    pal: face.pal
    svc: face.svc
    fontSize: Math.max(10, face.captionSize * 1.05)
  }

  CornerStat {
    visible: face.showStats
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.margins: face.margin
    pal: face.pal
    caption: "EPOCH"
    captionSize: face.captionSize
    valueSize: face.valueSize
    lines: [
      { text: face.h > 0 ? Model.epochRoman(face.h) : "—", font: face.pal.numeralFont,
        size: face.d * 0.11, color: face.pal.lavender, bold: false },
      { text: "SUBSIDY ₿" + (face.h > 0 ? Model.formatBtcAmount(Model.subsidySats(face.h)) : "—"),
        size: face.captionSize * 1.1, color: face.pal.muted, bold: false, font: face.pal.heightFont },
      { text: "SUPPLY ₿" + (face.h > 0 ? Model.supplyDisplayM(face.h) + "M" : "—"),
        size: face.captionSize * 1.1, color: face.pal.muted, bold: false, font: face.pal.heightFont },
      { text: (face.h > 0 ? Model.formatPercent(Model.supplyPercent(face.h)) : "—") + "% OF 21M",
        size: face.captionSize * 1.1, color: face.pal.muted, bold: false, font: face.pal.heightFont }
    ]
  }

  CornerStat {
    visible: face.showStats
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: face.margin
    alignRight: true
    pal: face.pal
    caption: "EXCHANGE"
    captionSize: face.captionSize
    valueSize: face.valueSize
    lines: {
      var out = [
        { text: "$" + (face.price > 0 ? Model.groupThousands(Math.round(face.price)) : "—"), suffix: "/" + face.ticker },
        { text: (face.price > 0 ? Model.satsPerUsd(face.price) : "—") + " SATS/USD",
          size: face.captionSize * 1.1, color: face.pal.muted, bold: false },
        { text: "MARKET " + Model.formatCompact(Model.marketCapUsd(face.h, face.price)) + " USD",
          size: face.captionSize * 1.1, color: face.pal.muted, bold: false }
      ]
      if (face.showHashrate)
        out.push({ text: "HASHRATE " + Model.formatHashrate(face.svc ? face.svc.hashrate : 0),
                   size: face.captionSize * 1.1, color: face.pal.muted, bold: false })
      return out
    }
  }

  CornerStat {
    visible: face.showStats
    anchors.left: parent.left
    anchors.bottom: parent.bottom
    anchors.margins: face.margin
    pal: face.pal
    lines: [
      { text: face.now.toLocaleTimeString(face.locale, face.timeFormat), size: face.d * 0.075,
        color: face.pal.teal, font: face.pal.valueFont }
    ]
  }

  CornerStat {
    visible: face.showStats
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.margins: face.margin
    alignRight: true
    pal: face.pal
    valueSize: face.valueSize
    lines: [
      { text: face.now.toLocaleDateString(face.locale, "dddd").toUpperCase(), color: face.pal.lavender,
        spacing: face.valueSize * 0.08 },
      { text: face.now.toLocaleDateString(face.locale, "MMM d, yyyy").toUpperCase(), color: face.pal.lavender,
        size: face.valueSize * 0.8, bold: false }
    ]
  }

  Text {
    id: hintText
    visible: face.showStats && face.hint !== ""
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: face.margin
    text: face.hint
    color: face.pal.muted
    opacity: 0.7
    font.pixelSize: face.captionSize
    font.letterSpacing: face.captionSize * 0.1
  }
}
