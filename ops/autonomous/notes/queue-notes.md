# queue-notes — round notes

2026-10-14: round 1, session 1 (opus, medium). Done in one session. `check-queue-coherence.sh` reports
`NOTES-ORPHAN <tag>` for a notes file whose tag is no queue item; its self-test went 15 → 17 checks, and three
mutants (the finding's tag dropped, the item lookup never matching, the notes block skipped) each turn it red.
`next-item.sh` output on the tree is byte-identical before and after. Rule 10, the resume prompt's STEP 4 and
`README.md` say where notes go; `.gitattributes` sets `merge=union` on `ops/autonomous/notes/*.md`.
