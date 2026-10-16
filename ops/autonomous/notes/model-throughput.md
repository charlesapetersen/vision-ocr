# model-throughput notes

## 2026-10-15 — session 1 of round 1 (Opus 5.5, medium)

Measured by running code: ten one-page files (five newspaper, five other) through score-gate with accurate mode
on, each leg alone under the heavy lock, a scratch helper logging every reader call. Figures in
`MODEL-THROUGHPUT-2026-10-15.tsv`; concurrency-6 legs run twice (the same leg differed by 5% (Falcon) and 13% (Paddle) between runs).

- Serial is slower. Concurrency 1 against 6, one reader: Falcon-OCR 221 s against 190/200 s, PaddleOCR-VL
  228 s against 152/134 s. Vision, compression and publishing for other files still overlap the reader, so
  reading several files at once keeps helping; do not make model batches serial.
- At concurrency 6 the one reader is the bottleneck: busy 188-195 s of Falcon's 190-200 s batch, 129-147 s of
  Paddle's 134-152 s, with helpers queued 356-645 s in total on the lock.
- Two readers at once (scratch: two lock files): Falcon 190/200 -> 150/164 s (-18 to -21%), Paddle 152/134 ->
  114/103 s (-23 to -25%). Each call slows (Falcon read 16.6 -> 24.1 s) but they overlap. The sum of two
  overlapping calls' peaks (an upper bound) was 7.2-7.6 GiB Falcon, 4.6 GiB Paddle; no page failed and the guard
  stopped none on this 18 GB Mac, though swap grew 0.84 GB over the first two-Falcon leg (the guard's limit is
  2 GB a call). Falcon's text moved by a few characters (45,015 -> 45,008 / 45,017), not checked which.
- Keeping the model loaded: at concurrency 6 with one reader, a call's time beyond the model's read
  (interpreter, imports, weight load, image preparation) is 2.3-2.8 s for Falcon (12-14% of reader time) and
  3.5-3.9 s for Paddle (26-27%); the weight load alone is 0.5 s and 1.4 s with the page cache warm. A resident
  reader would still prepare images, so that share is a ceiling on its gain, not an estimate (reasoned). After
  two readers the share is 10-14% and 21-23%.

Answer: two readers at once is the larger, simpler gain, and it depends on memory: two Falcon readers need about
8 GB beside Vision. That it suits Macs with 16 GB and up and not below is reasoned from the 18 GB run, not
measured on a smaller Mac. A resident reader adds at most ~10% (Falcon) and ~20% (Paddle) on top, at more cost
(a long-lived process, the guard, cancellation). Queued as `model-two-readers` and `model-resident-reader`.

Scratch harness kept for model-two-readers: `model-throughput-helper.patch` (the helper as measured: N lock
slots, per-call stats; applies to Sources/ at this commit) and `model-throughput-leg.sh` (one leg), both beside this file.
