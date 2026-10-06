#!/usr/bin/env bash
# ops/autonomous/mac-heavy-lock.sh — ONE heavy job at a time on this Mac, shared with Archive Suite.
#
# WHY. On 2026-10-06, about 13:30-14:05, the Mac froze (15-minute load average about 28, swap 6.6 of 8 GB):
# this daemon's gate suite, Archive Suite's builds and Tart VM runs, and CrashPlan were all running. test.lock
# and engine.lock serialise only this project, and Archive Suite's heavy.lock only that one. This lock spans
# both. Owner: "Queue a shared lock, top priority."
#
# THE PROTOCOL, identical to Archive Suite's W35.machine-lock (each repo carries its own copy of a helper, so
# neither depends on the other):
#   lock     ~/.local/state/mac-heavy.lock, a DIRECTORY taken with mkdir (atomic).
#   owner    $lock/owner, key=value lines: pid= project= label= start=<epoch> started=<local time>. Written to a
#            temporary name and renamed into place, so a reader never sees half of it.
#   release  by the holder, on any exit (trap). Only the pid in `owner` may remove it.
#   stale    when owner's pid is not running, or is running but started after `start` (a recycled pid), or
#            when `owner` is missing and the directory is over 60 s old (a taker died between its mkdir and
#            its write). The next taker removes it inside ~/.local/state/mac-heavy.lock.reclaim (a mkdir mutex,
#            so two takers cannot both reclaim and one delete the other's fresh lock), and logs that to
#            ~/.local/state/mac-heavy.log.
#   wait     a taker WAITS, polling every 5 s, logged once, with no time limit by default. While it waits it
#            keeps ~/.local/state/mac-heavy.lock.waiting/<its pid> (key=value: project= label= start=), so a
#            supervisor can tell a job queued here from a wedged one and not charge the wait to its clock
#            (`waiting-under`).
#   signals  the holder forwards TERM/INT/HUP to its command, so killing the holder's pid ends the job.
# Light work (a one-page OCR check, a script) does not take it.
#
# USAGE
#   mac-heavy-lock.sh run [--label L] [--wait S] -- <cmd> [args…]   take it, run <cmd>, release it
#   mac-heavy-lock.sh status                                         holder and waiters (read-only)
#   mac-heavy-lock.sh waiting-under PID                              0 if a live waiter descends from PID
#
# ENV  MAC_HEAVY_LOCK     the lock directory (default above; the prove harness points it at a sandbox)
#      MAC_HEAVY_PROJECT  written to `owner` (default vision-ocr)
#      MAC_HEAVY_TOUCH    a path touched on every poll while waiting. test-lock.sh passes test.lock, whose age
#                         is its stale test, so a long wait here does not get the suite lock broken.
#      MAC_HEAVY_HELD=1   set for <cmd>; a nested take inside it runs straight through.
#      MAC_HEAVY_POLL     seconds between polls (default 5)
#
# EXIT: `run` propagates <cmd>'s status · 4 not taken within --wait · 2 usage. `status`: 0 free, 1 held.
set -uo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

LOCK="${MAC_HEAVY_LOCK:-$HOME/.local/state/mac-heavy.lock}"
BASE="$(dirname "$LOCK")"
RECLAIM="$LOCK.reclaim"
WAITDIR="$LOCK.waiting"
LOGF="$BASE/mac-heavy.log"
PROJECT="${MAC_HEAVY_PROJECT:-vision-ocr}"
POLL="${MAC_HEAVY_POLL:-5}"
WAITFILE="$WAITDIR/$$"

usage() { sed -n '/^# USAGE/,/^# EXIT/p' "$0" | sed 's/^# \{0,1\}//'; }
_now() { date +%s; }
_age() { local m; m="$(stat -f %m "$1" 2>/dev/null)"; case "$m" in ''|*[!0-9]*) echo 0 ;; *) echo $(( $(_now) - m )) ;; esac; }
_field() { sed -n "s/^$1=//p" "$LOCK/owner" 2>/dev/null | head -1; }
# _alive PID [EPOCH] — PID is running and, given EPOCH, started no later than it (else the pid was recycled).
_alive() {
  case "$1" in ''|*[!0-9]*) return 1 ;; esac
  local ls st
  ls="$(ps -o lstart= -p "$1" 2>/dev/null | tr -s ' ' | sed 's/ *$//')"
  [ -n "$ls" ] || return 1
  case "${2:-}" in ''|*[!0-9]*) return 0 ;; esac
  st="$(date -j -f '%a %b %d %T %Y' "$ls" +%s 2>/dev/null)"
  case "$st" in ''|*[!0-9]*) return 0 ;; esac   # unreadable start: trust the pid rather than break a live lock
  [ "$st" -le $(( $2 + 1 )) ]
}
_log() { { mkdir -p "$BASE"; printf '%s\t%s\t%s\n' "$(date '+%F %T')" "$PROJECT" "$*" >> "$LOGF"; } 2>/dev/null || true; }
_holder() { printf "'%s' (%s, pid %s, %ss)" "$(_field label)" "$(_field project)" "$(_field pid)" "$(_age "$LOCK")"; }

_stale() {
  [ -d "$LOCK" ] || return 1
  local p; p="$(_field pid)"
  if [ -z "$p" ]; then [ "$(_age "$LOCK")" -ge 60 ]; return; fi
  ! _alive "$p" "$(_field start)"
}

# 0 if this call removed a stale lock.
_reclaim() {
  if ! mkdir "$RECLAIM" 2>/dev/null; then
    # A reclaim takes milliseconds, so a mutex older than a minute belongs to a reclaimer that died in it.
    # Broken by RENAME, so of two takers that both see it old only one removes it (and not a fresh one).
    [ "$(_age "$RECLAIM")" -ge 60 ] && mv "$RECLAIM" "$RECLAIM.dead.$$" 2>/dev/null \
      && { rm -rf "$RECLAIM.dead.$$"; _log "removed an abandoned $RECLAIM"; }
    return 1
  fi
  local rc=1 who
  # Asked again INSIDE the mutex: another reclaimer may have removed the stale lock and a live taker made a
  # fresh one since this caller looked.
  if _stale; then
    who="$(_holder)"
    rm -rf "$LOCK"
    echo "mac-heavy-lock: holder $who is gone — reclaimed the lock." >&2
    _log "reclaimed from dead holder $who"
    rc=0
  fi
  rmdir "$RECLAIM" 2>/dev/null
  return "$rc"
}

acquire() {
  local label="$1" wait_s="$2" waited=0 announced=0
  mkdir -p "$BASE" 2>/dev/null
  while :; do
    if mkdir "$LOCK" 2>/dev/null; then
      TOOK=1
      printf 'pid=%s\nproject=%s\nlabel=%s\nstart=%s\nstarted=%s\n' \
        "$$" "$PROJECT" "$label" "$(_now)" "$(date '+%F %T')" > "$LOCK/owner.$$" && mv -f "$LOCK/owner.$$" "$LOCK/owner"
      rm -f "$WAITFILE" 2>/dev/null
      [ "$announced" = 1 ] && _log "'$label' took the lock after waiting ${waited}s"
      return 0
    fi
    if _stale; then _reclaim && continue; fi
    if [ "$announced" = 0 ]; then
      echo "mac-heavy-lock: '$label' waiting for the machine lock, held by $(_holder)…" >&2
      _log "'$label' (pid $$) waiting for $(_holder)"
      mkdir -p "$WAITDIR" 2>/dev/null
      printf 'project=%s\nlabel=%s\nstart=%s\n' "$PROJECT" "$label" "$(_now)" > "$WAITFILE" 2>/dev/null
      announced=1
    fi
    [ -n "${MAC_HEAVY_TOUCH:-}" ] && [ -e "$MAC_HEAVY_TOUCH" ] && touch "$MAC_HEAVY_TOUCH" 2>/dev/null
    if [ "$wait_s" -gt 0 ] && [ "$waited" -ge "$wait_s" ]; then rm -f "$WAITFILE"; return 4; fi
    sleep "$POLL"; waited=$(( waited + POLL ))
  done
}

TOOK=0; CHILD=""
release() {
  rm -f "$WAITFILE" 2>/dev/null
  local p; p="$(_field pid)"
  # Ours by record, or made by us and killed before `owner` was written (else it stalls takers for 60 s).
  if [ "$p" = "$$" ] || { [ "$TOOK" = 1 ] && [ -z "$p" ]; }; then rm -rf "$LOCK"; fi
  return 0
}
# Pass a signal to the command, so killing this holder's pid ends the job rather than orphaning it.
_forward() { [ -n "$CHILD" ] && kill -"$1" "$CHILD" 2>/dev/null; [ -n "$CHILD" ] || exit "$2"; }

# waiting-under ROOT: is any live waiter ROOT itself or one of its descendants? The daemon asks this of its
# gate and its session, so their clocks stop while they are queued here.
waiting_under() {
  local root="$1" f p hops
  case "$root" in ''|*[!0-9]*) return 2 ;; esac
  for f in "$WAITDIR"/*; do
    [ -f "$f" ] || continue
    p="${f##*/}"
    # A waiter killed before its trap ran: its file goes, and a recycled pid cannot stand in for it.
    _alive "$p" "$(sed -n 's/^start=//p' "$f" 2>/dev/null)" || { rm -f "$f" 2>/dev/null; continue; }
    hops=0
    # Bounded: one `ps` per hop, and a pid recycled between hops can close a loop (test-lock.sh's lesson).
    while [ -n "$p" ] && [ "$p" != 0 ] && [ "$p" != 1 ] && [ "$hops" -lt 32 ]; do
      [ "$p" = "$root" ] && return 0
      p="$(ps -p "$p" -o ppid= 2>/dev/null | tr -d ' ')"
      hops=$(( hops + 1 ))
    done
  done
  return 1
}

status() {
  local rc=0 f
  if [ -d "$LOCK" ]; then
    printf 'mac-heavy  HELD by %s%s\n' "$(_holder)" "$(_stale && echo ' — HOLDER IS GONE (the next taker reclaims it)')"
    rc=1
  else
    printf 'mac-heavy  free (%s)\n' "$LOCK"
  fi
  for f in "$WAITDIR"/*; do
    [ -f "$f" ] && _alive "${f##*/}" && printf 'waiting    pid %s, %s\n' "${f##*/}" "$(tr '\n' ' ' < "$f")"
  done
  return "$rc"
}

LABEL="${PROJECT}-$$"; WAIT=0
CMD="${1:-}"; shift || true
while [ $# -gt 0 ]; do
  case "$1" in
    --label) LABEL="${2:-}"; shift 2 ;;
    --wait)  WAIT="${2:-}";  shift 2 ;;
    --)      shift; break ;;
    *)       break ;;
  esac
done
case "$WAIT$POLL" in *[!0-9]*) echo "mac-heavy-lock: --wait and MAC_HEAVY_POLL must be whole seconds" >&2; exit 2 ;; esac

case "$CMD" in
  status) status; exit $? ;;
  waiting-under) waiting_under "${1:-}"; exit $? ;;
  run)
    [ $# -gt 0 ] || { echo "mac-heavy-lock: 'run' needs a command after --" >&2; exit 2; }
    [ "${MAC_HEAVY_HELD:-}" = 1 ] && exec "$@"
    trap 'release' EXIT
    trap '_forward TERM 143' TERM
    trap '_forward INT 130' INT
    trap '_forward HUP 129' HUP
    acquire "$LABEL" "$WAIT" || { echo "mac-heavy-lock: not taken within ${WAIT}s — NOT running '$1'." >&2; exit 4; }
    # In the background so a signal reaches the trap at once (bash defers traps behind a foreground child);
    # `<&0` keeps the caller's stdin, which a background job would otherwise lose to /dev/null.
    MAC_HEAVY_HELD=1 "$@" <&0 &
    CHILD=$!
    wait "$CHILD"; rc=$?
    # A trapped signal interrupts `wait`; wait again for the command's own status.
    while kill -0 "$CHILD" 2>/dev/null; do wait "$CHILD"; rc=$?; done
    exit "$rc"
    ;;
  ''|-h|--help|help) usage; exit 0 ;;
  *) echo "mac-heavy-lock: unknown command '$CMD'" >&2; usage >&2; exit 2 ;;
esac
