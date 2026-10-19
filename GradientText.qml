import QtQuick
import QtQuick.Effects

// Text filled with a horizontal two-colour gradient: the gradient rectangle is
// masked by the rendered glyphs (same MultiEffect mask pattern as
// plugins/image-picker/ImagePicker.qml).
Item {
  id: root

  property alias text: glyphs.text
  property alias font: glyphs.font
  property color from: "#b9a7ff"
  property color to: "#f0a6d8"

  implicitWidth: glyphs.implicitWidth
  implicitHeight: glyphs.implicitHeight

  Text {
    id: glyphs
    anchors.centerIn: parent
    visible: false
    layer.enabled: true
    color: "white"
  }

  Rectangle {
    anchors.fill: glyphs
    gradient: Gradient {
      orientation: Gradient.Horizontal
      GradientStop { position: 0; color: root.from }
      GradientStop { position: 1; color: root.to }
    }
    layer.enabled: true
    layer.smooth: true
    layer.effect: MultiEffect {
      maskEnabled: true
      maskSource: glyphs
      maskThresholdMin: 0.3
      maskSpreadAtMin: 0.3
    }
  }
}
