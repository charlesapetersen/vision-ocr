#!/usr/bin/env bash
# ops/autonomous/compact-runlog.sh — keep $RUN's SESSION LOG bounded, so the file every fresh session
# reads to orient does not inflate its own startup cost without limit.
#
# WHY: $RUN (default $STATE/RUN.md) holds four things — a plain `RUN STATUS:` line, `## FOCUS`,
# `## HOLD (owner-only)` and `## SESSION LOG`. The first three are bounded by what a human writes. The
# SESSION LOG is not: every session PREPENDS an entry, forever, and every session reads the whole file
# before it starts work. So an un-pruned log is a silent, compounding tax on every cycle — and in the
# project this was ported from that tax was measured at ~62k tokens of orientation for 243 entries, most
# of it dead history, while the compactor reported a clean "no-op" every cycle for weeks.
#
# WHEN: the daemon calls this BETWEEN cycles (session exited, engine lock released, before the next
# launch) — so NO claude session is active and this can never race a session's SESSION LOG append.
#
# ⚠️ NEWEST-FIRST. Sessions PREPEND, so entry 1 is the newest. The sibling's Pass 1 was written to "drop
# the first N (oldest), keep the last KEEP" — correct only for an append-ordered log, and it would have
# archived the NEWEST entries and kept the oldest the day its other bug was fixed. Every walk below runs
# newest-first for that reason.
#
# SAFE BY CONSTRUCTION — the whole reason it is acceptable to let a script rewrite a live file:
#   * REGION-BOUNDED: only the `## SESSION LOG` region is ever touched. `RUN STATUS:`, `## FOCUS` and
#     `## HOLD` are structurally out of reach — the awk passes never leave the region, and the anchor +
#     pre-region checks below would abort if they somehow did.
#   * builds the result in mktemp, VALIDATES, and only THEN `mv`s;
#   * ANCHOR SURVIVAL: every one of ^RUN STATUS:, ^## FOCUS, ^## HOLD, ^## SESSION LOG must still be
#     present in the candidate, or ABORT with the file untouched;
#   * LINE CONSERVATION: kept + dropped == original, counted with awk END{NR} so a missing final newline
#     cannot skew it (`wc -l` undercounts an unterminated last line; awk counts AND re-terminates it).
#     This is what catches a torn multi-line entry, which is how the sibling once orphaned 1,631 bytes of
#     continuation lines while moving 217 bytes of first lines;
#   * PRE-REGION BYTE IDENTITY: everything through the SESSION LOG header must be byte-identical (diff -q);
#   * the ARCHIVE WRITE PRECEDES THE `mv` AND IS GUARDED, so entries can never leave the file without a
#     copy landing in the archive — the archive, not the clobber-prone .bak, is the durable record;
#   * keeps a .bak of the pre-compaction file;
#   * IDEMPOTENT: a clean no-op once the region is under both triggers.
# $RUN lives in $STATE and is not in git, so the .bak + the archive are the only recovery points.
#
# ⚠️ EXIT-CODE CONTRACT — 0 for success AND for a legitimate no-op; 1 ONLY when a pass truly ABORTED.
# The daemon logs a loud, greppable `⚠⚠ compact-runlog ABORTED` on nonzero and nothing else does. In the
# sibling project the two were conflated behind a `|| true`: the compactor aborted on EVERY cycle for
# weeks, the abort scrolled past in the daemon log looking like routine output, and the plan drifted to
# 96% of its context budget before anyone noticed. A no-op must therefore be silent-and-zero, and an
# abort must be the only thing that is nonzero.
set -uo pipefail

# Backgrounded/launchd shells here have essentially no PATH (CLAUDE.md's environment trap: basename, cut
# and timeout fail SILENTLY and loops report bogus results). This script's whole job is arithmetic over
# awk/grep/diff/mktemp output, so a missing tool would not error — it would produce empty counts, and an
# empty count read as a number is how a compactor decides there is nothing to do.
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

RUN="${1:-${VISIONOCR_RUN:-$HOME/.local/state/visionocr-autonomous/RUN.md}}"
ARCHIVE="${VISIONOCR_RUN_ARCHIVE:-$(dirname "$RUN")/RUN-SESSION-ARCHIVE.md}"
KEEP="${KEEP:-8}"              # SESSION LOG entries to retain inline
TRIGGER="${TRIGGER:-14}"       # only compact when the region exceeds this many entries…
MAX_BYTES="${MAX_BYTES:-24000}" # …OR this many bytes. ENTRY COUNT IS A PROXY; BYTES ARE THE COST — the
                               # thing being defended is the tokens a fresh session pays to orient, and
                               # one fat entry can cost more than eight lean ones. Firing on either means
                               # a drift in how entries are AUTHORED cannot silently un-bound the file.
                               # ~24 KB ≈ 6k tokens ≈ the 8 entries KEEP already allows, so the byte cap
                               # and the count cap agree instead of the byte one quietly permitting a
                               # region much larger than the count one ever would. 0 disables the byte cap.

# A real section header is a column-0 '## ' that is BLANK-PRECEDED **or** named here. Both halves are
# load-bearing, and the sibling had a live bug in each direction:
#   * TOO NARROW (blank-preceded alone): the next section header happened to have no blank line before it
#     — which is exactly the separator that goes missing when entries are blank-separated and PREPENDED,
#     because the one against the following header belongs to the OLDEST entry — so the region ran to EOF
#     and swept a whole other section into the drop set. The anchor guard caught it, so the file was never
#     corrupted; it was also never compacted, for weeks.
#   * TOO WIDE: a '## ' pasted INSIDE an entry body (a quoted heading, a diff hunk) must NOT truncate the
#     region. Naming the sections is safe here because $RUN is a machine-managed file with a small, known
#     set of top-level sections — that is a contract, not a guess. A pasted heading matches no name and is
#     not blank-preceded, so it stays body: MEASURED — a mid-body '## Not a real section' travelled to the
#     archive with its own entry (61 of 115 lines dropped, conservation exact, all four anchors intact).
#     MEASURED LIMIT of the name half: a body line that reproduces a section name VERBATIM at column 0 (a
#     session quoting '## HOLD (owner-only)' inside an entry) DOES close the region early. Cost, measured:
#     under-rotation, and at worst that one entry split across file and archive. No byte is lost —
#     conservation still holds and the archive is the recovery point — and the sections themselves are
#     untouched. That is the right side of the trade: the alternative (blank-preceded alone) is the bug
#     that silently disabled the sibling's compactor for weeks.
# Add new '## ' sections here if $RUN grows one. A future section that is neither named nor blank-preceded
# degrades safely: the region over-runs, the anchor guard aborts, the file is left untouched — and the
# EXIT-CODE CONTRACT makes that abort loud instead of a log line nobody reads.
# Passed to awk via -v, which is safe ONLY because this pattern contains no backslashes (BSD awk strips
# backslashes from -v values, which once turned an anchored pattern into an unanchored one).
SEC_HEADER_RE='^## (FOCUS|HOLD|SESSION LOG)'

[ -f "$RUN" ] || { echo "compact-runlog: no run-state file at $RUN — skip"; exit 0; }

ABORTED=""
# One region, one pass — but kept in a subshell so its internal `exit`s mean "this pass ended" and never
# "the script succeeded". A nonzero subshell IS an abort; that is the whole exit-code contract.
(
H=$(grep -nE '^## SESSION LOG' "$RUN" | head -1 | cut -d: -f1)
[ -n "$H" ] || { echo "compact-runlog: no '## SESSION LOG' header in $RUN — skip"; exit 0; }

# Count entries AND region bytes in one pass. Region = the header line .. the next real SECTION header.
# ENTRY HEADER RULE: a column-0 '### ' heading OR a column-0 date-led '20YY-MM-DD' line. BOTH are
# supported because both are authored in practice ('### 2026-08-16 — auto/…' and the bare date-led form),
# and a detector that knows only one of them is precisely the failure the ALARM below exists to shout
# about. Continuations are indented or blank, so a blank-preceded rule is NOT required here (entries are
# not reliably blank-separated; requiring it would UNDER-count).
# Heuristic limit, LOW and conservation-safe: a continuation line that itself starts at column 0 with a
# date would read as a new entry and shift a boundary. No byte is lost — conservation still holds and the
# archive is the recovery point.
# Regexes are awk-PROGRAM literals, never -v values, for the BSD-awk backslash reason noted above.
read -r N REGB <<EOF
$(awk -v h="$H" -v sec="$SEC_HEADER_RE" '
  {
    if (NR == h) { inreg=1; prevblank=0; next }
    if (inreg && /^## / && (prevblank || (sec != "" && $0 ~ sec))) inreg=0
    if (inreg) { bytes += length($0) + 1
                 if (/^### / || /^20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]/) c++ }
    prevblank = ($0 ~ /^[[:space:]]*$/)
  }
  END { print c+0, bytes+0 }' "$RUN")
EOF
case "$N"    in ''|*[!0-9]*) N=0 ;; esac
case "$REGB" in ''|*[!0-9]*) REGB=0 ;; esac

OVER=0
[ "$MAX_BYTES" -gt 0 ] && [ "$REGB" -gt "$MAX_BYTES" ] && OVER=1
if [ "$N" -le "$TRIGGER" ] && [ "$OVER" = 0 ]; then
  echo "compact-runlog: $N SESSION LOG entries <= trigger $TRIGGER and ${REGB}B <= budget ${MAX_BYTES}B — no-op"
  exit 0
fi

# ⚠⚠ ANTI-SILENT-FAILURE ALARM. Over budget but ~no entries DETECTED means the entry-header rule no longer
# matches how sessions actually write this section. That is not a quiet edge case: in the sibling project
# the detector wanted a '- ' bullet form the file never used, saw ZERO entries in an 81 KB section,
# reported a clean no-op every cycle for weeks, and the plan grew to 96% of its budget while a session was
# eventually dispatched to fix a file its own compactor was configured to be unable to fix. A threshold
# that cannot be reached and a compactor that is switched off look identical from the outside, and BOTH
# times the visible symptom was the word "no-op".
# It deliberately does NOT change the exit code: nothing ABORTED, so the daemon's ⚠⚠ line keeps meaning
# exactly one thing (see the EXIT-CODE CONTRACT). The daemon appends this stdout to its own log, so the
# alarm lands directly above the no-op lines that are the symptom.
if [ "$OVER" = 1 ] && [ "$N" -lt 2 ]; then
  echo "compact-runlog: ⚠⚠ ALARM — SESSION LOG is ${REGB}B (budget ${MAX_BYTES}B) but only $N entries were DETECTED."
  echo "compact-runlog:    The entry-header rule ('### ' heading or a column-0 20YY-MM-DD line) no longer"
  echo "compact-runlog:    matches the authored format. FIX THE DETECTOR in this script — do NOT raise the"
  echo "compact-runlog:    budget. Every session is paying ${REGB}B of orientation for this region."
fi

# Effective keep: walk entries NEWEST-FIRST accumulating whole-entry bytes and keep only those that fit
# the byte budget, clamped to [1, KEEP]. So one enormous entry cannot hold the whole region hostage, and
# the count cap can never be the looser of the two.
EKEEP="$KEEP"
if [ "$MAX_BYTES" -gt 0 ]; then
  EKEEP=$(awk -v h="$H" -v sec="$SEC_HEADER_RE" -v keep="$KEEP" -v budget="$MAX_BYTES" '
    {
      if (NR == h) { inreg=1; prevblank=0; next }
      if (inreg && /^## / && (prevblank || (sec != "" && $0 ~ sec))) inreg=0
      if (inreg) {
        if (/^### / || /^20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]/) e++
        if (e > 0) sz[e] += length($0) + 1
      }
      prevblank = ($0 ~ /^[[:space:]]*$/)
    }
    END { run=0; fit=0
          for (i = 1; i <= e && i <= keep; i++) { run += sz[i]; if (run > budget) break; fit++ }
          if (fit < 1) fit = 1
          print fit }' "$RUN")
fi
case "$EKEEP" in ''|*[!0-9]*) EKEEP=1 ;; esac
[ "$EKEEP" -ge 1 ] || EKEEP=1

CUT=$((N - EKEEP))
[ "$CUT" -gt 0 ] || { echo "compact-runlog: nothing to cut (N=$N, effective KEEP=$EKEEP) — no-op"; exit 0; }

TMP=$(mktemp) || exit 1
DROP=$(mktemp) || { rm -f "$TMP"; exit 1; }

# Split in ONE awk pass keyed on the entry ORDINAL, newest-first: the header + any preamble + entries
# 1..EKEEP + everything OUTSIDE the region -> kept; entries EKEEP+1..end -> archived. WHOLE ENTRIES
# TRAVEL TOGETHER — the ordinal only advances when a header line is crossed, so a continuation line can
# never be orphaned from its own entry. No line-range arithmetic, so a file whose last line lacks a
# newline cannot silently lose it.
awk -v h="$H" -v sec="$SEC_HEADER_RE" -v keep="$EKEEP" -v drop="$DROP" '
  {
    if (NR == h) { inreg=1; prevblank=0; print; next }          # the header itself is always kept
    if (inreg && /^## / && (prevblank || (sec != "" && $0 ~ sec))) inreg=0
    if (inreg && (/^### / || /^20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]/)) entry++
    if (inreg && entry > keep) print >> drop
    else print
    prevblank = ($0 ~ /^[[:space:]]*$/)
  }
' "$RUN" > "$TMP" || { rm -f "$TMP" "$DROP"; exit 1; }

# VALIDATE — any anomaly aborts with the file UNTOUCHED.
for a in '^RUN STATUS:' '^## FOCUS' '^## HOLD' '^## SESSION LOG'; do
  grep -qE "$a" "$TMP" || { echo "compact-runlog: VALIDATION FAIL ($a missing) — abort, $RUN untouched"; rm -f "$TMP" "$DROP"; exit 1; }
done
L_ORIG=$(awk 'END{print NR}' "$RUN"); L_KEPT=$(awk 'END{print NR}' "$TMP"); L_DROP=$(awk 'END{print NR}' "$DROP")
if [ "$((L_KEPT + L_DROP))" != "$L_ORIG" ]; then
  echo "compact-runlog: line conservation FAIL (kept $L_KEPT + dropped $L_DROP != orig $L_ORIG) — abort, $RUN untouched"
  rm -f "$TMP" "$DROP"; exit 1
fi
[ "$L_DROP" -gt 0 ] || { echo "compact-runlog: nothing dropped — abort, $RUN untouched"; rm -f "$TMP" "$DROP"; exit 1; }
[ "$L_KEPT" -lt "$L_ORIG" ] || { echo "compact-runlog: no line reduction — abort, $RUN untouched"; rm -f "$TMP" "$DROP"; exit 1; }
# Everything through the SESSION LOG header, byte for byte. This is what makes "RUN STATUS / FOCUS / HOLD
# are structurally untouchable" a checked property rather than a claim about the awk above.
if ! diff -q <(sed -n "1,${H}p" "$RUN") <(sed -n "1,${H}p" "$TMP") >/dev/null 2>&1; then
  echo "compact-runlog: pre-SESSION-LOG region changed — abort, $RUN untouched"; rm -f "$TMP" "$DROP"; exit 1
fi

# Commit: .bak, then the GUARDED archive append (BEFORE the mv, so entries are never removed from $RUN
# without a copy landing in the archive), then the atomic replace.
# Say WHY, even here. The abort banner at the foot points the reader "directly above", and the first cut
# of this line let `cp`'s own one-line stderr be the entire explanation — which in a daemon log is a bare
# "Permission denied" with no indication that a compaction pass had aborted.
cp "$RUN" "$RUN.bak" || { echo "compact-runlog: could not write $RUN.bak — abort, $RUN untouched"; rm -f "$TMP" "$DROP"; exit 1; }
{
  echo ""
  echo "<!-- $(date -u +%Y-%m-%dT%H:%MZ) archived $CUT SESSION LOG entries (oldest) from $(basename "$RUN") (kept newest $EKEEP inline; ${REGB}B region vs ${MAX_BYTES}B budget) -->"
  cat "$DROP"
} >> "$ARCHIVE" || { echo "compact-runlog: archive write to $ARCHIVE FAILED — abort, $RUN untouched"; rm -f "$TMP" "$DROP"; exit 1; }
mv "$TMP" "$RUN"
rm -f "$DROP"
echo "compact-runlog: archived $CUT SESSION LOG entries (newest $EKEEP kept of $N); $L_ORIG -> $L_KEPT lines; archive=$ARCHIVE"
) || ABORTED=1

if [ -n "$ABORTED" ]; then
  echo "compact-runlog: ⚠⚠ ABORTED — $RUN was left UNTOUCHED (reason directly above), so its SESSION LOG is"
  echo "compact-runlog:    NOT being kept bounded and every session's orientation cost will keep growing"
  echo "compact-runlog:    until this is fixed."
  exit 1
fi
exit 0
