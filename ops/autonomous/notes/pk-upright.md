# pk-upright — round notes

## 2026-10-15 — round 1, session 1 (Codex, gpt-6.1-sol, high)

Checkpoint: isolated worktree `/private/tmp/vo-pk-upright-20261015`, baseline 429ad66.
The nine named photos are pk03, pk04, pk07, pk19, pk21, pk27, pk28, pk29 and pk30.
Both model arrangements align only upright observations. Plan: turn only the model's
view and matching line coordinates upright, then carry text back onto the original
observations. The published image and line geometry must stay as they were.
Baseline production reproduction finished in `/private/tmp/pk-upright-20261015/`:
all nine freshly published PDFKit strings exactly match the earlier measurement's
outputs. The PDFKit render of pk19 is sideways, with the reported garbled text.
The new four-orientation production test failed 16 of 22 checks before the fix:
turned pages discard the stub reader's words and the reader sees turned pixels.
The image gate cannot render JPEG/HEIC inputs for pixel comparison (it says so);
the PDFKit before/after output renders will supply that comparison instead.

Checkpoint: the fix now turns only the align/regions reader's temporary image and
line frame, using the writer's existing transform. A strict majority of letters
and digits chooses the turn; original boxes, confidence, turn and strip IDs return
unchanged. Partial regression tests are compiling. Next: inspect their result,
publish all 31 photos with both readers, check raw readings against PDFKit output,
then full suite, ux-regression, self-review and the separate DONE WHEN pass.
The sandbox refused the heavy lock's process inspection, so locked runs use
escalation. No model APIs or paid runs.

Adversarial diff review (separate pass, before fixes): no defect found in the
pixel/box transform, original-metadata restoration, cancellation/fallback or
temporary-file cleanup. One test gap: the four source media boxes are identical
before rotation; invariant 5 calls for genuinely different source sizes. Give the
half-turned page a smaller media/crop box and assert it. The helper route and
mixed-orientation majority tests were also checked against their call paths.
Evidence correction: pk04's HEIC baseline is already visibly upright after the
production image wrapper honours its orientation; it belongs among the unchanged
controls, though the earlier table counted its stored sideways pixels among nine.

The original new regression passes 22/22 with the fix (partial run). Added majority
edge cases and helper coverage, and repaired the source-size fixture found in
review. That edit interrupted the preliminary full compile; it ran no checks and
is not a suite result. A fresh full run of the final inputs is queued. Rejected:
rotating the published page (changes the document's appearance) and merely
removing alignment's upright filter (wrong coordinates/order and still sideways
model pixels). Real-photo verification and the suite are waiting for the shared
heavy lock; there is no external blocker or owner decision.

Checkpoint (02:47): real-photo run acquired the lock. Falcon pk19: 11/13 -> 7/13
truth-band misses, 26 newly kept model tokens, all 20 PDFKit lines findable, exact
same PDFKit render and page box. Pk03 also keeps a model correction; pk04 is
unchanged. The saved pk19 model input was visually checked upright. Final suite
and serial UX regression are still queued. Running sessions: photo 2274, final
suite 15235, UX 88079; logs and `compare.py` are in the scratch evidence directory.

Checkpoint (02:50): Falcon has merged words on all eight actually turned pages;
pk04 remains unchanged. The four turned handwritten bands improve 47/56 -> 28/56
misses through the app. Print: pk21 improves 2 -> 1, pk30 worsens 1 -> 2; accepted
as the existing model alignment's reading tradeoff, now exposed on turned pages,
not a reason to suppress all model corrections there. All nine renders and boxes
are identical. Pk29's PDFKit line count rises 19 -> 20 (all findable); one new
compound token partly keeps Vision's digits and partly takes the model's word,
so a whole-token raw-text comparison counts 25 of 26 rather than 26 of 26.
Controls and PaddleOCR-VL remain in progress; no completion claim yet.

Checkpoint (03:13): Falcon finished all 31: all 23 upright controls exactly
unchanged in PDFKit text/render/box; print misses 21/774 unchanged, handwriting
49/84 -> 30/84. Paddle finished the affected pages: turned handwriting 47/56 ->
39/56. Its layout detector finds no region on pk19; pk28's model text fails the
existing anchor guard, so those keep Vision legitimately. Other turned pages keep
model corrections, including the region path. Raw-token diagnostic exceptions are
preserved line-end hyphen splits and partly corrected compound tokens (inspected).
Paddle controls, full suite and UX regression still pending.

Checkpoint (03:31): both readers finished all 31; all 23 upright controls per
reader exactly unchanged, all 62 renders/boxes identical, every PDFKit line
findable. Paddle total handwriting misses 63/84 -> 55/84, print 24/774 unchanged.
`PK-UPRIGHT-2026-10-15.tsv` holds the counts; private before/after PDFs, snapshots,
raw model inputs/readings and scripts are saved in
`$STATE/photo-sample/pk-upright-20261015/`. Photo session 2274 finished exit 0.
UX session 88079 now holds the lock (40 cases, serialized); final suite session
15235 waits behind it. No commit yet; queue box remains open pending those checks.

Verification instrument correction (03:46): the regression gate's supposedly
off leg was running Falcon-OCR. Measured `defaults read gate accurateMode = 1`
and all three saved readers Falcon; the command did not name the mode. Stopped
only this invalid measurement and its own model child. The regular leg now
explicitly passes `-accurateMode NO` (the accurate legs already pass YES). This
one-line tool fix is needed to verify this item; no checks or thresholds changed.
The interrupted run is not a regression result. A corrected serial run follows.

Checkpoint (03:58): full suite passed 2080/2080, no skips, including helper and
different-source-size coverage. Corrected UX regression is session 18123;
`ux-correct.log` is its log. Completion, commit and push still wait for that check.

## 2026-10-15 — round 1, session 2 (Opus 5.5, medium)

Adopted session 1's uncommitted worktree (`/private/tmp/vo-pk-upright-20261015`) by its diff; it stopped
while its corrected `ux-regression` run waited on the heavy lock, and that run never started. An
adversarial review found no defect (rotation checked pixel by pixel against `uprighted` for turns 1-3);
on its note the upright copy is now drawn grey for a grey page and without alpha (a quarter of the memory
on a grey page). A separate DONE WHEN check on the saved outputs, through PDFKit: PASS. The 8 truly turned
pages gain only words found in the model's reading (Falcon 100/100, Paddle 77/79, the two hyphen splits);
renders and boxes byte-identical on all 62 outputs; the 22 upright pages identical per reader; the model's
inputs seen upright. `ux-regression` not run: its rows are upright scans, where `modelPageTurn` is 0 and
the path is the old one; the `-accurateMode NO` fix to it stands on session 1's measured defaults.
