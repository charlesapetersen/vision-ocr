# Autonomous work queue

The ORDER in which an unattended session picks up work, in a form a script can read.
Resolved by `ops/autonomous/next-item.sh`; cross-checked against the register by
`ops/autonomous/check-queue-coherence.sh`.

**This file is not a tracker.** `BUGS.md` is the defect register and `TODO.md` is decided-but-undone
work, and they stay authoritative for *what* each item is, what was measured, and what a fix has to
satisfy. This file holds only the sequence, plus a cite back to the material that owns the content. An
item's `(origin: …)` / `(context: …)` cite is the thing to read before starting; the line here is a
pointer, never a specification.

**Why it exists at all.** Neither prose tracker is machine-readable as a queue — `TODO.md` encodes
status in `## <heading> — done <date>` suffixes and holds 10 checkbox lines in 45 KB; `BUGS.md` is 163
entries in ~480 KB. A daemon needs a deterministic answer to "is there work, is it blocked, or is
it drained", because those are three different owner actions. Duplicating state is a real cost, so it is
bounded to one line per item and policed by the coherence check — see that script's header.

## How to write an item

```
- [ ] **<tag>** — <one line of what to do>. (origin: BUGS.md C24)
- [ ] **<tag>** — <…> (blocked-on: <othertag>) — <why it must wait>
- [ ] **<tag>** — <…> [hold] needs: owner — <why only the owner can do it>
```

The tag is the first token after the checkbox and is what `(blocked-on: …)` matches, so keep it
distinctive and never reuse one. A missing prerequisite tag counts as UNMET, so a typo blocks the item
loudly rather than running work out of order. Tick the box in the **same commit** as the work, the way
`BUGS.md` and the `CLAUDE.md` status paragraph already move together.

⚠️ **`origin:` and `context:` are different claims, and mixing them breaks the resolver's contract.**

- **`(origin: BUGS.md <TAG>)`** means *this item IS that entry* — the entry is the specification, and the
  item is done when the entry closes. `check-queue-coherence.sh` therefore asserts that an open item's
  `origin:` entry is still OPEN, and a ticked one's is CLOSED.
- **`(context: …)`** means *that entry explains why this matters* and is **not** a status claim. Use it
  whenever the background is a CLOSED entry, which is the common case for standing work.

Getting this wrong is not a lint nit. `tools-compile` and `mutants` below originally cited their closed
provenance entries as `origin:`, and the coherence check caught it on its first real run. The consequence
would have been silent: the resume prompt tells a session to **rule out already-done first**, so it would
have opened those `FIXED` entries, concluded the work had shipped, and ticked live standing work off
unread. A cite that reads as a status claim when it is only a footnote is exactly how that happens.

## ⛔ Settled — do not re-open, do not "notice" these again

- **`R55` is `WONTFIX`** (owner, 2026-08-17). The measurement campaign was run and the owner closed it on
  the arithmetic: the gate's over-exclusion costs the sweep about 80 candidates and 0.7 GB against 1,164
  and ~10 GB, and loosening it would admit the hand-held photographs `D1` exists to keep out. The
  argument has been made and declined. Do not re-derive it, and do not file a follow-up that reaches the
  same question from another direction.
- **`C5`** (right-to-left text stored in visual order) and **`R9`** (picture-page JPEGs held in scratch)
  are `WONTFIX` with reasons in their entries. `R9`'s entry additionally *misdescribes the code* —
  following it literally would corrupt output.
- **`drawnLargestImage`'s `depth < 3` STAYS, and "make it `< 4` to match `largestImage`" is refused**
  (owner, 2026-08-18 — it was *decided* the other way on 2026-08-17 and retracted the next day on the
  code). The two numbers are the same reach in different frames: `largestImage` counts resource-dictionary
  levels from the page (`depth: 0` is the page, `< 4` refused), the drawn walk counts forms entered
  (`< 3` refuses a fourth). Both reach three nested forms; at four both are blind and both fall back.
  Raising it would CREATE a divergence, not close one. Do not re-derive this from the number mismatch —
  the `depth-cap` item carries the full reasoning and the check that pins it.

## The queue

<!-- SEEDED 2026-08-16 when the daemon was built, from CLAUDE.md's status paragraph, BUGS.md's headings,
     TODO.md and HANDOFF-2026-08-17.md. Every item below is a POINTER that was true at seeding time and
     has NOT been re-verified by running anything. The first thing a session does with an item is read its
     cited material and confirm the work is still open and still described correctly — this project's own
     rule is that an entry without evidence is a rumour, and a queue line is at best a rumour about an
     entry. Delete an item that turns out to be already done, and say so in the commit. -->

- [x] **C24b** — the remaining half of C24: the 45 pages that draw a *different* image than the shared
      `/Resources` dictionary holds took the shared plate's resolution. **DONE 2026-08-17** — the wiring
      landed and the gate ran. `rebuildDPI(of:)` applies the shipped policy to `drawnLargestImage`;
      **exactly 45 pages of 16,987 change resolution**, page-for-page the 45 the 2026-08-16 sweep named,
      sweep reproduced byte-identically twice, `dictRebuildDPI` equal to the pre-change record's
      `shippedRebuildDPI` on 48 of 48 rows. Retention against those pages' own embedded text is **+8 words
      of 3,025** over the 7 that have one (`AI 2027` p16 +11, p47 +13, `Batzell`'s two −4 each); bytes fall
      **25% / 81% / 3%** by document. `score-drawn-images` had to be repaired first — its
      `shippedRebuildDPI` column would have collapsed into a copy of the column it was compared against,
      a tool measuring itself. `score-routing`'s refused rows for `Batzell` and `AI 2027` came back, as
      predicted here, and the prediction was checked both ways rather than assumed. **`pageIsAnImage` was
      deliberately NOT wired** (2 pages would flip; it feeds D1's corpus gate — R55's territory), stated in
      the entry per CONTRIBUTING §4b. Not spent: a scoped `--only C24-rebuild` campaign — the three new
      mutants were put back by hand and watched red first. C24 is `FIXED`. At seeding, and still worth
      reading for the two refused repairs:
      MEASURED 2026-08-16 (then still open): `Flattener.drawnLargestImage` + `Tools/score-drawn-images.swift`
      report what a page draws; the 45 are **39 smaller and 6 wider**, and the "wider" six retire the
      observation the entry carried without a cause. The constant the entry wanted recalibrated faces
      **three** pages and gets two right — the one it gets wrong is `Batzell` p22, a 600 px figure sitting
      exactly on `minimumScanPixelWidth`'s own boundary value. Reviewed and corrected 2026-08-16: a check
      that could not fail (no fixture page reached the guard its own mutant edits), a bare form resolving
      names in the page's scope instead of its invoker's, a verdict column that shadowed `unreadable`, and
      the two walks disagreeing about depth — all fixed, sweep byte-identical, suite green.
      **The mutant campaign is DONE, 2026-08-17** — all five killed, recorded in
      `Tools/mutation-log.tsv`, and it cost ~45 min per verdict (2621-2719 s) rather than the ~40 estimated
      here. It also falsified `mutate.py`'s own startup estimate by **4.85x**, which is fixed and now
      self-tested; see the entry's `### The campaign` subsection. **A 2026-08-17 review of that commit found
      nine defects in it and they are fixed** in the follow-up: its "negative control" on the estimate was
      in-sample (out of sample the fix is still 4.22x low), its self-test coverage figure was reasoned rather
      than run (21 of 26 killed, not 12 of 14), `estimate_window`'s check could not fail, the free
      `--only nothing-matches-this` command ran a full baseline suite, and five files still published the
      suite's floor as an `exit 133` crash.
      **The blocker is retired, 2026-08-17.** `Batzell` p22 was rendered both ways by
      `Tools/score-rebuild-dpi.swift` (new; drives the shipped pipeline through
      `Flattener.rebuildDPIOverride`): **270 of its own 291 embedded words (92.8%)** at its own 70.6 DPI,
      **273 (93.8%)** at the 300 fallback, **274 (94.2%)** at the 369.6 it accidentally gets today — for 87%
      fewer published bytes. So `minimumScanPixelWidth` is right about all three pages it faces, needs no
      recalibration, and "rendering a page of type at 70 DPI is C9 again" was reasoned and is false.
      Note the trap: **counting characters, which this line asked for, reads 1,960–1,962 across every
      resolution from 70.6 to 369.6** — a 0.1% spread against retention's 1.4 points — and would have said
      "no difference" while being right by accident. (This line said a flat "1,961 at every resolution"
      until a 2026-08-17 review checked it against `REBUILD-DPI-2026-08-17.tsv`: three of those six rows
      are 1,960 or 1,962. Percentages here now carry their absolute counts, per CONTRIBUTING §3.)
      **What was left was ONE thing**: wire the drawn walk into `rebuildDPI` behind a corpus gate run,
      because it moves 45 pages. This line then said "expect `score-drawn-images`'s sweep unchanged and
      `score-routing`'s two refused rows to come back". **Half right, measured.** The verdict columns are
      unchanged to the row, but `policyMoves` is not and could not be: it compared production against the
      drawn walk, and once production *is* the drawn walk that column reads `same` on all 16,987 rows —
      the tool needed repairing before it could be the gate. The `score-routing` half is right.
      Read the entry's `C24b` and `C24's wiring` sections first, not this line.
      (origin: BUGS.md C24, FIXED)
- [ ] **C26** — a small line drawing is erased on the picture path, at the SHIPPED DEFAULT Photo
      detail setting. **[hold] needs: owner** — ⛔ **the measurement campaign is COMPLETE as of
      2026-08-19 (sub-steps 1, 2, 3, 3b and 4 all ✅ below) and what is left is the constant, which is
      not a session's to move.** R49/R50 state no growth-tolerance bar, so there is no standard a
      session could apply; the arithmetic, both signs of it, is in `NEEDS OWNER` in the run state and
      in the entry. The box stays `[ ]` because the register entry is still OPEN — the coherence check
      wants that — and `[hold]` because an unattended session offering itself this item would either
      re-derive a finished campaign or decide a threshold the owner has reserved. **Held 2026-08-19,
      after the sub-step (4) session; unhold it by deciding the bar.**
      Content loss, found by the owner on `1954 - Why.pdf` hours after `1.13.0`
      shipped. **Read the entry before anything else** — it carries the four-page rendering, the
      `score-threshold-loss` table, the mechanism and three named unmeasured questions.
      ✅ **The prediction is MEASURED and the mechanism is confirmed** (2026-08-17, in the entry):
      `score-mrc` at `MRC_BG=2` against `MRC_BG=1` shows `bgF` 8.0 and `fgF` 16.1 on the affected
      pages, a background layer that is 190 KB at Maximum stored as **1.8 KB** at Balanced, and
      PSNR 24.05 → 27.45. Photo detail = Maximum is a real workaround. Do not re-run that.
      ✅ **Sub-step 1 is DONE, 2026-08-18, and it changed the diagnosis.** `lost` — the column this
      line used to tell you to sweep — is `score-threshold-loss`'s *refused* luminance candidate,
      not the `paleDrawing(…).extent` the 5% bar reads. The tool now prints `extent`, `cover`,
      `cells` and `factor`, and on the two worst pages `extent` is **0.00000**: the guard's search
      finds nothing, so no value of the constant protects them. Sweep run and committed as
      `THRESHOLD-LOSS-2026-08-18.tsv` — 441 pages, 233 documents, 61 picture-route (2 protected,
      22 under the bar, 37 at zero), and the sub-bar cluster is led by `Doermann_1967` p10 at
      0.039, the show-through page R56 was refused for. **Do not re-run that sweep.**
      ⛔ **Do NOT tune `paleDrawingThreshold`** — not on this one document (the failure R55 and R56
      both record), and now also not on the sweep: 0.05 sits in a 4.9x gap above the next page down,
      the useful range below it is **one page wide** (0.045 protects `1976 - Regis McKenna Papers`
      p4 and nothing else new; below 0.039 admits `Doermann_1967` p10's show-through), and none of
      it reaches C26's own pages at 0.00000. **Retracted from this line**: "needs no new signal because `pageMarks`
      already finds these marks" — measured, `pageMarks`/`paleDrawing` do not find them.
      ✅ **Sub-step 2 is DONE, 2026-08-18, and it moved the defect to a different term.** The red
      line does land in `ink` rather than `pale` — that was the standing hypothesis and it is now
      measured. The drawings are **5,495 / 4,188 / 3,379 cells below their page's own Otsu** and
      `paleDrawing` is offered **8 / 350 / 0**, so no filter inside it is the answer. Being ink and
      outside the recognised words, they are cut out of the stencil by `textRegionMask` and left in
      the background — and `pageIsAllText()`'s **first** term, `inkOutsideText`, reads
      **0.0493 / 0.0540 / 0.0660 against a bar of 0.08**: it sees them and passes them.
      **Do not re-run this** — `score-threshold-loss --dump` and `score-text-route` both carry it,
      and the entry's "The drawings are INK" section has the tables.
      ✅ **Sub-step 3's per-page price is DONE, 2026-08-18, and 0.045 is affordable on these three
      pages** — ⛔ **but read `2.99x` here as THIS DOCUMENT ONLY: over the corpus's 16 moved pages it
      is `4.54x` and 185,353 B/page, measured 2026-08-19, and these three are ranks 1, 3 and 4 of 16
      by cost. See the (2)/(3) block below.** `Flattener.textPageInkOutsideThresholdOverride` (nil in the app; substitutes the
      guard's *comparand*, not its verdict, so R56's pale term keeps participating) plus `INKBAR` on
      `Tools/score-text-route.swift`: over all ten pages, the three are refused the shrink,
      `65,477 B -> 195,785 B`, **+130,308 B, 43,436 B/page, 2.99x on those three and 1.76x across
      the document's five picture-route pages** — the other five are already 1-bit and pay nothing.
      The stencil is byte-identical at both bars so all of it is tone layers, and **two picture-route
      pages read `same` with real bytes** (p2 at `inkOut` 0.1072, p10 at 0.9735), which is the seam's
      negative control. `inkOut` reproduced digit for digit through a second code path. Two mutants
      added (**96** in the catalogue) and both **watched failing** against mutated copies of
      `Sources/` — 12 checks, pristine 12/12, fails 3 and 2; `override-ignored` is killed by the new
      checks **and by nothing else in the suite**, and neither mutant has a `mutation-log.tsv` row.
      The term that fires is also on a fixture now — `makeScannedPDF(figure:)`, `inkOut` 0.0551 —
      though **not** the erasure itself. **Do not re-run any of that.**
      ✅ **Sub-step 3b — the corpus population — IS DONE, 2026-08-19. Do not re-derive it; the
      answer and the retraction it forced are in the (2)/(3) block below.** For the record of what it
      cost: the sweep took **105.6 min** for 233 documents / 2,129 sampled pages, so the estimate that
      mattered was the low end. ⚠️ **"3-4 hours, and read it as a FLOOR" was RETRACTED on
      2026-08-19 before the run, and the run confirmed the retraction** — three documents timed
      through the driver read 3.83 / 0.54 / 0.66 s a page and the honest range was called "tens of
      minutes to about three hours"; 105.6 min landed inside it. The two traps that shaped the driver
      are still true of the tool and still worth knowing: **`score-text-route` takes ONE pdf and
      treats later arguments as page numbers**, so a glob silently measures document 1 and prints a
      summary that reads like a corpus run; and **it samples up to 12 pages a document, not 2** —
      measured, 150 of the 233 hit that cap, so the sweep covered 2,129 of the corpus's 16,987 pages
      (12.5%), which is why *rates* from it extrapolate and *counts* do not.
      ✅ **SIZED, owner 2026-08-18: run it DETACHED ACROSS SESSIONS, the `C24b` mutant-campaign
      pattern.** It may not fit one session, and that is arithmetic rather than caution: 2.7 h at the
      worst measured rate against a `VISIONOCR_MAXRUN` backstop of 9000 s (2.5 h), so a session that
      tries to see it through can be killed mid-sweep. The resumability is what makes that safe. The shape that works, and the one `mutate.py`'s campaign
      already proved on 2026-08-17:
      ✅ **(1) IS DONE, 2026-08-19: `Tools/sweep-ink-bar.py`.** Resumable per document (rows are
      buffered and appended only when a document finishes, so "has a row" means "is done"); every
      document gets a row including the ones that measure nothing, or a resume retries them for ever;
      the tool's exits 2 and 3 and a drifted 13-column header ABORT rather than being recorded as 233
      identical failures; `--report` reads `verdict` against `barVerdict`, because `barVerdict` alone
      says `picture` on all five priced pages of `1954 - Why` including the two the bar does not move.
      71 `--self-test` checks (hook-enforced), 42 mutants watched failing, and it reproduces the
      entry's 65,477 -> 195,785 B digit for digit through a second process. One of the mutants found a
      case that could not fail — two cases generated from `sorted(CONFIG_EXITS)` *vanished* when that
      constant was emptied instead of failing. It deliberately does NOT take `test-lock.sh`: the lock
      is about two `tests` binaries sharing one plist keyed by process name, and a 3-4 hour hold would
      block every commit hook in the window.
      ✅ **(2) AND (3) ARE DONE, 2026-08-19. THE SWEEP RAN AND ITS ANALYSIS IS IN THE ENTRY.** It ran
      04:26 → 06:12, **105.6 min, `ok=233`, no failures and no resume needed**, and its result is
      committed as **`INKBAR-2026-08-19.tsv`** at the repo root beside `THRESHOLD-LOSS-2026-08-18.tsv`
      — 2,129 measured page rows. ⛔ **Do NOT re-run it, and do not re-derive the population.** The
      answer, with the arithmetic in `BUGS.md` C26 §"Sub-step 3b, the population":
      **17 pages in `[0.045, 0.08)`, 16 of which flip** `all-text` → `picture` (the seventeenth is a
      rounding boundary at 0.0450 and is `same`); **0.75%** of sampled pages, **18.0%** of the 89
      shrunk today, **10 documents of 233**; **838,569 → 3,804,222 B, +2,965,653 B, `4.54x`,
      185,353 B/page**; **+8.19%** of layered bytes over the 181 pages that reach layering; per
      document, over that document's own *priced* pages rather than its page count, **1.21x–3.60x**;
      and at corpus scale **~21 pages of 16,987 and ~4.0 MB, `+0.55%`** of R50's 721 MB gate.
      ⛔ **That last figure needs the STRATIFIED estimate and the obvious one is 6x high** — the sweep
      samples up to 12 pages a document whatever its length, and a page in a fully-sampled short
      document is **4.8x** likelier to move than one in a long document, which hold 98% of the corpus.
      "~130 pages, ~+24 MB, ~+3%" is **RETRACTED** in the entry. 8 of the 16 moved pages need no
      estimate at all: 86 documents were sampled completely.
      ⚠️ Read the entry's table's three counts as three things — `sampled` rows, `priced` rows (the
      ones carrying bytes), `moved` rows — and the factor divides by `priced`. The first draft printed
      `priced` under a `sampled` heading; the entry says so.
      ⛔ **AND IT RETRACTED THE ENTRY'S OWN `2.99x` AS A CORPUS FIGURE** — `1954 - Why`'s three pages
      are ranks 1, 3 and 4 of the 16 by cost, so the found document was the cheapest end of the band.
      Corrected in `BUGS.md` (three places), the file header and `CLAUDE.md`.
      ✅ **(4) IS DONE, 2026-08-19, AND IT CHANGED WHAT C26 IS.** The other 13 moved pages were
      rendered at both bars — `INKDUMP=<dir>` on `Tools/score-text-route.swift`, which writes both
      tone-layer pairs out of the same `mrcLayers` call the byte columns come from; the stencil is
      byte-identical at both bars, so the two backgrounds are the entire difference. ⛔ **Do not
      re-run it**; the per-page table is in `BUGS.md` C26 §"Sub-step 4, the benefit".
      **11 of the 13 lose something; 8 lose content outright — 7 whole lines of prose or table data, 1 a hand-drawn mark** —
      `Xin Qu et al_2018` p20 loses thirteen values out of a Pearson correlation matrix,
      `_1973_Committee Against Racism_` p4 seven lines of prose, `Broadhead - 1994` p6/p8/p9 three,
      one and three. Those are words Vision did not box, cut from the stencil by `textRegionMask` and
      destroyed at 1/8. ⛔ **So C26 is an invariant-1 defect, not the fidelity complaint it was opened
      as** — only `Riesman - 1954` p16 (a hand-drawn bracket broken into blobs) reproduces the
      founding failure mode. ⛔ **And the dearest page of the 16 buys NOTHING**: `RIESMAN_1942` p10,
      +702,280 B and 6.47x, whose only non-stencil ink is a pale scanner-edge strip; with
      `Riesman - 1954` p18 that is **32.4% of the band's byte cost on pages a reader cannot tell
      apart**, which cuts against a blanket bar.
      ⚠️ **Two verdicts read off whole-page difference maps were WRONG** and were overturned by 1:1
      crops plus an ink-outside-the-stencil map: `-auto-level` normalises each page on its own and
      amplifies the harmless `fillHoles` residue into what reads as legible text. If you render any of
      these pages again, settle legibility on a 1:1 crop and nothing else.
      The 13 in aggregate are **773,092 -> 3,608,437 B, +2,835,345, 4.67x, 218,103 B/page**, and all
      13 rows reproduced the sweep's `inkOut`/`layered`/`layeredAtBar` **identically**, compared
      programmatically rather than by eye.
      ⛔ **WHAT REMAINS ON C26 IS THE CONSTANT, AND IT IS NOT A SESSION'S TO MOVE** — see the block
      below. The measurement campaign is complete: population, price and benefit are all in the entry.
      ⛔ **THE CONSTANT ITSELF IS THE OWNER'S CALL, and it is in `NEEDS OWNER` as of 2026-08-19.**
      R55 is the precedent: the campaign runs, the owner closes it on the arithmetic. R49/R50 state
      **no** growth-tolerance bar (read 2026-08-19), so there is no standard a session could apply;
      what R50 was accepted on was "not one grew", and 0.045 grows ten documents.
      `Flattener.textPageInkOutsideThresholdOverride` stays `nil` in the app.
      ⚠️ **The release gate cannot see this defect class** — `score-gate.swift`'s own source says
      so, and it passed this exact document. Do not accept a green gate as evidence of a fix here;
      the instruments for this are `score-threshold-loss.swift` and `score-text-route.swift`'s
      `INKDUMP`, plus rendered before-and-after pages.
      (origin: BUGS.md C26)
- [ ] **C27** — spot colour is discarded because `pictureSaturationThreshold` is a bar on the page's
      MEAN saturation: the corpus's deliberately chosen two-ink fixture keeps its red on 1 page of 10.
      Fidelity, not content loss — no word or mark is lost — but the copy misrepresents how the
      document was printed, and inconsistently within itself. Read the entry; it has the per-page
      red-pixel measurements and the reason the mean cannot answer this question.
      ⚠️ **C26's sweep RAN on 2026-08-18 and it does NOT size this population** — the shared-sweep
      plan on this line was wrong, for the reason the entry itself gives: `sat` is a mean, so a page
      at 0.045 may be two-ink or uniformly tinted and no bar on a mean separates them. What the
      sweep gives is a bound and a candidate list: **13 pages of 441 sit in 0.03–0.06**, against 13
      that clear 0.06. `1954 - Why` p4 and p7 are two of the 13 in the band; the
      other eleven have never been looked at and are listed in the entry. **Do not re-run the
      sweep.** Sizing this population needs a per-page **saturated-pixel fraction** — what the
      owner's own C27 measurement used (`in red%`) — and no tool in this repo prints it over the
      corpus. That column, added to `score-threshold-loss` or beside it, is sub-step 1 now.
      ✅ One thing the sweep did settle, in this entry's favour: across the 0.06 bar the distribution
      is a **continuum**, 0.057 then 0.061, a gap of 0.004 — so no value of the constant separates
      the populations, which is the "statistic not number" claim with a number behind it for the
      first time. C26's 0.05, by contrast, sits in a 4.9x gap, so the two entries are no longer the
      same case and the "two constants, same shape" line is retracted in both.
      ⛔ **Do not raise `pictureSaturationThreshold`.** It gates the ROUTE, so a lower bar sends more
      text pages down the picture path and costs bytes on every one — the trade R49 and R50 were
      about. The entry argues the statistic is wrong rather than the number: a page with 3% of its
      area at 0.8 saturation is not a page with a uniform 0.03 cast, and a mean cannot separate them.
      (origin: BUGS.md C27)
- [ ] **depth-cap** — `Flattener.drawnLargestImage`'s `case "Form"` branch caps recursion at `depth < 3`
      while `largestImage` caps at `< 4`, and **the stated reason for the mismatch expired when `c17b3f3`
      made the drawn walk production**. That comment says so itself: the symmetry existed so the
      drawn-versus-dictionary sweep isolated one variable, and *"if this is ever wired into `rebuildDPI`,
      the cap becomes a question about pages rather than about agreement, and wants re-measuring then"*.
      The wiring landed and revisited neither the cap nor the comment.
      **Not a wrong answer on anything measured**: that same comment records `< 4` and `< 3` producing
      byte-identical sweeps over all 16,987 corpus pages, so nothing here nests that deep.
      ⛔ **THE 2026-08-17 DECISION — "set the cap to `< 4`" — IS RETRACTED, owner 2026-08-18, because its
      premise is wrong.** It rested on a latent divergence: *"`.unreadable` falls back to `largestImage`, so
      a page nesting images four levels deep would get a different answer depending on which path it
      took."* Read against the code, **there is no such divergence — the two caps are different NUMBERS
      for the SAME REACH**, because they count in different frames:
      `largestImage` walks resource *dictionaries* and starts at the PAGE's own at `walk(resources, depth: 0)`,
      refusing `depth 4` — so it reaches images inside **3 nested forms**. `drawnLargestImage` counts *forms
      entered*: at `s.depth 0` (page content) it may enter, `s.depth += 1` before scanning, and
      `guard s.depth < 3` blocks entering a fourth — so it also reaches **3 nested forms**. At four levels
      BOTH are blind and both degrade to the fallback, which is the same answer, not a different one.
      So `< 4` here would let the drawn walk enter a fourth form and see images `largestImage` cannot —
      **creating** the divergence the change was meant to remove. And the verification that decision
      prescribed cannot detect either outcome: `< 4` vs `< 3` was already measured byte-identical, so the
      corpus sweep is guaranteed to pass while proving nothing about the only case at issue.
      ⚠️ Confidence, stated plainly: verified by READING the control flow, not by executing it. The check
      below is what turns it into a measured claim, which is the point of adding it.
      ✅ **The decided fix, owner 2026-08-18: KEEP `< 3`, rewrite the comment, and add a check that PINS
      THE TWO WALKS TO THE SAME REACH.** The comment must state the frame-of-reference difference — that is
      what makes the two numbers legible and stops a third reader "noticing" the mismatch — and drop the
      instrument-symmetry justification that expired when `c17b3f3` made the walk production; the honest
      production reason is that three levels is what shipped, and a scan nested deeper returns nil and takes
      `fallbackRebuildDPI` exactly as the dictionary walk did. The check needs a fixture nesting forms
      **three and four** deep and asserts both walks agree at both depths: found at three, neither at four.
      **`A1.3` is the precedent and the reason this is a check rather than a comment** — `Tests/main.swift`
      already carries *"both outline walks truncate at the same depth"* because that mirror-walk pair
      truncated at different depths for real. Equal reach recorded only in prose is what let this be
      re-litigated into a wrong decision once already. One commit, one suite run, and the item retires
      instead of riding along. (context: BUGS.md C24 — CLOSED, and `c17b3f3` is the wiring; the entry is why
      this matters, not the work itself)
- [x] **stale-docs** — reconcile the status claims that have gone stale behind the work. DONE 2026-08-16:
      HANDOFF.md's "four entries are open" (naming R54-R57, all closed) became the one that is; the suite
      figure was corrected to a MEASURED 1,127 in HANDOFF.md, TECHNICAL.md and ARCHITECTURE.md; TODO.md's
      was dated rather than updated, so it cannot go stale again. check-staleness.sh gained two exclusions
      so it stops flagging correct historical writing. At seeding:
      `HANDOFF.md` said "Four entries are open" against an actual one and still described R56/R57 as open;
      the suite's check count was asserted as 836 (`HANDOFF.md`), 880 (`TECHNICAL.md`) and 1,046
      (`TODO.md`) against an actual 1,127. Run `ops/autonomous/check-staleness.sh` for the current list,
      and fix the documents rather than the check. (origin: TODO.md, and CLAUDE.md's own confession that
      its status paragraph "read 'nothing open' for a day after four entries were opened")
- [ ] **tools-compile** — run `Tools/check-tools-compile.sh` over *every* tool, not just the staged ones,
      and fix or delete what does not build. It is a standing gate that today only runs on the
      files a commit happens to touch: `score-text-route` had never compiled in any commit, and an
      annotation change silently broke `score-skew` and `score-reading-order` eleven days later.
      ⚠️ **RUN IT DETACHED AND POLL — this line said "~26 s" and that is a quiet-machine figure.** Measured
      2026-08-17 ~05:00: killed at the **120 s** foreground tool ceiling with no output at all, which a
      session cannot tell apart from a hang. It is one of the five gates in this repo that now need the
      detached-plus-poll shape; `ops/autonomous/resume-prompt.txt` §STEP 3 lists all five with their costs.
      Quoting a duration here again would just re-create the trap: every duration in this repo has turned
      out to be a reading of the machine's load.
      (context: BUGS.md C25 and T16 — both CLOSED; they are why this gate matters, not the work itself)
- [ ] **mutants** — work the survivors in `Tools/mutation-log.tsv`. A surviving mutant is either a gap in
      the checks or a value nothing depends on, and `BUGS.md` T5 records how to tell those apart. Run it
      scoped (`python3 Tools/mutate.py --only <substring>`), never the full catalogue — that is ~65 hours
      at the C24b campaign's measured ~45 min per mutant over the whole catalogue, whose size is
      `python3 Tools/mutate.py --list | tail -1` and not a number written here — this line said 89 while
      the tool printed 91, and C24's wiring made it 94. Not the ~55 hours it claimed off a 39m30s sample
      nor the ~70 minutes before that; read the estimate the tool prints at startup instead, and note it
      was 4.22x low the one time anyone checked it out of sample —
      and never
      while `Sources/` is being edited. The work item is the live survivor list in
      `Tools/mutation-log.tsv`. (context: BUGS.md T5 — CLOSED; it records how to tell a real gap from a
      value nothing depends on)
- [ ] **fault-inject** — run `Tools/fault-inject.sh` over all its cases and confirm each sabotage is still
      refused by the real build step. It builds into a scratch copy of the tree, so it is safe unattended.
      (origin: Tools/fault-inject.sh)
- [ ] **A1.3** — one live bullet of that finding's four; the other three are struck through in place
      (`R81`, `R83`). What is left: `observations(fromJSONLines:)` (`:161`) and `observations(fromJSONAt:)`
      (`:181`) have **no callers** since recognition came in-process, and they are divergent siblings —
      one refuses an undecodable line and an empty result, the other refuses neither. Dead code that
      would mislead the next reuse, which is the harm the entry names. Verified still unstruck
      2026-08-17. The entry's own title calls it "smaller, real, low value", so it is a delete-or-reconcile
      decision and not a campaign. (origin: REVIEW-2026-08-14.md A1.3)
- [ ] **A1.4** — the outstanding finding in review area 1. Read the entry before assuming it is still
      live: findings that graduated into `BUGS.md` are struck through in place there.
      (origin: REVIEW-2026-08-14.md A1.4)
- [ ] **A13.4** — the remainder of A13.4. Same caution as A1.4 about what has already graduated.
      (origin: REVIEW-2026-08-14.md A13.4)
- [ ] **A3.5** — observed but never triaged. Triage it: either it becomes a `BUGS.md` entry with
      measurements, or it is closed in place with the reason. (origin: REVIEW-2026-08-14.md A3.5)
- [ ] **A10.6** — the residue after its two real defects were fixed in `BUGS.md` R80: the
      **2/27-effective preset check** and the inert-control notes still stand. Read the entry before
      planning anything — the fixed half is struck through in place and the standing half is not.
      Verified still unstruck 2026-08-17. (origin: REVIEW-2026-08-14.md A10.6)
- [ ] **A11.8** — the invariant coverage table, and what its 2026-08-15 re-read left open. **Invariant 2's
      gap is CLOSED** (`BUGS.md` T10 made A11.1's check bite; `publishVerified` is driven by two checks and
      a mutant), and invariant 3's (c) and (d) gained real instruments (`score-run-width` in R81,
      `score-line-separation` in R82). What is still open is **invariant 1 — "never lose content silently"
      — at unit level only**, and the re-read makes it *harder*, not merely uncovered: both of
      `makeSearchablePDF`'s refusal messages sit downstream of guards that fire first, so a helper
      returning a short dictionary is refused by `HelperFailure.incomplete` and then falls back in-process,
      and `missingPages`' report may not be reachable at all.
      ⚠️ **The entry says explicitly that "add a test" is the WRONG next step until reachability is
      answered.** Answer that first. Invariant 5 also stays unenforced outside where it is asserted (A11.4).
      Verified still unstruck 2026-08-17. (origin: REVIEW-2026-08-14.md A11.8)
- [ ] **annot-r3** — the third adversarial review round on the annotation-preservation feature. Rounds one
      and two are recorded; this is the round that has not been run.
      (origin: TODO.md §"Preserving annotations through re-OCR")
- [ ] **zotero-2** — the Zotero library sweep, steps 2-4. ⚠️ Step 1 wants re-running first; the survey it
      produced is dated. Reads a Zotero library, so copy `zotero.sqlite` before querying it — Zotero holds
      a lock on it. (origin: TODO.md §"2. The Zotero library sweep")
- [x] **lock-report** — DONE 2026-08-19. `status` classifies the `pgrep -x tests` set by ancestry within that
      set, so the suite's own probe children stop reading as extra suites:
      `suite RUNNING — pid(s) 90955 90956` becomes
      `suite RUNNING — 1 suite (pid 90955), plus 1 probe child (pid 90956)`, while two UNRELATED
      `tests` processes now read `⚠️ 2 SUITES AT ONCE (pids …) — concurrent suites corrupt ALL of them`.
      Suppressing the children is only safe if that reading gets louder, so it is asserted as hard as the
      quiet one.
      **Point 2 below was already fixed** — in `df3ab6a`, and pinned by NOTHING; writing the missing check
      found a THIRD defect of the same shape, which the fix for point 2 had introduced: the replacement
      notice said *"reclaimed from a dead holder"* after an aged-out reclaim of a **live** holder too
      (measured over a real helper: `has held the lock 19885779s (>= 60s) — breaking it.` then
      `reclaimed from a dead holder`). ⚠️ And the adversarial review of THAT fix found a FOURTH: its
      replacement, *"just reclaimed (see the line above)"*, fired on the yield-to-an-out-of-band-suite path,
      where nothing was reclaimed and there is no line above. All four were one defect — `acquire` re-derived
      the reason from a lock directory `_try_acquire` had already deleted — so the reason is recorded by the
      branch that knows it now, and [13] is one assertion per reason plus the inverse row (CONTRIBUTING 4d)
      rather than a fifth patch.
      Gate: `prove-test-lock.sh` **43 → 71 checks, 0 failed, 0 skipped**, ~45 s, plus `prove-status.sh` 39/0.
      The review found **seven more surviving mutants** on top of the author's nine — including one that turned
      the two-suite alarm back into `1 suite plus a probe child` — because [12] stubs `pgrep` but uses the real
      `ps`, and the harness cannot CHOOSE pids: exact-vs-substring set membership, an ancestry cycle and a set
      with no parentless member are all invisible to it. `ps` is interposed on the same BASH_ENV seam now
      ([12b]), the one-pgrep decision is pinned ([12c]), and **the campaign is committed rather than described**
      — `ops/autonomous/tests/mutate-test-lock.sh` + `MUTANTS-test-lock-2026-08-19.tsv`, the precedent being
      `Tools/mutation-log.tsv`. It runs no suite and no build, so the whole catalogue is minutes.
      Sibling sweep, by grep: **three** other `pgrep -x tests` sites (`vision-ocr-autonomous.sh:999`,
      `status-digest.sh:289`, `run-state-lib.sh:75`) all use it as a boolean, which is correct — a probe child
      only exists under a suite — so this had exactly one site. ⚠️ That sentence said "five, starting with
      `daemon.sh`"; `daemon.sh` has no such call at all. The two consumers of `status`'s text match only
      `^lock` / `^suite  *RUNNING`. Written up in `README.md` under D7's closing note. Original text follows.
      — the two REPORTING defects in `ops/autonomous/test-lock.sh`. Both were measured
      2026-08-17 and neither is a safety defect: the mutual-exclusion belt answers correctly in both cases,
      so what is wrong is only what the owner and the next session are *told*. Queued rather than fixed on
      the day, on the owner's decision, because that file is the only thing standing between this run and two
      concurrent suites and a campaign was mid-flight on it.
      1. **`status` counts the suite's own child as a second suite.** `test-lock.sh status` printed
         `suite RUNNING — pid(s) 1536 98565`; the second pid is `build/tests --probe-hostile-page …`, which
         the suite forks *of itself* and whose process name is also `tests`, so `pgrep -x tests` matches it.
         It changes every few seconds as probes come and go, which makes it look like something respawning.
         Two pids is the one reading CLAUDE.md tells a session to treat as corruption, so it costs a session
         the time to rule that out **every time** — and it teaches the reader to discount a two-pid reading,
         which is the reading that would matter if two suites ever really did run.
         Fix: report only pids whose parent is not itself a `tests` process (or match the full command line
         and exclude `--probe-`), and have `status` say "1 suite (+1 probe child)" rather than listing raw
         pids. ⛔ Keep `pgrep -x`, never `-f` — CLAUDE.md's trap, and four loops once waited on each other.
      2. **The stale-lock reclaim prints a phantom holder.** After a commit attempt was killed mid-hook the
         next acquire logged `test-lock: '' holds the suite lock (pid ) — waiting up to 1800s…` — empty
         label, empty pid — then acquired immediately and ran fine. The behaviour is right and only the
         message is wrong, but that message is what a session reads when deciding whether to wait, and
         "waiting up to 1800s" on a lock nobody holds is the exact shape of the four loops above.
      ⚠️ Run `ops/autonomous/tests/prove-test-lock.sh` green BEFORE and AFTER — it was 42/0/1 on 2026-08-17,
      the skip being its real-detector arm, which correctly skips while any suite is running.
      (⚠️ It read **43/0/0** before this work on 2026-08-19, not 42/0/1: nothing named `tests` was running,
      so the arm that skips on a busy machine ran and passed. Both figures are the same harness on two
      machine states, which is what that arm is for. It is **58/0/0** now.)
      (origin: README.md §Defects D7's closing note; both entries began in RUN.md's NEEDS OWNER)
- [ ] **tsv-header-drift** — the sibling sweep from C26's 2026-08-18 instrument commit, both halves
      measured by grep on that day and neither empty. CONTRIBUTING §5 asks a tool that prints a TSV
      for "one `row(...)` printer over one `columns` array, with the width asserted", because
      counting tab escapes by eye has put the wrong field count under a header **three times** —
      T14's SKIP row, T15's `score-mrc` and T18's two — all three FIXED, cited as precedent rather
      than as work to redo. CONTRIBUTING §5 names the middle one by its review tag, which resolves in
      `REVIEW-2026-08-14.md` and not in the register; T15 is the register's name for it.
      1. **Three tools still build the header separately from the rows:**
         `Tools/score-picture-codec.swift`, `Tools/score-reading-order.swift` (**two** headers, lines
         145 and 238 — and its `let columns` at 258 is a local about text bands, not a TSV array, so
         a reader grepping for the good pattern gets a false positive) and `Tools/score-skew.swift`.
         `score-threshold-loss.swift` is the worked example: one `columns` array, one `row(…)` that
         returns nil on a width mismatch, and three self-test checks — two of which were watched
         failing against a copy with the width test removed.
      2. **Four tools exit 0 having measured nothing:** `Tools/pdf-embedded-text.swift`,
         `Tools/pdf-extract-pages.swift`, `Tools/pdf-info.swift` and `Tools/picture-signals.swift`
         skip an unopenable document with `continue` and count neither what they opened nor what they
         rendered. This is how C26's own corpus sweep silently measured zero pages from an `auto/`
         worktree (`testdocs/` is not committed) and reported success; `score-corpus` and now
         `score-threshold-loss` both refuse instead. Judge each one first — a single-document
         utility may be right to say nothing — but say so per tool rather than skipping the class.
      ⚠️ Any tool you touch is staged, so the pre-commit hook runs `check-tools-compile.sh` on it and
      the full suite. Budget a commit, not a check. (origin: the sibling sweep in C26's instrument
      commit, 2026-08-18; the rule is CONTRIBUTING §5)
- [ ] **argv-shape** — **UNTRIAGED, and one half of it can destroy corpus files.** The sibling sweep
      of C26's driver commit classified the argument parse of all 29 `.swift` tools (2026-08-19, in
      `BUGS.md` C26's `Sub-step 3b, the driver` section). Eleven take a path list; **eight take one pdf
      and read argv[2..] as something else**, so a corpus glob is silently mis-measured:
      `score-text-route` (page numbers via `compactMap { Int($0) }`, line 88), `score-corpus` and
      `score-line-separation` (a label then three `SearchableWriter` factors via `if let Double`),
      `score-routing` and `picture-signals` (a label, rest unread), `score-annotations` (a second pdf),
      `pdf-extract-pages`, `make-observations`.
      ⛔ **Decide the last two first.** `pdf-extract-pages` line 5 and `make-observations` line 40 take
      argv[2] as a path they **WRITE** — so `pdf-extract-pages testdocs/*/*.pdf` overwrites the second
      corpus file and prints `extracted 0 pages`. `testdocs/` is 1.2 GB of third-party PDFs that is not
      committed and cannot be rebuilt without the owner's Zotero library. Nobody has run it; this is
      latent, not observed. A refusal ("argv[2] exists and is a PDF — refusing to overwrite it") is
      cheap and is the invariant-1 shape.
      `score-rebuild-dpi` lines 70-72 is the counter-pattern to copy, and its comment already argues
      the case: *"Refused, not dropped… the row that never appears is indistinguishable from a
      resolution that was never asked for"*. `score-illumination` is a half-trap worth a line too — it
      DOES take a path list, but argv[1] is the population label, so a glob measures 232 of 233 and
      names the population after document 1. Only `score-text-route` documents its trap in its header.
      ⚠️ Triage before coding: some of these are single-document utilities that are right as they are,
      and the answer per tool belongs in the commit. Any tool you touch is staged, so budget a commit
      (a full suite) rather than a check. (origin: the sibling sweep in `BUGS.md` C26, 2026-08-19)
- [ ] **silent-image-writes** — **two of the five image writers in `Tools/` still swallow a failed
      write, and one of them can make the suite pass by writing nothing.** Found 2026-08-19 by the
      adversarial review of C26's sub-step (4) diff, which is also what corrected "three writers" to
      **five**; recorded in `BUGS.md` C26's sibling-sweep paragraph, and queued here because that
      paragraph says "both are queued rather than left in prose" and until this line existed it was not
      true. `score-threshold-loss` (`dumpFailures`), `score-mrc` (`MRC_DUMP`, fixed 2026-08-19, exit 6
      through `stop`) and `score-text-route` (`INKDUMP`, exit 4 counting promised against written) are
      the three that now account for what reached disk. The two left:
      1. ⛔ **`Tools/make-plate-fixtures.swift` — the worst of the five.** It writes eight 300-DPI
         fixture pages through `CGDataConsumer(url:)` and every failure is a bare `return`;
         `run_tests.sh` builds it and the suite reads what it wrote, and `run_tests.sh`'s own comment
         says the R56/R57 checks "would otherwise pass by having no fixtures to route". **So a partial
         write is a silent PASS in the suite** — evidence that is wrong rather than absent, which is the
         shape CLAUDE.md's environment-traps section exists for. It touches the suite's own scaffolding,
         so read what reads those fixtures before changing what it writes.
      2. `Tools/make_icon.swift:65` swallows its write, and the first draft of C26's paragraph defended
         it with "`iconutil -c icns` catches that". ⛔ **Measured, and FALSE**: an iconset holding **3 of
         the 10** files `make_icon` promises, correctly named and sized, makes `iconutil` exit **0** and
         produce a valid 7,241-byte `.icns`. So a partial icon set ships a degraded icon with a clean
         build — and `build.sh:113` discards make_icon's only diagnostic with `2>/dev/null`, which is
         the second half of the same defect and is in `build.sh` rather than in `Tools/`.
      ⚠️ `build.sh` and any tool you touch are both in the hook's code set, so budget a commit (a full
      suite) rather than a check. The counting shape to copy is `score-text-route`'s `INKDUMP`: count
      what was promised against what reached disk, name the missing files, and exit non-zero — an empty
      output directory reads as "there was nothing to write", which is how a dump settles a question the
      wrong way round. (origin: the sibling sweep in `BUGS.md` C26, 2026-08-19)
- [ ] **sweep-exit5** — `Tools/sweep-ink-bar.py`'s `CONFIG_EXITS` does not include
      `score-text-route`'s exit **5** (self-test failed, nothing measured), added 2026-08-19 by C26's
      sub-step (4). A systematic self-test failure would therefore be **recorded as 233 failed
      documents** instead of aborting the sweep on the first one — the same class of silent-garbage run
      the constant exists to prevent. Named rather than fixed by the session that added the exit.
      ⚠️ **Three edits, not one**, and the tool's header says one: the constant, its `--self-test`
      assertion, and `EXPECTED_CHECKS`. A staged `Tools/*.py` carrying `--self-test` is hook-enforced,
      so the self-test runs; the suite runs too because the file is under `Tools/`.
      (origin: the sibling sweep in `BUGS.md` C26, 2026-08-19)

## HOLD — owner-only, never auto-executed

These are offered to nobody. `next-item.sh` prints them as `hold` so they stay visible without ever being
picked, and the resume prompt surfaces them to the run log instead of acting on them.

- [ ] **taborder** — the tab-order walk is still by hand. [hold] needs: owner — it needs
      `AppleKeyboardUIMode` set in the guest and reads focus rings out of pixel diffs between captures,
      and the owner accepted it as a known gap on 2026-08-13 rather than queueing it.
      (origin: TODO.md, the one open checkbox there)
- [ ] **release** — cutting a release: a version bump, `./build.sh --dmg`, `hdiutil`, a tag, a GitHub
      release. [hold] needs: owner — judgement about what is fit to ship. Last released: 1.12.0.
      (origin: CHANGELOG.md, TECHNICAL.md)
- [ ] **corpus-write** — anything that writes `testdocs/` or the Zotero library itself. [hold] needs:
      owner — 1.2 GB of third-party copyrighted PDFs, not committed, and not regenerable without the
      source library. Reading it is fine; writing it is not. (origin: CLAUDE.md §"Not committed")
