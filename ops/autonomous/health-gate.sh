#!/usr/bin/env bash
# ops/autonomous/health-gate.sh — the daemon's periodic DETERMINISTIC regression gate.
#
# The daemon runs this ITSELF every $VISIONOCR_GATE_EVERY commits (health_gate() in
# vision-ocr-autonomous.sh) — no `claude` session, no LLM, no budget. It is build/test/grep, so spending a
# session on it would be paying a model to read exit codes. A nonzero exit makes the daemon retry once and
# then PARK the run, quoting this script's verdict line into the owner's park note. The verdict lines at
# the foot of this file are therefore a CONTRACT with `_run_gate_once` / `_classify_red` / `health_gate`
# and with `status-digest.sh`, not log messages. Do not reword them casually.
#
# ═════════════════════════════════════════════════════════════════════════════════════════════════════
# ⚠️ WHY THIS GATE EXISTS HERE IS NOT WHY IT EXISTED IN THE PROJECT IT WAS PORTED FROM
# ═════════════════════════════════════════════════════════════════════════════════════════════════════
# In the Archive Suite nothing gated a commit except the session's own discipline, so its health gate was
# the ONLY regression backstop: it ran the whole test matrix, and it ran it every 30 commits.
#
# Here `.githooks/pre-commit` already runs the FULL suite on every commit that stages
# `Sources/|Helper/|Tests/|Tools/|build.sh|run_tests.sh`, and an unattended session may not bypass it —
# the daemon's denylist refuses `git commit --no-verify` / `-n` precisely so that hook stays the thing
# standing between an unattended session and pushing untested code.
#
# SO PER-COMMIT REGRESSION COVER IS NOT THIS GATE'S JOB. Its job is the four things the hook does NOT do:
#
#   (a) `./build.sh`. The hook builds the app ONLY when `Sources/(App|ContentView|SettingsView).swift` is
#       staged — yet `run_tests.sh` excludes `App.swift` from the suite ENTIRELY (its `@main` collides
#       with `Tests/main.swift`'s top-level code). So on every other commit NOTHING proves the app still
#       links: not the hook, not the suite. `build.sh` also does work the suite never reaches at all —
#       bundling `jbig2`/`qpdf`, the relocation audit, signing — and that is where R31 lived.
#   (b) `Tools/check-tools-compile.sh` over EVERY tool (~26 s), not just the staged ones. The hook
#       type-checks staged tools only, which is seconds and is the right trade for a commit. It is not
#       enough over time, and this is measured, not hypothetical: `score-text-route` had NEVER compiled
#       in any commit while three documents cited its output (BUGS.md C25), and the annotation transplant
#       silently broke `score-skew` and `score-reading-order` ELEVEN DAYS later by adding a field to a
#       struct both had transcribed by hand (T16). A tool nobody has run this month is indistinguishable
#       from a tool that cannot run at all.
#   (c) The document-coherence checks (`check-staleness.sh`, `check-queue-coherence.sh`). The hook has no
#       opinion about whether the docs still describe the code. WARN-ONLY here — see their steps below.
#   (d) Catching a commit that reached `main` with the hook BYPASSED or simply never configured.
#       `core.hooksPath` is per-clone: a fresh clone, a new git worktree that someone re-initialised, or
#       a `git -c core.hooksPath=` invocation all have the hook silently absent. Every guarantee in the
#       paragraph above is conditional on that one setting, so this gate asserts it FIRST.
#
# Deterministic, and it makes NO commits and NO edits. Builds into gitignored `build/`.
#
# EXIT: 0 = GREEN (possibly with SKIPPED / KNOWN-FAILURE lanes named in the verdict line) · 1 = RED
#       · 2 = could not even start (no repo root).
set -uo pipefail

# ⚠️ EXPLICIT PATH, and this is the opposite of boilerplate — it is the difference between this gate
# meaning something and this gate rubber-stamping a broken bundle. CLAUDE.md's second environment trap:
# "Backgrounded shell commands have essentially no PATH — basename, cut, timeout fail silently and loops
# report bogus results." A launchd-spawned daemon (which is how this runs in production) is the extreme
# case. And the failure is SILENT BY DESIGN one level down: `build.sh` treats `bundle-libs.py` exit 1
# ("not installed") as benign and prints "(not installed — the app will look for them on PATH)", exiting
# 0. So a PATH without /opt/homebrew/bin does not fail the build — it produces a GREEN gate over an app
# bundle missing its own `jbig2` and `qpdf`. `swiftc` needs /usr/bin for the same reason.
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

# Repo root = two levels up from this script, as installed (ops/autonomous/health-gate.sh).
# VISIONOCR_GATE_ROOT overrides it. That override exists FOR TESTING and is documented here rather than
# hidden: the gate's own steps are a real build and a real ~40 min OCR suite (the whole gate measured
# 44m53s on 2026-08-16), so the only way to exercise
# its reporting (the RED verdict line, which step's tail gets quoted, the SKIPPED/KNOWN-FAILURE wording)
# without running them is to point it at a tree of stubs. Production never sets it.
ROOT="${VISIONOCR_GATE_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
cd "$ROOT" 2>/dev/null || { echo "health-gate: cannot cd to repo root '$ROOT'" >&2; exit 2; }
ROOT="$(pwd)"    # canonicalise, so a relative override still yields absolute "$ROOT/..." paths
OPS="$ROOT/ops/autonomous"

# Deliberately NOT exported: VISIONOCR_UNATTENDED. In the sibling project the equivalent
# (ARCHIVE_UNATTENDED=1) was load-bearing — it armed self-guards inside the scripts the gate invokes,
# without which the gate would open an app on the owner's screen. Nothing in THIS repo reads
# VISIONOCR_UNATTENDED except the daemon setting it for a session, so exporting it here would be a
# cargo-culted line that a later reader would mistake for a guarantee. The off-screen property is
# structural instead: no step here launches the app on the host (`build.sh` with no `--run`/`--install`,
# and the GUI lane runs inside a Tart VM with its own virtual display).

LOG="$(mktemp)"; fails=""
trap 'rm -f "$LOG"' EXIT

QUICK="${VISIONOCR_GATE_QUICK:-0}"

# Run a named check; record a failure without aborting (there is no `set -e` in this file, ON PURPOSE —
# the whole point of a gate is a COMPLETE verdict, so it accumulates failures instead of stopping at the
# first). On failure, append THAT STEP'S OWN tail to $LOG.
#
# WHY per-step and not one shared transcript (ported incident, 2026-08-08): $LOG used to accumulate every
# step's output and the RED branch printed `tail -40 "$LOG"` — i.e. the tail of whichever step ran LAST,
# which on a green-tailed run is a PASSING one. The 2026-08-08 park on `tag-vocabulary` reported
# "36 passed, 0 failed" under the heading "failing output", because two later steps overwrote the tail.
# The owner-facing park note is built from this text, so the one artifact naming the failure showed a
# step that had passed. Same family as the `step_skippable` bug below: a gate that misreports what it did
# is worse than a gate that says less.
step() {
  local name="$1"; shift
  printf '── %s ──\n' "$name"
  local out; out="$(mktemp)"
  if "$@" >"$out" 2>&1; then
    echo "  ✓ $name"
  else
    local rc=$?
    echo "  ✗ $name (rc=$rc)"; fails="$fails $name"
    { printf '\n===== %s (rc=%s) =====\n' "$name" "$rc"; tail -40 "$out"; } >>"$LOG"
  fi
  rm -f "$out"
}

# Like step(), but for a check that can legitimately be INCONCLUSIVE (exit 3 = skipped). A skip is not
# a pass: it prints ⊘ with the reason and is named in the final summary line.
#
# WHY (ported incident, 2026-07-29, root-caused 2026-07-30): the GUI-VM lane failed to reach the VM's
# guest agent, ran ZERO tests, fail-opened with exit 0 — and plain step() printed "✓ gui-vm". The gate
# reported GREEN including a GUI lane that had never executed, and the reason was buried in $LOG, which
# is only shown on RED. A gate that says ✓ for work it did not do is worse than no gate. NEVER collapse
# this back into step().
#
# The four-way mapping is exactly `Tools/vm-gui-check.sh`'s own documented contract
# (0 pass / 1 fail / 3 could-not-run), plus 4 for "ran, reproducibly failed, but tracked".
skips=""; warns=""
step_skippable() {
  local name="$1"; shift
  printf '── %s ──\n' "$name"
  # Capture THIS step's output separately. Reading a shared transcript would report the first 'SKIPPED'
  # anywhere in the file — including one left by an earlier step — as this step's reason. ($LOG is
  # failures-only for the same class of reason; see step() above. Only the `*)` arm contributes to it: a
  # skip and a known-failure are both reported inline, and neither is what RED is asking about.)
  local out; out="$(mktemp)"
  "$@" >"$out" 2>&1; local rc=$?
  case "$rc" in
    0) echo "  ✓ $name" ;;
    # `grep SKIPPED`, NOT `grep 'SKIPPED:'` as the sibling had it. vm-gui-check.sh writes
    # `vm-gui-check: SKIPPED — <reason>` — colon BEFORE the word, em dash after — so the colon-anchored
    # pattern would have matched nothing and printed "no reason reported" over a lane that stated its
    # reason perfectly well. Exactly the kind of silent wording mismatch this file keeps guarding against.
    3) local why; why="$(grep SKIPPED "$out" | tail -1)"
       echo "  ⊘ $name SKIPPED — ${why:-no reason reported}"; skips="$skips $name" ;;
    # 4 = ran, reproducibly FAILED, but the failures are known/tracked so they must not park the run.
    # The detail is echoed HERE, to the gate's own stdout, which is what lands in $STATE/last-gate.log —
    # not buried in $LOG, which is only shown on RED and deleted on exit. The first cut of the warn tier
    # printed a bare "✓", which is the silent-green bug wearing a different hat.
    4) echo "  ⚠ $name — KNOWN FAILURES (ran, did not pass; not parking):"
       grep -E '(^|[[:space:]])FAIL|[0-9]+ failed|error:' "$out" | sed 's/^/      /' | head -20
       warns="$warns $name" ;;
    *) echo "  ✗ $name (rc=$rc)"; fails="$fails $name"
       { printf '\n===== %s (rc=%s) =====\n' "$name" "$rc"; tail -40 "$out"; } >>"$LOG" ;;
  esac
  rm -f "$out"
}

# WARN-ONLY tier, for the two document-coherence checks. A doc/code mismatch is real and worth reporting,
# but it must NEVER park a run whose build and suite are green: the daemon parks on a nonzero exit here,
# and a park teaches its reader to ignore parks the moment one of them is a stale sentence in a tracker.
# (The sibling project learned this the other way round: a park whose only failing step was a DOCUMENT
# size check reached the owner as "a reproducible build/test regression on a broken tree" and cost him a
# morning hunting a bug that did not exist.)
#
# A MISSING check is a SKIP, not a warning. These two scripts are being written alongside this one, so
# until they land the honest report is "not verified", not "✓" and not "⚠".
step_warn() {
  local name="$1" script="$2"; shift 2
  printf '── %s ──\n' "$name"
  if [ ! -x "$script" ]; then
    echo "  ⊘ $name SKIPPED — $script is not present or not executable"
    skips="$skips $name"; return 0
  fi
  local out; out="$(mktemp)"
  if "$script" "$@" >"$out" 2>&1; then
    echo "  ✓ $name"
  else
    local rc=$?
    echo "  ⚠ $name (rc=$rc) — WARNING ONLY (ran, did not pass; deliberately NOT failing the gate):"
    tail -20 "$out" | sed 's/^/      /'
    warns="$warns $name"
  fi
  rm -f "$out"
}

# ── hooks-configured ─────────────────────────────────────────────────────────────────────────────────
# The precondition for every other guarantee in this repo, which is why it runs first and why it is a
# HARD step even though it is one `git config` read. CLAUDE.md tells each clone to run
# `git config core.hooksPath .githooks` ONCE — it is per-clone, uncommittable, and therefore exactly the
# kind of setup that is silently absent in a fresh clone or a re-initialised worktree. With it unset,
# `.githooks/pre-commit` never runs: every commit is untested, the daemon's `--no-verify` denial guards
# nothing, and this gate's whole "the hook already covers regressions" premise is false. That is a fact
# about the checkout, never inconclusive, so it REDs.
_check_hooks_configured() {
  local p
  p="$(git -C "$ROOT" config core.hooksPath 2>/dev/null)"
  if [ "$p" = ".githooks" ]; then
    echo "core.hooksPath = .githooks (the pre-commit suite gate is armed for this clone)"
    return 0
  fi
  echo "core.hooksPath is '${p:-<unset>}', expected '.githooks'."
  echo
  echo "Nothing is running .githooks/pre-commit in this checkout, so NO commit here has been"
  echo "test-gated — which also voids this gate's premise that per-commit regression cover is"
  echo "the hook's job. Fix it in one command, from the repo root:"
  echo
  echo "    git config core.hooksPath .githooks"
  echo
  echo "Then re-run the gate. (It is per-clone and cannot be committed, so every clone and every"
  echo "worktree needs it — CLAUDE.md, 'Install the hook once per clone'.)"
  return 1
}

# ── suite ────────────────────────────────────────────────────────────────────────────────────────────
# THE SINGLE MOST IMPORTANT LINE IN THIS FILE is the test-lock.sh wrapper below.
#
# CLAUDE.md's FIRST environment trap: "Never run two suites at once, in any two worktrees."
# `build/tests` has no bundle identifier, so `UserDefaults.standard` lands in a domain keyed by the
# process NAME — ~/Library/Preferences/tests.plist — and EVERY worktree shares that one file. A second
# suite's resetPrefs() removes every key and wipes the first one's settings mid-run. Measured:
# 882/883 -> 877/879. The symptom is the worst kind there is — a nearly-green run with a couple of
# unrelated failures, i.e. evidence that is WRONG rather than absent — and this gate is a PARK TRIGGER,
# so an unlocked suite here manufactures false parks AND corrupts whatever the owner was running.
#
# The daemon makes the collision easy to hit in three ways a human does not: it fires a session every
# cycle, every code commit runs the suite via the hook, and the owner keeps working interactively in the
# primary checkout at the same time.
#
# Written as a function rather than a one-liner so the wrapper cannot be "simplified" away by accident:
# a missing test-lock.sh REDs the step instead of silently falling back to an unlocked run.
_run_suite() {
  local tl="$OPS/test-lock.sh"
  if [ ! -x "$tl" ]; then
    echo "health-gate: $tl is missing or not executable."
    echo "REFUSING to run ./run_tests.sh unlocked. Two suites at once corrupt BOTH runs (build/tests has"
    echo "no bundle id, so every worktree shares ~/Library/Preferences/tests.plist; measured 882/883 ->"
    echo "877/879). Restore ops/autonomous/test-lock.sh — do not drop the wrapper."
    return 1
  fi
  # `run` propagates the command's own exit status, and releases the lock on ANY exit path including a
  # TERM from the daemon's gate watchdog — a lock leaked by a killed gate would block every later suite
  # until MAXAGE (90 min). --label is what `test-lock.sh status` and the daemon's idle explanation show
  # the owner when they wonder who is holding their suite.
  "$tl" run --label health-gate -- ./run_tests.sh
}

# ═════════════════════════════════════════════════════════════════════════════════════════════════════
# THE STEPS. Ordered CHEAP-AND-HERMETIC FIRST, expensive last, so a RED surfaces in the gate's first
# seconds rather than after ~10 minutes of build and OCR. (Same reasoning as the sibling's tier-2 block
# sitting ahead of its 15-20 min VM lane.)
# ═════════════════════════════════════════════════════════════════════════════════════════════════════

step hooks-configured _check_hooks_configured

# Document coherence — (c) above. WARN-ONLY, both of them. `check-staleness.sh` compares the documents
# against the REGISTER and against EACH OTHER: open-entry counts against `BUGS.md`, and each file's claimed
# suite check-count against the highest figure any document claims. `check-queue-coherence.sh` cross-checks
# each QUEUE.md item's cite against the register entry it names.
# Both are document edits when they fail, not bug hunts, and neither is worth a park.
#
# ⚠️ WORD THIS PRECISELY. An earlier version of this comment said check-staleness compares a claimed count
# "against the suite's ACTUAL count". It does not, and deliberately cannot: measuring that count means
# running `./run_tests.sh`, which this step must never do — it has to stay cheap enough to run on every gate,
# and starting a second suite is the exact corruption `test-lock.sh` exists to prevent. So the script labels
# its reference `claimed (…), NOT measured` and asserts only what it can prove: that the live documents
# contradict each other, so at most one of them is current. A gate comment claiming more standing than its
# script has is how a reader comes to trust a number nobody measured — precisely the failure this repo's
# verification discipline is built around.
step_warn staleness       "$OPS/check-staleness.sh"
step_warn queue-coherence "$OPS/check-queue-coherence.sh"

# EVERY tool, ~26 s — see (b) above. Hard step: a tool that does not type-check is a fact about the
# source, never inconclusive. Type-check, not build, so it does not catch a link failure; that is the
# script's own documented bargain and it still catches the whole C25/T16 class.
step tools-compile Tools/check-tools-compile.sh

if [ "$QUICK" = 1 ]; then
  # VISIONOCR_GATE_QUICK=1 — WIRING CHECKS ONLY. Both expensive lanes are announced as SKIPPED and named
  # in NOT VERIFIED, because a quick run that merely printed GREEN would be a gate claiming coverage it
  # has not got, which is the one thing every guard in this file exists to prevent.
  printf '── %s ──\n' "suite"
  echo "  ⊘ suite SKIPPED — VISIONOCR_GATE_QUICK=1 (./run_tests.sh did NOT run)"
  printf '── %s ──\n' "build"
  echo "  ⊘ build SKIPPED — VISIONOCR_GATE_QUICK=1 (./build.sh did NOT run)"
  skips="$skips suite build"
else
  step suite _run_suite
  # ./build.sh — see (a) above. Note WHY the PATH line at the top of this file is load-bearing here:
  # build.sh runs `python3 Tools/bundle-libs.py "$APP" jbig2 qpdf` and REFUSES the build only when that
  # exits >= 2 ("the audit rejected what I copied"); exit 1 means "not installed" and is treated as
  # BENIGN — it prints "(not installed — the app will look for them on PATH)" and carries on to a
  # successful build. So with jbig2/qpdf off the PATH this step passes over a bundle missing its own
  # tools. The gate would be green and the shipped app would silently fall back to Homebrew copies that
  # a user's machine may not have.
  step build ./build.sh
fi

# ── gui-vm: the interface checks only a running app can answer (U13, U15, U17) ────────────────────────
# OFF BY DEFAULT (VISIONOCR_GATE_GUI=1 to enable) because it needs two things a machine may simply not
# have: a Tart VM named $VM (default `archive-gui-runner`, shared with the Archive Suite) and vncdotool
# at ~/.tart-mirror/vncenv/bin/vncdotool. Turn it on with:
#
#     VISIONOCR_GATE_GUI=1 ops/autonomous/health-gate.sh          (or export it in $STATE/env)
#
# FAIL-OPEN by construction: vm-gui-check.sh already exits 0 pass / 1 fail / 3 could-not-run, which is
# step_skippable's contract exactly — a missing VM, a boot failure or a guest-agent timeout SKIPs, and
# only a reproducible check failure REDs. So the lane is inert on a machine without a VM instead of
# parking the run over absent infrastructure. It runs via step_skippable and NEVER via step(): this is
# the very lane whose entire documented history is "reported green while running zero tests".
# ~4 minutes, nine checks, off the owner's screen (the VM has its own virtual display).
[ "${VISIONOCR_GATE_GUI:-0}" = 1 ] && step_skippable gui-vm Tools/vm-gui-check.sh all

# ── fault-inject: does the build still NOTICE when something is broken on purpose? ────────────────────
# OFF BY DEFAULT (VISIONOCR_GATE_FAULT=1 to enable):
#
#     VISIONOCR_GATE_FAULT=1 ops/autonomous/health-gate.sh
#
# SAFE — it rsyncs the tree to an mktemp sandbox (excluding .git, build, testdocs, mutation-out) and
# sabotages THAT, so it cannot touch the working tree or the real build/ — but SLOW: seven cases, five of
# them running a real build step. It guards the code that only runs when something else fails (R31, R32,
# H2 — a bundling audit, a detach-on-failure path, a licence count, each written carefully and never once
# executed), which is exactly the kind of coverage worth having on a cadence rather than per commit. The
# seventh (`argv_writers`, T19) sabotages nothing: it feeds hostile argv to the two tools that WRITE
# argv[2], and asserts the destination is byte-identical afterwards. Read `--list` rather than this
# sentence — it said "six" for one case longer than it was true.
# ⚠️ It is under step_skippable for the four-way mapping, but note it has NO exit-3 lane of its own: it
# exits 0/1 only, so a missing rsync or swiftc REDs rather than skipping. That, as much as the runtime,
# is why it stays off unless someone deliberately arms it.
[ "${VISIONOCR_GATE_FAULT:-0}" = 1 ] && step_skippable fault-inject Tools/fault-inject.sh

# ═════════════════════════════════════════════════════════════════════════════════════════════════════
# VERDICT — an EXACT contract the daemon parses. `_classify_red` in vision-ocr-autonomous.sh reads the
# RED line with:  sed 's/^HEALTH GATE: RED[^A-Za-z0-9]*//'  then splits on spaces; `status-digest.sh`
# greps '^HEALTH GATE: RED' out of $STATE/last-gate.log to report "the last full check FAILED". So the
# prefix, the em dash and the space-separated step names are all load-bearing bytes.
#
# DEFENSIVE, and say so plainly so a future reader does not go looking for a live branch that is not
# there: `_classify_red` classifies ONLY `staleness` and `queue-coherence` as DOCUMENT steps and treats
# every other name as a CODE regression. Both of those run through step_warn, which never touches
# $fails — so as this file stands TODAY the daemon's document-only branch is UNREACHABLE. It is kept on
# both sides because the classification is what stops a doc nit being reported to the owner as "a
# reproducible build/suite regression on a broken tree", and because the day someone promotes either
# check to a hard step, the daemon must already know it is a document step.
# ═════════════════════════════════════════════════════════════════════════════════════════════════════
echo
if [ -n "$fails" ]; then
  echo "HEALTH GATE: RED —$fails"
  # Every FAILING step's own tail, each under its own banner — not the tail of a shared transcript,
  # which is the tail of whatever ran last. This text is what the daemon quotes into the park note.
  echo "--- failing output (tail, per failing step) ---"; cat "$LOG"
  exit 1
fi

# What actually ran, for the GREEN line — assembled AFTER the steps, from the switches AND from what the
# lanes reported. A lane that was off, that skipped, or that warned is NOT listed as having run: the
# original's version named every enabled lane and then contradicted itself in the same line
# ("GREEN (… + gui-vm) — NOT VERIFIED: gui-vm"), which is the summary-line half of the silent-green bug.
# `_lane_ran` is a substring test over the skip/warn sets, so it needs no extra bookkeeping in step().
_lane_ran() { case " $skips $warns " in *" $1 "*) return 1 ;; esac; return 0; }
ran="hooks + tools-compile (every tool)"
if [ "$QUICK" != 1 ]; then
  _lane_ran suite && ran="$ran + suite (locked)"
  _lane_ran build && ran="$ran + ./build.sh"
fi
_lane_ran staleness && _lane_ran queue-coherence && ran="$ran + document coherence"
[ "${VISIONOCR_GATE_GUI:-0}" = 1 ]   && _lane_ran gui-vm       && ran="$ran + gui-vm"
[ "${VISIONOCR_GATE_FAULT:-0}" = 1 ] && _lane_ran fault-inject && ran="$ran + fault-inject"
# Said LOUDLY and last, inside the parens (a ';' separator, so it cannot be mistaken for one of the
# verdict line's own ' — ' fields): a quick run is a wiring check, and the one thing it must not do is
# read like a gate that passed.
[ "$QUICK" = 1 ] && ran="$ran; ⚠ QUICK MODE (VISIONOCR_GATE_QUICK=1): NEITHER ./run_tests.sh NOR ./build.sh RAN — a WIRING CHECK, NOT a regression gate"

# A skip never REDs the gate (infra and absent prerequisites must not park a healthy run) but it MUST be
# visible HERE — this line is what lands in $STATE/last-gate.log and what the owner reads. "GREEN" alone
# would claim coverage the run does not have.
if [ -n "$skips" ] || [ -n "$warns" ]; then
  echo "HEALTH GATE: GREEN ($ran)${skips:+ — NOT VERIFIED:$skips}${warns:+ — KNOWN FAILURES:$warns}"
  [ -n "$skips" ] && echo "  ↳ the skipped lane(s) ran ZERO checks — each one's reason is printed above."
  # Deliberately does NOT say which tier a warn came from: $warns holds both a document-coherence check
  # that failed (step_warn) and a lane that ran and reproducibly failed a TRACKED check (step_skippable
  # rc=4). Naming one tier for both is how a summary line starts lying — the first cut of this line called
  # a failing `gui-vm` lane "a document-coherence check".
  [ -n "$warns" ] && echo "  ↳ the warned lane(s) RAN and did NOT pass — a tracked/known failure, or a document-coherence mismatch. Neither parks the run. Detail above."
  exit 0
fi
echo "HEALTH GATE: GREEN ($ran)"
exit 0
