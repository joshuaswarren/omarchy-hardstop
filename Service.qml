// Hard Stop — service entry point. Owns the clock, the state machine, the
// per-day latches and the recap file. The bar widget and the overlay read
// state from here and never compute it themselves.
import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

Item {
  id: root

  property var shell: null
  property var manifest: null
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")

  readonly property string pluginId: manifest && manifest.id
    ? String(manifest.id)
    : "io.github.joshuaswarren.hardstop"

  // Settings live on the shell.json plugins[] entry, the bar layout entry, or
  // both. Binding to shellConfig itself is what makes edits hot-apply.
  readonly property var settings: Model.mergeSettings(shell ? shell.shellConfig : null, pluginId)

  // Wall clock, resampled every tick. Never a running total: a suspend/resume
  // must land in the right phase on the first tick after waking.
  property real nowMs: Date.now()
  readonly property string todayKey: Model.dateKey(nowMs)

  // What was read from (and written to) state.json. A record from a previous
  // day normalizes away, so latches reset at midnight without a rollover path.
  property var storedLatch: Model.emptyLatch("")
  readonly property var latch: Model.normalizeLatch(storedLatch, todayKey)
  property bool stateLoaded: false

  // Not named `state`: Item already owns that property.
  readonly property var snapshot: Model.computeState(nowMs, settings, latch)

  // ------------------------------------------------------------ public API
  readonly property string phase: snapshot.phase
  readonly property int msRemaining: snapshot.msRemaining
  readonly property int minutesRemaining: snapshot.minutesRemaining
  readonly property int minutesOver: snapshot.minutesOver
  readonly property string remainingText: snapshot.remainingText
  readonly property string stopTimeText: snapshot.stopTimeText
  readonly property int snoozeCount: snapshot.snoozeCount
  readonly property int maxSnoozes: snapshot.maxSnoozes
  readonly property bool canSnooze: snapshot.canSnooze
  readonly property bool showWhenIdle: snapshot.showWhenIdle
  readonly property bool scheduledToday: snapshot.scheduledToday

  function snooze() {
    if (!canSnooze) {
      // A refusal is a reply to a click, so it speaks even when quiet.
      notify("Hard Stop", "No more snoozes today - time to wind down.")
      return false
    }
    var next = Model.cloneLatch(latch)
    next.snoozeCount = next.snoozeCount + 1
    // A fresh snooze window deserves its own stop notification and overlay.
    next.stopNotified = false
    next.autoOpened = false
    commitLatch(next)
    return true
  }

  function skipToday() {
    var next = Model.cloneLatch(latch)
    next.skipped = true
    commitLatch(next)
  }

  function openWindDown(early) {
    if (!shell || typeof shell.summon !== "function") return
    shell.summon(pluginId, JSON.stringify({ early: !!early }))
  }

  function completeRitual(recapText, tomorrowText) {
    var next = Model.cloneLatch(latch)
    next.done = true
    commitLatch(next)
    writeRecap(recapText, tomorrowText)
    runOnComplete()
  }

  // ------------------------------------------------------------------ tick
  Timer {
    interval: 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      root.nowMs = Date.now()
      root.applyEffects()
    }
  }

  // Notification and overlay edges, each latched so it fires once per day.
  function applyEffects() {
    if (!stateLoaded) return
    var due = Model.pendingEffects(snapshot, latch, settings)
    if (!due.warn && !due.stop && !due.autoOpen) return

    var next = Model.cloneLatch(latch)
    if (due.warn) {
      next.warnNotified = true
      notify("Wind down soon", minutesRemaining + " min until your stop time.")
    }
    if (due.stop) {
      next.stopNotified = true
      notify("That's the day", "Stop time reached. Time to close it out.")
    }
    if (due.autoOpen) {
      next.autoOpened = true
      openWindDown(false)
    }
    commitLatch(next)
  }

  function notify(title, body) {
    var base = String(omarchyPath || "").trim()
    var bin = base === "" ? "omarchy-notification-send" : base + "/bin/omarchy-notification-send"
    Quickshell.execDetached([bin, String(title), String(body)])
  }

  // ----------------------------------------------------------- state file
  readonly property string homeDir: Quickshell.env("HOME")
  readonly property string stateDir: Model.stateDirFor(Quickshell.env("XDG_STATE_HOME"), homeDir)
  readonly property string statePath: stateDir + "/state.json"

  // FileView reads twice on a cold start: once when `path` resolves, once from
  // the explicit reload after mkdir. Re-reading is harmless; overwriting a
  // latch the user already committed is not.
  property bool statePersisted: false

  function loadState(raw) {
    if (statePersisted) return
    storedLatch = Model.parseLatch(raw, todayKey)
    stateLoaded = true
  }

  function commitLatch(next) {
    next.date = todayKey
    storedLatch = next
    stateLoaded = true
    statePersisted = true
    stateFile.setText(JSON.stringify(next, null, 2) + "\n")
  }

  FileView {
    id: stateFile
    path: root.statePath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadState(text())
    onLoadFailed: root.loadState("")
  }

  Process {
    id: ensureStateDirProc
    command: ["mkdir", "-p", root.stateDir]
    running: false
  }

  Component.onCompleted: {
    ensureStateDirProc.running = true
    // Read once the directory exists. FileView reports a missing file through
    // onLoadFailed, which is the first-run path.
    Qt.callLater(function() { stateFile.reload() })
  }

  // ----------------------------------------------------------- recap file
  readonly property string recapPath: {
    var expanded = Model.expandTilde(settings.recapFile, homeDir)
    if (!Model.isSafePath(expanded)) {
      console.warn("hardstop: refusing unsafe recapFile", settings.recapFile)
      return ""
    }
    return expanded
  }

  property string pendingRecapBlock: ""

  function writeRecap(recapText, tomorrowText) {
    var block = Model.recapBlock(todayKey, recapText, tomorrowText)
    if (!block || recapPath === "") return
    pendingRecapBlock = block
    ensureRecapDirProc.command = ["mkdir", "-p", Model.parentDir(recapPath)]
    ensureRecapDirProc.running = true
  }

  function flushRecap(existing) {
    if (pendingRecapBlock === "") return
    var block = pendingRecapBlock
    pendingRecapBlock = ""
    recapFile.setText(Model.appendRecap(existing, block))
  }

  FileView {
    id: recapFile
    path: root.recapPath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    // Both arms are no-ops unless a completeRitual left a block pending, so
    // the implicit load when `path` first resolves cannot rewrite the file.
    onLoaded: root.flushRecap(text())
    onLoadFailed: root.flushRecap("")
  }

  Process {
    id: ensureRecapDirProc
    running: false
    onExited: recapFile.reload()
  }

  function runOnComplete() {
    var cmd = String(settings.onCompleteExec || "").trim()
    if (cmd === "") return
    // The user authored this string. Recap and tomorrow text never reach it.
    Quickshell.execDetached(["sh", "-c", cmd])
  }

  // Scriptable control (keybindings, scripts): the same entry points the
  // chip's menu uses. `omarchy-shell hardstop <method>`.
  IpcHandler {
    target: "hardstop"

    function snooze(): void { root.snooze() }
    function skip(): void { root.skipToday() }
    function windDown(): void { root.openWindDown(true) }
    function status(): string { return JSON.stringify(root.snapshot) }
  }
}
