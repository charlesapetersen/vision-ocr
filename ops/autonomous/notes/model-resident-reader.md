# model-resident-reader

## 2026-10-16 — session 1 (Opus 5.5, medium)

Prototype, not shipped (`model-resident-reader.patch`, against db21f5d; the legs: `model-resident-reader-leg.sh`).
`read-model.py --serve` keeps one model loaded per reader slot on a Unix socket in `$TMPDIR`, named by slot and
a key of its command; `Recogniser.ResidentReader` connects or starts it. The server leaves after 60 s idle only
once it can take the slot's lock itself. Guard, cancel, time limit and the helper's SIGTERM kill it. Seven
suite checks covered reuse, cancel in the app and through the helper, the guard mid-reading and another model's
server being stopped; they passed in a partial run (94/95, the one failure a mistyped section filter).

Measured by running code (`MODEL-RESIDENT-2026-10-16.tsv`): one page read cold 15.0 s, loaded 10.4/9.8 s,
text identical. Ten pages at two readers: PaddleOCR-VL -6.9% over five pairs (-11.7 to -3.7%), Falcon-OCR
-3.8% over three (-7.8 to -0.2%), two server starts a leg. The table's 2.3-3.9 s start-up share does not turn
into batch time: with two readers the GPU is busy throughout, and a page's start-up (CPU: interpreter, imports)
overlapped the other slot's reading.

Closed by the item's prototype clause: under 10% with each reader. Rejected: shipping PaddleOCR-VL alone
(-6.9%, though reps 1-2 read -10.8%): for that, two long-lived processes holding 2.5-4 GB between pages and a
minute after a batch, and the review's open edges (a helper SIGKILLed mid-reading leaves its server reading
unguarded up to 540 s). The patch carries the review's fixes (stop the slot's own server at critical pressure,
SO_NOSIGPIPE, a request timeout) if this is reopened, for example on a Mac where one reader slot is the rule.
Measured on the way: `Process` children do not inherit the helper's lock descriptors.
