// Pure helpers for the Timechain plugin: settings defaults, chain math, block
// bookkeeping, fetch classification and formatting. No QML imports, ES5 only,
// so the same file loads in QML (`import "TimechainModel.js" as Model`) and in
// node tests through the guarded module.exports at the bottom. DESIGN.md §5.

var PLUGIN_ID = "io.github.perfect-hero.mondo-block-clock"

var HALVING_INTERVAL = 210000
var RETARGET_INTERVAL = 2016
var COIN = 100000000
var MAX_SUPPLY_BTC = 21000000
var DAY_SEC = 86400

// Single source of truth for settings defaults (DESIGN.md §8). The manifest's
// `defaults` and schema `defaultValue`s mirror this; tests/manifest.test.js
// keeps them in step.
var DEFAULTS = {
  apiBase: "https://mempool.space",
  refreshIntervalSec: 30,
  priceRefreshSec: 120,
  showTimerRing: true,
  showHashrate: false,
  desktopWidget: false,
  desktopScreen: "",
  desktopAnchor: "center",
  desktopSize: 480,
  desktopMargin: 48,
  desktopOpacity: 90,
  desktopStats: true,
  timeFormat: "h:mm AP",
  screensaver: false,
  chain: "btc",
  xbtApiBase: "https://mempool.lazarus-xbt.xyz"
}

// The chains the dial can follow (DESIGN.md §10.10). Both share Bitcoin's
// ledger up to XBT's fork at 961,640 and keep its halving schedule, 21 M cap
// and 2,016-block retargets, so all the chain math is common; only the data
// source and the labels differ. The XBT price comes from its own explorer.
var CHAINS = {
  btc: { id: "btc", ticker: "BTC", name: "Bitcoin", pow: "SHA-256" },
  xbt: { id: "xbt", ticker: "XBT", name: "Bitcoin BLAKE2b", pow: "BLAKE2b" }
}

function chainInfo(id) { return CHAINS[id] || CHAINS.btc }

function otherChain(id) { return id === "xbt" ? "btc" : "xbt" }

var INT_RANGES = {
  refreshIntervalSec: [15, 300],
  priceRefreshSec: [60, 900],
  desktopSize: [240, 1200],
  desktopMargin: [0, 400],
  desktopOpacity: [20, 100]
}

var ANCHORS = ["center", "top-left", "top-right", "bottom-left", "bottom-right"]

// ---- settings

function toBool(value, fallback) {
  if (typeof value === "boolean") return value
  var s = String(value).trim().toLowerCase()
  if (s === "true" || s === "1" || s === "yes" || s === "on") return true
  if (s === "false" || s === "0" || s === "no" || s === "off") return false
  return fallback
}

function toInt(value, fallback, range) {
  var n = parseInt(String(value), 10)
  if (!isFinite(n)) n = fallback
  if (range) n = Math.max(range[0], Math.min(range[1], n))
  return n
}

// DEFAULTS merged with a raw bar entry, every value coerced and clamped.
// Unknown keys (including `id`) are dropped.
function resolveConfig(entry) {
  var raw = entry && typeof entry === "object" ? entry : {}
  var out = {}
  for (var key in DEFAULTS) {
    var def = DEFAULTS[key]
    var v = raw[key]
    if (v === undefined || v === null) { out[key] = def; continue }
    if (typeof def === "boolean") out[key] = toBool(v, def)
    else if (typeof def === "number") out[key] = toInt(v, def, INT_RANGES[key])
    else out[key] = String(v)
  }
  out.apiBase = String(out.apiBase).trim().replace(/\/+$/, "") || DEFAULTS.apiBase
  out.xbtApiBase = String(out.xbtApiBase).trim().replace(/\/+$/, "") || DEFAULTS.xbtApiBase
  if (!CHAINS[out.chain]) out.chain = DEFAULTS.chain
  // Derived, not a setting (entryWith only writes DEFAULTS keys): the API in use.
  out.source = out.chain === "xbt" ? out.xbtApiBase : out.apiBase
  if (ANCHORS.indexOf(out.desktopAnchor) === -1) out.desktopAnchor = DEFAULTS.desktopAnchor
  if (!String(out.timeFormat).trim()) out.timeFormat = DEFAULTS.timeFormat
  return out
}

// Idle seconds before the screensaver: the shell's `idle.screensaver` (the
// same timeout Omarchy's own screensaver uses), else Omarchy's default 150.
function screensaverTimeoutSec(idleConfig) {
  var v = idleConfig ? Number(idleConfig.screensaver) : NaN
  return isFinite(v) && v >= 1 ? Math.round(v) : 150
}

// First layout entry whose id is ours, from a `bar` config subtree.
function findEntry(barConfig, id) {
  var layout = barConfig && barConfig.layout
  if (!layout) return null
  var sections = ["left", "center", "right"]
  for (var s = 0; s < sections.length; s++) {
    var arr = layout[sections[s]]
    if (!arr || !arr.length) continue
    for (var i = 0; i < arr.length; i++) {
      if (arr[i] && String(arr[i].id || "") === id) return arr[i]
    }
  }
  return null
}

// Full entry for updateEntryInline, which replaces the whole entry: current
// resolved config plus one change. Values equal to DEFAULTS are omitted so
// shell.json only records what the user changed.
function entryWith(config, key, value) {
  var next = {}
  for (var k in DEFAULTS) {
    var v = k === key ? value : config[k]
    if (v !== DEFAULTS[k]) next[k] = v
  }
  return next
}

// ---- chain math (integer satoshis, consensus right-shift semantics)

function epochIndex(h) { return Math.floor(h / HALVING_INTERVAL) }

function epochStart(h) { return epochIndex(h) * HALVING_INTERVAL }

function subsidySatsForEpoch(i) {
  if (i >= 64) return 0
  return Math.floor(50 * COIN / Math.pow(2, i))
}

function subsidySats(h) { return subsidySatsForEpoch(epochIndex(h)) }

function blocksToHalving(h) { return epochStart(h) + HALVING_INTERVAL - h }

function halvingProgress(h) { return (h - epochStart(h)) / HALVING_INTERVAL }

// Coins issued by blocks 0..h inclusive. Below 2^53 sats for every height.
function supplySats(h) {
  var e = epochIndex(h)
  var total = 0
  for (var i = 0; i < e; i++) total += HALVING_INTERVAL * subsidySatsForEpoch(i)
  return total + (h - epochStart(h) + 1) * subsidySatsForEpoch(e)
}

function supplyBtc(h) { return supplySats(h) / COIN }

function supplyPercent(h) { return supplyBtc(h) / MAX_SUPPLY_BTC * 100 }

// Millions, truncated to two decimals as timechaincalendar.com does: "20.09".
function supplyDisplayM(h) {
  return (Math.floor(supplyBtc(h) / 1e4) / 100).toFixed(2)
}

function roman(n) {
  var map = [[1000, "M"], [900, "CM"], [500, "D"], [400, "CD"], [100, "C"], [90, "XC"],
             [50, "L"], [40, "XL"], [10, "X"], [9, "IX"], [5, "V"], [4, "IV"], [1, "I"]]
  var out = ""
  for (var i = 0; i < map.length; i++) {
    while (n >= map[i][0]) { out += map[i][1]; n -= map[i][0] }
  }
  return out
}

function epochRoman(h) { return roman(epochIndex(h) + 1) }

function blocksToRetarget(h, difficulty) {
  if (difficulty && isFinite(difficulty.remainingBlocks)) return difficulty.remainingBlocks
  return RETARGET_INTERVAL - h % RETARGET_INTERVAL
}

function retargetProgress(h, difficulty) {
  if (difficulty && isFinite(difficulty.progressPercent)) return difficulty.progressPercent / 100
  return (h % RETARGET_INTERVAL) / RETARGET_INTERVAL
}

function satsPerUsd(price) { return price > 0 ? Math.round(COIN / price) : 0 }

function marketCapUsd(h, price) { return price > 0 ? supplyBtc(h) * price : 0 }

// ---- blocks

function clampAge(ageSec) { return Math.max(0, ageSec) }

// Block objects are kept slim; extras exist only on tip-page blocks.
function slimBlock(b) {
  if (!b || !isFinite(b.height) || !isFinite(b.timestamp)) return null
  var out = { height: b.height, id: String(b.id || ""), timestamp: b.timestamp, tx_count: b.tx_count || 0 }
  var x = b.extras
  if (x) {
    if (x.pool && x.pool.name) out.pool = String(x.pool.name)
    if (isFinite(x.medianFee)) out.medianFee = x.medianFee
    if (isFinite(x.reward)) out.reward = x.reward
    if (isFinite(x.firstSeen)) out.firstSeen = x.firstSeen
  }
  return out
}

function slimBlocks(arr) {
  var out = []
  if (!arr || !arr.length) return out
  for (var i = 0; i < arr.length; i++) {
    var s = slimBlock(arr[i])
    if (s) out.push(s)
  }
  return out
}

// Merge incoming blocks into the newest-first list. When `isTipPage`, a block
// whose id differs from the cached one at the same height is a reorg: that
// height and everything above it are dropped first (DESIGN.md §9). Backfill
// pages never trigger reorg handling because they overlap the tip page.
// Blocks older than the 24 h window (plus one hour of slack) are pruned.
function mergeBlocks(existing, incoming, nowSec, isTipPage) {
  var byHeight = {}
  var i
  var list = existing || []
  var reorgFrom = Infinity
  // A tip page that does not touch the cached run (offline for more than a
  // page of blocks) would leave a hole; drop the cache and backfill instead.
  if (isTipPage && list.length && incoming.length) {
    var lowest = Infinity
    for (i = 0; i < incoming.length; i++) lowest = Math.min(lowest, incoming[i].height)
    if (list[0].height < lowest - 1) list = []
  }
  if (isTipPage) {
    var cached = {}
    for (i = 0; i < list.length; i++) cached[list[i].height] = list[i].id
    for (i = 0; i < incoming.length; i++) {
      var c = cached[incoming[i].height]
      if (c !== undefined && c !== "" && incoming[i].id !== "" && c !== incoming[i].id)
        reorgFrom = Math.min(reorgFrom, incoming[i].height)
    }
  }
  for (i = 0; i < list.length; i++) {
    if (list[i].height < reorgFrom) byHeight[list[i].height] = list[i]
  }
  for (i = 0; i < incoming.length; i++) {
    var prev = byHeight[incoming[i].height]
    // A backfill block has no extras; never let it overwrite a richer copy.
    if (prev && prev.id === incoming[i].id && prev.pool && !incoming[i].pool) continue
    byHeight[incoming[i].height] = incoming[i]
  }
  var cutoff = nowSec - DAY_SEC - 3600
  var out = []
  for (var h in byHeight) {
    if (byHeight[h].timestamp >= cutoff) out.push(byHeight[h])
  }
  out.sort(function(a, b) { return b.height - a.height })
  return out
}

// Height to request next when backfilling the 24 h window, or -1 when the
// oldest block already reaches past it (or nothing is known yet).
function backfillHeight(blocks, nowSec) {
  if (!blocks || !blocks.length) return -1
  var oldest = blocks[blocks.length - 1]
  if (nowSec - oldest.timestamp > DAY_SEC) return -1
  if (oldest.height <= 0) return -1
  return oldest.height - 1
}

function blocksLast24h(blocks, nowSec) {
  var n = 0
  if (!blocks) return 0
  for (var i = 0; i < blocks.length; i++) {
    if (clampAge(nowSec - blocks[i].timestamp) <= DAY_SEC) n++
  }
  return n
}

// Seconds since the tip appeared: local first-seen time when we watched it
// arrive, else mempool's firstSeen, else the miner timestamp.
function sinceLastBlockSec(tip, nowMs) {
  if (!tip) return 0
  var seenMs = tip.firstSeenAt || (tip.firstSeen ? tip.firstSeen * 1000 : tip.timestamp * 1000)
  return Math.floor(clampAge(nowMs - seenMs) / 1000)
}

// ---- fetch classification and backoff (DESIGN.md §5.1)

// curl -sS -w '\n%{http_code}' output: body, newline, three-digit status.
function splitCurlOutput(text) {
  var s = String(text || "")
  var nl = s.lastIndexOf("\n")
  var codeText = nl === -1 ? s : s.slice(nl + 1)
  var status = parseInt(codeText.trim(), 10)
  return { body: nl === -1 ? "" : s.slice(0, nl), status: isFinite(status) ? status : 0 }
}

// "ok" | "backoff" | "config" | "network". Parse failures are the caller's
// "bad" case because only the caller knows the expected shape.
function classify(exitCode, status) {
  if (exitCode !== 0 || status === 0) return "network"
  if (status >= 200 && status < 300) return "ok"
  if (status === 429 || status >= 500) return "backoff"
  return "config"
}

var BACKOFF_CAP_SEC = 300
// Local network failures (offline, DNS, suspend) cost the server nothing, so
// they retry sooner; 429 and 5xx keep the full cap.
var NETWORK_BACKOFF_CAP_SEC = 60

function nextIntervalSec(currentSec, baseSec, outcome) {
  if (outcome === "ok") return baseSec
  if (outcome === "config") return BACKOFF_CAP_SEC
  var cap = outcome === "network" ? Math.max(baseSec, NETWORK_BACKOFF_CAP_SEC) : BACKOFF_CAP_SEC
  return Math.min(cap, Math.max(baseSec, currentSec) * 2)
}

// The 1 s clock jumped: the machine slept or the clock was set.
function clockJumped(prevMs, nowMs) {
  return nowMs - prevMs > 5000 || nowMs < prevMs
}

// ±20 % jitter; `rand` in [0, 1) is injected for tests.
function jitterMs(sec, rand) {
  return Math.round(sec * 1000 * (0.8 + 0.4 * rand))
}

// ---- formatting

function groupThousands(n) {
  var s = String(Math.round(Math.abs(n)))
  var out = ""
  while (s.length > 3) { out = "," + s.slice(-3) + out; s = s.slice(0, -3) }
  return (n < 0 ? "-" : "") + s + out
}

function formatUsd(n) { return n > 0 ? "$" + groupThousands(n) : "—" }

// 1.665e12 → "1.67T"
function formatCompact(n) {
  if (!(n > 0)) return "—"
  var units = [[1e12, "T"], [1e9, "B"], [1e6, "M"], [1e3, "K"]]
  for (var i = 0; i < units.length; i++) {
    if (n >= units[i][0]) return (n / units[i][0]).toFixed(2) + units[i][1]
  }
  return String(Math.round(n))
}

// 272 → "4:32", 3725 → "1:02:05"
function formatElapsed(sec) {
  sec = Math.max(0, Math.floor(sec))
  var h = Math.floor(sec / 3600)
  var m = Math.floor(sec % 3600 / 60)
  var s = sec % 60
  var ss = (s < 10 ? "0" : "") + s
  if (h > 0) return h + ":" + (m < 10 ? "0" : "") + m + ":" + ss
  return m + ":" + ss
}

var BITCOIN_SIGN = "₿"

// The bar shows the BTC/USD price, whole dollars: "$81,754".
// On XBT the ticker leads, so the two prices are never mistaken: "XBT $812".
function barLabel(priceUsd, chain) {
  var text = priceUsd > 0 ? formatUsd(Math.round(priceUsd)) : "$ —"
  return chain === "xbt" ? "XBT " + text : text
}

// Vertical bars stack the sign over the price in three-digit groups, the way
// the clock stacks hours over minutes: ["$", "81", "754"].
function barLines(priceUsd, chain) {
  var lines = chain === "xbt" ? ["XBT", "$"] : ["$"]
  if (!(priceUsd > 0)) { lines.push("—"); return lines }
  var s = String(Math.round(priceUsd))
  var head = s.length % 3
  if (head) lines.push(s.slice(0, head))
  for (var i = head; i < s.length; i += 3) lines.push(s.slice(i, i + 3))
  return lines
}

// ---- dial geometry and labels (DESIGN.md §6)

var TIMER_CYCLE_SEC = 600

// The 10-minute block timer: which cycle we are in and how full it is.
function timerState(sec) {
  var s = Math.max(0, Math.floor(sec))
  return { cycle: Math.floor(s / TIMER_CYCLE_SEC), progress: (s % TIMER_CYCLE_SEC) / TIMER_CYCLE_SEC }
}

// 24 h tick ring: 12 o'clock is now, older blocks run clockwise.
function tickAngleDeg(ageSec) {
  return Math.min(DAY_SEC, clampAge(ageSec)) / DAY_SEC * 360
}

// Ticks fade from 90 % (now) to 30 % (24 h ago).
function tickOpacity(ageSec) {
  return 0.9 - 0.6 * Math.min(DAY_SEC, clampAge(ageSec)) / DAY_SEC
}

// Edge-marker labels sit tangent to the ring; in the lower half they would
// read upside down, so they flip by 180°. Angle is clockwise from 12.
function markerFlipped(angleDeg) {
  var a = ((angleDeg % 360) + 360) % 360
  return a > 90 && a < 270
}

// 312500000 sats → "3.125"; trailing zeros dropped.
function formatBtcAmount(sats) {
  var s = (sats / COIN).toFixed(8)
  return s.replace(/\.?0+$/, "")
}

function formatPercent(value, digits) {
  return (isFinite(value) ? value : 0).toFixed(digits === undefined ? 1 : digits)
}

// 9.94e20 H/s → "994 EH/s"
function formatHashrate(hps) {
  if (!(hps > 0)) return "—"
  var units = [[1e21, "ZH/s"], [1e18, "EH/s"], [1e15, "PH/s"], [1e12, "TH/s"]]
  for (var i = 0; i < units.length; i++) {
    if (hps >= units[i][0]) return Math.round(hps / units[i][0]) + " " + units[i][1]
  }
  return Math.round(hps) + " H/s"
}

function tooltipText(state) {
  if (!state || !(state.height > 0)) return "Block Clock · waiting for data"
  var parts = [(state.chain === "xbt" ? "XBT block " : "Block ") + state.height]
  parts.push(formatElapsed(state.sinceLastBlockSec) + " ago")
  if (state.tip && state.tip.pool) parts.push(state.tip.pool)
  if (state.priceUsd > 0) parts.push(formatUsd(state.priceUsd))
  var text = parts.join(" · ")
  if (state.stale) text += "\nstale · last update " + formatElapsed(state.staleSec) + " ago"
  return text
}

// ---- arc text, pills and hover details (DESIGN.md §6.4, §6.7)

// Lay glyphs along a circle of radius r. `widths` are the glyph advances in
// px; `anchorDeg` (clockwise from 12) is where the text starts, or its middle
// with align "center". Text reads clockwise with its tops outward; `flipped`
// text reads counter-clockwise with its tops inward, so it stays upright in
// the lower half. Returns each glyph's centre angle in degrees.
function arcGlyphs(widths, r, anchorDeg, align, flipped) {
  var total = 0
  for (var i = 0; i < widths.length; i++) total += widths[i]
  if (!(r > 0)) return widths.map(function() { return anchorDeg })
  var k = 180 / Math.PI / r
  var dir = flipped ? -1 : 1
  var start = align === "center" ? anchorDeg - dir * total * k / 2 : anchorDeg
  var out = [], run = 0
  for (var j = 0; j < widths.length; j++) {
    out.push(start + dir * (run + widths[j] / 2) * k)
    run += widths[j]
  }
  return out
}

// Whether (x, y) is on an arc band: centre (cx, cy), mid radius r, centred
// on `angleDeg` (clockwise from 12), `sweepDeg` long, `halfWidth` either side
// of r, with round ends.
function arcHit(x, y, cx, cy, r, angleDeg, sweepDeg, halfWidth) {
  var dx = x - cx, dy = y - cy
  var dist = Math.hypot(dx, dy)
  var a = Math.atan2(dx, -dy) * 180 / Math.PI
  var off = ((a - angleDeg) % 360 + 540) % 360 - 180
  if (Math.abs(off) <= sweepDeg / 2) return Math.abs(dist - r) <= halfWidth
  // Round ends: distance to the nearer end point.
  var endDeg = angleDeg + (off > 0 ? 1 : -1) * sweepDeg / 2
  var ex = cx + r * Math.sin(endDeg * Math.PI / 180)
  var ey = cy - r * Math.cos(endDeg * Math.PI / 180)
  return Math.hypot(x - ex, y - ey) <= halfWidth
}

// Supply fractions (0..1) at each halving, for the tick marks on the supply
// ring: 50 %, 75 %, 87.5 %, … while the marks stay at least `minDeg` apart.
function supplyHalvingMarks(minDeg) {
  var out = [], prev = 0
  for (var e = 1; e < 34; e++) {
    var f = supplySats(e * HALVING_INTERVAL - 1) / COIN / MAX_SUPPLY_BTC
    if ((f - prev) * 360 < minDeg) break
    out.push(f)
    prev = f
  }
  return out
}

var MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

function formatMonthYear(ms) { var d = new Date(ms); return MONTHS[d.getMonth()] + " " + d.getFullYear() }
function formatMonthDay(ms) { var d = new Date(ms); return MONTHS[d.getMonth()] + " " + d.getDate() }

function formatSignedPercent(x) {
  if (!isFinite(x)) return "—"
  return (x >= 0 ? "+" : "−") + Math.abs(x).toFixed(1) + "%"
}

// Average seconds between the blocks in the list (newest first), or 0.
function averageIntervalSec(blocks, nowSec) {
  var recent = []
  for (var i = 0; i < (blocks || []).length; i++)
    if (nowSec - blocks[i].timestamp <= DAY_SEC) recent.push(blocks[i].timestamp)
  if (recent.length < 2) return 0
  return (recent[0] - recent[recent.length - 1]) / (recent.length - 1)
}

var RING_KEYS = ["supply", "halving", "difficulty", "day", "timer"]

// What the dial centre shows while a ring is hovered: a caption, a short
// value for the big gradient text, and a detail line.
function ringInfo(key, s) {
  var h = s.height || 0
  var nowMs = s.nowMs || 0
  if (h <= 0) return null
  if (key === "supply")
    return { caption: "BITCOIN SUPPLY", value: formatPercent(supplyPercent(h)) + "%",
             detail: BITCOIN_SIGN + groupThousands(Math.floor(supplyBtc(h))) + " of 21,000,000 mined" }
  if (key === "halving") {
    var left = blocksToHalving(h)
    return { caption: "BLOCKS TO HALVING", value: groupThousands(left),
             detail: "≈ " + formatMonthYear(nowMs + left * 600000) + " · subsidy " + BITCOIN_SIGN
                     + formatBtcAmount(subsidySats(h)) + " → " + BITCOIN_SIGN + formatBtcAmount(subsidySats(h + left)) }
  }
  if (key === "difficulty") {
    var d = s.difficulty
    var rem = blocksToRetarget(h, d)
    var when = d && isFinite(d.estimatedRetargetDate) ? d.estimatedRetargetDate : nowMs + rem * 600000
    var change = d && isFinite(d.difficultyChange) ? " · est. " + formatSignedPercent(d.difficultyChange) : ""
    return { caption: "BLOCKS TO DIFFICULTY ADJUST", value: groupThousands(rem),
             detail: "≈ " + formatMonthDay(when) + change }
  }
  if (key === "day") {
    var avg = averageIntervalSec(s.blocks, Math.floor(nowMs / 1000))
    return { caption: "BLOCKS IN THE LAST 24 HOURS", value: String(s.blocksLast24h || 0),
             detail: avg > 0 ? "avg " + formatElapsed(avg) + " apart · newest in pink" : "newest in pink" }
  }
  if (key === "chain") {
    if (s.chain === "xbt")
      return { caption: "NODES OVER MINERS", value: "XBT",
               detail: "Bitcoin BLAKE2b · forked at block 961,640 · press c for BTC" }
    return { caption: "BITCOIN", value: "BTC", detail: "SHA-256 proof of work · press c for XBT" }
  }
  if (key === "timer") {
    var pool = s.tip && s.tip.pool ? " · " + s.tip.pool : ""
    return { caption: "SINCE THE LAST BLOCK", value: formatElapsed(s.sinceLastBlockSec || 0),
             detail: "block " + h + pool }
  }
  return null
}

// Which ring a point at distance r from the centre is over, for a dial of
// ring diameter d (radii as in TimechainDial.qml), or "".
function ringAt(r, d) {
  if (!(d > 0)) return ""
  var x = r / d
  if (x > 0.535) return ""
  if (x > 0.488) return "supply"
  if (x > 0.452) return "halving"
  if (x > 0.4) return "difficulty"
  if (x > 0.35) return "day"
  if (x > 0.3) return "timer"
  return ""
}

// ---- desktop widget (DESIGN.md §7.3)

// Window geometry for the desktop widget. `desktopSize` is the ring diameter;
// the dial box adds 10 % for the edge pills. With corner stats the window
// takes the popup's proportions (rings at 0.74 of the height), so the face
// looks the same as the tuned popup.
var DESKTOP_STATS_W = 1.49
var DESKTOP_STATS_H = 1.35

function desktopLayout(cfg) {
  var c = cfg || DEFAULTS
  var size = c.desktopSize || DEFAULTS.desktopSize
  var stats = c.desktopStats !== false
  var w = Math.round(stats ? size * DESKTOP_STATS_W : size / 0.9)
  var h = Math.round(stats ? size * DESKTOP_STATS_H : size / 0.9)
  var a = ANCHORS.indexOf(c.desktopAnchor) === -1 ? DEFAULTS.desktopAnchor : c.desktopAnchor
  return {
    width: w,
    height: h,
    dialFraction: size / Math.min(w, h),
    top: a.indexOf("top") === 0,
    bottom: a.indexOf("bottom") === 0,
    left: /-left$/.test(a),
    right: /-right$/.test(a),
    margin: a === "center" ? 0 : (c.desktopMargin === undefined ? DEFAULTS.desktopMargin : c.desktopMargin),
    opacity: (c.desktopOpacity || DEFAULTS.desktopOpacity) / 100
  }
}

// Which monitors get a desktop widget: every one when `wanted` is empty;
// the named one when it is connected; otherwise the first, so unplugging the
// chosen monitor moves the widget rather than hiding it.
function pickScreens(names, wanted) {
  var list = names || []
  var w = String(wanted || "").trim()
  if (!w) return list.slice()
  if (list.indexOf(w) !== -1) return [w]
  return list.length ? [list[0]] : []
}

if (typeof module !== "undefined") {
  module.exports = {
    PLUGIN_ID: PLUGIN_ID,
    HALVING_INTERVAL: HALVING_INTERVAL,
    RETARGET_INTERVAL: RETARGET_INTERVAL,
    DAY_SEC: DAY_SEC,
    DEFAULTS: DEFAULTS,
    INT_RANGES: INT_RANGES,
    ANCHORS: ANCHORS,
    BACKOFF_CAP_SEC: BACKOFF_CAP_SEC,
    NETWORK_BACKOFF_CAP_SEC: NETWORK_BACKOFF_CAP_SEC,
    clockJumped: clockJumped,
    resolveConfig: resolveConfig,
    findEntry: findEntry,
    entryWith: entryWith,
    epochIndex: epochIndex,
    epochStart: epochStart,
    subsidySats: subsidySats,
    blocksToHalving: blocksToHalving,
    halvingProgress: halvingProgress,
    supplySats: supplySats,
    supplyBtc: supplyBtc,
    supplyPercent: supplyPercent,
    supplyDisplayM: supplyDisplayM,
    roman: roman,
    epochRoman: epochRoman,
    blocksToRetarget: blocksToRetarget,
    retargetProgress: retargetProgress,
    satsPerUsd: satsPerUsd,
    marketCapUsd: marketCapUsd,
    clampAge: clampAge,
    slimBlock: slimBlock,
    slimBlocks: slimBlocks,
    mergeBlocks: mergeBlocks,
    backfillHeight: backfillHeight,
    blocksLast24h: blocksLast24h,
    sinceLastBlockSec: sinceLastBlockSec,
    splitCurlOutput: splitCurlOutput,
    classify: classify,
    nextIntervalSec: nextIntervalSec,
    jitterMs: jitterMs,
    groupThousands: groupThousands,
    formatUsd: formatUsd,
    formatCompact: formatCompact,
    formatElapsed: formatElapsed,
    barLabel: barLabel,
    barLines: barLines,
    TIMER_CYCLE_SEC: TIMER_CYCLE_SEC,
    timerState: timerState,
    tickAngleDeg: tickAngleDeg,
    tickOpacity: tickOpacity,
    markerFlipped: markerFlipped,
    formatBtcAmount: formatBtcAmount,
    formatPercent: formatPercent,
    formatHashrate: formatHashrate,
    tooltipText: tooltipText,
    desktopLayout: desktopLayout,
    arcGlyphs: arcGlyphs,
    arcHit: arcHit,
    supplyHalvingMarks: supplyHalvingMarks,
    formatMonthYear: formatMonthYear,
    formatMonthDay: formatMonthDay,
    formatSignedPercent: formatSignedPercent,
    averageIntervalSec: averageIntervalSec,
    RING_KEYS: RING_KEYS,
    ringInfo: ringInfo,
    ringAt: ringAt,
    pickScreens: pickScreens,
    CHAINS: CHAINS,
    chainInfo: chainInfo,
    otherChain: otherChain,
    screensaverTimeoutSec: screensaverTimeoutSec
  }
}
