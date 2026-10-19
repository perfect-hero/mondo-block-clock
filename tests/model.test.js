"use strict"

const test = require("node:test")
const assert = require("node:assert/strict")
const M = require("../TimechainModel.js")

// ---- chain math: the hand-checked table in DESIGN.md §5.3

const HEIGHTS = [
  // h,        roman, subsidy BTC, toHalving, progress,  supply BTC
  [0,          "I",   50,          210000,    0,         50],
  [209999,     "I",   50,          1,         0.999995,  10500000],
  [210000,     "II",  25,          210000,    0,         10500025],
  [840000,     "V",   3.125,       210000,    0,         19687503.125],
  [971130,     "V",   3.125,       78870,     0.62443,   20097284.375],
  [1049999,    "V",   3.125,       1,         0.999995,  20343750],
  [1050000,    "VI",  1.5625,      210000,    0,         20343751.5625],
]

for (const [h, rom, subsidy, toHalving, progress, supply] of HEIGHTS) {
  test(`chain math at height ${h}`, () => {
    assert.equal(M.epochRoman(h), rom)
    assert.equal(M.subsidySats(h), subsidy * 1e8)
    assert.equal(M.blocksToHalving(h), toHalving)
    assert.ok(Math.abs(M.halvingProgress(h) - progress) < 1e-5)
    assert.equal(M.supplySats(h), Math.round(supply * 1e8))
    assert.equal(M.supplyBtc(h), supply)
  })
}

test("supply display truncates like the site", () => {
  assert.equal(M.supplyDisplayM(971130), "20.09")
  assert.ok(Math.abs(M.supplyPercent(971130) - 95.7013) < 1e-3)
})

test("subsidy reaches zero after 64 halvings and supply stays integral", () => {
  assert.equal(M.subsidySats(64 * 210000), 0)
  assert.equal(M.subsidySats(33 * 210000), 0)        // 5e9 >> 33 = 0
  assert.equal(M.subsidySats(32 * 210000), 1)        // 5e9 >> 32 = 1 sat
  const s = M.supplySats(64 * 210000)
  assert.ok(Number.isSafeInteger(s))
  assert.ok(s < 21e6 * 1e8)
})

test("roman numerals", () => {
  assert.deepEqual([1, 4, 5, 9, 14, 33, 64].map(M.roman), ["I", "IV", "V", "IX", "XIV", "XXXIII", "LXIV"])
})

test("retarget values prefer the API and fall back to height math", () => {
  assert.equal(M.blocksToRetarget(971131, { remainingBlocks: 581 }), 581)
  assert.equal(M.blocksToRetarget(971131, null), 581)
  assert.ok(Math.abs(M.retargetProgress(971131, { progressPercent: 71.18 }) - 0.7118) < 1e-12)
  assert.ok(Math.abs(M.retargetProgress(971131, null) - 1435 / 2016) < 1e-12)
})

test("price-derived values", () => {
  assert.equal(M.satsPerUsd(82868), 1207)
  assert.equal(M.satsPerUsd(0), 0)
  assert.equal(M.formatCompact(M.marketCapUsd(971130, 82868)), "1.67T")
})

// ---- settings

test("resolveConfig applies defaults to a bare entry", () => {
  // Plus the derived data source.
  const want = { ...M.DEFAULTS, source: M.DEFAULTS.apiBase }
  assert.deepEqual(M.resolveConfig({ id: M.PLUGIN_ID }), want)
  assert.deepEqual(M.resolveConfig(null), want)
})

test("resolveConfig coerces, clamps and validates", () => {
  const c = M.resolveConfig({
    refreshIntervalSec: "5", priceRefreshSec: 5000, desktopOpacity: "abc",
    showHashrate: "on", desktopWidget: "0", desktopAnchor: "middle",
    apiBase: " http://127.0.0.1:8787/ ", timeFormat: "  ", extra: 1,
  })
  assert.equal(c.refreshIntervalSec, 15)
  assert.equal(c.priceRefreshSec, 900)
  assert.equal(c.desktopOpacity, 90)
  assert.equal(c.showHashrate, true)
  assert.equal(c.desktopWidget, false)
  assert.equal(c.desktopAnchor, "center")
  assert.equal(c.apiBase, "http://127.0.0.1:8787")
  assert.equal(c.timeFormat, "h:mm AP")
  assert.equal("extra" in c, false)
})

test("findEntry scans every bar section", () => {
  const bar = { layout: { left: [{ id: "a" }], center: [], right: [{ id: "b" }, { id: M.PLUGIN_ID, desktopWidget: true }] } }
  assert.deepEqual(M.findEntry(bar, M.PLUGIN_ID), { id: M.PLUGIN_ID, desktopWidget: true })
  assert.equal(M.findEntry(bar, "missing"), null)
  assert.equal(M.findEntry({}, M.PLUGIN_ID), null)
})

test("entryWith writes the full non-default entry", () => {
  const config = M.resolveConfig({ desktopSize: 600 })
  assert.deepEqual(M.entryWith(config, "desktopWidget", true), { desktopSize: 600, desktopWidget: true })
  assert.deepEqual(M.entryWith(config, "desktopSize", 480), {})
})

// ---- blocks

const NOW = 1791837600
const blk = (height, ageSec, id, extras) =>
  Object.assign({ height, id: id || "id" + height, timestamp: NOW - ageSec, tx_count: 1 }, extras ? { pool: "P" } : {})

test("slimBlock keeps only the fields the plugin uses", () => {
  const s = M.slimBlock({
    height: 9, id: "x", timestamp: 100, tx_count: 2, size: 5,
    extras: { pool: { name: "Foundry USA" }, medianFee: 3, reward: 4, firstSeen: 99, coinbaseRaw: "zz" },
  })
  assert.deepEqual(s, { height: 9, id: "x", timestamp: 100, tx_count: 2, pool: "Foundry USA", medianFee: 3, reward: 4, firstSeen: 99 })
  assert.equal(M.slimBlock({ id: "no height" }), null)
  assert.deepEqual(M.slimBlocks([{ height: 1, timestamp: 1 }, null, {}]).length, 1)
})

test("mergeBlocks dedupes, sorts newest first and prunes past 25 h", () => {
  const out = M.mergeBlocks([blk(10, 600), blk(9, 90000 + 3601)], [blk(11, 0), blk(10, 600)], NOW, true)
  assert.deepEqual(out.map(b => b.height), [11, 10])
})

test("mergeBlocks drops the reorged height and everything above it", () => {
  const cached = [blk(12, 0, "old12"), blk(11, 600, "old11"), blk(10, 1200)]
  const page = [blk(11, 300, "new11"), blk(10, 1200)]
  const out = M.mergeBlocks(cached, page, NOW, true)
  assert.deepEqual(out.map(b => b.id), ["new11", "id10"])
})

test("mergeBlocks drops a cache the tip page does not reach", () => {
  const cached = [blk(80, 12000), blk(79, 12600)]
  const out = M.mergeBlocks(cached, [blk(100, 0), blk(99, 600)], NOW, true)
  assert.deepEqual(out.map(b => b.height), [100, 99])
  const touching = M.mergeBlocks([blk(98, 1200)], [blk(100, 0), blk(99, 600)], NOW, true)
  assert.deepEqual(touching.map(b => b.height), [100, 99, 98])
})

test("mergeBlocks ignores id differences on backfill pages", () => {
  const cached = [blk(12, 0), blk(11, 600, "a")]
  const out = M.mergeBlocks(cached, [blk(11, 600, "b")], NOW, false)
  assert.deepEqual(out.map(b => b.height), [12, 11])
})

test("a backfill copy never replaces a tip-page copy with extras", () => {
  const out = M.mergeBlocks([blk(11, 600, "a", true)], [blk(11, 600, "a")], NOW, false)
  assert.equal(out[0].pool, "P")
})

test("backfillHeight walks down until the window is covered", () => {
  assert.equal(M.backfillHeight([], NOW), -1)
  assert.equal(M.backfillHeight([blk(100, 0), blk(90, 6000)], NOW), 89)
  assert.equal(M.backfillHeight([blk(100, 0), blk(80, 86401)], NOW), -1)
})

test("blocksLast24h counts by age and tolerates future timestamps", () => {
  assert.equal(M.blocksLast24h([blk(3, -120), blk(2, 600), blk(1, 86400), blk(0, 86401)], NOW), 3)
})

test("sinceLastBlockSec prefers local first-seen, then mempool firstSeen, then timestamp", () => {
  const nowMs = NOW * 1000
  assert.equal(M.sinceLastBlockSec({ timestamp: NOW - 300 }, nowMs), 300)
  assert.equal(M.sinceLastBlockSec({ timestamp: NOW - 300, firstSeen: NOW - 200 }, nowMs), 200)
  assert.equal(M.sinceLastBlockSec({ timestamp: NOW - 300, firstSeen: NOW - 200, firstSeenAt: nowMs - 5000 }, nowMs), 5)
  assert.equal(M.sinceLastBlockSec({ timestamp: NOW + 60 }, nowMs), 0)
  assert.equal(M.sinceLastBlockSec(null, nowMs), 0)
})

// ---- fetch classification and backoff

test("splitCurlOutput separates body and status", () => {
  assert.deepEqual(M.splitCurlOutput('{"a":1}\n200'), { body: '{"a":1}', status: 200 })
  assert.deepEqual(M.splitCurlOutput("971138\n200\n".trimEnd()), { body: "971138", status: 200 })
  assert.deepEqual(M.splitCurlOutput("line1\nline2\n429"), { body: "line1\nline2", status: 429 })
  assert.deepEqual(M.splitCurlOutput(""), { body: "", status: 0 })
})

test("classify maps exit codes and statuses", () => {
  assert.equal(M.classify(0, 200), "ok")
  assert.equal(M.classify(0, 429), "backoff")
  assert.equal(M.classify(0, 503), "backoff")
  assert.equal(M.classify(0, 404), "config")
  assert.equal(M.classify(28, 0), "network")
  assert.equal(M.classify(0, 0), "network")
})

test("nextIntervalSec doubles from the current interval up to the cap", () => {
  const seq = []
  let cur = 30
  for (let i = 0; i < 5; i++) { cur = M.nextIntervalSec(cur, 30, "backoff"); seq.push(cur) }
  assert.deepEqual(seq, [60, 120, 240, 300, 300])
  assert.equal(M.nextIntervalSec(300, 30, "ok"), 30)
  assert.equal(M.nextIntervalSec(30, 30, "config"), 300)
  assert.equal(M.nextIntervalSec(30, 30, "network"), 60)
  assert.equal(M.nextIntervalSec(60, 30, "network"), 60)       // network errors cap at 60 s
  assert.equal(M.nextIntervalSec(240, 30, "network"), 60)      // even after server backoff
  assert.equal(M.nextIntervalSec(60, 120, "network"), 120)     // never below the base interval
})

test("clockJumped spots suspend and clock changes", () => {
  assert.equal(M.clockJumped(1000, 2000), false)
  assert.equal(M.clockJumped(1000, 7001), true)
  assert.equal(M.clockJumped(5000, 1000), true)
})

test("jitterMs stays within ±20 %", () => {
  assert.equal(M.jitterMs(30, 0), 24000)
  assert.equal(M.jitterMs(30, 0.5), 30000)
  assert.ok(M.jitterMs(30, 0.999999) <= 36000)
})

// ---- formatting

test("number formatting", () => {
  assert.equal(M.groupThousands(82699), "82,699")
  assert.equal(M.groupThousands(1234567), "1,234,567")
  assert.equal(M.formatUsd(82699), "$82,699")
  assert.equal(M.formatUsd(0), "—")
  assert.equal(M.formatCompact(994e6), "994.00M")
  assert.equal(M.formatElapsed(272), "4:32")
  assert.equal(M.formatElapsed(3725), "1:02:05")
  assert.equal(M.formatElapsed(-5), "0:00")
})

test("bar label and vertical lines", () => {
  assert.equal(M.barLabel(81754.4), "$81,754")
  assert.equal(M.barLabel(0), "$ —")
  assert.deepEqual(M.barLines(81754), ["$", "81", "754"])
  assert.deepEqual(M.barLines(104999.6), ["$", "105", "000"])
  assert.deepEqual(M.barLines(1250000), ["$", "1", "250", "000"])
  assert.deepEqual(M.barLines(0), ["$", "—"])
  assert.equal(M.barLabel(812.45, "xbt"), "XBT $812")
  assert.deepEqual(M.barLines(812.45, "xbt"), ["XBT", "$", "812"])
})

test("tooltip text", () => {
  assert.equal(M.tooltipText(null), "Block Clock · waiting for data")
  assert.equal(
    M.tooltipText({ height: 971130, sinceLastBlockSec: 272, tip: { pool: "F2Pool" }, priceUsd: 82699 }),
    "Block 971130 · 4:32 ago · F2Pool · $82,699")
  assert.equal(
    M.tooltipText({ height: 1, sinceLastBlockSec: 0, priceUsd: 0, stale: true, staleSec: 300 }),
    "Block 1 · 0:00 ago\nstale · last update 5:00 ago")
})

// ---- dial helpers

test("timerState wraps every ten minutes", () => {
  assert.deepEqual(M.timerState(0), { cycle: 0, progress: 0 })
  assert.deepEqual(M.timerState(300), { cycle: 0, progress: 0.5 })
  assert.deepEqual(M.timerState(600), { cycle: 1, progress: 0 })
  assert.deepEqual(M.timerState(1350), { cycle: 2, progress: 0.25 })
  assert.deepEqual(M.timerState(-5), { cycle: 0, progress: 0 })
})

test("tick angle and fade by age", () => {
  assert.equal(M.tickAngleDeg(0), 0)
  assert.equal(M.tickAngleDeg(21600), 90)          // 6 h ago → 3 o'clock
  assert.equal(M.tickAngleDeg(43200), 180)         // 12 h ago → 6 o'clock
  assert.equal(M.tickAngleDeg(-60), 0)
  assert.equal(M.tickAngleDeg(99999), 360)
  assert.equal(M.tickOpacity(0), 0.9)
  assert.ok(Math.abs(M.tickOpacity(86400) - 0.3) < 1e-12)
})

test("edge markers flip in the lower half", () => {
  assert.deepEqual([0, 45, 90, 91, 180, 269, 270, 315, 450].map(M.markerFlipped),
    [false, false, false, true, true, true, false, false, false])
})

test("amount, percent and hashrate formatting", () => {
  assert.equal(M.formatBtcAmount(312500000), "3.125")
  assert.equal(M.formatBtcAmount(5000000000), "50")
  assert.equal(M.formatBtcAmount(156250000), "1.5625")
  assert.equal(M.formatPercent(95.70135), "95.7")
  assert.equal(M.formatPercent(NaN), "0.0")
  assert.equal(M.formatHashrate(9.94e20), "994 EH/s")
  assert.equal(M.formatHashrate(1.2e21), "1 ZH/s")
  assert.equal(M.formatHashrate(0), "—")
})

// ---- desktop widget

test("desktopLayout: stats on uses the popup proportions", () => {
  const l = M.desktopLayout(M.resolveConfig({}))
  assert.equal(l.width, Math.round(480 * 1.49))
  assert.equal(l.height, Math.round(480 * 1.35))
  assert.ok(Math.abs(l.dialFraction * l.height - 480) < 1e-9)
  assert.deepEqual([l.top, l.bottom, l.left, l.right, l.margin], [false, false, false, false, 0])
  assert.equal(l.opacity, 0.9)
})

test("desktopLayout: stats off is the dial box, square", () => {
  const l = M.desktopLayout(M.resolveConfig({ desktopStats: false, desktopSize: 360 }))
  assert.equal(l.width, 400)
  assert.equal(l.height, 400)
  assert.ok(Math.abs(l.dialFraction - 0.9) < 1e-9)
})

test("desktopLayout: corner anchors and margins", () => {
  const cases = {
    "top-left": [true, false, true, false],
    "top-right": [true, false, false, true],
    "bottom-left": [false, true, true, false],
    "bottom-right": [false, true, false, true],
  }
  for (const [anchor, want] of Object.entries(cases)) {
    const l = M.desktopLayout(M.resolveConfig({ desktopAnchor: anchor, desktopMargin: "0" }))
    assert.deepEqual([l.top, l.bottom, l.left, l.right], want, anchor)
    assert.equal(l.margin, 0)
  }
  assert.equal(M.desktopLayout(M.resolveConfig({ desktopAnchor: "top-left" })).margin, 48)
  assert.equal(M.desktopLayout(M.resolveConfig({ desktopAnchor: "middle" })).top, false)
})

test("pickScreens", () => {
  assert.deepEqual(M.pickScreens(["eDP-1", "DP-2"], ""), ["eDP-1", "DP-2"])
  assert.deepEqual(M.pickScreens(["eDP-1", "DP-2"], " DP-2 "), ["DP-2"])
  assert.deepEqual(M.pickScreens(["eDP-1", "DP-2"], "HDMI-A-1"), ["eDP-1"])
  assert.deepEqual(M.pickScreens([], "DP-2"), [])
})

// ---- arc text, pills and hover

test("arcGlyphs from 12 o'clock and centred", () => {
  const r = 180 / Math.PI           // 1 px of arc = 1 degree
  assert.deepEqual(M.arcGlyphs([2, 4], r, 10, "start", false), [11, 14])
  assert.deepEqual(M.arcGlyphs([2, 4], r, 90, "center", false), [88, 91])
  // Flipped text runs counter-clockwise, still centred on the anchor.
  assert.deepEqual(M.arcGlyphs([2, 4], r, 180, "center", true), [182, 179])
  assert.deepEqual(M.arcGlyphs([3], 0, 45, "start", false), [45])
})

test("arcHit", () => {
  // Arc of radius 100 about (0, 0), centred at 90° (3 o'clock), 20° long, ±5 px.
  assert.equal(M.arcHit(100, 0, 0, 0, 100, 90, 20, 5), true)
  assert.equal(M.arcHit(106, 0, 0, 0, 100, 90, 20, 5), false)
  assert.equal(M.arcHit(0, -100, 0, 0, 100, 90, 20, 5), false)
  // Round end: 1.5° past the end is ~2.6 px away (inside), 5° is ~8.7 px.
  const at = deg => [100 * Math.sin(deg * Math.PI / 180), -100 * Math.cos(deg * Math.PI / 180)]
  assert.equal(M.arcHit(...at(101.5), 0, 0, 100, 90, 20, 5), true)
  assert.equal(M.arcHit(...at(105), 0, 0, 100, 90, 20, 5), false)
  // Wraps through 12 o'clock.
  assert.equal(M.arcHit(5, -100, 0, 0, 100, 355, 20, 5), true)
})

test("supplyHalvingMarks", () => {
  const m = M.supplyHalvingMarks(4)
  assert.ok(Math.abs(m[0] - 0.5) < 1e-6)
  assert.ok(Math.abs(m[1] - 0.75) < 1e-6)
  assert.ok(Math.abs(m[2] - 0.875) < 1e-6)
  assert.equal(m.length, 6)          // 98.4 % → 99.2 % is under 4°
})

test("screensaverTimeoutSec follows the shell's idle setting", () => {
  assert.equal(M.screensaverTimeoutSec({ screensaver: 7200, lock: 28800 }), 7200)
  assert.equal(M.screensaverTimeoutSec({ screensaver: "300" }), 300)
  assert.equal(M.screensaverTimeoutSec({}), 150)
  assert.equal(M.screensaverTimeoutSec(null), 150)
  assert.equal(M.screensaverTimeoutSec({ screensaver: 0 }), 150)
})

test("chain setting picks the data source", () => {
  assert.equal(M.resolveConfig(null).source, "https://mempool.space")
  assert.equal(M.resolveConfig({ chain: "xbt" }).source, "https://mempool.lazarus-xbt.xyz")
  assert.equal(M.resolveConfig({ chain: "xbt", xbtApiBase: "http://node:8080/" }).source, "http://node:8080")
  assert.equal(M.resolveConfig({ chain: "doge" }).chain, "btc")
  assert.equal("source" in M.entryWith(M.resolveConfig({ chain: "xbt" }), "chain", "xbt"), false)
  assert.equal(M.otherChain("btc"), "xbt")
  assert.equal(M.chainInfo("nope").ticker, "BTC")
})

test("ringAt bands", () => {
  const d = 400
  assert.equal(M.ringAt(0.515 * d, d), "supply")
  assert.equal(M.ringAt(0.478 * d, d), "halving")
  assert.equal(M.ringAt(0.425 * d, d), "difficulty")
  assert.equal(M.ringAt(0.39 * d, d), "day")
  assert.equal(M.ringAt(0.322 * d, d), "timer")
  assert.equal(M.ringAt(0.2 * d, d), "")
  assert.equal(M.ringAt(0.6 * d, d), "")
})

test("ringInfo", () => {
  const nowMs = Date.UTC(2026, 9, 12, 20, 0, 0)
  const s = {
    height: 971158, nowMs, blocksLast24h: 151, sinceLastBlockSec: 429, tip: { pool: "Foundry USA" },
    difficulty: { remainingBlocks: 554, difficultyChange: 4.7368, estimatedRetargetDate: Date.UTC(2026, 9, 16, 12) },
    blocks: [{ timestamp: nowMs / 1000 - 60 }, { timestamp: nowMs / 1000 - 660 }, { timestamp: nowMs / 1000 - 1260 }],
  }
  assert.equal(M.ringInfo("halving", s).value, "78,842")
  assert.match(M.ringInfo("halving", s).detail, /^≈ \w{3} 2028 · subsidy ₿3.125 → ₿1.5625$/)
  assert.equal(M.ringInfo("difficulty", s).value, "554")
  assert.match(M.ringInfo("difficulty", s).detail, /^≈ Oct 1[56] · est\. \+4\.7%$/)
  assert.equal(M.ringInfo("supply", s).value, "95.7%")
  assert.equal(M.ringInfo("day", s).value, "151")
  assert.equal(M.ringInfo("day", s).detail, "avg 10:00 apart · newest in pink")
  assert.equal(M.ringInfo("timer", s).value, "7:09")
  assert.equal(M.ringInfo("timer", s).detail, "block 971158 · Foundry USA")
  assert.equal(M.ringInfo("halving", { height: 0 }), null)
  assert.equal(M.formatSignedPercent(-0.031), "−0.0%")
})
