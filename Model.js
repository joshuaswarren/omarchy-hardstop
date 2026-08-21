.pragma library

// Pure logic for Hard Stop. Everything here is a function of its arguments so
// the same code runs under QML and under tests/run-model-tests.mjs.

var PLUGIN_ID = "io.github.joshuaswarren.hardstop"
var DAY_KEYS = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
var BAR_SECTIONS = ["left", "center", "right"]
var MINUTE_MS = 60000
var SNOOZE_MINUTES = 15
var FINAL_MINUTES = 5

function isPlainObject(value) {
  return !!value && typeof value === "object" && !Array.isArray(value)
}

function pad2(value) {
  var n = Math.floor(Number(value) || 0)
  return n < 10 ? "0" + n : String(n)
}

function defaultSchedule() {
  return { mon: "17:00", tue: "17:00", wed: "17:00", thu: "17:00", fri: "17:00" }
}

function defaultSettings() {
  return {
    schedule: defaultSchedule(),
    warnMinutes: 30,
    maxSnoozes: 2,
    recapFile: "~/Documents/day-recaps.md",
    onCompleteExec: "",
    quiet: false,
    showWhenIdle: true
  }
}

// "Monday", "MON", "mon" all mean the same day.
function normalizeDayKey(key) {
  var short = String(key || "").trim().toLowerCase().slice(0, 3)
  return DAY_KEYS.indexOf(short) === -1 ? "" : short
}

function dayKeyForMs(ms) {
  return DAY_KEYS[new Date(ms).getDay()]
}

function dateKey(ms) {
  var d = new Date(ms)
  return d.getFullYear() + "-" + pad2(d.getMonth() + 1) + "-" + pad2(d.getDate())
}

// "17:00" -> 1020 minutes past midnight. -1 when unparseable.
function parseTimeOfDay(value) {
  var match = /^\s*(\d{1,2}):(\d{2})\s*$/.exec(String(value || ""))
  if (!match) return -1
  var hours = Number(match[1])
  var minutes = Number(match[2])
  if (hours > 23 || minutes > 59) return -1
  return hours * 60 + minutes
}

function formatClock(minutesOfDay) {
  if (minutesOfDay < 0) return ""
  return pad2(Math.floor(minutesOfDay / 60)) + ":" + pad2(minutesOfDay % 60)
}

function normalizeSchedule(raw) {
  if (!isPlainObject(raw)) return defaultSchedule()
  var out = {}
  var found = false
  for (var key in raw) {
    var day = normalizeDayKey(key)
    if (day === "") continue
    if (parseTimeOfDay(raw[key]) < 0) continue
    out[day] = String(raw[key]).trim()
    found = true
  }
  // A schedule object that parsed to nothing is a typo, not "no work ever".
  return found ? out : defaultSchedule()
}

function toBool(value, fallback) {
  if (value === true || value === false) return value
  if (value === undefined || value === null || value === "") return fallback
  var text = String(value).trim().toLowerCase()
  if (text === "true" || text === "yes" || text === "1" || text === "on") return true
  if (text === "false" || text === "no" || text === "0" || text === "off") return false
  return fallback
}

function toInt(value, fallback, min, max) {
  var n = Math.floor(Number(value))
  if (!isFinite(n)) return fallback
  if (n < min) return min
  if (n > max) return max
  return n
}

function entrySettingsFor(entry, pluginId) {
  if (typeof entry === "string") return String(entry) === pluginId ? {} : null
  if (!isPlainObject(entry)) return null
  if (String(entry.id || "") !== pluginId) return null
  var copy = {}
  for (var key in entry) {
    if (key === "id") continue
    copy[key] = entry[key]
  }
  return copy
}

function collectEntry(list, pluginId) {
  if (!Array.isArray(list)) return null
  for (var i = 0; i < list.length; i++) {
    var found = entrySettingsFor(list[i], pluginId)
    if (found !== null) return found
  }
  return null
}

// Keys may live on the plugins[] entry, on the bar layout entry, or both.
// The layout entry wins so behavior matches wherever the user put them.
function mergeSettings(shellConfig, pluginId) {
  var id = String(pluginId || PLUGIN_ID)
  var raw = defaultSettings()
  var sources = []

  if (isPlainObject(shellConfig)) {
    var fromPlugins = collectEntry(shellConfig.plugins, id)
    if (fromPlugins) sources.push(fromPlugins)

    var bar = isPlainObject(shellConfig.bar) ? shellConfig.bar : null
    var layout = bar && isPlainObject(bar.layout) ? bar.layout : null
    if (layout) {
      for (var i = 0; i < BAR_SECTIONS.length; i++) {
        var fromLayout = collectEntry(layout[BAR_SECTIONS[i]], id)
        if (fromLayout) sources.push(fromLayout)
      }
    }
  }

  for (var s = 0; s < sources.length; s++) {
    for (var key in sources[s]) {
      if (sources[s][key] === undefined || sources[s][key] === null) continue
      raw[key] = sources[s][key]
    }
  }

  return {
    schedule: normalizeSchedule(raw.schedule),
    warnMinutes: toInt(raw.warnMinutes, 30, 1, 720),
    maxSnoozes: toInt(raw.maxSnoozes, 2, 0, 24),
    recapFile: String(raw.recapFile || "").trim() || "~/Documents/day-recaps.md",
    onCompleteExec: String(raw.onCompleteExec || "").trim(),
    quiet: toBool(raw.quiet, false),
    showWhenIdle: toBool(raw.showWhenIdle, true)
  }
}

function emptyLatch(day) {
  return {
    date: String(day || ""),
    snoozeCount: 0,
    skipped: false,
    done: false,
    warnNotified: false,
    stopNotified: false,
    autoOpened: false
  }
}

function cloneLatch(latch) {
  var src = isPlainObject(latch) ? latch : {}
  return {
    date: String(src.date || ""),
    snoozeCount: toInt(src.snoozeCount, 0, 0, 999),
    skipped: src.skipped === true,
    done: src.done === true,
    warnNotified: src.warnNotified === true,
    stopNotified: src.stopNotified === true,
    autoOpened: src.autoOpened === true
  }
}

// Yesterday's latches must not silence today, so a stale date reads as fresh.
function normalizeLatch(raw, todayKey) {
  var day = String(todayKey || "")
  if (!isPlainObject(raw) || String(raw.date || "") !== day) return emptyLatch(day)
  var latch = cloneLatch(raw)
  latch.date = day
  return latch
}

function parseLatch(rawText, todayKey) {
  var text = String(rawText || "").trim()
  if (text === "") return emptyLatch(todayKey)
  try {
    return normalizeLatch(JSON.parse(text), todayKey)
  } catch (e) {
    return emptyLatch(todayKey)
  }
}

// Minutes past midnight for today's stop, or -1 on an off day.
function scheduledMinutesFor(nowMs, schedule) {
  var table = isPlainObject(schedule) ? schedule : defaultSchedule()
  return parseTimeOfDay(table[dayKeyForMs(nowMs)])
}

function stopMsFor(nowMs, schedule) {
  var minutes = scheduledMinutesFor(nowMs, schedule)
  if (minutes < 0) return -1
  var d = new Date(nowMs)
  d.setHours(Math.floor(minutes / 60), minutes % 60, 0, 0)
  return d.getTime()
}

function effectiveStopMs(stopMs, snoozeCount) {
  if (stopMs < 0) return -1
  return stopMs + toInt(snoozeCount, 0, 0, 999) * SNOOZE_MINUTES * MINUTE_MS
}

function phaseFor(nowMs, stopMs, warnMinutes, latch) {
  var state = cloneLatch(latch)
  if (state.done || state.skipped) return "done"
  var effective = effectiveStopMs(stopMs, state.snoozeCount)
  if (effective < 0) return "offday"

  var remaining = effective - nowMs
  if (remaining <= 0) return "over"
  if (remaining <= FINAL_MINUTES * MINUTE_MS) return "final"
  if (remaining <= toInt(warnMinutes, 30, 1, 720) * MINUTE_MS) return "warning"
  return "idle"
}

function remainingTextFor(phase, minutesRemaining) {
  if (phase === "final") return minutesRemaining + " min"
  if (phase !== "idle" && phase !== "warning") return ""
  return Math.floor(minutesRemaining / 60) + ":" + pad2(minutesRemaining % 60)
}

function computeState(nowMs, settings, latch) {
  var config = isPlainObject(settings) ? settings : defaultSettings()
  var state = cloneLatch(latch)
  var stopMs = stopMsFor(nowMs, config.schedule)
  var scheduledToday = stopMs >= 0
  var effective = effectiveStopMs(stopMs, state.snoozeCount)
  var phase = phaseFor(nowMs, stopMs, config.warnMinutes, state)
  var msRemaining = scheduledToday ? effective - nowMs : 0
  var minutesRemaining = msRemaining > 0 ? Math.ceil(msRemaining / MINUTE_MS) : 0
  // Rounded up so the first second past stop already reads "1 min", matching
  // how minutesRemaining rounds on the other side of the boundary.
  var minutesOver = msRemaining < 0 ? Math.ceil(-msRemaining / MINUTE_MS) : 0
  var maxSnoozes = toInt(config.maxSnoozes, 2, 0, 24)

  return {
    phase: phase,
    scheduledToday: scheduledToday,
    stopMs: stopMs,
    effectiveStopMs: effective,
    msRemaining: msRemaining,
    minutesRemaining: minutesRemaining,
    minutesOver: minutesOver,
    remainingText: remainingTextFor(phase, minutesRemaining),
    stopTimeText: scheduledToday ? formatClock(scheduledMinutesFor(nowMs, config.schedule)) : "",
    snoozeCount: state.snoozeCount,
    maxSnoozes: maxSnoozes,
    canSnooze: scheduledToday && phase !== "done" && state.snoozeCount < maxSnoozes,
    showWhenIdle: config.showWhenIdle === true
  }
}

// Which once-per-day side effects are due right now. The caller latches each
// one it fires so an effect never repeats within the day.
function pendingEffects(state, latch, settings) {
  var config = isPlainObject(settings) ? settings : defaultSettings()
  var current = cloneLatch(latch)
  var quiet = config.quiet === true
  var live = !!state && state.scheduledToday && state.phase !== "done" && state.phase !== "offday"
  // Resuming from suspend past the stop time skips straight to the stop
  // notification; a "wind down soon" nudge then would be a lie.
  var warnDue = live && (state.phase === "warning" || state.phase === "final")
  var stopDue = live && state.phase === "over"

  return {
    warn: warnDue && !quiet && !current.warnNotified,
    stop: stopDue && !quiet && !current.stopNotified,
    // The overlay is the whole point of the plugin, so quiet only silences
    // notifications, never the wind-down itself.
    autoOpen: stopDue && !current.autoOpened
  }
}

function recapLines(text) {
  var raw = String(text || "").split("\n")
  var out = []
  for (var i = 0; i < raw.length && out.length < 5; i++) {
    var line = raw[i].trim().replace(/^[-*]\s*/, "")
    if (line !== "") out.push(line)
  }
  return out
}

// Dated markdown section, or null when there is nothing worth writing.
function recapBlock(day, recapText, tomorrowText) {
  var lines = recapLines(recapText)
  var tomorrow = String(tomorrowText || "").trim().replace(/^[-*]\s*/, "")
  if (lines.length === 0 && tomorrow === "") return null

  var parts = ["## " + String(day || "")]
  if (lines.length > 0) parts.push("- " + lines.join("\n- "))
  if (tomorrow !== "") {
    parts.push("### Tomorrow")
    parts.push("- " + tomorrow)
  }
  return parts.join("\n\n") + "\n"
}

function appendRecap(existingText, block) {
  var existing = String(existingText || "").replace(/\s+$/, "")
  if (!block) return existing === "" ? "" : existing + "\n"
  if (existing === "") return block
  return existing + "\n\n" + block
}

function expandTilde(path, home) {
  var p = String(path || "").trim()
  var h = String(home || "").replace(/\/+$/, "")
  if (p === "~") return h
  if (p.indexOf("~/") === 0) return h + p.slice(1)
  return p
}

// The recap file is the only user-pointable path this plugin writes, and the
// write is a whole-file UTF-8 round-trip. Require: absolute, no traversal, a
// visible filename, and a plain-text extension — so a typo (or a hostile
// shell.json edit) cannot aim the ritual at a dotfile like ~/.bashrc or
// silently mangle a binary.
function isSafeRecapPath(path) {
  var p = String(path || "")
  if (p.charAt(0) !== "/") return false
  if (p.split("/").indexOf("..") !== -1) return false
  var name = p.slice(p.lastIndexOf("/") + 1)
  if (name === "" || name.charAt(0) === ".") return false
  return /\.(md|markdown|txt)$/i.test(name)
}

function parentDir(path) {
  var p = String(path || "")
  var cut = p.lastIndexOf("/")
  if (cut <= 0) return "/"
  return p.slice(0, cut)
}

// XDG spec: a relative XDG_STATE_HOME must be ignored. Requiring the leading
// slash also keeps the mkdir argv from ever starting with "-".
function stateDirFor(xdgStateHome, home) {
  var base = String(xdgStateHome || "").trim()
  if (base.charAt(0) !== "/") base = String(home || "").replace(/\/+$/, "") + "/.local/state"
  return base.replace(/\/+$/, "") + "/omarchy-hardstop"
}
