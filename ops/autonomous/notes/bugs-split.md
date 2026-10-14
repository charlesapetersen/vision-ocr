# bugs-split — round notes

2026-10-14, bs-readers (round 1, session 1). `bugs-entry.sh` prints `bugs/<TAG>.md` in place of the body when
the index line's tag has a file beside the register; `--status`, `--list` and `--list-open` read the index. The
hook's rule-8 check reads `BUGS.md` and `bugs/`, and counts a WONTFIX heading as a close only if HEAD did not
already give that tag WONTFIX (index or file), so bs-move's moves of closed entries are not refused. The first
version piped `git show` into `grep -q` under pipefail and read every move as a close; the proof caught it.
`ops/autonomous/tests/prove-bugs-split.sh`, 11 checks, red under three mutants (resolver reading only `BUGS.md`,
hook reading only `BUGS.md`, hook reading only `bugs/`). After review: an empty or unreadable entry file exits 2,
and a body left under an index line whose file exists is reported on stderr. Added to the health gate as
`bugs-split-proof`. Real register: `--list`, `--list-open` and `C24`/`C57`/`T14` output unchanged (no `bugs/` yet).
For bs-index-check: `next-item.sh` and `check-queue-coherence.sh` read headings only, so the index alone
serves them; the new check is that each `bugs/<TAG>.md` first line equals its index line.
