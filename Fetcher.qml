import QtQuick
import Quickshell.Io
import "TimechainModel.js" as Model

// One curl request at a time for one endpoint (DESIGN.md §5.1). No `-f`, so
// an HTTP error keeps its status and body; the status rides on the last line
// via -w. `finished` fires once both the exit code and stdout are in.
Item {
  id: root

  property string name: ""
  // API base the paths are fetched from (the service's current source).
  property string base: ""
  property string _path: ""
  property string _sentBase: ""
  readonly property bool busy: proc.running || _pending

  // outcome: "ok" | "backoff" | "config" | "network". `error` is curl's
  // stderr (e.g. "Could not resolve host"), empty on success.
  signal finished(string outcome, int status, string body)
  property string lastError: ""

  property bool _pending: false
  property bool _haveExit: false
  property bool _haveOutput: false
  property int _exitCode: 0
  property string _output: ""

  // false when a request for this endpoint is already in flight.
  function fetch(path) {
    if (busy) return false
    _path = path
    _sentBase = base
    _pending = true
    _haveExit = false
    _haveOutput = false
    _output = ""
    proc.command = ["curl", "-sS", "--max-time", "10", "-w", "\n%{http_code}", base + path]
    proc.running = true
    return true
  }

  function _finish() {
    if (!_haveExit || !_haveOutput) return
    _pending = false
    // The source changed while this was in flight (a chain switch): drop the
    // reply and ask the new source instead.
    if (_sentBase !== base) { fetch(_path); return }
    var parts = Model.splitCurlOutput(_output)
    var outcome = Model.classify(_exitCode, parts.status)
    if (outcome === "ok") lastError = ""
    root.finished(outcome, parts.status, parts.body)
  }

  Process {
    id: proc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root._output = String(text || "")
        root._haveOutput = true
        root._finish()
      }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var line = String(text || "").trim().split("\n").pop()
        if (line) root.lastError = line.replace(/^curl: /, "")
      }
    }
    onExited: function(exitCode) {
      root._exitCode = exitCode
      root._haveExit = true
      root._finish()
    }
  }
}
