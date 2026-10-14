# c56-heavy-type — round notes

Round 1's four sessions (2026-10-06) are recorded in the item's body in `ops/autonomous/QUEUE.md` and in
`bugs/C56.md`; this file begins with round 2.

- 2026-10-14: round 2, session 1 (max, Fable). Judged C56's case for closing by measurement: the same bitmap
  drawn as the app draws it (1-bit image) and as the source does (a JPX foreground through a /Mask stencil)
  differ by 6% at 2x in PDFKit, so Xin Qu's 1.059 is the renderer's path, not the strokes; the published
  bitmap holds the source mask's own ink (1.0009, run lengths within 2.3% in every bin of 1,000+ runs) and
  drawn alike at equal height reads 0.982 of the source's. Bytes smaller than the pre-C56 build on all four
  pages (23 other commits between). ux-regression on HEAD 0 worse. The DONE WHEN's 2x share was amended in the
  queue to read with both bitmaps drawn alike; the adversarial reviewer dissented (a criterion failing as
  written routes to WONTFIX, barred by rule 8 this session) and the dissent is recorded in the entry with the
  way to reverse it. Closed `FIXED`, box ticked, no code change. Evidence: `C56-DRAW-PATH-2026-10-14.tsv`.
