import QtQuick

// Fixed Timechain colours and fonts (DESIGN.md §6.1–6.2). A plain object,
// one per surface, not a singleton: singletons survive the component cache.
QtObject {
  readonly property color bg: "#0f1116"
  readonly property color bgElevated: "#161a21"
  readonly property color hairline: "#14ffffff"
  readonly property color text: "#e6e8ef"
  readonly property color muted: "#8a90a0"
  readonly property color teal: "#5fd3e0"
  readonly property color amber: "#ffb347"
  readonly property color red: "#ff5c5c"
  readonly property color lavender: "#b9a7ff"
  readonly property color pink: "#f0a6d8"
  readonly property color tick: "#ffffff"
  readonly property color bitcoinOrange: "#f7931a"
  readonly property color nodeGold: "#f5cf75"

  // Ring colours (the reference design): amber halving, red-orange difficulty,
  // and a thin amber supply line.
  readonly property color ringSupply: "#d9a35c"
  readonly property color ringHalving: "#ffae42"
  readonly property color ringDifficulty: "#ff5a3c"

  readonly property string heightFont: "JetBrainsMono Nerd Font"
  readonly property string valueFont: "Liberation Sans"
  readonly property string numeralFont: "Liberation Serif"
}
