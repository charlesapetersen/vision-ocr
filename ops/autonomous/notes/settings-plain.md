# settings-plain

2026-10-14 — round 1, session 1 (Codex gpt-6.1-sol, high).
Before: Accurate mode uses unexplained runtime/layout terms, hides the default when off, and timing
requires a click and times every ready reader. Worktree: /private/tmp/vo-20261014-203901-48598.
Checkpoint: reading the controls and download/timing lifecycle; before renders in progress under
/private/tmp/settings-plain.JVcWkj. No app changes yet. Next: plain copy, download-specific timing,
regression checks, off-screen renders, full suite/build and separate self-review/acceptance passes.
This item cites the owner's request, not a BUGS entry, so checkpoints and evidence live here.
(The session ran out of workspace credits after the rewrite and the red checks, uncommitted.)

2026-10-14 — round 1, session 2 (Claude Opus 5.5, medium). Adopted session 1's worktree; turned on the
`afterDownload` call its red checks were written against (7 red without it, measured).
Reviewer findings fixed: the automatic check now times Vision beside the new reader on its kinds of page,
since the table's "× Vision" divides by Vision from the same run (option rejected: the reader alone, as
the item says, which compares this Mac's reader with our Mac's Vision); the button's run replaces the
stored timing again and only automatic runs merge; one failed download no longer cancels the check of a
reader that completed; Stop with nothing running leaves no message.
Not changed, recorded: a batch can still start during a speed check, as it could beside the button (its
times would then read slow); turning Accurate mode off now also stops a running check.
Renders: /private/tmp/settings-plain.JVcWkj/{before,after3} via render.swift there (scratch, not kept).
Plain-reading checker, three passes. Flagged and fixed: jbig2/qpdf in the preview, "Not used here", the
default's wording, "Allow in choices" (now "Offer in Choose pages"), the speed-check sentence, the cut-off
"Photographs" preset (now "Photos"), "4× Vision", KB, ".ocr.pdf", memory differing by kind, "Uncertain
text" (now "Unsure words"); the megapixel refusal also named two retired labels. Left: the reader names
PaddleOCR-VL/Falcon-OCR (owner: keep names beside a plain description), the report folder path, "Photo
detail" beside "Photographed pages".
Automatic timing evidence: production DownloadRunner -> TimingRunner with a stand-in for the reading
itself (Tests, settings-plain section); the real TimingRun.run has its own section. Not clicked through
in a GUI (nothing may draw on the display); the app builds.
