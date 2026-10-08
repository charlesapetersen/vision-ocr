#!/usr/bin/env bash
# gate hook: runs ops/autonomous/health-gate.sh unchanged, passes its log through, and ends with the verdict in
# the form CONTRACT.md section 2 asks for:
#   HEALTH GATE: GREEN                                   exit 0
#   HEALTH GATE: RED — <step>, <step>                    exit 1
#   HEALTH GATE CLASS: doc|code|mixed                    (after a RED line)
# There is no skip code: health-gate.sh has no exit that means "skipped". Any nonzero exit without a RED line
# (killed, a tool missing) is RED, named "no verdict (exit N)", because the daemon reads every nonzero gate exit
# as RED (its own timeouts are the engine's, not this hook's). Exit 0 is GREEN, as the daemon reads it.
# The step names are read the way the daemon's _classify_red does: after the prefix, up to the next " — " (a
# stamped suite skip rides after it as a note). Document steps: staleness, queue-coherence,
# queue-coherence-selftest; every other step builds or tests code. Heavy: the engine runs it under the heavy
# lock, and the gate takes test.lock itself. It writes what the gate writes (build products, suite stamps).
set -u
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
log="$(mktemp -t agent-gate)" || exit 3
trap 'rm -f "$log"' EXIT
"$SCRIPTS/health-gate.sh" 2>&1 | tee "$log"
rc=${PIPESTATUS[0]}
vline="$(grep -m1 '^HEALTH GATE: RED' "$log")"
if [ -n "$vline" ]; then
  steps="$(printf '%s' "$vline" | sed 's/^HEALTH GATE: RED[^A-Za-z0-9]*//' | tr -s ' ' | sed 's/^ *//; s/ *$//')"
  steps="${steps%% — *}"
  list=""; doc=0; code=0
  oldifs="$IFS"; IFS=' '
  for s in $steps; do
    list="${list:+$list, }$s"
    case "$s" in staleness|queue-coherence|queue-coherence-selftest) doc=1 ;; *) code=1 ;; esac
  done
  IFS="$oldifs"
  [ -n "$list" ] || { list="unnamed"; code=1; }
  echo "HEALTH GATE: RED — $list"
  if [ "$doc" = 1 ] && [ "$code" = 1 ]; then echo "HEALTH GATE CLASS: mixed"
  elif [ "$doc" = 1 ]; then echo "HEALTH GATE CLASS: doc"
  else echo "HEALTH GATE CLASS: code"; fi
  exit 1
fi
if [ "$rc" = 0 ]; then
  echo "HEALTH GATE: GREEN"
  exit 0
fi
echo "HEALTH GATE: RED — no verdict (exit $rc)"
echo "HEALTH GATE CLASS: code"
exit 1
