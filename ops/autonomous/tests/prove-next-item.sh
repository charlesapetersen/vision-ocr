#!/usr/bin/env bash
# prove-next-item.sh — harness for `next-item.sh`'s `(not-before: DATE)` gate.
#
# WHAT IT PROVES, on a scratch queue with VISIONOCR_TODAY pinned:
#   [1] an item dated in the future is reported `blocked:not-before:<date>`, not `ok`
#   [2] the same item is `ok` on and after its date
#   [3] a malformed date blocks rather than offering the item
#   [4] a not-before gate and an unmet `blocked-on` are both named
#   [5] a queue whose only open item is date-gated exits 4 (all blocked), not 0; 0 once the date passes
#   [6] with two clauses the later date wins, and a malformed one wins over both
#   [7] an empty `(not-before:)` in prose is not a clause and does not hide the real one
#   [8] a VISIONOCR_TODAY that is not YYYY-MM-DD refuses (exit 2) instead of ordering wrongly
#   [9] unpinned, today comes from `date`
# Reads nothing outside its temp directory; no suite, no build.
set -uo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

HERE="$(cd "$(dirname "$0")" && pwd)"
NI="$HERE/../next-item.sh"
T="$(mktemp -d -t vo-prove-next)"
trap 'rm -rf "$T"' EXIT
: > "$T/BUGS.md"
fail=0
q() { printf '%s\n' "$@" > "$T/Q.md"; }
run() { VISIONOCR_QUEUE="$T/Q.md" VISIONOCR_BUGS="$T/BUGS.md" VISIONOCR_TODAY="$1" "$NI" "$T"; }
expect() {  # label, wanted line prefix, today
  local got; got="$(run "$3" | cut -f1-2)"
  if printf '%s\n' "$got" | grep -qxF -- "$2"; then echo "PASS $1"
  else echo "FAIL $1: wanted [$2], got [$got]"; fail=1; fi
}

q '- [ ] **later** — wait a week. (not-before: 2026-10-14)'
expect '[1] future date blocks'        "$(printf 'blocked:not-before:2026-10-14\tlater')" 2026-10-07
expect '[2a] on the date it is offered' "$(printf 'ok\tlater')" 2026-10-14
expect '[2b] after the date too'        "$(printf 'ok\tlater')" 2026-11-01

q '- [ ] **bad** — typo. (not-before: 14/10/2026)'
expect '[3] malformed date blocks'      "$(printf 'blocked:not-before:14/10/2026\tbad')" 2027-01-01

q '- [ ] **both** — two gates. (blocked-on: nosuch)' '      (not-before: 2026-10-14)'
expect '[4] both gates named, wrapped'  "$(printf 'blocked:nosuch,not-before:2026-10-14\tboth')" 2026-10-07

q '- [ ] **later** — wait. (not-before: 2026-10-14)'
run 2026-10-07 > /dev/null; rc=$?
if [ "$rc" -eq 4 ]; then echo "PASS [5] exit 4"; else echo "FAIL [5] exit $rc, wanted 4"; fail=1; fi

run 2026-10-14 > /dev/null; rc=$?
if [ "$rc" -eq 0 ]; then echo "PASS [5b] exit 0 on the date"; else echo "FAIL [5b] exit $rc, wanted 0"; fail=1; fi

q '- [ ] **two** — two dates. (not-before: 2026-10-01)' '      (not-before: 2026-12-01)'
expect '[6a] later date wins'           "$(printf 'blocked:not-before:2026-12-01\ttwo')" 2026-10-07
q '- [ ] **two** — two dates. (not-before: 2026-10-01) (not-before: soon)'
expect '[6b] malformed wins over date'  "$(printf 'blocked:not-before:soon\ttwo')" 2027-01-01

q '- [ ] **prose** — the script gained `(not-before:)` today.' '      (not-before: 2026-10-14)'
expect '[7a] prose mention skipped'     "$(printf 'blocked:not-before:2026-10-14\tprose')" 2026-10-07
expect '[7b] and the item opens later'  "$(printf 'ok\tprose')" 2026-10-14

q '- [ ] **later** — wait. (not-before: 2026-12-01)'
run 20261207 > /dev/null 2>&1; rc=$?
if [ "$rc" -eq 2 ]; then echo "PASS [8] bad today refused"; else echo "FAIL [8] exit $rc, wanted 2"; fail=1; fi

q "- [ ] **now** — due today. (not-before: $(date +%Y-%m-%d))"
got="$(VISIONOCR_QUEUE="$T/Q.md" VISIONOCR_BUGS="$T/BUGS.md" "$NI" "$T" | cut -f1)"
if [ "$got" = ok ]; then echo "PASS [9] real date"; else echo "FAIL [9] got [$got]"; fail=1; fi

[ "$fail" -eq 0 ] && echo "prove-next-item: all pass" || echo "prove-next-item: FAILED"
exit "$fail"
