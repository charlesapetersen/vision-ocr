# model-two-readers notes

## 2026-10-16 — session 1 of round 1 (Opus 5.5, medium)

Built: `Recogniser.readerSlots` (2 from 16 GB where twice the reader's `memoryNeedGB` fits under half the
memory: Falcon-OCR and PaddleOCR-VL from 16 GB, LightOnOCR-3 from 32 GB, a lab reader by path never) and
`takeReaderSlot` (two lock files; a two-slot reading takes either, a one-slot reading takes both in order,
so nothing runs beside a reader that may not share).

Measured by running code (`MODEL-TWO-READERS-2026-10-16.tsv`, one evening, each leg alone under the heavy
lock, every page published in every leg). PaddleOCR-VL PASSES: one-reader mean 142.6 s, two-reader (committed
code) 101.9 s, -28.6%. Falcon-OCR FAILS the 15% bar: first pair 202.8 -> 172.3 s (-15.04%, within rounding
of the bar; rep 3's s02 took 171 s, no retry logged), second interleaved pair 181.9 -> 162.0 s (-11.0%);
pooled over four of each, 192.4 -> 167.1 s, -13.1%. The one-reader time moved by 21 s between pairs, the
two-reader time hardly at all (162-165 s apart from rep 3). Falcon's calls slow when two run (16.6 -> 24.1 s
a read, model-throughput), so the GPU, not the slot, is most of its limit (reasoned).

NEXT: the box stays open on Falcon's criterion only. Two readers are kept: faster for both readers, nothing
lost. Options for the next session: a third slot is ruled out by memory (3 x 3.9 GB); the remaining gain is
`model-resident-reader`'s start-up share (10-14% for Falcon), which this item blocks. Recommended: close this
item on PaddleOCR-VL's pass and Falcon's measured 11-19%, and let model-resident-reader carry Falcon's time
(this session did not change the DONE WHEN itself).

- The guard with two readers: the first build (no retry) let one of ten Falcon pages fall back to Vision when
  pressure turned critical with two readings running (new rep 2). Pressure and swap are machine-wide, so a
  reading that shared the memory and was stopped by either (or not started at critical pressure) is now read
  again alone, taking every slot; a stop for its own footprint over the cap is not retried. The 2 GB swap
  limit stays per reading. After that, no page fell back in four legs; Falcon rep 3 (182.6 s) was the slow
  one, likely a retry (reasoned: retries are not logged).
- Rejected: sizing slots by the memory setting (default 5 GB) rather than the readers' peaks; two of 5 GB
  leave no second slot even on this 18 GB Mac. Falcon's 7.8 of 8 GB on 16 GB is accepted because the retry
  catches pressure; 16 GB is reasoned, not measured on a 16 GB Mac.
- Known gap: an older app version running at once locks only the first file, so a new two-slot reading can
  run beside its reading (needs two versions at once; not handled).

## 2026-10-16 — session 2 of round 1 (Opus 5.5, medium)

Instrument: score-gate sees a batch's end only on its 20 s timer, so session 1's wall times (and this session's
`wall_s`) are rounded up to 162/182/202 s. Fixed: the gate now prints `seconds`, the time to the last outcome.
`end_s` (last PDF's mtime) is the measure below; session 1's "-28.6% / -11 to -15%" were on the rounded clock.

Built: waiting readings go longest page first (`ReaderTicket`, a flock-held file per waiter in
`$TMPDIR/visionocr-model-reader.queue`, ranked by the characters Vision read on the page). Timelines of the old
code showed the batch's 40-56 s pages starting last and running alone.

Measured by running code, same session, every page published, no fallback (`MODEL-TWO-READERS-2026-10-16.tsv`):
PaddleOCR-VL 101.0 -> 82.4 s, -18.4%, PASSES. Falcon-OCR 170.4 -> 148.2 s, -13.0% (unordered: 152.2, -10.7%),
FAILS 15%. The per-call log shows why: both slots busy from 2 s to 140 s, but a Falcon page read beside another
takes 1.5-1.6x as long, so two slots do ~1.13x one's work; perfect order would gain ~3% more at most (283 s of
shared reading over two slots = 141.5 s against 148.4 s). A third slot is ruled out by memory.

Not met, and this item cannot meet it by scheduling: Falcon's 15%. Recommended to the owner (RUN.md NEEDS OWNER):
accept -13% and tick, unblocking model-resident-reader, whose start-up share (10-14% for Falcon) is the next gain.
The item is marked `needs: owner` so no session spends another attempt on it. Rejected: lowering the bar here.
Reasoned, not fixed: size is a weak guide for handwriting (few Vision characters, long reading); LightOnOCR-3 has
one slot below 32 GB, so it does not apply there.
