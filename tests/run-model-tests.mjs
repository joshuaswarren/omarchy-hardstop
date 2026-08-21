// Truth table for Model.js. Runs the QML JS library verbatim in a sandbox so
// the tested source is byte-for-byte what Quickshell loads.
//
//   node tests/run-model-tests.mjs

import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import vm from "node:vm";

const here = dirname(fileURLToPath(import.meta.url));
const source = readFileSync(join(here, "..", "Model.js"), "utf8").replace(/^\.pragma\s+library\s*$/m, "");

const M = vm.createContext({});
vm.runInContext(source, M, { filename: "Model.js" });

let failures = 0;
let checks = 0;

function check(label, actual, expected) {
  checks++;
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  if (a !== e) {
    failures++;
    console.error(`FAIL ${label}\n  expected: ${e}\n  actual:   ${a}`);
  }
}

// 2026-08-21 is a Friday, 2026-08-22 a Saturday. Local time throughout, which
// is what Model.js computes from too.
const at = (y, mo, d, h, mi) => new Date(y, mo - 1, d, h, mi, 0, 0).getTime();
const FRI_1700 = at(2026, 8, 21, 17, 0);
const SAT_1700 = at(2026, 8, 22, 17, 0);
const MIN = 60000;

const defaults = M.mergeSettings(null, "io.github.joshuaswarren.hardstop");
const fresh = (day) => M.emptyLatch(day);
const FRI = "2026-08-21";

// ---------------------------------------------------------------- defaults
check("default settings", defaults, {
  schedule: { mon: "17:00", tue: "17:00", wed: "17:00", thu: "17:00", fri: "17:00" },
  warnMinutes: 30,
  maxSnoozes: 2,
  recapFile: "~/Documents/day-recaps.md",
  onCompleteExec: "",
  quiet: false,
  showWhenIdle: true,
});

check("weekday is scheduled", M.stopMsFor(FRI_1700 - 3 * 3600000, defaults.schedule), FRI_1700);
check("weekend is not scheduled", M.stopMsFor(SAT_1700 - 3 * 3600000, defaults.schedule), -1);
check("date key", M.dateKey(FRI_1700), FRI);
check("day key", M.dayKeyForMs(FRI_1700), "fri");

// -------------------------------------------------------------- phase table
const phaseAt = (offsetMs, latch) =>
  M.phaseFor(FRI_1700 + offsetMs, FRI_1700, defaults.warnMinutes, latch || fresh(FRI));

check("T-3h idle", phaseAt(-3 * 3600000), "idle");
check("T-31min idle", phaseAt(-31 * MIN), "idle");
check("T-30min warning", phaseAt(-30 * MIN), "warning");
check("T-6min warning", phaseAt(-6 * MIN), "warning");
check("T-5min final", phaseAt(-5 * MIN), "final");
check("T-1min final", phaseAt(-1 * MIN), "final");
check("T+0 over", phaseAt(0), "over");
check("T+1min over", phaseAt(1 * MIN), "over");
check("off day", M.phaseFor(SAT_1700, -1, 30, fresh("2026-08-22")), "offday");

const skipped = Object.assign(fresh(FRI), { skipped: true });
const done = Object.assign(fresh(FRI), { done: true });
check("skipped forces done", phaseAt(-3 * 3600000, skipped), "done");
check("done forces done", phaseAt(1 * MIN, done), "done");

// ------------------------------------------------------------------- snooze
const snoozed = Object.assign(fresh(FRI), { snoozeCount: 1 });
check("effective stop shifts 15min", M.effectiveStopMs(FRI_1700, 1), FRI_1700 + 15 * MIN);
check("effective stop shifts 30min", M.effectiveStopMs(FRI_1700, 2), FRI_1700 + 30 * MIN);
check("snooze pushes over back to warning", phaseAt(0, snoozed), "warning");
check("snooze reopens final", phaseAt(11 * MIN, snoozed), "final");
check("snooze reopens warning", phaseAt(-10 * MIN, snoozed), "warning");
check("snooze T+16min over", phaseAt(16 * MIN, snoozed), "over");

// -------------------------------------------------------------- full state
const stateAt = (offsetMs, latch, settings) =>
  M.computeState(FRI_1700 + offsetMs, settings || defaults, latch || fresh(FRI));

const idle = stateAt(-165 * MIN);
check("idle remainingText", idle.remainingText, "2:45");
check("idle minutesRemaining", idle.minutesRemaining, 165);
check("idle stopTimeText", idle.stopTimeText, "17:00");
check("idle scheduledToday", idle.scheduledToday, true);
check("idle canSnooze", idle.canSnooze, true);
check("idle maxSnoozes", idle.maxSnoozes, 2);
check("idle minutesOver", idle.minutesOver, 0);

check("warning remainingText", stateAt(-31 * MIN).remainingText, "0:31");
check("final remainingText", stateAt(-5 * MIN).remainingText, "5 min");
check("final remainingText at 1min", stateAt(-1 * MIN).remainingText, "1 min");

const over = stateAt(7 * MIN);
check("over phase", over.phase, "over");
check("over minutesOver", over.minutesOver, 7);
check("over minutesRemaining floors at 0", over.minutesRemaining, 0);
check("over remainingText empty", over.remainingText, "");

const offday = M.computeState(SAT_1700, defaults, fresh("2026-08-22"));
check("offday phase", offday.phase, "offday");
check("offday stopTimeText empty", offday.stopTimeText, "");
check("offday canSnooze", offday.canSnooze, false);

const maxed = Object.assign(fresh(FRI), { snoozeCount: 2 });
check("snoozes exhausted", stateAt(-40 * MIN, maxed).canSnooze, false);
check("done cannot snooze", stateAt(-40 * MIN, done).canSnooze, false);

// ------------------------------------------------------------------ latches
check("stale latch reads fresh", M.normalizeLatch(
  { date: "2026-08-20", snoozeCount: 2, done: true, skipped: true, warnNotified: true, stopNotified: true, autoOpened: true },
  FRI,
), fresh(FRI));
check("todays latch survives", M.normalizeLatch({ date: FRI, snoozeCount: 1, done: true }, FRI),
  Object.assign(fresh(FRI), { snoozeCount: 1, done: true }));
check("null latch", M.normalizeLatch(null, FRI), fresh(FRI));
check("garbage json", M.parseLatch("{not json", FRI), fresh(FRI));
check("empty file", M.parseLatch("", FRI), fresh(FRI));
check("parsed latch", M.parseLatch(JSON.stringify({ date: FRI, autoOpened: true }), FRI),
  Object.assign(fresh(FRI), { autoOpened: true }));

// ------------------------------------------------------------------ effects
const effects = (offsetMs, latch, settings) =>
  M.pendingEffects(stateAt(offsetMs, latch, settings), latch || fresh(FRI), settings || defaults);

check("idle fires nothing", effects(-40 * MIN), { warn: false, stop: false, autoOpen: false });
check("warning fires warn", effects(-20 * MIN), { warn: true, stop: false, autoOpen: false });
check("warn latched once", effects(-20 * MIN, Object.assign(fresh(FRI), { warnNotified: true })),
  { warn: false, stop: false, autoOpen: false });
check("stop fires stop and overlay", effects(1 * MIN, Object.assign(fresh(FRI), { warnNotified: true })),
  { warn: false, stop: true, autoOpen: true });
check("resume past stop skips warn", effects(1 * MIN), { warn: false, stop: true, autoOpen: true });
check("stop latched once", effects(1 * MIN, Object.assign(fresh(FRI), { warnNotified: true, stopNotified: true, autoOpened: true })),
  { warn: false, stop: false, autoOpen: false });

const quiet = M.mergeSettings({ plugins: [{ id: "io.github.joshuaswarren.hardstop", quiet: true }] },
  "io.github.joshuaswarren.hardstop");
check("quiet silences warn", effects(-20 * MIN, null, quiet), { warn: false, stop: false, autoOpen: false });
check("quiet keeps the overlay", effects(1 * MIN, null, quiet), { warn: false, stop: false, autoOpen: true });
check("skipped fires nothing", effects(1 * MIN, skipped), { warn: false, stop: false, autoOpen: false });
check("offday fires nothing",
  M.pendingEffects(offday, fresh("2026-08-22"), defaults), { warn: false, stop: false, autoOpen: false });

// ----------------------------------------------------------- settings merge
const ID = "io.github.joshuaswarren.hardstop";
const merged = M.mergeSettings({
  plugins: [{ id: ID, warnMinutes: 10, quiet: true, recapFile: "~/notes/day.md" }],
  bar: {
    layout: {
      left: [{ id: "omarchy.clock" }],
      right: [{ id: ID, warnMinutes: 45, maxSnoozes: 4 }],
    },
  },
}, ID);
check("layout wins over plugins", merged.warnMinutes, 45);
check("plugins entry still applies", merged.quiet, true);
check("plugins entry recapFile", merged.recapFile, "~/notes/day.md");
check("layout-only key", merged.maxSnoozes, 4);
check("unset key keeps default", merged.showWhenIdle, true);

check("string layout entry merges nothing", M.mergeSettings({
  plugins: [{ id: ID, warnMinutes: 12 }],
  bar: { layout: { right: [ID] } },
}, ID).warnMinutes, 12);

check("custom schedule normalizes day names", M.mergeSettings({
  plugins: [{ id: ID, schedule: { Monday: "09:30", SAT: "13:00", nope: "10:00", tue: "bogus" } }],
}, ID).schedule, { mon: "09:30", sat: "13:00" });

check("unparseable schedule falls back", M.mergeSettings({
  plugins: [{ id: ID, schedule: { xxx: "yyy" } }],
}, ID).schedule, defaults.schedule);

check("out-of-range warnMinutes clamps", M.mergeSettings({
  plugins: [{ id: ID, warnMinutes: 0 }],
}, ID).warnMinutes, 1);

check("other plugin ids ignored", M.mergeSettings({
  plugins: [{ id: "omarchy.media", warnMinutes: 1 }],
}, ID).warnMinutes, 30);

// -------------------------------------------------------------------- recap
check("recap only", M.recapBlock(FRI, "shipped the parser\nfixed the latch", ""),
  "## 2026-08-21\n\n- shipped the parser\n- fixed the latch\n");
check("tomorrow only", M.recapBlock(FRI, "", "open the PR"),
  "## 2026-08-21\n\n### Tomorrow\n\n- open the PR\n");
check("both", M.recapBlock(FRI, "shipped it", "open the PR"),
  "## 2026-08-21\n\n- shipped it\n\n### Tomorrow\n\n- open the PR\n");
check("neither", M.recapBlock(FRI, "", ""), null);
check("whitespace only", M.recapBlock(FRI, "  \n\n \t", "   "), null);
check("null inputs", M.recapBlock(FRI, null, null), null);
check("inputs trimmed", M.recapBlock(FRI, "  padded  ", "  later  "),
  "## 2026-08-21\n\n- padded\n\n### Tomorrow\n\n- later\n");
check("existing bullets not doubled", M.recapBlock(FRI, "- already a bullet", "* starred"),
  "## 2026-08-21\n\n- already a bullet\n\n### Tomorrow\n\n- starred\n");
check("five line cap", M.recapBlock(FRI, "a\nb\nc\nd\ne\nf\ng", ""),
  "## 2026-08-21\n\n- a\n- b\n- c\n- d\n- e\n");
check("blank lines do not consume the cap", M.recapLines("a\n\n\nb\n\nc"), ["a", "b", "c"]);

check("append to empty file", M.appendRecap("", M.recapBlock(FRI, "one", "")),
  "## 2026-08-21\n\n- one\n");
check("append after existing", M.appendRecap("## 2026-08-20\n\n- old\n", M.recapBlock(FRI, "new", "")),
  "## 2026-08-20\n\n- old\n\n## 2026-08-21\n\n- new\n");
check("append normalizes trailing blanks",
  M.appendRecap("## 2026-08-20\n\n- old\n\n\n\n", M.recapBlock(FRI, "new", "")),
  "## 2026-08-20\n\n- old\n\n## 2026-08-21\n\n- new\n");

// --------------------------------------------------------------------- paths
check("tilde expands", M.expandTilde("~/Documents/day-recaps.md", "/home/joshuawarren"),
  "/home/joshuawarren/Documents/day-recaps.md");
check("bare tilde", M.expandTilde("~", "/home/joshuawarren/"), "/home/joshuawarren");
check("absolute untouched", M.expandTilde("/tmp/x.md", "/home/j"), "/tmp/x.md");
check("traversal rejected", M.isSafeRecapPath("/home/j/../../etc/passwd.md"), false);
check("relative rejected", M.isSafeRecapPath("notes.md"), false);
check("markdown accepted", M.isSafeRecapPath("/home/j/Documents/day-recaps.md"), true);
check("txt accepted", M.isSafeRecapPath("/home/j/notes/end-of-day.TXT"), true);
check("dot-directory component accepted", M.isSafeRecapPath("/home/j/.local/share/recaps.md"), true);
check("dotfile rejected", M.isSafeRecapPath("/home/j/.bashrc"), false);
check("dotfile with md extension rejected", M.isSafeRecapPath("/home/j/.evil.md"), false);
check("binary extension rejected", M.isSafeRecapPath("/home/j/notes.bin"), false);
check("no extension rejected", M.isSafeRecapPath("/home/j/notes"), false);
check("trailing slash rejected", M.isSafeRecapPath("/home/j/notes.md/"), false);
check("parent dir", M.parentDir("/home/j/Documents/day-recaps.md"), "/home/j/Documents");
check("state dir from xdg", M.stateDirFor("/run/user/1000/state", "/home/j"),
  "/run/user/1000/state/omarchy-hardstop");
check("state dir fallback", M.stateDirFor("", "/home/j"), "/home/j/.local/state/omarchy-hardstop");
check("relative xdg ignored per spec", M.stateDirFor("relative/state", "/home/j"),
  "/home/j/.local/state/omarchy-hardstop");
check("option-shaped xdg ignored", M.stateDirFor("-rf", "/home/j"),
  "/home/j/.local/state/omarchy-hardstop");

// -------------------------------------------------------- QML library compat
const body = source.replace(/^\s*\/\/.*$/gm, "");
for (const banned of ["let ", "const ", "=>", "import ", "export "]) {
  check(`no "${banned.trim()}" in Model.js`, body.includes(banned), false);
}

console.log(`${checks - failures}/${checks} checks passed`);
if (failures > 0) {
  console.error(`${failures} failing`);
  process.exit(1);
}
