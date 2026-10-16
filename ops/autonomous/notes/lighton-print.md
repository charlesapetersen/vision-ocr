# lighton-print notes

## 2026-10-15 — session 1 (Opus 5.5, medium)

LightOnOCR-3-4B (hw-panel's 8-bit MLX build, the card's empty prompt, 2,048 px, 4,096 tokens) read the bake-off
sample's 67 pages through `bakeoff.sh --build lighton3`, whole and as crops as the others, under the 12 GB guard.
Scored by `score-bakeoff.py`, which reproduces OCR-BAKEOFF-2026-10-07's Falcon and Vision rows exactly.

- Missed words, LightOnOCR-3 against Falcon-OCR: old print 0.61% / 0.23%, newspapers 0.86% / 0.52%, modern
  1.20% / 0.63%. Worse on every class; added words about the same (newspapers 0.113 / 0.118).
- Speed, quiet machine (the job held the heavy lock throughout): 39 s a page whole, 103 s as crops (Falcon 12, 30).
- Memory: peak 7.9 GB, nothing killed or cut. It fits the guard but not ModelGuard's default 5 GB.
- The losses are skipped lines, spread over pages, not one artefact: s46, s43 (newspapers), s20 (modern, 9.6%),
  s09 (old, 10.9%: the figure's caption and the three lines under the figure are gone).

Answer: it does not beat Falcon-OCR on any class, so nothing is queued; it stays the handwriting reader only.
Instrument note: the first launch took the heavy lock per read and stalled behind an Archive Suite run; relaunched
as `mac-heavy-lock.sh run -- bakeoff.sh run`, which holds it once (the inner takes pass through).
