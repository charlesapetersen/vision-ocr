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

2026-10-14, bs-index-check (round 1, session 2). `next-item.sh` and `check-queue-coherence.sh` needed no change:
both read headings, and the index keeps them. The coherence check gains an index section: each `bugs/<TAG>.md`
whose first line differs from its index line is `INDEX-DISAGREE`, one with no index line `INDEX-MISSING`, a
tag with a file and two headings `INDEX-DUPLICATE`, a file not named for a tag `INDEX-BADNAME`; struck `~~`
headings match as in the resolver (review caught that and the last two). `prove-bugs-split.sh` [5], 9 more
checks (20 in all): both readers print the same over inline and split fixtures, a prerequisite is met from a
moved entry's index status, and the check goes red on a disagreeing fixture and stays green under a mutant
without the block. Real tree: both outputs byte-identical to before.
A simulated split of the whole real register (scratch dir; 197 files, index 238,664 B) read the same through
`--list`, `--list-open`, `C57`/`C24`/`T14`/`C41` and `next-item.sh`, and the new check reported one thing:
FOR bs-move, `R63` has TWO entries (BUGS.md lines ~23411 and ~23884, same defect recorded twice, second
heading without the `**failed**` bold). The resolver has only ever reached the first. bs-move must merge them
into one `bugs/R63.md` under the first heading, or give the second its own tag, before splitting.

2026-10-14, bs-move (round 1, session 2). R63's second record moved, verbatim, to the end of the first under a
`####` sub-heading (own commit; rejected retagging it R63.1, which keeps `bugs-entry.sh R63` blind to it). Then
197 entries moved to `bugs/`; BUGS.md 2,266,505 -> 238,574 B, each index line followed by one blank line. An awk
reconstruction (each index line and its blank line replaced by its file) is byte-identical to the old register.
Old vs new: all 197 `bugs-entry.sh <TAG>` outputs, `--list`, `--list-open`, `next-item.sh`,
`check-queue-coherence.sh` and `check-staleness.sh` identical; closed-heading count 194 on both. Rule 3 amended.
`check-staleness.sh` exits 1 on main before and after (OPEN-COUNT claims, CHECK-COUNT-REFERENCE): not this item.
