import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "TimechainModel.js" as Model

// The only owner of chain state and the only component that touches the
// network (DESIGN.md §3.2, §5). Surfaces bind to the properties below through
// shell.serviceFor(id) and never fetch on their own.
Item {
  id: root

  property var shell: null

  // ---- settings: the bar entry merged with DEFAULTS (DESIGN.md §8.1)
  readonly property var _entry: shell ? Model.findEntry(shell.barConfig, Model.PLUGIN_ID) : null
  property var config: Model.resolveConfig(null)

  // ---- public state (DESIGN.md §5.4)
  property int blockHeight: 0
  property var tip: null
  property var recentBlocks: []
  property var difficulty: null
  property real priceUsd: 0
  property real priceAt: 0
  property real hashrate: 0
  property bool online: false
  property bool ready: false
  property real lastSuccessAt: 0
  property int newBlockSerial: 0
  property real nowMs: Date.now()
  readonly property int sinceLastBlockSec: Model.sinceLastBlockSec(tip, nowMs)
  readonly property bool stale: blockHeight > 0 && nowMs - Math.max(lastSuccessAt, _startedAt) > 120000
  readonly property int staleSec: Math.floor((nowMs - (lastSuccessAt || _cacheSavedAt || _startedAt)) / 1000)
  readonly property int blocksLast24h: Model.blocksLast24h(recentBlocks, Math.floor(nowMs / 1000))

  signal newBlock(var block)

  // ---- internals
  readonly property string _stateDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/mondo-block-clock"
  property real _startedAt: Date.now()
  property real _cacheSavedAt: 0
  property bool _stateDirReady: false
  property bool _cacheDirty: false
  property int _tipIntervalSec: Model.DEFAULTS.refreshIntervalSec
  property var _pendingFirstSeen: null
  property int _backfillPages: 0
  property int _backfillTarget: -1
  property string _lastTipOutcome: ""
  property string _lastTipLog: ""

  readonly property int _maxBackfillPages: 16

  function log() {
    var args = ["[timechain]"]
    for (var i = 0; i < arguments.length; i++) args.push(arguments[i])
    console.log(args.join(" "))
  }

  readonly property string chain: config.chain
  readonly property var chainInfo: Model.chainInfo(config.chain)

  // ---- settings

  // After our own write the shell sometimes refreshes plugin facades with the
  // pre-write bar config and then never again (observed in M2; a race inside
  // the shell). So a successful write applies locally at once, and for a few
  // seconds refreshes that disagree with it are treated as stale.
  property var _writtenConfig: null
  property real _writtenUntil: 0

  function syncConfig() {
    var next = Model.resolveConfig(_entry)
    if (_writtenConfig) {
      if (JSON.stringify(next) === JSON.stringify(_writtenConfig) || Date.now() > _writtenUntil) _writtenConfig = null
      else return
    }
    applyConfig(next)
  }

  function applyConfig(next) {
    if (JSON.stringify(next) === JSON.stringify(config)) return
    var prev = config
    // Keep the outgoing chain's data, so switching back is instant.
    if (ready && prev.source !== next.source) stashCache(prev.source)
    config = next
    if (!ready) return
    if (prev.source !== next.source) {
      log("source", next.source, "- switching chain state")
      resetChainState()
      restoreCache(next.source)
    }
    if (prev.source !== next.source || prev.refreshIntervalSec !== next.refreshIntervalSec) {
      _tipIntervalSec = next.refreshIntervalSec
      refresh()
    }
    if (prev.priceRefreshSec !== next.priceRefreshSec) fetchPrice()
    if (next.showHashrate && !prev.showHashrate) fetchHashrate()
  }

  on_EntryChanged: syncConfig()

  function updateSetting(key, value) {
    if (!shell || typeof shell.updateEntryInline !== "function") return false
    var entry = Model.entryWith(config, key, value)
    if (!shell.updateEntryInline(Model.PLUGIN_ID, entry)) return false
    var next = Model.resolveConfig(entry)
    _writtenConfig = next
    _writtenUntil = Date.now() + 5000
    applyConfig(next)
    return true
  }

  // The fullscreen dial; a JSON payload of {"screensaver": true} opens it in
  // screensaver mode (Overlay.qml).
  function openFullscreen(payloadJson) {
    if (shell && typeof shell.summon === "function") shell.summon(Model.PLUGIN_ID, payloadJson || "")
  }

  // Switch between the chains: "btc", "xbt" or "toggle".
  function chainAction(action) {
    var a = String(action || "toggle")
    var next = a === "toggle" ? Model.otherChain(config.chain) : a
    if (!Model.CHAINS[next]) return "unknown chain: " + a
    if (next !== config.chain) updateSetting("chain", next)
    return next
  }

  function desktopAction(action) {
    var a = String(action || "toggle")
    var current = config.desktopWidget === true
    var next = a === "show" ? true : a === "hide" ? false : a === "toggle" ? !current : null
    if (next === null) return "unknown action: " + a
    if (next !== current) updateSetting("desktopWidget", next)
    return next ? "shown" : "hidden"
  }

  // ---- lifecycle

  function resetChainState() {
    blockHeight = 0
    tip = null
    recentBlocks = []
    difficulty = null
    priceUsd = 0
    priceAt = 0
    hashrate = 0
    online = false
    lastSuccessAt = 0
    _pendingFirstSeen = null
    _backfillTarget = -1
    _startedAt = Date.now()
  }

  // Runs once the cache read has finished either way (DESIGN.md §5.5), so a
  // late cache load can never land on top of fresher network data.
  function start() {
    if (ready) return
    ready = true
    log("started; height", blockHeight, "blocks", recentBlocks.length, "api", config.source)
    fetchTip()
    fetchPrice()
    if (!difficulty && blockHeight > 0) fetchDifficulty()
    if (config.showHashrate) fetchHashrate()
  }

  function refresh() {
    _tipIntervalSec = config.refreshIntervalSec
    fetchTip()
    if (blockHeight > 0) {
      fetchBlocks()
      fetchDifficulty()
    }
    fetchPrice()
    if (config.showHashrate) fetchHashrate()
    return "ok"
  }

  // After suspend the backoff interval is meaningless; poll again soon. The
  // network may need a few seconds to come back, and network failures retry
  // within a minute anyway.
  function onClockJump() {
    log("clock jumped (resume?), polling now")
    _tipIntervalSec = config.refreshIntervalSec
    resumeTimer.restart()
  }

  // Surfaces that show the price call this when they open (DESIGN.md §5.2).
  function requestFreshPrice() {
    if (Date.now() - priceAt > 60000) fetchPrice()
  }

  // ---- tip poll: the heartbeat

  function fetchTip() {
    tipTimer.stop()
    if (!tipFetcher.fetch("/api/blocks/tip/height")) scheduleTip()
  }

  function scheduleTip() {
    tipTimer.interval = Model.jitterMs(_tipIntervalSec, Math.random())
    tipTimer.restart()
  }

  function onTipResult(outcome, status, body) {
    var h = parseInt(String(body).trim(), 10)
    if (outcome === "ok" && !(h > 0)) outcome = "bad"
    if (outcome === "ok") {
      online = true
      lastSuccessAt = Date.now()
      if (raiseHeight(h)) {
        fetchBlocks()
        fetchDifficulty()
      }
    } else {
      online = false
    }
    var next = Model.nextIntervalSec(_tipIntervalSec, config.refreshIntervalSec, outcome === "bad" ? "backoff" : outcome)
    // Log changes only: an hour offline would otherwise add 60 identical lines.
    var line = ["tip poll", outcome, status ? "(HTTP " + status + ")" : "", "next ~" + next + "s",
                outcome === "network" && tipFetcher.lastError ? "- " + tipFetcher.lastError : ""].join(" ")
    if (line !== _lastTipLog) log(line, outcome === "ok" ? "h=" + h : "")
    _lastTipLog = line
    if (outcome === "config") log("check API base:", config.source)
    _lastTipOutcome = outcome
    _tipIntervalSec = next
    scheduleTip()
  }

  // Every height increase goes through here, whichever response brings it:
  // a refresh fetches the tip and the tip page together, and either may land
  // first. Returns true when the height moved.
  function raiseHeight(h) {
    if (!(h > blockHeight)) return false
    var live = ready && blockHeight > 0
    log(live ? "new block" : "tip", h, live ? "(was " + blockHeight + ")" : "")
    if (live) _pendingFirstSeen = { height: h, at: Date.now() }
    blockHeight = h
    if (live) newBlockSerial++
    return true
  }

  // ---- blocks: tip page on every new height, backfill to cover 24 h

  function fetchBlocks() {
    if (!blocksFetcher.fetch("/api/v1/blocks")) blocksRetry.restart()
  }

  function onBlocksResult(outcome, status, body) {
    if (outcome !== "ok") { log("tip page", outcome, status); return }
    var page
    try { page = Model.slimBlocks(JSON.parse(body)) } catch (e) { log("tip page: bad JSON"); return }
    if (!page.length) return
    applyBlocks(page, true)
    maybeBackfill()
  }

  function applyBlocks(page, isTipPage) {
    var nowSec = Math.floor(Date.now() / 1000)
    var merged = Model.mergeBlocks(recentBlocks, page, nowSec, isTipPage)
    var prevTip = tip
    recentBlocks = merged
    if (!merged.length) return
    var top = merged[0]
    if (raiseHeight(top.height)) fetchDifficulty()
    if (!prevTip || prevTip.height !== top.height || prevTip.id !== top.id) {
      var next = JSON.parse(JSON.stringify(top))
      if (_pendingFirstSeen && _pendingFirstSeen.height === next.height) next.firstSeenAt = _pendingFirstSeen.at
      tip = next
      if (prevTip && next.height > prevTip.height) root.newBlock(next)
    } else if (prevTip.firstSeenAt && !top.firstSeenAt) {
      // Keep our own first-seen time when the same tip is re-fetched.
      var kept = JSON.parse(JSON.stringify(top))
      kept.firstSeenAt = prevTip.firstSeenAt
      tip = kept
    }
    markCacheDirty(isTipPage)
  }

  function maybeBackfill() {
    if (backfillTimer.running || backfillFetcher.busy) return
    _backfillPages = 0
    scheduleBackfill()
  }

  function scheduleBackfill() {
    var next = Model.backfillHeight(recentBlocks, Math.floor(Date.now() / 1000))
    if (next < 0 || _backfillPages >= _maxBackfillPages) {
      if (_backfillPages > 0) log("backfill done:", _backfillPages, "pages,", recentBlocks.length, "blocks,", blocksLast24h, "in 24 h")
      return
    }
    _backfillTarget = next
    backfillTimer.restart()
  }

  function onBackfillResult(outcome, status, body) {
    if (outcome !== "ok") { log("backfill", outcome, status, "at", _backfillTarget, "- will resume on next block"); return }
    var page
    try { page = Model.slimBlocks(JSON.parse(body)) } catch (e) { log("backfill: bad JSON"); return }
    _backfillPages++
    if (!page.length) return
    applyBlocks(page, false)
    scheduleBackfill()
  }

  // ---- difficulty, price, hashrate

  function fetchDifficulty() { difficultyFetcher.fetch("/api/v1/difficulty-adjustment") }

  function onDifficultyResult(outcome, status, body) {
    if (outcome !== "ok") { log("difficulty", outcome, status); return }
    try { difficulty = JSON.parse(body) } catch (e) { log("difficulty: bad JSON"); return }
    markCacheDirty(false)
  }

  function fetchPrice() {
    priceTimer.restart()
    priceFetcher.fetch("/api/v1/prices")
  }

  function onPriceResult(outcome, status, body) {
    if (outcome !== "ok") { log("price", outcome, status); return }
    var p
    try { p = JSON.parse(body) } catch (e) { log("price: bad JSON"); return }
    if (!(p && p.USD > 0)) return
    priceUsd = p.USD
    priceAt = Date.now()
    markCacheDirty(false)
  }

  function fetchHashrate() { hashrateFetcher.fetch("/api/v1/mining/hashrate/3d") }

  function onHashrateResult(outcome, status, body) {
    if (outcome !== "ok") { log("hashrate", outcome, status); return }
    try {
      var r = JSON.parse(body)
      if (r && r.currentHashrate > 0) hashrate = r.currentHashrate
    } catch (e) { log("hashrate: bad JSON") }
  }

  // ---- cache (DESIGN.md §5.5)

  // One file with a section per data source (version 2); a version 1 file
  // is one source's section.
  property var _cacheAll: ({})

  function applyCache(text) {
    var c
    try { c = JSON.parse(text) } catch (e) { log("cache unreadable, ignoring"); return }
    if (c && c.version === 2 && c.sources) _cacheAll = c.sources
    else if (c && c.version === 1 && c.apiBase) { var all = {}; all[c.apiBase] = c; _cacheAll = all }
    else { log("cache from another version, ignoring"); return }
    restoreCache(config.source)
  }

  function restoreCache(source) {
    var c = _cacheAll[source]
    if (!c) { log("no cache for", source); return }
    var nowSec = Math.floor(Date.now() / 1000)
    recentBlocks = Model.mergeBlocks([], Model.slimBlocks(c.blocks), nowSec, false)
    blockHeight = Math.max(c.height || 0, recentBlocks.length ? recentBlocks[0].height : 0)
    tip = c.tip && c.tip.height === blockHeight ? c.tip : (recentBlocks.length ? recentBlocks[0] : null)
    difficulty = c.difficulty || null
    priceUsd = c.priceUsd || 0
    priceAt = c.priceAt || 0
    hashrate = c.hashrate || 0
    _cacheSavedAt = c.savedAt || 0
    log("cache loaded:", source, "height", blockHeight, "blocks", recentBlocks.length, "saved", Math.round((Date.now() - _cacheSavedAt) / 1000) + "s ago")
  }

  function stashCache(source) {
    if (blockHeight <= 0) return
    var all = {}
    for (var k in _cacheAll) all[k] = _cacheAll[k]
    all[source] = {
      height: blockHeight,
      tip: tip,
      blocks: recentBlocks,
      difficulty: difficulty,
      priceUsd: priceUsd,
      priceAt: priceAt,
      hashrate: hashrate,
      savedAt: Date.now()
    }
    _cacheAll = all
    _cacheDirty = true
  }

  // New blocks save at once; everything else at most once a minute.
  function markCacheDirty(now) {
    _cacheDirty = true
    if (now) saveCache()
    else if (!saveTimer.running) saveTimer.start()
  }

  function saveCache() {
    if (!_stateDirReady || !_cacheDirty) return
    stashCache(config.source)
    _cacheDirty = false
    saveTimer.stop()
    cacheFile.setText(JSON.stringify({ version: 2, sources: _cacheAll }))
  }

  function statusJson() {
    return JSON.stringify({
      height: blockHeight,
      online: online,
      stale: stale,
      ready: ready,
      lastSuccessAt: lastSuccessAt,
      tipIntervalSec: _tipIntervalSec,
      blocks: recentBlocks.length,
      blocksLast24h: blocksLast24h,
      sinceLastBlockSec: sinceLastBlockSec,
      priceUsd: priceUsd,
      apiBase: config.source,
      chain: config.chain,
      desktopWidget: config.desktopWidget
    })
  }

  // ---- objects

  Fetcher { id: tipFetcher; name: "tip"; base: root.config.source; onFinished: (o, s, b) => root.onTipResult(o, s, b) }
  Fetcher { id: blocksFetcher; name: "blocks"; base: root.config.source; onFinished: (o, s, b) => root.onBlocksResult(o, s, b) }
  Fetcher { id: backfillFetcher; name: "backfill"; base: root.config.source; onFinished: (o, s, b) => root.onBackfillResult(o, s, b) }
  Fetcher { id: difficultyFetcher; name: "difficulty"; base: root.config.source; onFinished: (o, s, b) => root.onDifficultyResult(o, s, b) }
  Fetcher { id: priceFetcher; name: "price"; base: root.config.source; onFinished: (o, s, b) => root.onPriceResult(o, s, b) }
  Fetcher { id: hashrateFetcher; name: "hashrate"; base: root.config.source; onFinished: (o, s, b) => root.onHashrateResult(o, s, b) }

  Timer { id: tipTimer; repeat: false; onTriggered: root.fetchTip() }

  // A tip page that collided with one already in flight retries shortly.
  Timer { id: blocksRetry; interval: 2000; repeat: false; onTriggered: root.fetchBlocks() }

  Timer {
    id: backfillTimer
    interval: 400
    repeat: false
    onTriggered: backfillFetcher.fetch("/api/blocks/" + root._backfillTarget)
  }

  Timer {
    id: priceTimer
    interval: root.config.priceRefreshSec * 1000
    repeat: true
    running: root.ready
    onTriggered: root.fetchPrice()
  }

  Timer {
    interval: 600000
    repeat: true
    running: root.ready && root.config.showHashrate
    onTriggered: root.fetchHashrate()
  }

  Timer {
    interval: 1000
    repeat: true
    running: true
    onTriggered: {
      var now = Date.now()
      var jumped = Model.clockJumped(root.nowMs, now)
      root.nowMs = now
      if (jumped && root.ready) root.onClockJump()
    }
  }

  Timer { id: resumeTimer; interval: 3000; repeat: false; onTriggered: root.refresh() }

  Timer { id: saveTimer; interval: 60000; repeat: false; onTriggered: root.saveCache() }

  Process {
    id: mkdirProc
    command: ["mkdir", "-p", root._stateDir]
    onExited: function(exitCode) {
      root._stateDirReady = exitCode === 0
      if (exitCode !== 0) root.log("cannot create", root._stateDir)
      else root.saveCache()
    }
  }

  FileView {
    id: cacheFile
    path: root._stateDir + "/state.json"
    watchChanges: false
    printErrors: false
    onLoaded: {
      root.applyCache(text())
      root.start()
    }
    onLoadFailed: root.start()
    onSaveFailed: root.log("cache write failed")
  }

  // The desktop widget lives here too: one window per chosen monitor, not
  // one per bar (DESIGN.md §7.3, verified M0).
  DesktopWidget { svc: root }

  // ---- screensaver: after the shell's idle.screensaver timeout, open the
  // fullscreen dial in screensaver mode, unless the screen is locked or
  // Omarchy's stay-awake is on. Video and other idle inhibitors hold it off.
  // Omarchy's idle service still runs the lock timer.
  readonly property int screensaverSec: Model.screensaverTimeoutSec(shell ? shell.idleConfig : null)
  readonly property bool userIdle: idleMonitor.isIdle

  IdleMonitor {
    id: idleMonitor
    enabled: root.config.screensaver === true
    timeout: root.screensaverSec
    respectInhibitors: true
    onIsIdleChanged: if (isIdle && !screensaverGate.running) screensaverGate.running = true
  }

  Process {
    id: screensaverGate
    command: ["bash", "-c", "[[ -f \"$HOME/.local/state/omarchy/indicators/stay-awake\" ]] && exit 3; "
      + "[[ $(omarchy-shell lock isLocked 2>/dev/null) == true ]] && exit 4; exit 0"]
    onExited: function(code) {
      console.log("[timechain] idle " + root.screensaverSec + "s; screensaver " + (code === 0 ? "opening" : "skipped (" + code + ")"))
      if (code === 0 && idleMonitor.isIdle) root.openFullscreen(JSON.stringify({ screensaver: true }))
    }
  }

  // IPC lives only here: bar widgets exist once per monitor (DESIGN.md §3.4).
  IpcHandler {
    target: "io.github.perfect-hero.mondo-block-clock"

    function refresh(): string { return root.refresh() }
    function status(): string { return root.statusJson() }
    function desktop(action: string): string { return root.desktopAction(action) }
    function chain(action: string): string { return root.chainAction(action) }
    // Open the screensaver now, to try it without waiting for the idle timeout.
    function screensaver(): string { root.openFullscreen(JSON.stringify({ screensaver: true })); return "opened" }
  }

  Component.onCompleted: {
    syncConfig()
    _tipIntervalSec = config.refreshIntervalSec
    mkdirProc.running = true
  }
}
