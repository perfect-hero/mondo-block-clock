# Block Clock for Omarchy — Design Document

**Status:** Draft v2 (review incorporated) · **Date:** 2026-10-12 · **Author:** Perfect Hero
**Plugin id:** `io.github.perfect-hero.mondo-block-clock` · **Target:** Omarchy 4.0.x (omarchy-shell on Quickshell 0.3.1, Qt 6.11.2)

---

## 0. Changes from v1

v1 was reviewed against the shell source (verdict: approve with changes).
Every review finding is resolved below; `[D#]` and `[Q#]` refer to that review.

| Area | v1 | v2 |
|---|---|---|
| Service lookup (§3.2) | assumed; Singleton fallback | verified; used as a **binding**, null-tolerant; Singleton fallback dropped [Q1, D18] |
| IPC (§3.4) | `shell call … refresh` | `IpcHandler` in `Service.qml` only; `omarchy-shell io.github.perfect-hero.mondo-block-clock refresh` [D1] |
| Summon routing (§3.4) | risk, two mitigations | resolved by `kinds`; bar widget keeps `open/close/opened` [Q2] |
| Settings (§8) | `plugins[]` fallback | deleted; bar entry is the on/off switch and the store; defaults applied in code; full-entry writes [D2, D6] |
| Ring gradient (§6.4) | stops in clockwise order | stops authored as `1 − p` (Qt interpolates counter-clockwise) [D3] |
| Annulus path (§6.4) | `PathLine` + inner arc | inner arc `moveToStart: false`; 0 and 360° guarded [D4] |
| Desktop layer (§7.3) | `ExclusionMode.Ignore`; hosted in service | `ExclusionMode.Normal`; service hosting is the M0 top risk, bar-widget fallback [D7, D9] |
| Polling (§5.2) | tip 20 s, price 60 s, `curl -f` | tip 30 s ±20 %, price 300 s + on open; status-code aware curl [Q5, D8] |
| Startup (§5.5) | cache and network race | scheduler starts after cache load; cache in `$XDG_STATE_HOME` [D10] |
| Hidden dials (§7.2) | eager per-monitor dial | dial inside `Loader { active: opened }`; timers stop when hidden [D11] |
| Overlay latency (§10) | "< 100 ms" | decided at M4 [D12] |
| Block timer (§5.3) | miner timestamp | local `firstSeenAt`, fallback to timestamp [D14] |
| Supply display (§5.3) | 20.10M | truncated: 20.09M; integer satoshi math [Q6, D15] |
| Keybind (§7.4) | `SUPER+SHIFT+B` (Browser) | `SUPER+ALT+B` (unbound on target) [D13] |
| Hyprland rule (§7.3) | `layerrule = noanim, …` | Lua `hl.layer_rule`; "blur off" dropped |
| Dev workflow (§10) | repo symlinked into plugins dir | repo **lives** in plugins dir; `~/Projects/mondo-block-clock` symlinks to it [D5] |
| Fonts (§6.2) | `Style.font.small` | `Style.font.caption` |
| Locale (§6, §8) | implicit en-US | explicit `Qt.locale("en_US")` + `timeFormat` setting [D16] |
| Reorgs (§9) | compare any page | compare within the tip page only [D17] |

Facts verified on the target machine or in the shell source are marked **[verified]**.
The few remaining unknowns are marked **[M0]** and are the whole scope of the spike (§10).

---

## 1. Goals and non-goals

### Goals
- A faithful, polished reproduction of the Block Clock dial: concentric gradient
  rings for supply, halving, difficulty, last-24h blocks; a huge gradient block height in
  the center; epoch/subsidy/supply, exchange/sats/market-cap, time and date in the corners.
- Four surfaces from one model:
  1. **Bar widget**: the BTC/USD price (`$81,685`) in the bar (block height until v0.2); pulses on a new block; left-click opens a popup.
  2. **Popup panel**: the full dial plus corner stats, anchored to the bar widget.
  3. **Always-on desktop widget**: the dial above the wallpaper, click-through, per-screen.
  4. **Fullscreen overlay**: a large dial summoned by a Hyprland keybind, dismissed by Esc.
- A **time-since-last-block ring** that fills over 10 minutes and shifts color each
  10-minute cycle, plus a subtle pulse in the bar when a block is found.
- Fixed "Timechain" palette independent of the active Omarchy theme.
- Public mempool.space as the only data source. USD only.
- Publishable: MIT, README with preview, settings schema, submittable to the
  Omarchy plugin marketplace.

### Non-goals (v1)
- Self-hosted mempool or Bitcoin Core RPC (an `apiBase` setting leaves the door open).
- The site's "supply slider" time-travel feature.
- Fee market, mempool depth, miner charts, price history.
- Theme-following colors (§13).
- Multiple fiat currencies.
- A desktop-only mode without a bar entry (§8.1, deferred).

---

## 2. Reference: what the dial shows

From the photographed reference (block 971130, 2026-10-12). Rings are drawn **outer → inner**,
all start at 12 o'clock and fill **clockwise**; each ring's label sits at its leading edge
and shows the *remaining* count.

| Ring (outer→inner) | Full circle means | Fill | Edge label |
|---|---|---|---|
| **Supply %** | 21,000,000 BTC | supply / 21M (≈95.7%) | none (value shown top-left) |
| **Blocks to halving** | one 210,000-block reward epoch | (h − epochStart) / 210,000 | blocks remaining, e.g. `78870` |
| **Blocks to difficulty adjust** | one 2,016-block retarget period | API `progressPercent` | blocks remaining, e.g. `582` |
| **Last 24 hours blocks** | 24 hours of wall-clock time | tick per block at its age | count, e.g. `148` |
| **Block timer** (added) | 10 minutes since last block | elapsed / 600 s, wraps | `m:ss` under the height |

Center: wordmark `TIMECHAIN CALENDAR`, label `BLOCK HEIGHT`, the height in a huge
lavender→pink gradient.

| Corner | Lines |
|---|---|
| Top-left | `EPOCH` + roman numeral (`V`) · `SUBSIDY ₿3.125 PER BLOCK` · `SUPPLY ₿20.09M · 95.7% OF 21M` |
| Top-right | `EXCHANGE 82868 USD/BTC` · `1207 SATS/USD` · `MARKET 1.67T USD` |
| Bottom-left | local time `3:22 PM` (teal) |
| Bottom-right | `MONDAY` · `OCT 12, 2026` (lavender) |

Sanity check **[verified]**: the photo shows 971130; the live API tip was 971131 with
`remainingBlocks` 581 (`2016 − 971131 % 2016 = 581`), and `1050000 − 971130 = 78870`.

---

## 3. Architecture

### 3.1 One plugin, three kinds

```
~/.config/omarchy/plugins/io.github.perfect-hero.mondo-block-clock/     (git repo; see §10)
  manifest.json          kinds: ["service", "bar-widget", "overlay"]
  Service.qml            data model, poller, cache, IpcHandler, desktop window(s)
  BarWidget.qml          bar pill (BTC/USD price), owns Panel.qml via Loader
  MapPin.qml             curved value pill with the remaining-blocks count
  ArcText.qml            text laid along a circle (ring legend, pill values)
  Panel.qml              popup (Ui/Panel); TimechainDial inside Loader { active: opened }
  Overlay.qml            fullscreen overlay containing TimechainDial
  TimechainDial.qml      the dial (rings, labels, centre), size-agnostic
  TimechainFace.qml      a whole surface: dial + corner stats; used by Panel, Overlay, desktop window
  DesktopWidget.qml      Variants of bottom-layer PanelWindows, instantiated by Service.qml
  GradientText.qml       lavender→pink text via a MultiEffect mask (block height)
  DialRing.qml           one gradient annulus-sector ring + edge marker + label
  BlockTickRing.qml      24h tick ring
  TimerRing.qml          10-minute block timer ring
  CornerStat.qml         label / value / sub-label stack
  TimechainPalette.qml   fixed color + font tokens (plain QtObject, one per surface)
  TimechainModel.js      pure functions + DEFAULTS: epoch, subsidy, supply, roman, formats, ring math
  Fetcher.qml            one curl Process + status parsing (one instance per endpoint)
  tests/                 node --test suites for TimechainModel.js and manifest/DEFAULTS parity
  fixtures/              offline JSON for screenshots and replay (read-only at runtime)
  README.md  LICENSE  preview.png
```

`TimechainPalette` stays a per-surface `QtObject`, **not** a `pragma Singleton`. It cannot be
called `Palette`: QtQuick ships a built-in `Palette` type that shadows a same-named local file,
and `palette` is a FINAL property on `Item` [found M2].

Precedent **[verified]**: `omarchy.media` declares `kinds: ["service","bar-widget"]`
(with `keepLoaded: true`, which we do not copy); `omarchy.emojis` is an `overlay`;
`omarchy.background` owns a `PanelWindow`, but it is first-party and parented to
`serviceHost`, whereas third-party services get a **null parent** (`shell.qml:923`).

### 3.2 Who owns the data

`Service.qml` is the **only** component that talks to the network and the only owner of
chain state. The bar widget, popup, overlay and desktop window read from it.

Lookup path **[verified]**: a third-party widget's facade comes from
`pluginShellForId(moduleName)` (`plugins/bar/Bar.qml:234-237`); its `_serviceLookup`
is gated by `pluginOwnsTarget` (`shell.qml:385-394, 608-610`), so a plugin can fetch
exactly its own service. The overlay receives the same facade from the panel Loader
(`shell.qml:1342`).

**Rule: always a binding, never cached.**

```qml
readonly property var svc: bar && bar.shell ? bar.shell.serviceFor(moduleName) : null   // BarWidget
readonly property var svc: shell ? shell.serviceFor("io.github.perfect-hero.mondo-block-clock") : null  // Overlay
```

`svc` is null (i) under a third-party replacement bar (`Bar.qml:238-243`), (ii) before the
service finishes loading, (iii) when the plugin is disabled, and (iv) during hot-reload,
when services are destroyed and rebuilt (`shell.qml:1452-1461`). Every consumer renders a
placeholder (`₿ —`, empty dial) when `svc` is null and never throws. Caching the reference
in `Component.onCompleted` would leave a dangling object after a reload.

**[verified M0, test 4]** Traced from the widget: at creation `svc` is null, then the
binding re-evaluates to the live service (`ticks=0`) and the label counts. On a plugin
reload the shell destroys the widget *and* the service (`svc` → null first) and creates
both again; the new widget binds to the new service with no warnings. Service state does
not survive a reload — the disk cache (§5.5) is what makes reloads cheap.

### 3.3 Lifecycle

- The `service` entry point is mounted at shell start and rebuilt on plugin hot-reload.
  We do **not** set `keepLoaded`: it is one manifest-level flag that pins *both* the service
  and the overlay Loader (`shell.qml:1024-1040, 1316, 1337`), which would cost service
  hot-reload.
- A disk cache (§5.5) makes rebuilds cheap and avoids a cold-start burst against the API.
- The popup is loaded by the bar widget's `Loader` (weather pattern) so it participates in
  the bar's one-popup-at-a-time coordinator. Each per-monitor widget therefore owns a Panel;
  the dial inside it is behind `Loader { active: panel.opened }` so N monitors do not mean
  N live dials [D11].
- The overlay is loaded on demand by `summon` (asynchronous Loader, `shell.qml:1338`) and
  destroyed on `hide` immediately after `close()` — no exit animation.
- **Enabled state:** a third-party plugin is enabled iff its id is in `shell.json`, which
  for us means iff the bar entry exists (§8). Removing the widget from the bar removes the
  service, overlay and desktop widget too. The README says so.

### 3.4 IPC surface

| Command | Effect | Route |
|---|---|---|
| `omarchy-shell shell toggle io.github.perfect-hero.mondo-block-clock` | toggle the fullscreen overlay | panel Loader, `overlay` entry point |
| `omarchy-shell io.github.perfect-hero.mondo-block-clock refresh` | force a full refresh | `IpcHandler` in `Service.qml` |
| `omarchy-shell io.github.perfect-hero.mondo-block-clock desktop toggle\|show\|hide` | desktop widget | `IpcHandler` in `Service.qml` |
| `omarchy-shell io.github.perfect-hero.mondo-block-clock status` | JSON: height, online, lastSuccessAt | `IpcHandler` in `Service.qml` |

```qml
// Service.qml — same pattern as plugins/services/media/Service.qml:476
IpcHandler {
  target: "io.github.perfect-hero.mondo-block-clock"
  function refresh(): string { root.refresh(); return "ok" }
  function desktop(action: string): string { return root.desktopAction(action) }
  function status(): string { return root.statusJson() }
}
```

- `shell call` is **not** used: `callIfLoaded` only reaches loaded panel/overlay items
  (`shell.qml:1279-1291`) **[verified]**.
- The handler lives only in the service. Bar widgets exist once per monitor and would
  register duplicate targets (`Ui/BarWidget.qml:25-28`).
- Routing **[verified]**: because `kinds` contains `overlay`, `isBarWidgetPanelPlugin`
  returns false (`shell.qml:1138-1150`), so `summon`/`hide`/`toggle` always reach the
  overlay. Consequences: the popup cannot be hotkey-summoned, and `togglePanelAt` for the
  widget's bar slot also opens the overlay (`shell.qml:1731-1738`). The bar widget still
  exposes `open/close/opened` at its root so it stays in the bar's left/right panel
  navigation (`Bar.qml:627-644`).
- **Re-registration across a reload [verified M0, test 3]:** with an instance id in
  `status()`, three consecutive plugin reloads were each answered by the *new* service
  instance, and the log had no duplicate-target warning for `io.github.perfect-hero.mondo-block-clock`
  (the old instance is destroyed before the new one registers). During the ~1–2 s rebuild
  window a call returns `Target not found.` with exit code 1; a call made mid-rebuild can
  also block until the shell finishes. Scripts and keybinds use `omarchy-shell -q` where
  a miss is harmless (it exits 0).

---

## 4. Manifest

```json
{
  "schemaVersion": 1,
  "id": "io.github.perfect-hero.mondo-block-clock",
  "name": "Block Clock",
  "version": "0.1.0",
  "author": "Perfect Hero",
  "license": "MIT",
  "description": "Bitcoin timechain dial: block height, supply, halving and difficulty rings, last-24h blocks, price — in the bar, a popup, on the desktop, or fullscreen.",
  "kinds": ["service", "bar-widget", "overlay"],
  "entryPoints": {
    "service": "Service.qml",
    "barWidget": "BarWidget.qml",
    "overlay": "Overlay.qml"
  },
  "barWidget": {
    "displayName": "Block Clock",
    "description": "₿ block height in the bar; click for the full Timechain dial.",
    "category": "Info",
    "allowMultiple": false,
    "defaultSection": "right",
    "defaults": { "...mirrors DEFAULTS in TimechainModel.js, §8...": null },
    "schema": [ "...see §8..." ]
  }
}
```

Manifest `defaults` are registry metadata only; enabling inserts a bare `{ id }`
(`PluginRegistry.qml:516-525`) **[verified]**. They are kept for the settings UI and must
equal `DEFAULTS` in `TimechainModel.js`; a unit test enforces this (§11).

---

## 5. Data model

### 5.1 Endpoints

| Purpose | Endpoint | Cadence | Size |
|---|---|---|---|
| Tip height | `GET /api/blocks/tip/height` → `971131` (text) | every `refreshIntervalSec` (default 30 s, ±20 % jitter) | ~6 B |
| Tip page (15, with `extras`) | `GET /api/v1/blocks` | on height change | ~30 KB |
| Backfill (10, no extras) | `GET /api/blocks/:height` | cold start only, paged | lighter |
| Difficulty | `GET /api/v1/difficulty-adjustment` | on height change | ~300 B |
| Price | `GET /api/v1/prices` → `{time, USD, …}` | every `priceRefreshSec` (default 120 s; was 300 before the bar showed price), and on open of a price-showing surface | ~100 B |
| Hashrate (opt-in) | `GET /api/v1/mining/hashrate/3d` | every 10 min, only if `showHashrate` | ~400 B |

Block fields used: `height, id, timestamp, tx_count`; for tip-page blocks also
`extras.pool.name, extras.medianFee, extras.reward`. Pool name is only shown for the tip,
so backfill uses the lighter non-v1 endpoint. **[verified M1]** `/api/v1/blocks` returns 15
blocks with `extras`; `/api/blocks/:h` returns 10 (h and the 9 below) without. A cold start
takes 13–15 backfill pages for ~160 blocks. Tip-page blocks also carry `extras.firstSeen`
(when mempool.space first saw the block), used as the timer fallback before the miner
timestamp (§5.3).

**Transport [verified]:** `Quickshell.Io.Process` + `StdioCollector`, as weather does
(`plugins/panels/weather/Panel.qml`). `QtWebSockets` is not installed; `XMLHttpRequest`
is untested inside Quickshell and not used.

```
curl -sS --max-time 10 -w '\n%{http_code}' <url>
```

`Fetcher.qml` splits off the last line as the status code (no `-f`, so 429 is
distinguishable and the body is kept) and classifies:

| Result | Class | Action |
|---|---|---|
| exit 0, 2xx, parses | ok | update state, reset interval |
| exit 0, 429 or 5xx | backoff | double current interval, cap 300 s, add jitter |
| exit 0, other 4xx | config | log `[timechain] check apiBase`, stale state, poll at 300 s |
| non-zero exit | network | as backoff |
| 2xx but malformed | bad data | `console.warn`, discard, keep state |

Each `Fetcher` guards with `running`: a tick that finds its endpoint in flight is skipped,
so no endpoint ever has two concurrent requests.

### 5.2 Polling strategy

- A single scheduler `Timer` in the service drives everything; surfaces never fetch.
- **Tip poll** is the heartbeat: 30 s ± 20 % (≈2,900 req/day). mempool.space publishes no
  limit and no documented `Retry-After`; this is a conservative default.
- **On tip change:** fetch the tip page and difficulty; merge blocks by height; record
  `firstSeenAt = Date.now()` for the new tip (§5.3).
- **Price:** 120 s, plus one immediate fetch when the popup, overlay or desktop widget
  becomes visible and the last price is older than 60 s. The bar pill shows the price.
- **24 h cold start:** after the tip page, page backwards with `/api/blocks/:height`
  spaced 400 ms until the oldest block is older than 24 h, **capped at 16 pages**. With the
  cache this runs only on first install or after > 24 h offline.
- **Stale:** UI shows the stale state once the last successful tip poll is > 2 min old.

### 5.3 Derived values (`TimechainModel.js`, pure, unit-tested)

All supply math is integer satoshis (consensus right-shift semantics) [D15].

```
HALVING = 210000
epochIndex(h)        = floor(h / HALVING)                       // 4 at 971130
epochRoman(h)        = roman(epochIndex(h) + 1)                 // "V"
subsidySats(h)       = i >= 64 ? 0 : floor(5e9 / 2^i)           // i = epochIndex(h); 312500000 = ₿3.125
epochStart(h)        = epochIndex(h) * HALVING
blocksToHalving(h)   = epochStart(h) + HALVING - h              // 78870
halvingProgress(h)   = (h - epochStart(h)) / HALVING            // 0.62443
supplySats(h)        = Σ_{i<epochIndex} HALVING * floor(5e9 / 2^i)
                       + (h - epochStart(h) + 1) * subsidySats(h)   // +1: genesis inclusive
                     // 2,009,728,437,500,000 sats = ₿20,097,284.375 at 971130
supplyDisplayM(h)    = floor(supply / 1e4) / 100                // "20.09" — truncate, as the site does
supplyPercent(h)     = supply / 21e6                            // 95.7 %
blocksToRetarget     = api.remainingBlocks   (fallback 2016 - h % 2016)
retargetProgress     = api.progressPercent / 100   (fallback (h % 2016) / 2016)
satsPerUsd(price)    = round(1e8 / price)                       // 1207 at $82,868
marketCap            = supply * price                           // $1.665T → "1.67T"
blocksLast24h        = count(blocks where clampAge(now - timestamp) <= 86400)
clampAge(a)          = max(0, a)                                // miner clocks can run ahead
sinceLastBlock       = now - (tip.firstSeenAt ?? tip.firstSeen * 1000 ?? tip.timestamp * 1000)   // 1 s Timer
```

Supply sums stay below 2^53 sats (2.1e15 < 9.0e15), so doubles are exact. Unclaimed and
provably-unspendable coins (~150–200 BTC) are not special-cased; the difference from the
site is display rounding only [Q6].

Hand-checked values the unit tests must reproduce:

| h | epoch | subsidy | blocksToHalving | halvingProgress | supply (BTC) |
|---|---|---|---|---|---|
| 0 | I | 50 | 210,000 | 0 | 50 |
| 209999 | I | 50 | 1 | 0.999995 | 10,500,000 |
| 210000 | II | 25 | 210,000 | 0 | 10,500,025 |
| 840000 | V | 3.125 | 210,000 | 0 | 19,687,503.125 |
| 971130 | V | 3.125 | 78,870 | 0.62443 | 20,097,284.375 |
| 1049999 | V | 3.125 | 1 | 0.999995 | 20,343,750 |
| 1050000 | VI | 1.5625 | 210,000 | 0 | 20,343,751.5625 |

### 5.4 Service public surface

```qml
// Service.qml (root Item, null parent)
property var shell                       // injected; `settings` is never injected (shell.qml:928-932)
readonly property var   config           // DEFAULTS merged with the bar entry (§8)
readonly property int   blockHeight      // not `height`: Item.height is FINAL [M1]
readonly property var   tip              // latest block + firstSeenAt
readonly property var   recentBlocks     // newest first, pruned to 24 h
readonly property var   difficulty       // raw API object
readonly property real  priceUsd
readonly property real  priceAt          // epoch ms
readonly property real  hashrate
readonly property int   sinceLastBlockSec
readonly property bool  online           // last tip poll ok
readonly property bool  ready            // cache loaded or failed; scheduler running
readonly property real  lastSuccessAt
readonly property int   newBlockSerial   // increments on each new tip → pulses
function refresh()
function desktopAction(action)           // "toggle" | "show" | "hide"
function updateSetting(key, value)       // full-entry write (§8)
function statusJson()
signal newBlock(var block)
```

### 5.5 Disk cache

- Path: `$XDG_STATE_HOME/mondo-block-clock/state.json` (default
  `~/.local/state/mondo-block-clock/`), outside Omarchy's own namespace and outside the
  plugins directory (writes there would trigger plugin reloads, `shell.qml:1474-1480`).
- `FileView.setText` does not create directories: the service runs `mkdir -p` once via
  `Process` before the first write.
- Contents: `{version, height, tip, blocks[], difficulty, priceUsd, priceAt, savedAt}`.
  Written at most once per minute and on every new block.
- **Startup order [D10]:** the scheduler starts only after `FileView` `onLoaded` or
  `onLoadFailed`. Network results merge by height and the highest tip wins regardless of
  source, so a late cache can never overwrite newer data.
- Blocks older than 24 h are pruned on load and on every merge.

---

## 6. Visual design

### 6.1 Palette (`Palette.qml`, fixed)

| Token | Value | Use |
|---|---|---|
| `bg` | `#0f1116` | popup/overlay surface; desktop disc (optional, default transparent) |
| `bgElevated` | `#161a21` | dial face behind rings |
| `hairline` | `#ffffff` @ 8% | ring tracks, guide circles |
| `ringSupply` / `ringHalving` / `ringDifficulty` | `#d9a35c` / `#ffae42` / `#ff5a3c` | solid ring colours since v0.3 (the gradient `ringStops` of v0.1–0.2 are gone); each ring's track is its own colour at 20–30 % |
| `heightGradient` | `#b9a7ff` → `#f0a6d8` (left→right) | block height, date |
| `teal` | `#5fd3e0` | clock, timer ring cycle 1 |
| `amber` / `red` | `#ffb347` / `#ff5c5c` | timer ring cycle 2 / 3+ |
| `text` | `#e6e8ef` | values |
| `muted` | `#8a90a0` | labels, wordmark |
| `tick` | `#ffffff` @ 70%, newest `#f0a6d8` | 24 h block ticks |

Stop positions are first guesses, tuned against a side-by-side screenshot in M2.

### 6.2 Typography

- **Labels:** shell `Style.font` family, uppercase, letter-spacing 0.12 em, size
  `Style.font.caption` (`Commons/Style.qml:327`).
- **Block height:** JetBrainsMono Nerd Font Bold, tabular digits. Size 0.19 × D.
- **Corner values:** Liberation Sans / Noto Sans Bold, 0.045 × D.
- **Epoch numeral:** Liberation Serif Regular, 0.11 × D, lavender with 1 px outline.
- All of the above and `U+20BF` are present on the target (`fc-list ':charset=20bf'`)
  **[verified]**.
- **Locale:** dates and times are formatted with `Qt.locale("en_US")` explicitly so the
  reference look does not depend on the system locale. Time uses the `timeFormat` setting
  (default `h:mm AP`); date is `dddd` / `MMM d, yyyy`, uppercased.

### 6.3 Geometry (relative to dial diameter `D`)

```
ring 1 (supply)        outer r = 0.500 D   thickness 0.010 D
ring 2 (halving)             r = 0.468 D   thickness 0.014 D
ring 3 (difficulty)          r = 0.440 D   thickness 0.014 D
ring 4 (24h ticks)           r = 0.400 D   tick length 0.020 D, width 1.5 px
ring 5 (10-min timer)        r = 0.360 D   thickness 0.008 D
center text block            r < 0.30 D
ring labels                  none on the dial; hovering a ring shows its name and details in
                             the centre (v0.2; the 11 o'clock label stack was removed)
pins                         map pin on the halving and difficulty arc ends: round head
                             (text-fitted, upright), tip 1.65 r from the head centre, outline
                             in the ring's colour there; head points outward, the inner pin
                             turns inward when the two are within 24°
arc ends                     rounded (discs in the end colours)
glow                         blurred copy of the rings at 50 % beneath them; faint lavender
                             radial light behind the dial
corner stats                 corners of the hosting surface, not of the dial
```

### 6.4 Ring rendering

QtQuick.Shapes has `fillGradient` but no stroke gradient, so each progress ring is a
**filled annulus sector** drawn with `Shape.CurveRenderer` **[verified]**
(`Shapes/plugins.qmltypes:51, 210-218`; used first-party in `Ui/BorderOverlay.qml:28-33`).
No MSAA fallback.

**Gradient direction [D3]:** Qt's `ConicalGradient` interpolates **counter-clockwise** from
`angle` (0° = 3 o'clock). With `angle: 90` (12 o'clock) the stops are fed reversed so the
ring reads red → green clockwise:

```qml
fillGradient: ConicalGradient {
  centerX: cx; centerY: cy; angle: 90
  // Palette.ringStops authored clockwise; position = 1 - p
  GradientStop { position: 1.00; color: "#ff4d5a" }
  GradientStop { position: 0.70; color: "#ff8c42" }
  GradientStop { position: 0.45; color: "#ffd84d" }
  GradientStop { position: 0.20; color: "#b8e04a" }
  GradientStop { position: 0.00; color: "#4fd18b" }
}
```

**[verified M0, test 2]** (`SpikeRing.qml`, screenshot sampled at radius 163 px on a
360 px surface): 3° clockwise from 12 o'clock `#ff4e59`, 90° `#ff8145`, 180° `#ffc84a`,
225° `#e9da4c`, and on the full ring 357° `#53d188` — red → green clockwise as intended.
The 70 % sector ends between 250° and 256° (expected 252°). Zoomed crops show clean
radial edges at both ends and no chord artefacts. The full ring has no geometric seam;
it does show the inherent hard green→red step at 12 o'clock where a 360° conical gradient
wraps. No gradient ring reaches 100 % in practice (halving and retarget progress top out
just below 1 before resetting; supply never does; the timer ring uses solid colours), so
it is accepted.

**Path [D4]:** `PathAngleArc.moveToStart` defaults to `true`, which would start a second
subpath. The inner arc sets it to `false`, so the arc's implicit line from the current
point *is* the radial edge:

```qml
Shape {
  preferredRendererType: Shape.CurveRenderer
  visible: progress > 0
  ShapePath {
    strokeWidth: -1
    fillRule: ShapePath.OddEvenFill
    fillGradient: /* as above */
    // outer arc, clockwise from 12 o'clock
    PathAngleArc { centerX: cx; centerY: cy; radiusX: rOuter; radiusY: rOuter
                   startAngle: -90; sweepAngle: sweep }
    // inner arc, back to 12 o'clock; draws the end radial line itself
    PathAngleArc { centerX: cx; centerY: cy; radiusX: rInner; radiusY: rInner
                   startAngle: -90 + sweep; sweepAngle: -sweep; moveToStart: false }
    // implicit close draws the start radial line
  }
}
```

- `sweep = clamp(progress, 0, 1) * 360`.
- `progress ≤ 0`: the Shape is hidden.
- `progress ≥ 1`: a separate full-ring `ShapePath` (two full circles, outer then inner with
  `moveToStart: true`, `OddEvenFill`) replaces the sector so there is no seam.

The unfilled remainder is a thin `hairline` stroke ring beneath. Colour depends on angle,
not progress — the supply ring reaches green only because it is 95 % full, as in the
reference. `sweep` animates with `NumberAnimation { duration: 600; easing.type: Easing.OutCubic }`.

**Alternatives considered:** `Canvas` (blurry at HiDPI); a `ShaderEffect` (crisper, needs
shipped `qsb` shaders — v2 option if Shapes is too slow on the desktop widget).

### 6.5 24-hour tick ring

12 o'clock = now; a block `age` seconds old is drawn at `age / 86400 × 360°` **clockwise**,
matching the other rings' sweep [Q7]. Ages are clamped below at 0 and blocks older than
86,400 s are not drawn. `Repeater` of rotated 1.5 px `Rectangle`s (~150 items). Newest tick
pink and longer; ticks fade 70 % → 35 % with age. A muted dot marks "now"; the count is in
the ring's hover details. Re-layout once per minute.

### 6.6 Block timer ring and states

- Fills clockwise over 600 s from `firstSeenAt` (fallback: tip timestamp, §5.3).
  Cycle 1 teal, 2 amber, 3+ red; resets on a new block. `m:ss` under the height.
- **New block:** `newBlockSerial` increments → bar pill sweeps lavender→pink→foreground over
  1.2 s; height scales 1.0→1.04→1.0 over 400 ms; rings animate to new sweeps.
- **Stale** (> 2 min since last successful tip poll): rings at 40 % opacity, `stale · 5m`
  caption under the wordmark, dim dot on the bar pill.
- **Loading** (`ready` false, or no data yet): rings at 0 %, height `······`.
- **No service** (`svc` null, §3.2): bar shows `₿ —`; dial surfaces show the loading state.
- All 1 Hz timers run only while their surface is visible.

---

## 7. Surfaces

### 7.1 Bar widget (`BarWidget.qml`)

- Extends `Ui/BarWidget` with a `WidgetButton` (text, not an icon slot) **[built M1]**.
- Text: the price, `$81,685`, in `bar.fontFamily` (v0.2; it showed `₿ 971130` before). In a
  vertical bar the sign and the price stack in three-digit groups (`$` / `81` / `685`), the
  way the clock stacks hours over minutes. Still pulses on each new block.
- Clicks: left = toggle popup (until M2: refresh) · right = toggle desktop widget (via
  `svc.desktopAction`) · middle = `svc.refresh()`.
- Dimmed (the shell's 45 % `dimmed` state) while stale or when there is no service.
- Tooltip: `Block 971130 · 4:32 ago · F2Pool · $82,699` (price from cache).
- Exposes `open/close/opened` at root for bar navigation (§3.4).

### 7.2 Popup panel (`Panel.qml`)

- Extends `Ui/Panel` with the weather open/close/toggle/popout contract **[verified]**.
- Size 640 × 580 px (scaled by `Style`); dial `D = 460`; corner stats in the panel corners;
  `Palette.bg` with the shell's `popups.border` frame.
- `TimechainDial` sits in `Loader { active: panel.opened }` [D11]; opening triggers a price
  refresh if stale (§5.2).
- Keys: `Esc` closes · `d` desktop toggle · `f` closes the popup and summons the overlay ·
  `r` refresh.

### 7.3 Always-on desktop widget

**Hosted in `Service.qml` [verified M0, test 1].** A `Variants` + `PanelWindow` declared
in the null-parented third-party service root is created, maps on its screen, sits on
layer level 1 (bottom) beneath tiled windows, and logs no warnings. With `mask: Region {}`
a hand pointer test recorded 0 hover/press events; with `mask: null` (control) it recorded
7 enters and 2 presses. The mask can also be swapped at runtime. Only one monitor
(eDP-1) was available, so multi-screen mapping is untested but uses the standard
`Variants { model: Quickshell.screens }` pattern from `Background.qml:181`.

```qml
Variants { model: targetScreens   // Quickshell.screens, or the one named by desktopScreen
  PanelWindow {
    required property var modelData
    screen: modelData
    visible: root.config.desktopWidget
    WlrLayershell.namespace: "mondo-block-clock"
    WlrLayershell.layer: WlrLayer.Bottom          // above omarchy-background, below windows
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Normal           // respect the bar's zone; reserve nothing
    color: "transparent"
    mask: Region {}                               // empty region = no input
    anchors / margins: from desktopAnchor, desktopMargin
    implicitWidth/Height: desktopSize (+ room for corner stats if desktopStats)
    TimechainDial { opacity: root.config.desktopOpacity / 100 }
  }
}
```

- **Layer [verified]:** `omarchy-background` is `WlrLayer.Background`
  (`plugins/background/Background.qml:217`); `Bottom` sits above it and below windows.
- **Click-through [verified]:** `Region {}` is an empty region; `null` would make the whole
  window take input. Same as `plugins/osd/Osd.qml:135-137`.
- **Exclusion [D9]:** `Normal` with the default `exclusiveZone: 0` keeps the widget out of
  the bar's zone on whichever edge the bar is [verified on two edges]. With the bar on the
  left (28 px) a centred surface sat at x=794, not 780 [M0]; with the bar on top (26 px)
  `center` sits at y = 26 + (1054 − h)/2 and `top-right` at y = 26 + margin [M3]. The plugin
  never touches the bar's position (`omarchy bar position <edge>`).
- **Fallback (not needed):** each per-monitor bar widget would own the desktop window.
  Kept here only in case multi-monitor testing reveals a problem.
- **Hyprland (README, user's `~/.config/hypr/`):**
  `hl.layer_rule({ match = { namespace = "mondo-block-clock" }, no_anim = true, animation = "none" })`
  — same form as `default/hypr/apps/omarchy-shell.lua:5`. Layer blur is opt-in, so no blur
  rule is needed.
- Toggle: `desktopWidget` setting, bar right-click, IPC `desktop toggle`. Toggles persist by
  writing the setting (§8).

### 7.4 Fullscreen overlay (`Overlay.qml`)

- Pattern of `plugins/emojis/Emojis.qml` **[verified]**: root `Item` with
  `open(payloadJson)`, `close()`, `dismiss()` → `shell.hide(id)`; a `PanelWindow` on
  `WlrLayer.Overlay`, `Palette.bg` @ 88 % scrim, `Exclusive` keyboard focus while open.
- Dial `D = 0.78 × min(screen.width, screen.height)`; corner stats at screen corners with
  `Style.gapsOut × 6` margins.
- `Esc`, scrim click, or the keybind again closes it. No exit animation (§3.3).
- Opening triggers a price refresh if stale.
- Suggested binding (README; `SUPER + ALT + B` is unbound on the target **[verified]**):
  `o.bind("SUPER + ALT + B", "Timechain calendar", "omarchy-shell shell toggle io.github.perfect-hero.mondo-block-clock")`
- README note: the keybind and `togglePanelAt` open the overlay, never the popup.

---

## 8. Settings

### 8.1 Where settings live

- **The bar layout entry is both the plugin's on/off switch and its settings store**
  (`README.md:274-276`, `PluginRegistry.qml:148-163`) **[verified]**. There is no
  `plugins[]` fallback: third-party facades expose only the `bar` subtree.
- **Defaults are applied in code.** `TimechainModel.js` exports `DEFAULTS`; every surface
  reads `setting(key) = key in entry ? entry[key] : DEFAULTS[key]`. The manifest `defaults`
  and schema `defaultValue`s mirror it (test-enforced, §11).
- **Service read path:** `shell.barConfig` is a deep copy of `bar` reassigned on every
  `shell.json` change (`shell.qml:326-328, 879`). The service scans
  `barConfig.layout.{left,center,right}` for the first entry whose
  `Util.canonicalWidgetId(id)` is ours, merges with `DEFAULTS` into `config`, and only
  updates `config` (and restarts timers / rebuilds windows) when
  `JSON.stringify(merged)` actually changed.
- **Widget read path:** the bar passes the entry to the widget (`BarModel.js:10-18`);
  same merge.
- **Writes:** `shell.updateEntryInline(ownId, settings)` replaces the whole entry
  (`shell.qml:1078-1097`), scoped to the caller's own id (`shell.qml:648-651`). Writers
  always send the **full merged** settings object, never a patch.
- **Future desktop-only mode:** an own `~/.config/omarchy/timechain.json` watched with
  `FileView`, as Omascape does (`omascape/OmascapeConfig.qml:46`). Not in v1.

### 8.2 Schema

| key | type | default | notes |
|---|---|---|---|
| `apiBase` | string | `https://mempool.space` | any mempool instance; no trailing slash |
| `refreshIntervalSec` | integer 15–300 | 30 | tip poll; ±20 % jitter applied |
| `priceRefreshSec` | integer 60–900 | 120 | the bar shows price; plus on-open refresh |
| `showTimerRing` | boolean | true | 10-minute block timer ring |
| `showHashrate` | boolean | false | `HASHRATE 994 EH/s` under market cap; enables hashrate polling |
| `desktopWidget` | boolean | false | always-on widget |
| `desktopScreen` | string | `""` | empty = every screen; else a monitor name |
| `desktopAnchor` | enum (`options`) | `center` | `center, top-left, top-right, bottom-left, bottom-right` |
| `desktopSize` | integer 240–1200 | 480 | dial diameter, px |
| `desktopMargin` | integer 0–400 | 48 | px from anchored edges |
| `desktopOpacity` | integer 20–100 | 90 | percent |
| `desktopStats` | boolean | true | corner stats around the desktop dial |
| `timeFormat` | string | `h:mm AP` | Qt time format, `en_US` locale |

Types follow first-party schemas (`integer`, `string`, `enum` with `options`, as in
`agents/manifest.json`); there is no `number` type in use.

---

## 9. Error handling and resilience

- Every fetch has a 10 s timeout; failures never clear existing state.
- Classification and backoff per §5.1: backoff doubles the *current* interval with jitter
  and resets on success. 429/5xx cap at 300 s; local network failures (offline, DNS,
  refused) cap at 60 s, since they cost the server nothing [M2].
- **Suspend/resume [M2]:** the service's 1 s clock detects a wall-clock jump (> 5 s, or
  backwards), resets the backoff and refreshes 3 s later. Found when the laptop slept
  17:15–17:36 and Wi-Fi returned at 17:49: with a 300 s network cap the popup stayed stale
  for minutes after the network was back.
- Network failures log curl's own message (`Could not resolve host`, `Failed to connect`),
  and repeated identical poll results are logged once.
- Malformed JSON → `console.warn("[timechain] …")`, response discarded.
- Clock skew: ages and `sinceLastBlock` clamp at 0; the timer prefers local `firstSeenAt`
  so a miner timestamp minutes in the past does not inflate it.
- **Reorgs [D17]:** compared only within the tip page (overlapping cold-start pages are not
  compared). If the tip page's block at height `h` has a different `id` from the cache,
  that entry and everything above it are replaced. Pruning is by height and age.
- Concurrency: one in-flight request per endpoint (§5.1).
- Writes only to `$XDG_STATE_HOME/mondo-block-clock/` and, via the shell API, our own
  bar entry. No secrets.

---

## 10. Delivery plan

**Dev workflow [D5]:** the git repo lives at
`~/.config/omarchy/plugins/io.github.perfect-hero.mondo-block-clock` so the shell's
`inotifywait -r` watcher (which does not follow symlinks) sees edits and hot-reloads.
`~/Projects/mondo-block-clock` is a symlink to it. `.git/` is ignored by the watcher;
any other write in the directory — including docs — triggers a (debounced) plugin reload,
so runtime output (cache, replay state, screenshots) goes to `$XDG_STATE_HOME` or a
scratch directory, never into the repo. The fixture server (`tests/fixture_server.py`)
synthesizes its chain in memory and writes nothing, so it can run from the repo.

**Hot-reload does not apply code changes to any entry point [found in M0, tests 1 and 4].**
On a file change the shell logs `Local plugin changed, reloading`, destroys the service and
bar widget and recreates them — but from the **old** compiled code. Version markers in
`Service.qml` (two consecutive reloads), `BarWidget.qml` (`w1`→`w2`) and `Overlay.qml`
(opened, closed, edited `o1`→`o2`, opened again: still `o1`) all stayed stale and appeared
only after `omarchy restart shell`.
Probable cause (not verified): `finishPluginReload` calls `Qt.clearComponentCache()`
(`shell.qml:1470`) while the previous `Qt.createComponent` object from `ensureService`
(`shell.qml:914`) is still alive, and Qt does not evict a still-referenced type.
Consequences:
- The edit loop for all plugin code is **edit → `omarchy restart shell`** (≈ 2 s; the bar
  blinks). Hot-reload is still useful for one thing: it rebuilds live objects, so it
  exercises the null-service and re-binding paths (§3.2).
- The v1 rationale "no `keepLoaded`, so edits apply live" no longer holds for the service;
  `keepLoaded` stays off for the reasons in §3.3 and §7.4 only.
- Keeping the repo inside the plugins directory still helps whatever does reload, and costs
  nothing.
- Worth an upstream report: it affects every third-party plugin's dev loop.

| Milestone | Scope | Exit criteria |
|---|---|---|
| **M0 Spike (2–3 h)** | Minimal 3-kind manifest. (1) Service with a `Variants` + `PanelWindow` on `WlrLayer.Bottom` with `Region {}` mask. (2) One `ConicalGradient` annulus sector at ~70 %, screenshotted. (3) `IpcHandler` answering `status`, then a file touch to force hot-reload and call it again. (4) Bar widget showing a service property via the binding. | (1) window maps on every screen and is click-through, or the bar-widget fallback is chosen; (2) red at 12 o'clock, clockwise to green; (3) handler answers after reload with no duplicate-target warning; (4) value shows and survives reload. Results recorded in §3–§7 |
| **M1 Model + bar** ✅ | `TimechainModel.js` + `DEFAULTS` + node tests; `Fetcher.qml`; `Service.qml` poller, cache, backoff, IPC; `BarWidget.qml` with pulse, tooltip, null-service state | `₿ height` live; pulses on a real block; 429 replay backs off; shell restart reloads from cache with no cold-start paging — all met, see §10.1 |
| **M2 Dial + popup** ✅ | `TimechainDial`, rings, ticks, timer, corner stats; `Panel.qml` | side-by-side with the reference within tuning distance; no hidden live dials on other monitors — see §10.2 |
| **M3 Desktop widget** ✅ | layer window per §7.3 (or fallback), settings, toggles | survives workspace switches, theme changes, hot-reload and shell restart; < 1 % idle CPU — all met, see §10.3 |
| **M4 Overlay + keybind** ✅ | `Overlay.qml`, README binding | opens and closes reliably, Esc works. **Decide** open latency: accept the async-Loader cost, or `keepLoaded` and lose service hot-reload — decided: async Loader, see §10.4 |
| **M5 Publish** | README (incl. enabled-state note, keybind, layer rule, overlay-vs-popup note), preview.png, LICENSE, `omarchy plugin validate`, marketplace issue | installable via `omarchy plugin add <repo> --enable` |

### 10.1 M1 results (2026-10-12)

| Exit criterion | Evidence |
|---|---|
| Live height in the bar | `₿ / 971 / 138` stacked in the vertical bar; status IPC `height 971138, online` |
| New-block pulse | mainnet block 971139 logged as `new block`; on the fixture chain three mined blocks each turned the label lavender → pink (peak `#f0a6d8`-ish, sampled from the screen) |
| 429 backs off | fixture server poll gaps after switching to 429: +31.1 s, +66.2 s, +104.7 s (expected 30/60/120 s ±20 %), next 240 s; stale after 2 min with data kept; one success resets to the base interval |
| Restart loads cache, no paging | `cache loaded: height 971138 blocks 164`, one tip poll, zero backfill requests |
| Also exercised | malformed JSON (discarded, logged, backoff), hung server (curl 10 s timeout → network, backoff), switching `apiBase` (state reset, fresh backfill, cache keyed by `apiBase`) |

Found while building M1:
- **`refresh()` race.** It fetches the tip and the tip page together; when the page landed
  first it raised the height directly, so the tip poll saw nothing new and no pulse fired.
  Every height increase now goes through one `raiseHeight()`, whichever response brings it.
- **`height` is FINAL on `Item`**, so the service exposes `blockHeight`.
- **`omarchy bar set` stores values as strings** (`"15"`); `resolveConfig` coerces them.
- **Editing `shell.json` in place is not picked up** by the running shell; a write that
  replaces the file (as editors that save via rename, and the shell itself, do) is. The
  README should point users at `omarchy bar set` or the settings UI.
- **journald drops lines under bursty logging** (a per-frame colour trace did it). The
  service only logs state changes; for debugging, `quickshell log --pid <pid>` reads the
  instance log directly and is not rate-limited.

### 10.2 M2 results (2026-10-12)

- **Popup** opens beside the left-edge bar from a left click on the widget; Esc closes it;
  `d` toggles the desktop setting, `r` refreshes, `f` closes it and summons the overlay;
  Tab moves between bar panels. The face is behind `Loader { active: opened }`, so closed
  popups on other monitors build no dial. Zero QML warnings after a clean restart.
- **Dial** checked against live data in screenshots: supply 95.7 % ends near 11:30;
  halving marker `78856` near 7:30 (62 %); retarget marker `568` near 8:30 (72 %); 157
  ticks in 24 h with the newest pink at 12; timer teal → amber → red across ten-minute
  cycles (seen at 0:31, 11:10, 52:13); stale caption and 40 % rings while offline.
- **Layout changes from §6:** the dial is 0.74 of the popup's shorter side (0.8 collided
  with the corners); ring labels sit on `bg`-coloured chips so they stay legible where the
  nearly-full supply ring runs under them; the top-left corner is three short lines
  (`SUBSIDY ₿3.125`, `SUPPLY ₿20.09M`, `95.7% OF 21M`) in JetBrains Mono, because
  Liberation Sans's `₿` overlapped the next digit; block height is 0.16 × D, not 0.19 × D,
  so six digits fit inside r < 0.30 D.
- **Settings write race in the shell.** After `updateEntryInline` the shell sometimes
  refreshes plugin facades with the *pre-write* bar config and never again, so the
  service kept the old value (reproduced twice from a fresh restart: file `true`, service
  `false`). The service now applies its own successful writes locally and, for 5 s,
  ignores refreshes that disagree with them. Verified: 12/12 toggles across two fresh
  restarts, and outside changes via `omarchy bar set` still propagate.
- **Not yet done:** a side-by-side against timechaincalendar.com for colour stops and
  proportions (the photo is warm-tinted); tuning is deferred to M5's preview work.

### 10.3 M3 results (2026-10-12)

- **Built as planned** (§7.3): `DesktopWidget.qml` is a `Variants` instantiated inside
  `Service.qml`. Its model is empty while `desktopWidget` is off, so no window exists rather
  than a hidden one. Geometry and screen choice are pure functions in the model
  (`desktopLayout`, `pickScreens`, unit-tested).
- **Geometry.** `desktopSize` is the ring diameter. Stats off: a square of `size / 0.9`
  (the dial box) on a round backing. Stats on: `1.49 × size` by `1.35 × size`, the popup's
  proportions (rings at 0.74 of the height), on a rounded `bg` rectangle; the default 480
  gives 715 × 648. Opacity applies to one layer, so rings do not show through each other.
  `desktopScreen` naming a monitor that is not connected falls back to the first screen.
- **Ring labels hide below D = 400** (they hit the 8 px floor and overran the disc at 300).
- **Verified on eDP-1, bar on top:** maps on layer 1 under windows; `center` at
  603,229 (715 × 648); `top-right` at 1157,74; stats off 533 × 533; size 300 → 333 × 333;
  live changes via `omarchy bar set` (string values coerce); survives workspace switches,
  a shell restart (comes back from the saved setting), a hot-reload (one window, recreated),
  and a theme re-apply. No QML warnings from the plugin.
- **CPU** (8 cores, `/proc` deltas): widget visible on an empty workspace 0.45 % of one core
  for quickshell + 0.15 % for Hyprland; covered by a window 0.37 %; widget off 0.07 %.
- **Hand edits to `shell.json` are unreliable.** A rename-style write was picked up in M1
  but ignored in M3 (the shell did not re-read the file until a restart). README: change
  settings with `omarchy bar set`, the bar right-click, or `d` in the popup.
- **Not covered:** multiple monitors (one available); right-click on the widget is the same
  `desktopAction` path as the IPC call that was tested.

### 10.4 M4 results (2026-10-12)

- **Built on the Emojis pattern** (§7.4): `Overlay.qml` is a root `Item` with
  `open/close/dismiss/toggle`; a full-screen `PanelWindow` (namespace
  `mondo-block-clock-overlay`, `WlrLayer.Overlay`, `Exclusive` keyboard focus,
  `ExclusionMode.Ignore`, no `screen` so it opens on the focused monitor) holding a
  `TimechainFace` at `dialFraction: 0.78`. The service comes from the facade's
  `serviceFor`, as a binding. Opening asks the service for a fresh price.
- **Scrim is 95 %, not 88 %:** at 88 % a terminal's text behind it stayed readable and
  competed with the dial.
- **Keys:** `Esc`/`q` close · `r` refresh · `d` desktop widget; a hint line sits at the
  bottom centre. Clicking anywhere closes it (the face has no interactive parts).
- **Latency decision: keep the asynchronous Loader, no `keepLoaded`.** From the
  `omarchy-shell shell toggle` call to the layer being mapped: 60, 46, 47, 51, 45 ms (this
  includes starting the `omarchy-shell` process); hide to unmapped ≈ 37 ms. Not worth
  losing service hot-reload for.
- **Verified:** five open/close cycles via IPC; keyboard (`wtype` from an empty workspace):
  `d` hid then showed the desktop widget, `Esc` closed; the popup's `f` path calls the same
  `summon`. No QML warnings from the plugin.
- **Keybind:** `SUPER + ALT + B` (modmask 72; the existing B binds are 65, 68, 73, 76)
  added to the user's `~/.config/hypr/bindings.lua`, backup alongside; `hyprctl binds`
  lists it and the command toggles the overlay. A synthetic chord from `wtype` did not
  trigger it (Hyprland does not appear to run binds for virtual-keyboard input), so the
  physical key press is left to the user.

### 10.5 M5 results (2026-10-12, local part)

- **README** covers install, the bar-entry-is-the-switch note, clicks and keys, the
  keybind and the overlay-versus-popup routing, the optional layer rule, every setting
  (set with `omarchy bar set`, not hand edits), IPC, network use and privacy, and the dev
  loop. **LICENSE** MIT. **preview.png** is the fullscreen view at 1280 × 720, taken on an
  empty workspace with the desktop dial hidden.
- **`fontFamily` removed:** it was in the schema and `DEFAULTS` but nothing read it.
- **Validated:** `omarchy plugin validate` passes on a fresh clone of the repo (silent,
  rc 0; a `{}` manifest as control fails with rc 1); 45 model tests pass.
- **Colour tuning not done.** Headless Chromium (with and without SwiftShader WebGL)
  only ever rendered timechaincalendar.com's loading spinner, so there is still no
  side-by-side; the palette is as built in M2.
- **There is no marketplace in Omarchy itself:** `omarchy plugin add <git-url>` clones,
  validates and moves the plugin into place. Publishing means a public git repo.

### 10.6 v0.2 changes (2026-10-12, owner feedback)

- **Bar shows the BTC/USD price** (`$81,685`), not the height; it still pulses on new
  blocks and the tooltip keeps the block details. Default `priceRefreshSec` 300 → 120.
- **Map pins** (`MapPin.qml`) replace the tangent pills for blocks to halving and to the
  difficulty adjustment, drawn above all rings so no ring covers them.
- **No ring labels on the dial.** Hovering a ring (by distance from the centre,
  `Model.ringAt`) or a pin swaps the centre to that ring's caption, value and detail
  (`Model.ringInfo`): supply %, halving month and next subsidy, retarget date and expected
  change, 24 h count and average spacing, time since the last block and its pool. A hint
  line ("hover a ring for details") sits at the bottom centre of the popup and overlay.
  The hover `MouseArea` takes no buttons, so the overlay's click-to-close still works.
- **Styling:** rounded arc ends; a soft glow (blurred copy of the rings); a faint radial
  light behind the dial; halving/difficulty rings 0.014 D, supply 0.010 D, timer 0.008 D;
  the corner price grouped (`81,685 USD/BTC`).
- **Verified:** 49 tests; no QML warnings; screenshots of the overlay (pins sit on their
  arc ends) and the bar. **Hover is not verified:** Hyprland cursor warps
  (`hl.dsp.cursor.move`) delivered no pointer events at all (no `entered`), the same
  limitation as M0's synthetic pointer test, so it needs a real mouse.
- The owner turned the desktop dial off (`desktopWidget` false, its default).

### 10.7 v0.3 changes (2026-10-13, owner feedback with a photo of the reference)

Supersedes the ring styling of §6.3–6.5 and §10.6 where they differ.

- **Rings follow the reference design:** solid colours instead of the gradient. Supply is
  a hairline (`ringSupply`) at r 0.500 D, with a tick at each halving's share of the
  21 M (50, 75, 87.5, 93.75, 96.9, 98.4 %; `Model.supplyHalvingMarks`) and a dot at
  12 o'clock. Halving (`ringHalving`, r 0.478 D) and difficulty (`ringDifficulty`,
  r 0.425 D) are 0.008 D bands with a start tick across them at 12 o'clock. The 24 h ticks
  (r 0.375 D) are short dashes along the circle, 0.011 × 0.0055 D, fading 90 → 30 %, with
  no track. The timer (r 0.322 D) is a fine line with a dot on its leading edge. Glow
  removed: at small blur radii it drew offset ghost copies, and the reference is crisp.
- **Legend:** curved small capitals along each ring from just after 12 o'clock
  ("SUPPLY % ›" outside the supply line; "BLOCKS TO HALVING ›", "BLOCKS TO DIFFICULTY
  ADJUST ›" inside their rings; "LAST 24 HOURS BLOCKS ›" inside the ticks).
  `ArcText.qml` places one Text per glyph (`Model.arcGlyphs`); its FontMetrics calls
  re-run on font changes only because the bindings set the font first.
- **Value pills** (`MapPin.qml`): a band curved along the ring, centred on the leading
  edge, as long as its text needs, outlined in the ring colour, with a small pointer on
  the outer side. The text follows the curve and turns over in the lower half
  (`Model.markerFlipped`). The pills are hit-tested analytically (`Model.arcHit`); the old
  pin collision flip is gone because the pills sit on different radii and cannot overlap.
- Hover bands (`Model.ringAt`) moved to the new radii. The centre value is capped at
  0.15 D and 0.54 D wide to stay inside the timer ring.
- **Verified (v0.3):** 50 tests; no QML warnings; overlay screenshots at 1920 × 1080 and the face
  at popup size (640 × 580, labels at the 8 px floor, nothing overlapping). Hover **is**
  verified now: screenshots taken with the real pointer resting on the difficulty pill and
  on the supply ring showed those rings' details in the centre.

### 10.8 v0.4 changes (2026-10-13, owner feedback): keys and screensaver

- **`Esc`/`q` close everywhere.** The popup gained `q` (`PanelKeyCatcher` handles `Esc`).
- **The desktop dial takes input** (supersedes §7.3's click-through). Its window keeps the
  bottom layer but drops the empty mask and asks for keyboard focus `OnDemand`, so a click
  on the dial gives it the keyboard: `f` fullscreen, `Esc`/`q`/`d` hide the desktop dial,
  `r` refresh. Double-click opens fullscreen. Clicks outside the dial's window are
  unaffected; on an empty workspace a click on the wallpaper did nothing anyway.
- **Screensaver** (`screensaver` setting, default off). The service runs a Quickshell
  `IdleMonitor` (inhibitors respected) with the shell's `idle.screensaver` timeout
  (`shell.idleConfig`, `Model.screensaverTimeoutSec`, fallback 150 s). On idle it checks
  the stay-awake flag file and `omarchy-shell lock isLocked`, then summons the overlay with
  `{"screensaver": true}`. In that mode the overlay hides the hint, turns off ring hover,
  and closes on any key, any click, pointer movement, or the monitor reporting activity,
  each after a 1 s grace. Omarchy's idle service is untouched and still locks at
  `idle.lock`; its terminal screensaver is turned off with `omarchy toggle screensaver`
  (it would otherwise open under the overlay).
- **Verified:** 51 tests; no QML warnings. A screensaver-mode summon showed no hint and
  closed on Space and on Shift (the normal overlay ignores both). With the timeout forced
  to 6 s the idle monitor opened the screensaver after about 7 s
  (`[timechain] idle 6s; screensaver opening`). A Hyprland cursor warp did not close it:
  warps are not input to the idle protocol or the surface, as in M0.
  **Not verified:** that a physical click gives the desktop dial keyboard focus, and that
  real mouse movement closes the screensaver; both need the owner's hands.
- **Follow-up (owner):** `d` in the popup shows the desktop dial and closes the popup;
  `d`/`f` on the desktop dial open fullscreen; `d`/`f` in fullscreen show the desktop dial
  and close fullscreen. IPC `screensaver` opens the screensaver on demand. Owner confirmed
  `Esc` closes the popup, the desktop dial (after a click, so click-to-focus works) and
  fullscreen.
- Owner's machine: `screensaver` on, Omarchy's terminal screensaver off, `idle.screensaver`
  7200 s and `idle.lock` 28800 s unchanged.

### 10.9 v0.5 changes (2026-10-13): Block Clock

- **Renamed "Block Clock"** (manifest name and display name, dial caption, tooltips,
  docs), so it no longer uses the reference site's product name; the README keeps the
  "inspired by" credit. The plugin id, repo and window namespaces are unchanged.
  Author: Perfect Hero (manifest, LICENSE, this document).
- **`Esc`/`q` in fullscreen close everything**, hiding the desktop dial too; `d`/`f` are
  the way back to the desktop dial. The screensaver's any-key close leaves the desktop
  dial alone. Known edge: showing the desktop dial from the command line *while*
  fullscreen is open hands the keyboard to the new dial (its `OnDemand` focus wins), so
  `Esc` then hides only the dial. Not reachable from the keys, since `d` closes fullscreen.
- **The Bitcoin logo replaces the elapsed timer** under the block height: an orange disc
  (`bitcoinOrange` `#f7931a`) with a white ₿ (Noto Sans Bold) tilted 14°. The logo is
  public domain. Hover still swaps in the ring's detail line; the time since the last
  block remains on the timer ring's hover.
- **Verified:** 51 tests, no QML warnings; screenshot (the new preview); `Esc` and `q` from
  fullscreen with the desktop dial on left nothing open.

### 10.10 v0.6 changes (2026-10-13): BTC / XBT chains, vector logo

- **XBT (Bitcoin BLAKE2b)** can replace Bitcoin as the dial's chain. It forked at 961,640
  (proof of work SHA-256 → BLAKE2b-256) and keeps Bitcoin's ledger, halving schedule,
  21 M cap and 2,016-block retargets (project-reported: lazarus-xbt.xyz), so all chain
  math is shared and only the data source and labels change (`Model.CHAINS`).
  Its explorer, `mempool.lazarus-xbt.xyz`, is a mempool instance: all five endpoints the
  plugin uses answered in mempool.space's format (probed 2026-10-13). Its `/v1/prices`
  USD (~$805) is unverified, and its other currencies are implausible (EUR 6.91), so the
  README flags the price.
- **Settings:** `chain` (`btc` | `xbt`) and `xbtApiBase`. `resolveConfig` adds a derived
  `source` (the active API base, never written back). Switching stashes the outgoing
  chain's data and restores the incoming one's from the cache, now one file with a
  section per source (`version: 2`; a version 1 file is read as one section). Each
  `Fetcher` fetches paths against `base`; a reply that lands after the source changed is
  dropped and the request repeated against the new source, so no BTC data can land in
  XBT state or the reverse.
- **UI:** a BTC | XBT segmented switch top centre of the face (with stats); `c` in the
  popup, fullscreen and the focused desktop dial; IPC `chain btc|xbt|toggle`. On XBT the
  caption reads "BLOCK CLOCK · XBT", the price "USD/XBT", the bar `XBT $805`, the tooltip
  "XBT block …".
- **Logo:** drawn from the public-domain Wikimedia "Bitcoin.svg" paths with `PathSvg`, so
  it is vector at any size (replaces the tilted-glyph approximation). On XBT a teal
  node-network badge (three linked nodes) sits on its lower right, for "nodes over
  miners"; hovering the logo shows "NODES OVER MINERS / XBT" (or "BITCOIN / BTC").
- **Verified:** 52 tests; no QML warnings; IPC switch to XBT (height 977,077, price
  $804.66, 90 blocks after a few seconds) and `c` back to BTC (cache restored instantly,
  "saved 10s ago"); the state file holds both sources; screenshots of both modes.
- **Follow-up (owner):** the exchange line is "$83,303" in the value style with a small
  muted "/BTC" (or "/XBT") suffix on its baseline (`CornerStat` line `suffix`); the
  switch moved to 6 o'clock, above the hint line. Owner confirmed the switch works by
  mouse in the popup and fullscreen.
- **XBT mark, final (owner's choice after three concept pages):** three gold nodes
  (`nodeGold` `#f5cf75`, 0.13 of the coin across) on a gold track at 35 % opacity, radius
  1.5 coin radii, no glow, one turn every 60 s (`BitcoinLogo.orbit`). It replaces the
  corner node badge. The turn runs only where `motion` is on: popup and fullscreen; the
  desktop dial and the screensaver hold it still. The logo's slot reserves the orbit's
  height on both chains so a switch does not move the layout. Verified: two screenshots
  5 s apart show the nodes about 30° on; no warnings.

---

## 11. Testing

- **Unit:** `TimechainModel.js` is ES5-compatible; `node --test tests/` covers the §5.3
  table, roman numerals, formatting, ring math, age clamping, and the backoff schedule.
- **Parity:** a test loads `manifest.json` and asserts `barWidget.defaults` and every
  schema `defaultValue` equal `DEFAULTS`.
- **Fixture replay:** `python3 -I tests/fixture_server.py` serves a synthetic chain on
  `127.0.0.1:8787`; `/__admin/mine` adds a block, `/__admin/mode/<ok|429|500|404|badjson|hang>`
  switches failure modes, and every request is logged with a timestamp. Point the plugin
  at it with `omarchy bar set io.github.perfect-hero.mondo-block-clock apiBase http://127.0.0.1:8787`.
- **Runner:** `tests/run.sh` runs the node suites and `omarchy plugin validate .`.
- **Visual:** `omarchy capture screenshot` of popup, desktop and overlay at 1× and 2×.
- **Shell health:** `omarchy plugin validate`; `omarchy-shell shell listPlugins`; QML
  warnings from the shell's log. `omarchy-launch-shell` runs Quickshell under
  `systemd-cat -t omarchy-shell`, so the log is `journalctl -t omarchy-shell -f`
  (also `quickshell log --pid <pid>`) **[verified M0]**. Prefix every plugin log line with
  `[timechain]`. The shell already logs duplicate-`IpcHandler` warnings for several
  first-party targets; only warnings naming our files or target count. Zero is the bar.
- **Performance:** desktop widget < 1 % idle CPU in `btop`.

---

## 12. Resolved questions

All eight v1 open questions are folded in above:
service lookup (§3.2), summon routing (§3.4), layer choice (§7.3), input mask (§7.3),
rate limits (§5.2), supply display (§5.3), 24 h direction (§6.5), CurveRenderer (§6.4).

The four M0 tests (§10) are done, on 2026-10-12:

| Test | Result | Where recorded |
|---|---|---|
| 1. Desktop window hosted in a third-party service | pass (single monitor) | §7.3 |
| 2. Gradient direction and annulus path | pass | §6.4 |
| 3. `IpcHandler` across a plugin reload | pass; ~1–2 s miss window | §3.4 |
| 4. Bar widget service binding across a reload | pass | §3.2 |
| (found) Hot-reload uses stale code for every entry point | edit → `omarchy restart shell` | §10 |

Still unverified: desktop windows on a second monitor.

---

## 13. Future work (not in v1)

- `palette: "theme"` mode mapping ring stops to the theme's accent/urgent colors.
- Optional WebSocket via `websocat` when present, for sub-second new-block pulses.
- Fiat currency setting and `EUR/GBP/...` corner stats.
- Notification on new block (height, pool, median fee), off by default.
- Desktop-only mode with its own config file (§8.1).
- Self-hosted node auto-detect through the WireGuard tunnel.
