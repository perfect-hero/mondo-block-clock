import QtQuick

// A corner block: muted caption, then any number of value lines, aligned to
// the corner it sits in (DESIGN.md §2 corner table).
Column {
  id: stat

  required property TimechainPalette pal
  property string caption: ""
  property var lines: []            // [{ text, color?, size?, font?, bold?, suffix? }]
  property bool alignRight: false
  property real captionSize: 10
  property real valueSize: 16

  spacing: Math.round(valueSize * 0.2)

  Text {
    visible: stat.caption !== ""
    anchors.right: stat.alignRight ? parent.right : undefined
    text: stat.caption
    color: stat.pal.muted
    font.pixelSize: stat.captionSize
    font.letterSpacing: stat.captionSize * 0.12
  }

  Repeater {
    model: stat.lines

    // A value, and optionally a smaller muted suffix on the same baseline
    // ("$83,255" + "/BTC").
    Row {
      required property var modelData
      anchors.right: stat.alignRight ? parent.right : undefined
      spacing: suffix.visible ? Math.round(stat.captionSize * 0.35) : 0

      Text {
        id: value
        text: modelData.text
        color: modelData.color || stat.pal.text
        font.family: modelData.font || stat.pal.valueFont
        font.pixelSize: modelData.size || stat.valueSize
        font.bold: modelData.bold === undefined ? true : modelData.bold
        font.letterSpacing: modelData.spacing || 0
      }

      Text {
        id: suffix
        visible: !!modelData.suffix
        y: value.baselineOffset - baselineOffset
        text: modelData.suffix || ""
        color: stat.pal.muted
        font.family: stat.pal.valueFont
        font.pixelSize: stat.captionSize * 1.1
        font.letterSpacing: stat.captionSize * 0.08
      }
    }
  }
}
