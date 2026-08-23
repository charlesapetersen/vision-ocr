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
  whenever the background is a CLOSED entry, which is the common case for standing work — and equally when it
  is an OPEN one, which is the case for a finished sub-step of a campaign whose parent stays `[ ]` by design
  (every `c28-*` box below). ⚠️ **Because it is not a status claim, `check-queue-coherence.sh` does not
  resolve it at all**: `cited()` scans `(origin: …)` clauses only, so a `context:` cite is exempt from
  `TICKED-OPEN` *and* from `WOULD-REDO` *and* from `CITE-MISSING`. Measured 2026-08-23, and pinned by that
  script's `--self-test`; the sub-box bullet further down asserted the opposite for four days, and the
  numbers that settled it are there.

Getting this wrong is not a lint nit. `tools-compile` and `mutants` below originally cited their closed
provenance entries as `origin:`, and the coherence check caught it on its first real run. The consequence
would have been silent: the resume prompt tells a session to **rule out already-done first**, so it would
have opened those `FIXED` entries, concluded the work had shipped, and ticked live standing work off
unread. A cite that reads as a status claim when it is only a footnote is exactly how that happens.

⚠️ **RECORDING A FINISHED SUB-STEP: A SUB-BOX IS PARSED AS A TOP-LEVEL ITEM, AND ITS SPAN IS GREEDY.**
A long campaign whose box stays `[ ]` by design reports NO progress to the daemon: `completed_items()` counts
ticked boxes here and closed register entries there, so a session that finishes a sub-step advances neither,
and `nocomplete.count` walks to the auto-park. On 2026-08-19 that took four consecutive sessions. Recording
the finished sub-step as its own ticked box is the fix, under three constraints, all MEASURED that day rather
than reasoned — the first attempt broke the coherence check twice:

- It must sit **AFTER its parent's cite line**, not inside the parent's block. Both `next-item.sh` and
  `check-queue-coherence.sh` give every box a GREEDY SPAN — each following line up to the next box — so a
  sub-box in the middle of a block STEALS the remainder of it, the parent's `(origin: …)` line included.
  Measured: that produced `DUPLICATE-TAG` *and* `TICKED-OPEN`, and left the parent citing nothing at all.
- It needs **its own tag**. Reusing the parent's is a duplicate, and `(blocked-on: …)` then resolves to
  whichever came first.
- It must not carry an **`(origin: …)`** cite. ⛔ **This bullet said "it must cite **no register entry**" and
  gave a reason that is FALSE, and it stood from 2026-08-19 to 2026-08-23 while sixteen TICKED boxes depended
  on the opposite.** The claim was that `(context: …)` "does NOT exempt it — the check is
  `[ "$st" = "x" ] && [ "$n_open" -gt 0 ]`, which never looks at *which* cite word was used". That condition
  is real, but `n_open` is counted from `cited()`, and `cited()` scans `/\(origin:[^)]*\)/` **only** — the
  word `context` appears nowhere in the parser, so the cite word is *exactly* what it looks at. ✅ **MEASURED
  2026-08-23, not reasoned**: over a fixture matrix of eight items, a `[x]` on an OPEN entry is reported
  through `origin:` and silent through `context:`, and an `[ ]` on a CLOSED entry likewise — and on this file
  **as it stood at `ad5861d`, before the box recording this work was added**, the shipped check reads
  `OK 56 items 6 cited`, exit 0, while one line of `cited()` widened to harvest `context:` turns that into
  **24 findings (16 `TICKED-OPEN`, 8 `WOULD-REDO`) over 31 cited items**, every one of them correct
  bookkeeping. (⚠️ The item total is 57 with that box in; the six BUGS.md-citing items do not move, because
  it cites a README defect and not the register.) ⛔ **Fourteen of the sixteen `TICKED-OPEN` are the `c28-*`
  sub-boxes this very section tells you how to write**, so enforcing the rule as written would have flagged
  its own convention; two of the eight `WOULD-REDO` are `tools-compile` and `mutants`, the pair the semantics
  bullets above were written for, each of which says CLOSED inside its own cite text (two different strings —
  read them at those items rather than trusting one quotation for both). ✅ So the parent keeps the
  `(origin: …)` and the sub-box carries
  a `(context: …)`, which is what every `c28-*` box already does. The gate for this is
  `check-queue-coherence.sh --self-test`, added the same day and watched failing against two sabotages of
  `cited()` and two of the guard it feeds — widen `cited()` to `context:` and seven of its fifteen checks go
  red; stop it harvesting `origin:` and seven do, which is what stops a checker that reports *nothing* from
  passing; loosen `TICKED-OPEN`'s `-gt 0` to `-ge 0` and two do, which is the sabotage the first version of
  that self-test could not see at all.
  ⚠️ **The cost of the exemption, so it is a decision and not a discovery**: a `context:` cite is
  **unvalidated in every direction**. Write `context:` where you meant `origin:` and no status is ever
  compared; name a tag that does not exist and not even `CITE-MISSING` fires. Both are pinned by that
  self-test, so they can change on purpose and not by accident.

## How to SIZE an item — and why an unbounded verb strands a worktree

**The failure this prevents.** A session that is interrupted mid-item leaves its worktree dirty. The
daemon's answer is to write `$STATE/rescue/<stamp>.patch` and name the worktree in `daemon.log`, which
costs a hand review to decide whether the patch is redundant; until someone does that, **every following
cycle logs "a worktree is holding UNCOMMITTED WORK — this is NOT an empty queue"** — the daemon telling
the truth in a way that reads like a fault. Seven such rescues accumulated in the four days to 2026-08-20.

⚠️ **THIS SECTION SAID "the work is not lost" AND THAT WAS TOO STRONG WHEN IT WAS WRITTEN.** Hours later
a session stranded 481 insertions across 9 files and **no patch was written**, because the snapshot was
gated on the progress verdict and an owner commit had moved the fingerprint — `README.md` §Defects **D12**,
fixed the same day, with `prove-daemon.sh` [18] as its gate. So the net exists and is now reachable on
every path, but treat it as insurance against a reboot rather than a reason to leave work uncommitted:
the recovery still cost a hand-written patch, a re-run of a full suite, and a session spent re-verifying
someone else's diff. **Sizing is the cheap lever; the rescue is the expensive one.**
The lever is item size, and D6 said so when the budget was raised: *"If this stops helping, the next lever
is item size, not another raise."*

**The envelope a box has to fit.** `MAXRUN` is **14400 s (4 h)** and the budget is **$35** a session — but
neither is the binding constraint, because **a usage limit ends a session at any moment regardless of
size** (measured 2026-08-20: four consecutive sessions fast-failed in 8-9 s). So sizing cannot make
interruption impossible. What it controls is **how many minutes of uncommitted work are exposed when one
happens.**

**The cost model, measured rather than assumed.**

| what a commit touches | what it costs |
|---|---|
| docs, the register, this file, a `.tsv` | **free** — the hook prints "no code staged, skipping the suite" and it lands in seconds |
| `Sources/` `Helper/` `Tests/` `Tools/` `build.sh` `run_tests.sh` | **one full suite**, measured 474-5554 s — read `$STATE/suite-timings.tsv` and never quote one figure |
| a NEW check | **two** suite runs — the watch-it-fail control, then the hook's green run |
| a scoped `mutate.py` run | **a baseline suite plus ~45 min per mutant** (five took 4h27m end to end) |

**The rules that follow from it.**

1. **One code commit per box.** If the work needs two, it needs two boxes, or one box with tickable
   sub-boxes. A box that implies three code commits implies three suite runs — 1.5 to 4.5 hours of
   machine time before the last of them lands, and everything before the first commit is exposed.
2. **Split the free work out.** Measurement, triage, a register entry, a doc correction and this file's own
   checkboxes are all free commits. Landing them first turns one long exposure into several short ones, and
   it is why `C28`'s campaign has never stranded anything: each sub-step committed on its own.
3. **Anything over about an hour of compute is a detached driver, not a session.** Write the driver, commit
   it first, start it with `nohup`/`setsid` so it outlives the session, make its output resumable, and leave
   a resume note in the SESSION LOG naming the worktree, the log and the exact resume command. That is
   `C26` sub-step 3b's pattern and it is the only shape that has worked here. Later sessions poll; a
   polling cycle scoring as no-progress is correct, not a fault.
4. ⛔ **WRITE THE BOUND INTO THE BOX, AS A NUMBER.** *"work the survivors"*, *"run over all its cases"*,
   *"steps 2-4"* and *"the SIX that mis-measure"* are all licence to start something a session cannot
   finish, and a session reading its first `ok` has no other source for how much is enough. **One mutant.
   One tool. Three pages.** If the bound is genuinely "all of them", say how many that is and how long it
   took last time.
5. **Never size against a quiet machine.** Every duration this project has written down turned out to be a
   reading of the machine's load: the suite has run 474 s and 5554 s on the same corpus-free tree, and
   loadavg does not predict it. Size against the WORST row in the ledger plus headroom.


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
- [x] **C26** — a small line drawing is erased on the picture path, at the SHIPPED DEFAULT Photo
      detail setting. ✅ **CLOSED 2026-08-20 on the rendered proof; the entry is `FIXED`.**
      ✅ **UNHELD 2026-08-19: the owner decided the bar at a check-in — move
      `Flattener.textPageInkOutsideThreshold` from 0.08 to 0.045, behind a corpus gate.** ⚠️ **The
      move landed the same day WITHOUT a fresh corpus gate, deliberately**, and the substitution — the
      already-committed `INKBAR-2026-08-19.tsv`, which compares exactly these two states page by page
      over 233 documents — ✅ **was ACCEPTED BY THE OWNER as C26's gate at a 2026-08-19 check-in**, so no
      fresh `score-gate` run is owed and this is no longer an open question. Do not re-raise it.
      The
      measurement campaign is COMPLETE (sub-steps 1, 2, 3, 3b and 4 all ✅ below) and ⛔ **must not be
      re-derived**: expect the **16 pages** named in `INKBAR-2026-08-19.tsv` to move and nothing else.
      The owner's reasoning, recorded because it is what makes this a session's work rather than his:
      the loss is **content, not fidelity** — 8 of the 13 measured pages lose whole lines of prose or
      table data — so invariant 1 governs, and ~4.0 MB / **+0.55%** of corpus output is a cheap price
      for not destroying words. R35's refusal of a change worth the same 0.55% does not transfer: R35
      weighed 0.55% as a *prize* and this is 0.55% as a *price*. ⚠️ **But the bar move does NOT close
      the entry**, and the counter-finding is accepted rather than waved away: **32.4% of the band's
      byte cost lands on two pages a reader cannot tell apart** (`RIESMAN_1942` p10, `Riesman - 1954`
      p18), which says a threshold is a blunt instrument and not the right final answer. So the
      stencil question this campaign surfaced — *why is recognised-page prose dropped from the stencil
      at all* — **WAS opened as its own register entry, `C28`, on 2026-08-19** (it is an item of its own
      below); this line read "is to be OPENED" until then, and C26 no longer stays open for it. It is
      not worked here. ⚠️ This line then said the entry stays OPEN and this box stays `[ ]` *for the
      founding-page render*, which ran on 2026-08-20 — see the ✅ block below.
      **Held 2026-08-19 after the sub-step (4) session, unheld the same day by the decision above.**
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
      `Xin Qu et al_2018` p20 loses thirteen values out of a Pearson correlation matrix — ✅ **and that
      claim was re-measured independently by `c28-halfres` 2026-08-20 and HOLDS: they are the matrix's
      LAST column, stencil ink `0.0000`, 1,375 of the page's 6,233 out-of-stencil map pixels** —
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
      ✅ **THE CONSTANT HAS MOVED — 0.08 -> 0.045, landed 2026-08-19.** Do not do it again. The suite
      carries the flip (three checks that recorded the defect now record the fix, watched failing
      against 0.08 on the way in, plus a new mutant `const/textPageInkOutsideThreshold`), and the
      entry's `#### The constant moved` section is the diff and the numbers. ⚠️ **Two instruments
      changed meaning with it**: `INKBAR=0.045` now exits 2 ("equals the shipped bar"), so it is
      `INKBAR=0.08` that prices the old behaviour, and `sweep-ink-bar.py --bar 0.045` would abort on
      document 1 — the tool headers say so now.
      ✅ **THE STENCIL QUESTION IS NOW ITS OWN ENTRY, `C28`, opened 2026-08-19** (FOCUS item 3, done).
      Do not work it from here and do not fold it back in — it is its own item below.
      ✅ **THE RENDERED PROOF RAN 2026-08-20 AND THE ENTRY IS CLOSED.** `INKBAR=0.08
      INKDUMP=<dir> score-text-route "…/1954 - Why.pdf" 4 6 7`, exit 0: `verdict` reads `picture` on
      all three (`inkOut` 0.0540 / 0.0493 / 0.0660), 195,785 B against 65,477 B at the old bar,
      stencil byte-identical, backgrounds **612 px against 153 px**. Read at 1:1 over each drawing's
      own rect the cartoons are whole and legible as shipped and illegible at 0.08. ⛔ **The verdict is
      those crops.** The section's first draft led with a ratio — "5.7x / 6.3x / 5.7x the fine detail" —
      and blank rects on the same page measure 3.6x–14.2x, so the ratio tracks the downsample factor and
      is retracted in place; what holds is absolute, 11.99–12.35 over the drawings against a
      blank-paper floor of 2.10–2.51 as shipped, and 1.87–2.16 at the old bar, which is that floor.
      `BUGS.md` C26 §"The rendered proof on the founding pages" is the whole of it. The
      measurement campaign is complete: population, price and benefit are all in the entry, and ⛔ none
      of it is to be re-derived.
      ✅ **THE CONSTANT WAS THE OWNER'S CALL AND HE MADE IT: 0.08 -> 0.045**, at a 2026-08-19 check-in,
      on R55's precedent — the campaign runs, the owner closes it on the arithmetic. R49/R50 state
      **no** growth-tolerance bar (read 2026-08-19), so no session could have applied a standard; what
      R50 was accepted on was "not one grew", and 0.045 grows ten documents, which is the trade the
      owner took. This line said "not a session's to move" until the decision; it is kept, corrected in
      place, because the reason it said so is still the reason a session must not move the *next* one.
      `Flattener.textPageInkOutsideThresholdOverride` stays `nil` in the app — the constant moves, the
      seam does not.
      ⚠️ **The release gate cannot see this defect class** — `score-gate.swift`'s own source says
      so, and it passed this exact document. Do not accept a green gate as evidence of a fix here;
      the instruments for this are `score-threshold-loss.swift` and `score-text-route.swift`'s
      `INKDUMP`, plus rendered before-and-after pages.
      (origin: BUGS.md C26)
      - [x] **C26-constant** — `Flattener.textPageInkOutsideThreshold` 0.08 -> 0.045, the owner's
        2026-08-19 decision, landed with the suite's checks and a mutant. Ticked because the sub-step
        finished, NOT because the item above did: that one stays open for the stencil question, which
        is also why this box carries no register cite — a `[x]` citing an open entry is TICKED-OPEN
        drift, and this box's span must stay clear of the cite line above it. ⚠️ **Both reasons have
        since gone**: the stencil question became `C28` on 2026-08-19, the founding-page render that
        replaced it ran on 2026-08-20, and the item above is now `[x]` with C26 `FIXED`. The no-cite
        rule still holds for these two sub-boxes — it is about the *shape*, not about C26's status.
      - [x] **C26-stencil-open** — the stencil question opened as its own register entry (`C28`) on
        2026-08-19, the third of the owner's three commits and the last thing FOCUS item 3 asked for.
        Docs plus two corrected doc comments; no constant moved. Same no-cite rule as the box above.
- [ ] **C28** — the 1-bit stencil is the intersection of the page's ink with Vision's word boxes, so
      prose the recogniser missed is in neither the stencil nor the text layer and survives only in a
      background stored at **1/8** on a page read as all text. Invariant 1: measured over 13 corpus
      pages in C26 sub-step 4, **7 lose whole lines of running prose or table data** and nothing
      reports it. ⛔ **This is the entry C26's campaign surfaced, not a re-run of C26** — C26's bar
      move is shipped and is a page-wide proxy for this; read `BUGS.md` C28, then C26's
      sub-step 4 section ("the benefit"), and do NOT re-derive either.
      ✅ **THE TWO CODE COMMENTS ARE CORRECTED as of sub-step 3, 2026-08-20** —
      `Sources/Flattener.swift` and `Tests/main.swift` no longer stop at C26 sub-step 4's 13 pages and
      7 prose losses; both now carry the campaign total. That was the last residue of the owner's
      2026-08-20 check-in note. The campaign total to quote is **86 pages rendered, 24 losing content,
      19 of them type and 6 a hand-made mark, with one page in both buckets** (`Atkinson_1939` p3,
      corrected 2026-08-21 by `c28-shapeterm` — so the two no longer sum to the 24; it read
      "18 of them type and 6" before) — and note it is arrived at by ADDITION over the five
      renders (13 + 8 + 24 + 20 + 21), not by re-measuring. ⚠️ **This line said 21 / 12 / 10 while 45 pages
      had been read**, because sub-step 2's commit did not update it; if your sub-step renders pages,
      update this number in the same commit or the next reader inherits the same gap.
      ✅ **ALL THREE RIDE-ALONG DEBTS BELOW ARE DISCHARGED 2026-08-21 by the `c28-all73` sub-step's
      commit** — the settings blurb, the tool header and the `Tools/README.md` row all landed on the
      suite-paying commit that measured the whole 73. The three paragraphs are kept as the record of
      what was decided and why. ⚠️ **One of them was wrong about its own target**: the "by construction"
      phrase was in `Tools/README.md` only — `git show 5be15c3:Tools/score-shape-term.swift` never
      contained it — so what that header was really owed was any mention of 3b, which it now carries
      along with the 73-page result. ⚠️ The blurb also gained a check it did not
      have: `Tests/main.swift` now asserts that **no** `PhotoDetail` blurb promises nothing is lost,
      plus a non-vacuity row, watched failing (1 failure) against the pre-fix string in a standalone
      harness built from `git show HEAD:Sources/Prefs.swift`.
      ⛔ **THE SETTINGS BLURB WAS DECIDED, owner 2026-08-21, to RIDE ALONG on the next commit that
      runs the suite — do NOT make it a commit of its own.** `Sources/Prefs.swift`'s
      `PhotoDetail.smallest` blurb loses the clause *"though nothing is lost from them"* and gains
      NOTHING in its place, so the two lines become exactly:
          return "Photographs keep a third of their resolution and look "
               + "noticeably soft up close. Files are about a fifth the size."
      The owner chose deletion over a caveat so the string cannot go stale again whichever way C28
      lands — a warning about small print would itself need retracting if C28 is fixed. ⚠️ **Replace the
      two-line "deliberately unchanged" comment beside it** rather than leaving it: it says the wording
      is the owner's call and the honest wording depends on C28, and both halves of that are now spent.
      Say instead that the clause was deleted on 2026-08-21 because p20 measured it false, and keep the
      `BUGS.md` C28 pointer, so the next reader does not restore the promise as a "fix". ✅ **No check
      asserts on it** — verified 2026-08-21 at the check-in, not inherited from the review: the suite
      reads `Prefs.PhotoDetail` only through `rawValue` and `downsample`, and `Tests/main.swift`'s twelve
      `blurb` references are all `Preset.blurb` and `Flattener.Mode.blurb`. ⚠️ `Sources/` is in the
      pre-commit suite regex, so alone this one clause buys a 45-90 minute suite; this is the same call
      the owner made on the two code comments above, and it discharges the last `## NEEDS OWNER` bullet.
      ⚠️ **TWO MORE `Tools/` DOCUMENTATION DEBTS RIDE WITH IT, added 2026-08-21 by `c28-pictures`.**
      `Tools/score-shape-term.swift`'s header and `Tools/README.md`'s `score-shape-term` row both still
      say the shape term is blind to a hand-made mark **by construction**, which that sub-step refuted
      (it fires 17 and 11 line groups on a pen ornament). `Tools/` matches the same suite regex, so a
      docs-only commit cannot carry them either. Both should say instead that the term reads 0 on four
      hand-made marks and fires on three, and point at `BUGS.md` C28
      `#### The same shape term on PICTURES`. ⚠️ The header's "13 pages of the 73" is stale too — it is
      8 of the 73 plus 5 of C26's rescued 16.
      ✅ **The first sub-step is DONE 2026-08-20 — the 8 near-misses are rendered and 4 of the 8 lose
      content.** Do not re-run it; the sub-box below and the entry's
      `#### The eight near-misses, RENDERED` carry the table, the byte price and the method.
      ⛔ **Two corrections came out of it that this box was itself wrong about.** (1) The instrument
      line here said `INKBAR=0.08 INKDUMP=<dir>`, and for pages BELOW the shipped bar that compares a
      page **with itself** — measured, `barVerdict` `all-text`, `barDelta` `same`, two byte-identical
      backgrounds — so it would have read as "loses nothing". Use a bar **below the page's own
      `inkOut`**; `INKBAR=0.02` covers that population. (2) An un-normalised at-bar background is a
      good locator (out-of-stencil ink is solid there, in-stencil ink only a pale `fillHoles` ghost);
      a `-normalize`d one misled twice more, on top of the two the entry already records.
      ✅ **The second sub-step is DONE 2026-08-20 too — the other 24 pages of the six read documents,
      and the loss reaches `inkOut` 0.0137 (an estimating equation) and 0.0008 (a word).** Do not re-run
      it; the `c28-sixdocs` sub-box below and the entry's
      `#### The other 24 in the six read documents, RENDERED` carry the table, the two instrument facts
      and the byte price.
      ✅ **The third sub-step is DONE 2026-08-20 as well — the twenty highest-`inkOut` pages of what
      was left, and 8 of the 20 lose content.** Do not re-run it; the `c28-topink` sub-box below and the
      entry's `#### The twenty highest-inkOut of the remaining 41, RENDERED` carry the tables, the two
      instrument corrections and the byte price.
      ✅ **The FOURTH sub-step is DONE 2026-08-20 and it CLOSES the population — the last 21 pages of
      the 73, and 2 of the 21 lose content.** 8 + 24 + 20 + 21 = 73, all read. Do not re-run it; the
      `c28-last21` sub-box below and the entry's `#### The last 21 of the 73, RENDERED` carry the
      tables, the byte price and three instrument facts.
      ✅ **Question 5 is DONE 2026-08-20 — the run report now names every page it stored at an
      eighth.** Do not re-do it; the `c28-report` sub-box below and the entry's
      `#### The report, SHIPPED` carry the four decisions in it and the one part no check reaches.
      ✅ **Question 2's 1/2 HALF IS DONE 2026-08-20 and the loss does NOT reproduce there.** Do not
      re-run it; the `c28-halfres` sub-box below and the entry's
      `#### The same loss at 1/2, RENDERED over 16 of the 109` carry the table, the two negative
      controls, the two instrument defects and a retraction of its own draft. **16 of the 109 rendered,
      no content loss found at 1/2 in any window read**, including on the two pages where the same ink
      WAS destroyed at 1/8 before the 2026-08-19 bar move — so this entry stays bounded to the 73 pages
      at 8x/16x rather than 182.
      ⚠️ **The base is one window a page** (six got a second, two more were re-read by the review), so
      widening a window is what strengthens it, not adding pages.
      ✅ **Question 2's 1/3 HALF IS DONE 2026-08-21 and it DOES reproduce**, which closes question 2. Do
      not re-run it; the `c28-thirdres` sub-box below and the entry's
      `#### The same loss at 1/3, RENDERED over 16 of the 109` carry the table, the two negative
      controls, the byte price and five instrument facts. **1 of 16 loses content** (`Xin Qu et al_2018`
      p20's correlation matrix, 460 px legible and 307 px not), 2 degrade and 5 read clean — and the
      term that orders them is the page's **own rebuild resolution**, not `inkOut`. `PHOTODETAIL=` on
      `Tools/score-text-route.swift` is the seam it needed.
      ✅ **QUESTION 3 HAS ITS FIRST MEASUREMENT, 2026-08-21, AND THE SHAPE TERM SEPARATES** — 12 of 13
      labelled pages, `lineN` ≥ 1 on 6 of 6 type-losers and 0 on 6 of 6 non-losers, the miss being a
      hand-drawn mark the rule reads 0 on (⛔ published as "by construction" and refuted by 3b, below).
      Do not re-run it; the `c28-shapeterm`
      sub-box below and the entry's `#### A shape term, MEASURED over 13 labelled pages` carry the
      table, the crops, the three instrument answers and what is left.
      ⛔ **3b RAN 2026-08-21 AND THE TERM ERRS IN BOTH DIRECTIONS — do NOT re-run it**; the
      `c28-pictures` sub-box below and `BUGS.md` C28 `#### The same shape term on PICTURES` carry it.
      `lineN` ≥ 1 on **6 of 10** picture pages, 2 of the 3 true halftone plates among them, and it reads
      **0 on two pages whose content loss is measured** (`1954 - Why` p6 and p7, C26's own founding
      cartoons). So question 3's "without admitting pictures" is answered **no**, and the same run
      refuted "blind to a hand-made mark by construction" — it fires 17 and 11 groups on a pen ornament.
      ✅ **THE TERM WAS THEN READ OVER THE WHOLE 73 ON 2026-08-21 AND QUESTION 4 GOT ITS FIRST
      PAGE-LEVEL BYTE PRICE OUT OF THE SAME RUN — do NOT re-run either**; the `c28-all73` sub-box below
      and `BUGS.md` C28 `#### The same shape term over ALL 73` carry both, with
      `SHAPETERM-73-2026-08-21.tsv`. `lineN` ≥ 1 on **12 of 12** type-losers, **3 of 57** non-losers,
      and all three of those are the rim of recognised type. The wiring costs **+2,362,625 B over 16 of
      73 pages** against the cheapest page-wide bar rescuing the same 13 at **+6,202,065 B over 41** —
      38.1% of the bytes, 15.5% of the spend on pages that do not lose content against 58.5% — but the bar rescues 15 of 16
      losers and the term 13.
      **So questions 1, 2, 3 and 5 are measured, question 4 is measured at the LAYERING seam, and what
      is left is question 4 at the `textRegionMask` seam** — the seam question 3's own sentence names,
      the one 3b's bound does NOT cover, and now the only thing under this entry unpriced at any scale.
      ✅ **PRICED 2026-08-22, so ALL FIVE QUESTIONS ARE MEASURED and what is left of this entry is the
      DECISION AND THE WIRING, not another measurement. Do NOT re-run it**; the `c28-stencilseam`
      sub-box below and `BUGS.md` C28 `#### The price at the textRegionMask seam` carry it, with
      `WIDEN-STENCIL-2026-08-22.tsv`. Over the **same 16 pages** the layering wiring refuses:
      **+2,315 B, 1.0029x** against **+2,362,625 B** — **0.098%**, 1,020x cheaper — **2.12%** of it on
      pages that lose nothing, **6 of the 16 getting CHEAPER**, and per document **~18.42 pages for
      +2,728 B**, which is **0.068% of C26's shipped ~4.0 MB**. ⛔ **NOT the same protection**: the shrink
      refusal keeps all **73,370** out-of-stencil ink pixels on those 16 pages, the widening admits
      **36,709 — 50.03%** (5.4% to 96.9% per page, **24.1%** on `Scott_TK` p3, a measured loser), so
      **quote the coverage beside the ratio**. ✅ Positive control at 1:1:
      `Jones et al_2010` p7's estimating equation is blank in the shipped stencil and legible in the
      widened one for +369 B — ⚠️ read at 1:1 on **1 of the 13** losers; the other twelve have only a
      stencil that grew.
      ⛔ **Do not read that as "the fix is nearly free".** The same run measured the correctness price:
      `Wilcox` p2's pen ornament becomes a hard-edged 1-bit blob (R57's failure mode, on a page that
      loses nothing), 4 of the 10 picture pages admit ink at all, and **a widened region lowers
      `inkOutsideText`, so widening pushes every page toward the all-text verdict that shrinks
      backgrounds 8x** — `1954 - Why` p4 goes 0.0540 → **0.0524** against a bar of 0.045, i.e. a more
      generous rule re-destroys the cartoon C26's bar move rescued. Anything wired must hold
      `pageIsAllText`'s region at the **recognised** one, or measure that. It also buys **no
      searchability**: a synthetic box carries no string, so `SearchableWriter` still has nothing to draw.
      ⚠️ Do not quote T15's 1.33x as the page-level figure, and note `linePx` is an area and not a byte
      count.
      ✅ **THE OTHER THING THAT WAS LEFT — the population of sub-bar pages carrying a picture — IS
      MEASURED 2026-08-22 AND IT HOLDS NO PRINTED PLATE. Do NOT re-run it**; the `c28-subbarpix` sub-box
      below and `BUGS.md` C28 `#### Are there PICTURES in the sub-bar 73?` carry it, with
      `SUBBARPIX-2026-08-22.tsv`. **0 printed plates and 0 printed figures over the 73, and the largest
      non-text mark anywhere is ≤3% of a page** — that pair is what survives every boundary choice and is
      the claim to quote; the device / camera / annotation counts are FLOORS, not a census.
      ⛔ **Three of 3b's four substrates are absent and the fourth is NOT**: continuous tone occurs, as
      camera photography — `1976 - Regis McKenna Papers` p4 is a colour photograph of a memo whose `txtN`
      is **45** and `txtShare` **0.2157**, so the component test accepts a fifth of its out-of-stencil map
      and only `lineN = 0` refuses it. ⛔ **So the bound is the GROUPING, not the component test**, and an
      ornament rect on another page agrees: map 666 px, accepted components **664**, grouped **0**. Those
      two constants are the same ones behind the term's false negatives on C26's cartoons, which makes
      relaxing them a two-sided trade rather than a fix.
      ✅ **THE CORPUS FIGURE IS DONE 2026-08-21 — do NOT re-derive it**; the `c28-corpus` sub-box below
      and `BUGS.md` C28 `#### The corpus figure` carry it, with `Tools/stratify-corpus.py`. Per
      document, over the whole 16,987-page corpus: **~127 pages are still shrunk 8x/16x and ~19 of them
      lose content (0.11% of the corpus). The shape term's wiring refuses ~18 of the ~127 for
      +2,694,515 B and rescues ~14.7 of the ~19; the cheapest page-wide bar refuses ~60 for
      +8,289,863 B and rescues ~17.9** — both incremental to C26's shipped
      ~4.0 MB, so the term is two thirds of a fix already accepted and the bar 2.1x its whole bill.
      ⛔ **Three pairs of ratios in this box move as a result.** Term against bar is **30.9%** of pages
      and **32.5%** of bytes corpus-wide against the **39.0%** and **38.1%** these 41 sampled rows read,
      so the term gets cheaper relative to the bar and not dearer; the share of the spend that buys
      nothing goes the other way (**15.5% → 18.0%** and **58.5% → 61.0%**); and the
      pooled-over-stratified factor is **not** a constant (4.58x / 5.48x / 6.57x / 6.93x over four arms
      of one population), so C26's 5.96x is its band's number and must never be used to correct a
      sampled count.
      ⛔ **THE RIM FIX — "the one cheap thing worth trying first" — WAS TRIED 2026-08-21. Do NOT re-run
      the sweep**; the `c28-rimfix` sub-box below and `BUGS.md` C28 `#### The rim fix, MEASURED` carry
      it, with `SHAPETERM-RIM-2026-08-21.tsv`. A dilated-`region` collar over the same 73 pages reads
      r=1 **12/12 type, 2/51 nothing**; r=2 **11/12, 1/51**; r=3 **9/12, 1/51**. ⛔ **As a REPLACEMENT
      it is refused** — r=1 is the only radius that keeps every real loss, and it clears two rims of
      three while **adding one of its own** (a 1-px collar splits a three-component rim into four,
      reaching `lineMinimumMembers`); from r=2 it destroys real losses.
      ✅ **BUT AS A SECOND CONDITION IT IS THE BEST RULE THIS CAMPAIGN HAS MEASURED ON THE SUB-BAR
      73**: `lineN >= 1 AND rim1N >= 1` reads **12 of 12 type-losers and 1 of 51
      non-losers**, on 14 pages rather than 16, and the manufactured firing cannot enter it. ⚠️ It is
      **post-hoc** (chosen after seeing these 73) and the hand-made bucket does not move (1 of 4).
      ⛔ **AND IT BUYS NOTHING ON A PICTURE PAGE — RUN 2026-08-21, do NOT re-run it**; the
      `c28-rimpictures` sub-box below and `BUGS.md` C28 `#### The conjunction on a PICTURE page` carry
      it, with `SHAPETERM-PICTURES-RIM-2026-08-21.tsv`. `rim1N == rim2N == rim3N == lineN` on **10 of
      10** pages, the **largest** accepted-line rect identical at every radius, and a 3-px collar removes
      **4 accepted-line pixels of 16,294** page-wide — so the conjunction fires on the same **6 of 10**
      the r=0 rule does and 3b's `textRegionMask` finding is untouched *as measured*. The collar is
      `dilate(region, r) \ region`, so it reaches only a mark within `r` px of a padded word box.
      ⚠️ A collar is worse for the **local** variant than any boolean shows: at r=1
      `Scott_TK` p3 keeps 278 of 1,796 accepted line pixels and its largest group MOVES. And note
      `outPx` interleaves too (`_1967_Yearly Increase` p1 reads 5,863, above eight of the twelve
      type-losers), so it is not the term either.
      ⛔ **AND ONE PROCESS WARNING WORTH MORE THAN THE MEASUREMENT: a draft of `c28-halfres` tried to
      RETRACT a correct claim of this campaign's, in six places, and the adversarial review of its diff
      refuted it from the same page.** The draft measured stencil ink over source ink in one rect of
      `Xin Qu et al_2018` p20's correlation matrix (top-left, **0.98x** — stencilled), concluded the
      "thirteen values" claim was misattributed, and would also have told the next suite-paying commit
      to change a **correct** comment in `Sources/Flattener.swift:1476`. The matrix's LAST column reads
      stencil ink **0.0000** over `62x233+741+378` and holds **1,375 of the page's 6,233**
      out-of-stencil map pixels: thirteen values, exactly as published. **A stencil-ink ratio is a claim
      about its rect, not about the page** — find the whole page's out-of-stencil concentrations first,
      then choose rects. No code comment is owed by that sub-step; `Flattener.swift:1476` is right.
      ⛔ **Before driving the map again, read sub-step 4's last three paragraphs.** The map must be
      INTERIOR-cropped on **both** images — `inkOutsideText` walks x ∈ [w/16, w−w/16),
      y ∈ [h/16, h−h/16) and divides by interior ink; uncropped it reads up to 256x the guard's own
      number on a photographed sheet. `Disk:0` is **not** the identity (measured: 0 px at `Disk:0`,
      133 at `Disk:1`, 15 at `Disk:2`, 0 at `Disk:3` on one page), and a connected-component rect off
      the interior-cropped map is in a **different coordinate frame** from one off the whole map —
      count the white pixels inside a rect before believing it names anything.
      ⚠️ **Do not widen `textRegionMask` without pricing it — and do not quote the wrong price.** T15's
      1.33x over 74 corpus *picture* pages is the STENCIL-bytes total; the page total on the 26 cleanly-comparable
      pages is **1.07x**, which is what a widening is judged on, and T15 records the whole-sample gap
      as 84% R50's shrink. Widening still owes an R49/R50 byte
      measurement; the entry lists a cheaper variant (exempt text-shaped regions from the background
      shrink rather than admitting them to the stencil). And this is the third place R56's lesson
      applies — the term that works is likely to be about *where and what shape* a mark is, not how
      dark it is.
      ⚠️ **The release gate cannot see this class either** — same `score-gate.swift` limitation C26
      records. Do not accept a green gate as evidence.
      (origin: BUGS.md C28)
- [x] **c28-nearmiss** — **DONE 2026-08-20.** C28's first sub-step: the eight pages nearest the shipped
      bar from below (`inkOut` 0.0353-0.0450) rendered at both factors and read at 1:1. **4 of the 8
      lose content** — two lines of running prose each on `Broadhead - 1994` p3 and `Jones et al_2010`
      p5, table figures / column heads / Roman row labels / the Google-scan footer on `Scott_TK` p3,
      and a **handwritten signature** on a 1939 letter on `Atkinson_1939` p3; the other four
      (`Broadhead` p5 / p7 / p10 / p12) lose only page edges, gutter and the scanner's thumbs. Three
      of the four losses are cross-checked against the stencil's own ink in the rect — **0.0% / 0.13%
      / 3.6%** where the loss is, against 7.6% / 11.4% / 15.4% on the adjacent lines that survive;
      `Scott_TK` p3 is the fourth and rests on the crop and the locator agreeing. `inkOut` and
      `layered` reproduce `INKBAR-2026-08-19.tsv` digit for digit
      on all eight rows, stencil byte-identical at both bars on all eight, `INKDUMP` 7 files per page
      with none missing.
      ⛔ **The result is the ORDERING, not the count, and it is that NO VALUE OF THE CONSTANT
      SEPARATES THE EIGHT**: sorted by `inkOutsideText` they read
      lose / no / lose / no / no / lose / no / lose, so the sets interleave — a bar low enough to
      protect all four losers protects all four non-losers too. The lowest of the eight loses two
      lines of prose and two of the four highest lose nothing. Within `Broadhead - 1994` the fraction
      *does* sort its eight rendered pages perfectly (0.0767 / 0.0590 / 0.0465 / 0.0450 lose,
      0.0441 / 0.0410 / 0.0405 / 0.0370 do not, no inversion) and the shipped bar misses p3 by at most
      0.00005 — so `p8`-vs-`p10`, the pair C28 was opened citing, is the bar getting it right. Every
      actual inversion among the eight is cross-document; `Atkinson_1939` p2-vs-p3 and `Jones`
      p12-vs-p5 are pairs where BOTH pages lose, so they are not inversions.
      **C28's case for a shape term, measured rather than argued.** ⚠️ A first draft of this box said
      "the useful bar is per scan"; the audit of the diff refuted it — the other three documents
      contributed one rendered page each, so no per-document window is computable for them.
      Price of un-shrinking the eight: 430,679 -> 1,754,076 B, **+1,323,397 B, 4.07x, 165,425 B/page**,
      of which **57.4% lands on the four that lose nothing**.
      Corpus read-only throughout; every image written to `mktemp`-style scratch under `/tmp`.
- [x] **c28-sixdocs** — **DONE 2026-08-20.** C28's second sub-step: the other **24** still-shrunk pages
      in the six documents C26 sub-step 4 had already read. Six invocations, `rc=0` on all, `INKDUMP`
      7 files per page with none missing, and `inkOut` / `layered` / `extent` reproduce
      `INKBAR-2026-08-19.tsv` digit for digit on all 24 rows.
      ⛔ **The loss reaches a THIRD of the way to zero, which is the result.** `Jones et al_2010` **p7**
      loses the **two displayed lines of the paper's estimating equation (2)** and the
      `(p-value 0.12).` after its Hansen J statistic — at `inkOut` **0.0137** — while the
      `ε_it ~ iid(0,σ²)` line under the equation SURVIVES (2.87% stencil ink; a first draft of this box
      listed it as lost and the published-page composite refuted that). Its **p2** loses
      the word "value." at **0.0008**, against a previous lowest measured loser of 0.0353. Displayed
      mathematics is a failure class this campaign had not seen: Vision boxes prose and misses set
      equations. `Riesman - 1954` p20 loses a **hand-drawn pen line** to a smear (stroke still
      followable, so degraded rather than lost); five `Xin Qu` pages lose the **footnote separator
      rule**; the other 16 lose page edges, gutter, the scanner's thumbs, two specks or nothing at all.
      Stencil-ink cross-check on the three that matter: **0.00% / 0.00% / 0.06%** in the rect against
      **15.59% / 11.94% / 17.69%** on the adjacent line or type.
      ⛔ **TWO INSTRUMENT FACTS, both of which the next batch needs.** (1) **11 of the 24, and 27 of the
      73, cannot be priced through the override seam at all**: `pageIsAllText` is a strict `<` and
      `INKBAR` is refused outside (0,1), so a page whose `inkOut` is 0 has no legal bar below it. The
      test is `barDelta`, NOT the printed value — `Riesman - 1954` p12 prints `0.0000` and did flip. The
      tool's summary line also formats the bar `%.4f`, so `INKBAR=0.00001` prints as `0.0000`. (2) The
      instrument that works on every page is `ink AND NOT dilate(stencil)` off the dump's own
      `-source.png` and `-stencil.png` — three `magick` calls, no override, no second `mrcLayers` run —
      **validated against `Broadhead - 1994` p3/p10**, where it NAMES the two lines sub-step 1 read by
      eye and shows p10 holding no type at all. ⚠️ Its first two versions were both wrong and measured
      so: `-compose Minus` computes `dst - src` (caught by counts RISING with the dilation radius), and
      without the dilation the map carries a glyph-edge rim from the Otsu-vs-Sauvola mismatch worth
      **0.97x to 19.4x** `inkOut` depending on the page — negligible on the eight `Jones`/`Xin Qu`
      pages, 3.3x/3.6x on `Broadhead`, 8.0x/19.4x on `Riesman` p20/p24, and worst on `Atkinson_1939`
      p1 (34,158 px at r=0 against 15 px at r=3, on a page whose `inkOut` is 0.0000).
      ⛔ **And its pixel COUNT discriminates nothing** — the losing control 15,431 px, the non-losing one
      15,727 px, flat across r = 2/3/4 — so a scalar "how much ink is outside" fails exactly as the
      page-wide fraction did. Second measured refusal of a scalar; question 3's term must be shape.
      **Per-document windows: measurable for two documents now, and disjoint.** `Broadhead - 1994`'s
      two lowest pages (0.0193, 0.0140) lose nothing, so all ten of its sampled pages the first term can
      move are read and still order perfectly — window unchanged at **[0.04415, 0.04495]** — while
      `Jones et al_2010` also orders all **six** of its layered pages perfectly, with a window of at
      most **0.0137** (**0.0008** if its single lost word counts). ⛔ **But the sharp result is that
      `Riesman - 1954` has NO window: its p18 at 0.0676 loses nothing while its p16 at 0.0565 loses a
      hand-drawn bracket, so no bar orders that scan's own pages — a within-document inversion, which
      is what actually kills "the useful bar is per scan".** ⚠️ And "disjoint" holds only of
      `Broadhead` against the rest: `Jones` ∩ `Atkinson_1939` ∩ `CAR` ∩ `Xin Qu` is (0.0016, 0.0137].
      No single bar satisfies `Broadhead` and `Jones`:
      at 0.0137 or below, `Broadhead` p2/p4 are protected too, which is **+379,584 B** on two pages of
      thumbs. Byte price of the 13 the seam reaches: 499,203 → 2,065,879 B, **+1,566,676 B, 4.14x,
      120,514 B/page**, of which **94.7% buys nothing a reader would miss** (71.4% counting the word and
      the pen line). Corpus read-only; every image written to scratch under `/tmp`.
- [x] **c28-topink** — **DONE 2026-08-20.** C28's third sub-step: the **twenty** highest-`inkOut` pages
      of the 41 that were left — the twelve highest across eleven never-read documents, plus the completion
      of `Ford_1941_Speech_` (6) and `Stanford_1891_…opening day speech` (4), because a whole document is
      the only way to ask whether a bar orders that document's own pages. Eleven invocations, `rc=0` on
      all, `INKDUMP` 7 files per page with none missing on all 20 (140 files), and `inkOut` / `layered` /
      `extent` reproduce `INKBAR-2026-08-19.tsv` digit for digit on all 20 rows (by script). All twenty
      flipped verdict, so unlike sub-step 2 every one has both a byte price and a render pair.
      **8 of the 20 lose content.** `Herbert Marks papers` p11 loses the typescript line
      `City of Seattle` and the word `etc.` (59 out-of-stencil marks on the page);
      `_1958_Executive Pay` p3 loses **two lines** of 1958 magazine prose and p5 **one**;
      `Merriam_1913` p2 loses a word of body text; `Ford_1941_Speech_` p6 loses the **page folio `-6-`**
      and p1 a **pencilled marginal annotation**; `_1939_Former students` p6 loses a **handwritten
      signature**; `Doermann_1967` p21 loses a **hand-inked margin number**. Three of those classes are
      new to the campaign (a folio, a pencil annotation, magazine body text). The other twelve lose
      platen strips, a gutter shadow, column rules, a photograph's frame, stamp arcs and specks.
      ⛔ **THE RESULT IS THAT THE BAR PROTECTS THE WRONG END OF ITS OWN RANGE FIRST.** Sorted by
      `inkOut` the twenty read `n n n n L L n n L L L L L L n n n n n n`: the eight losers span
      **[0.0051, 0.0165]**, with **four non-losers above that span, six below and two inside**.
      `pageIsAllText()` protects a page exactly when its `inkOut` is at or above the bar, so the four
      pages **of the 41** carrying the MOST ink outside the recognised words are the first four any bar
      protects and **not one of them loses anything**.
      ⚠️ **Two claims this sub-step RETRACTED after the review of its own diff — do not re-derive
      them.** (a) "A contiguous middle band, a stronger refusal than sub-step 1's interleaving": the
      set is not contiguous (`Ford_1941` p3 and `Stanford_1891` p3 sit inside it losing nothing), and
      the "six below" half is a **selection effect** — all six came from the two documents completed
      for convenience, and the twelve the stated rule chose read `n n n n L L n n L L L L`, four
      non-losers above every loser and NONE below, which is sub-step 1's shape in a fresh population.
      (b) "It weakens the bar-overpays half": that compared **37.6% over 14 pages** against two
      **whole-sample** figures. Like for like the twenty read **54.2%** against 57.4% (sub-step 1) and
      56.6% (sub-step 2) — flat — and on sub-step 3's own narrower basis sub-step 2 reads 50.7%.
      ⛔ **The steepest-RATIO page buys nothing, for the third time**: `1976 - Regis McKenna Papers` p4,
      **+350,632 B at 7.89x** (steepest in the campaign), 13 out-of-stencil components at
      `area-threshold=400` (8 at 800, the sensitivity it was first measured at) — platen/binding
      strips, a page corner and a staple shadow, no type. Joins `RIESMAN_1942` p10 and
      `Riesman - 1954` p18 **on ratio only**: ⚠️ it is not the dearest of the twenty, `Doermann_1967`
      p21 is (+361,465 B) and that page loses a hand-inked margin number.
      All twenty: 861,180 → 3,892,140 B, **+3,030,960 B, 4.52x, 151,548 B/page**; a bar protecting
      every loser is **+2,225,619 B** over 14 of them.
      ⚠️ **Two instrument corrections, the first of which voided the locator's own first run.**
      (1) The `ink AND NOT dilate(stencil)` map must be **INTERIOR-cropped — both images, not just the
      map** — because `inkOutsideText` walks only x ∈ [w/16, w−w/16), y ∈ [h/16, h−h/16) and divides by
      interior ink. Uncropped the fraction reads 0.4479 on `Ford_1941` p1 against an `inkOut` of
      0.0051, and the worst *ratio* is **256x** (`Stanford_1891` p4). Cropped, the twenty read
      **0.56x–16.0x**. ⚠️ Sub-step 2's numbers were already interior, so its 0.97x–19.4x band stands;
      only its published shell recipe omitted the crop, and cropping the numerator alone understates by
      1.8x. Six of the twenty read below 1.0 and **why is not established** — the erosion, the Otsu
      implementation and the dump's stencil being mask ∧ region are three candidates, none isolated.
      (2) The locator's *fraction* interleaves as badly as
      sub-step 2's pixel count did — `L n n n L n n n L L L L L n n L n n n n` — the third measured
      refusal of a scalar and the first on the fraction form.
      Every LOSS settled by a four-row 1:1 crop (source / **stencil** / background at the bar /
      background as shipped) with rects from connected components rather than by eye; tight-rect stencil
      ink in the lost rect **0.00%–6.42%** on eight of the nine marks against 7.80%–33.8% on the
      adjacent surviving line, `Merriam_1913` p2 the weak ninth at 15.7% and resting on its crop.
      ⚠️ Three of the twenty non-losers rest on the map alone with no 1:1 crop (`_1967_Ampex` p1,
      `UN-OCred` p7, `Stanford_1891` p3); `Ford_1941` p3 was the fourth until the review pointed out
      that its verdict carries the within-document argument, and it was then cropped — its largest
      out-of-stencil mark is the curled sheet's own edge shadow, typescript crisply in the stencil.
      Corpus read-only; all 140 dumps, maps and crops written under `/tmp`.
      (context: BUGS.md C28)
- [x] **c28-last21** — **DONE 2026-08-20, and it CLOSES C28's question 1.** C28's fourth sub-step: the
      last **21** of the 73 — the 21 sub-step 3 left, **not** "the 21 lowest": the two sets interleave
      over ranks **15-26** because sub-step 3 completed two documents for convenience, and one of the
      six pages that puts there — `Ford_1941` p2 — ties `Williams_1958` p1's printed 0.0023 and loses
      nothing. `inkOut`
      0.0000-0.0041, 15 printing 0.0000, in six
      documents. 8 + 24 + 20 + 21 = 73, so every page still shrunk at the shipped bar has been rendered
      at both factors and read. **2 of the 21 lose content** — the words `their education,` and `but`
      on `Williams_1958_DEMOCRACY OR MERITOCRACY` p1, a 1958 Manchester Guardian sheet, at `inkOut`
      **0.0023** (illegible as shipped, legible in the at-bar composite, and the two rects hold
      **1,212 of the 1,521** px the map flags in components of ≥8 px — the page-wide count is 1,544 and
      the interior one 1,493, three populations the entry distinguishes); and a **pencilled annotation
      on `_1939_Former students` p2 at an `inkOut` that prints 0.0000**, which the Otsu map is blind to
      and the adversarial review of the diff found with an `-lat 25x25-8%` map. **Over the 73 that is
      16 losing content, 11 type and 5 hand-made** ⚠️ (12 + 5 as of 2026-08-21, one page in both — `c28-shapeterm`), and a campaign total of **86 rendered, 24 losing
      content**.
      ⛔ **THE RESULT IS A LOSS ON A PAGE NO USABLE BAR CAN REACH**: p2's `inkOut` prints 0.0000 and its
      `barDelta` is `same`, so production's own first term is blind to exactly the ink that is lost.
      ⚠️ That bounds `inkOutsideText` to [0, 1e-5) rather than proving it zero — and neither reading
      leaves a shippable bar (at exactly 0 the strict `<` means only a bar of 0 protects it, and that
      makes `pageIsAllText()` false on all 16,987 pages — the shrink off corpus-wide rather than on the
      73 it currently reaches; if positive, the bar is under 1e-5 against a shipped 0.045). Sorted
      by `inkOut` the twenty-one read `n n L n n n n n n n n n n n L n n n n n n`, but the second `L`'s
      rank is **undetermined** — 15 of the 21 tie at a printed 0.0000.
      ⚠️ **A first draft of this box claimed "44 of the 73 sit strictly below the losing page and not
      one loses anything"; the review refuted it from the entry's own sub-step 2 table** —
      `Jones et al_2010` p2 loses a word at 0.0008. ⚠️ **A second draft then said "37 lose nothing",
      forgetting that this sub-step's own `_1939` p2 is itself one of the 44**; of the 44, **2 lose
      content, 1 degrades a hand-drawn mark, 5 blur a footnote rule and 36 lose nothing.**
      ⚠️ **The "same scan, same recogniser" heuristic this box recommended returned 1 of the 7 pages it
      named** (`_1939_Former students` p2; the other five `_1939` pages and `Herbert Marks papers` p12
      lose nothing) — worth something, but not a filter.
      ⛔ **The map's fraction is refused again, from the top this time — the same third refusal in a
      fresh population**:
      `Herbert Marks papers` p12 holds the highest out-of-stencil fraction of the 21 — 0.04775, 37x the
      losing page's and **11.65x its own `inkOut`** — and loses nothing, because a pale typescript
      leaves the page-wide Otsu a rim on every glyph that the Sauvola stencil does not have. Its 209
      components have a largest of **49 px**: no type-shaped mark at all. `frac`/`inkOut` over the
      campaign's cropped maps now spans **0.00x to at least 35x** — the table's 53.94x is arithmetic on
      an `inkOut` printed to 4 dp, so the true ratio is somewhere in (35.9x, 107.8x].
      **Two corrected figures**: **25 of the 73**, not 27, cannot be priced through the seam (7 of these
      21 flip, 14 do not; `_1939` p14 prints `0.0000` and flips); and the 7 priced pages cost
      **377,587 -> 1,684,507 B, +1,306,920 B, 4.46x, 186,703 B/page**, of which **65.5% buys nothing** —
      the worst overpay of the four sub-steps (57.4% / 56.6% / 54.2% / 65.5% on the same basis).
      ⛔ **FOUR INSTRUMENT FACTS, one of them a slip made here and one a missed loss.** (0) **The map's
      page-wide Otsu is blind to pale pencil on a shadowed sheet** — on `_1939` p2 it reads 44 px and
      1 px in two rects where `-lat 25x25-8%` reads 2,069 and 1,371, and that is how a real loss was
      nearly filed as "nothing". Otsu's two failures are opposite: a rim invented on a pale typescript,
      real pale ink missed on a shadowed sheet. (1) ImageMagick's
      `-morphology Erode Disk:0` is **radius 4**, not the identity: `Guilford` p1 reads 0 px at
      `Disk:0`, **133 at `Disk:1`**, 15 at `Disk:2`, 0 at `Disk:3`, and
      `-define morphology:showKernel=1` prints `Disk:0` as 9x9+4+4 — so start a sweep at r=1. (2) A connected-component rect taken off the **interior-cropped** map needs
      `+mx+my` to reach page coordinates and one off the **whole** map needs nothing; the offset was
      added to both here and produced a confident negative 200 px away from any flagged ink. Count the
      white pixels in a rect before believing it (`400x60+690+1478` holds 1,212, `40x40+1050+1700`
      holds 0). (3) A better eye-free cross-check than the entry's earlier one: **stencil ink over
      SOURCE ink in the same tight rect** — 0.21 and 0.17 on the two lost rects against 1.09 and 1.06
      on their own lines' survivors — but it is a within-page contrast, and over those twelve rects it
      does **not** interleave, so any corpus bar on it would sit in an untested 0.21-to-0.40 gap
      established on two pages (`Herbert Marks` p12's bands read a uniform 0.40-0.47 and lose nothing).
      Reproduction: 21/21 rows reproduce `INKBAR-2026-08-19.tsv` on `inkOut`, `layered` and `extent`,
      checked by script; six invocations, `rc=0` on each, 147 dump files with none missing; source and
      stencil sizes asserted equal per page. Corpus read-only; every dump, map and crop under `/tmp`.
      (context: BUGS.md C28)
- [x] **c28-report** — **DONE 2026-08-20.** C28's question 5, invariant 1's other half: a page could
      lose seven lines of prose to the 8x shrink and the run report said nothing. `Flattener.MRCLayers`
      now carries `shrunkAsAllText` and `inkOutsideText` out of the layering decision;
      `OCRModel.shrunkTextPageSummary` turns the adopted pages into one sentence; a new
      `shrunkTextPageNote` callback puts it in the log, which `RunReport` copies verbatim.
      **Four decisions, each with the campaign behind it, and do not re-litigate them without reading
      `#### The report, SHIPPED`:** (1) every accepted page is named, **no bar on the fraction** —
      sorted by `inkOutsideText` the losers and the non-losers interleave over all 73, and
      `_1939_Former students` p2 loses a pencilled annotation at a fraction printing `0.0000`, so any
      filter drops a known loser; (2) collected **after** the `after < before` adoption guard, because
      a layering larger than its JPEG is discarded and that page loses nothing; (3) emitted on the
      **success path only**, beside `tookJBIG2Route()`, for A9.2's reason — a document that fails its
      page-count gate publishes nothing to describe; (4) **not** a failure, because 57 of the 73 do
      not lose content (73 − 16 — ⚠️ *not* the count that lose nothing at all, which is at most 51).
      ⛔ **The short circuit is load-bearing and there is a check on it.** `pageIsAllText()` sits behind
      `!keepEveryPixel` so `PhotoDetail.maximum` does not pay a histogram pass over up to 100
      megapixels — a defect `mrcLayers`' own comment records being found and removed once. The
      measurement is assigned *inside* the closure and `inkOutsideText` is `nil` at Maximum, measured.
      **Eleven checks**, folded into the two `c26Layers` calls that block already makes rather than
      taking their own — two check the flag in both directions (only the positive one also asserts
      `backgroundWidth`; the negative one carries it in its message), two pin
      the fraction against an independently computed `inkOutsideText`, one pins the Maximum `nil`, six
      exercise the summary. ⚠️ The *width* is not independent of the flag (both descend from one
      `allText` local), so that pair catches a flag wired to a constant, not a wrong verdict. Watched
      failing against a two-part mutant (flag hard-wired `false`, the measurement hoisted out of the
      closure) driven through a probe on the suite's own C26 fixture: the positive-direction flag
      check and the Maximum-`nil` check both go red; the negative-direction one does **not**.
      ⛔ **What no check reaches: the wiring itself**, because **no test runs a document through
      `makeSearchablePDF` down the MRC route at all** — the three `.mrc` tests call `mrcLayers`
      directly and assemble by hand, so the whole adoption loop including `after < before` is
      uncovered. Pre-existing and wider than this fix. The missing half is the *routing* one: the
      suite already has a fixture `pageIsAllText()` accepts (`r50text`), but none known to reach the
      picture route and then be read as all text — and `Mode.grayscale`, the obvious shortcut, is
      refused by `canUseJBIG2` and takes the Flate route.
      (context: BUGS.md C28)
- [x] **c28-halfres** — **DONE 2026-08-20.** C28's question 2, first half: does the same loss reproduce
      at **1/2**, the factor every layered page that is NOT read as all text keeps on the default Photo
      detail? **No.** Sixteen of the 109 such pages were rendered and read at 1:1 against a 1/8
      reference on the same rect from the same `mrcLayers` call (ten of the sixteen; the other six
      cannot have one), and **no content loss was found at 1/2 in any window read** —
      including the two on which the same ink WAS destroyed at 1/8 before the 2026-08-19 bar move. So
      C28 stays bounded to the 73 pages
      at 8x/16x rather than widening to 182. Population recomputed from `INKBAR-2026-08-19.tsv` rather
      than quoted (`barVerdict` picture **109**, all-text **73**; at the old bar 93 / 89): all **6**
      pages below the bar that are `picture` only because `paleDrawing` refuses them, **2** of the 16
      the bar move rescued as positive controls, **8** of the other 87, spanning `inkOut` 0.0902–0.9949.
      13 invocations, `rc=0` on every one, `INKDUMP` **7 files on all 16 pages**, and `inkOut`, `extent`
      and `route` reproduce the committed sweep **digit for digit on all 16 rows**.
      ⛔ **THE SHARP RESULT IS A PROCESS ONE: THIS SUB-STEP'S OWN DRAFT TRIED TO RETRACT A CORRECT
      CLAIM AND ITS ADVERSARIAL REVIEW REFUTED IT.** The draft measured one rect of `Xin Qu et al_2018`
      p20's matrix (top-left values, stencil-over-source ink **0.98x** — stencilled), concluded the
      campaign's "thirteen values" wording was misattributed, and edited six places plus a queued
      instruction to change a **correct** code comment. The matrix's LAST column reads **0.0000** over
      `62x233+741+378` and holds **1,375 of the page's 6,233** out-of-stencil map pixels — thirteen
      values, exactly as published, legible at 1/2 and a smear at 1/8. All six edits are reverted.
      **A stencil-ink ratio is a claim about its rect, not about the page**, and the stencil's coverage
      of one table is not uniform (0.98x top-left, 0.00x last column, same matrix). The related trap is
      real and stays recorded: `fillHoles` leaves stencilled ink in the background as a pale ghost, so
      comparing the two BACKGROUNDS makes a ghost's disappearance look like a loss — and a
      ghost-only rect looks like safety while the page loses content 421 px away.
      **Two negative controls, both fired.** The 6 pale-refused pages cannot be flipped by any bar
      (`noPaleDrawing` is false), so their two backgrounds are byte-identical and their two rows are
      visually identical — the pipeline checking itself. And on the two control pages the byte columns
      reproduce the committed sweep **with the columns swapped** (this run's `layered` = the file's
      `layeredAtBar`), which is the documented consequence of the 2026-08-19 bar move.
      ⛔ **TWO SILENT INSTRUMENT DEFECTS, BOTH IN THE SHELL, both worth not repeating.** (1)
      `%[fx:int(mean*w*h/255+0.5)]` is **not** a pixel count — fx `mean` is already normalised to
      `[0,1]`, so every count read **255x low** (a 3778x2252 page reported 3,975 ink pixels) while every
      RATIO stayed right, which is why one read did not catch it. (2) `-connected-components:verbose`
      prints the mean colour as `gray(255)`, never the word `white`, so `awk '$NF=="white"'` matched
      **nothing on all 16 pages** and read as "no component above the threshold" — a filter that cannot
      match is a check that cannot fail.
      ⛔ **What is NOT done: 1/3.** `PhotoDetail.smallest` is the factor-3 case and `score-text-route`
      measures the default, so nothing here says what Smallest does; that is the parent box's **2b**.
      And 16 of 109 is a sample, stated as one. ✅ **1/3 IS DONE 2026-08-21 — see `c28-thirdres` below,
      and it DOES reproduce**, which disturbs nothing measured here.
- [x] **c28-thirdres** — **DONE 2026-08-21, and it CLOSES C28's question 2.** The second half of
      question 2: does the loss reproduce at **1/3**, `PhotoDetail.smallest`? **Yes, on 1 of 16 pages.**
      ⛔ **`Xin Qu et al_2018` p20 loses the correlation matrix's last column** — thirteen values legible
      in the 460 px background Balanced gives it and unreadable in Smallest's 307 px one; at zoom 8
      `−0.130*` reads `−#.1##*`, the `0` a solid blob and `30` not resolving into two glyphs. Same
      thirteen values C26 sub-step 4 found destroyed at 1/8, so that page is destructive at 1/8 **and**
      at 1/3 and safe only at 1/2 — one step of the setting. Two more of the sixteen are **degraded and
      still legible** (`_1973_CAR` p4's unrecognised prose lines over two windows; `Jones et al_2010`
      p12's table rule, darkest pixel 25 in the source → 56 at 1/2 → 136 at 1/3 against paper at ~250,
      continuous throughout) and five read clean — the three `1954 - Why` cartoons whole, `Riesman - 1954`
      p16's pen bracket and both tick marks unbroken, and a **whole line of unrecognised typescript** on
      `Atkinson_1939` p2 fully readable.
      ⛔ **THE ORDERING CLAIM THIS BOX FIRST MADE WAS RETRACTED BY THE REVIEW OF ITS OWN DIFF, SAME DAY.**
      Sorted by source width the three clean `1954 - Why` pages (1,224 px) sit BETWEEN the two degraded
      ones (1,208 and 1,240), so width interleaves the verdicts exactly as `inkOut` does — a FOURTH
      refused scalar, not a new ordering; and the quantity read was source pixel WIDTH, never
      `rebuildDPI`. ⚠️ Also retracted: **8 of the 16 have a 1:1 reading, not 16**, and these sixteen are
      not the 1/2 sub-step's sixteen (overlap two). Read the entry's
      `##### ⛔ RETRACTED BY THE ADVERSARIAL REVIEW OF THIS DIFF` before quoting anything below.
      The withdrawn claim, kept so it is not re-derived: The sixteen span 921–5,129 px of source width; the loser is the
      narrowest, and the next two narrowest (`1944_Options` p1 at 1,208, `Jones` p12 at 1,240) are the
      two that degrade. `Flattener.rebuildDPI(of:)` already computes it on every page. Untested as a bar
      — one page is not a calibration — and it would be this entry's fourth signal class.
      ⚠️ **AND A DRAFT OF THIS SUB-STEP WAS ON COURSE TO CONCLUDE "NO LOSS AT 1/3" OFF ITS FIRST FIVE
      PAGES**, every one of which is clean. What overturned it was choosing the sixth page by narrowness
      instead of by `inkOut`. If you extend this, sort by source width.
      **Byte price**: over the sixteen, 3,804,222 B at 1/2 → 2,459,319 B at 1/3, **−1,344,903 B,
      0.6465x** — and ⛔ **the page that loses content saves 17,705 B, the LEAST of the sixteen**,
      while `RIESMAN_1942` p10, whose only out-of-stencil ink is a pale scanner-edge strip, saves
      240,578 B. Cost and harm are anti-correlated, which is `#### And the same bar overpays` again.
      ✅ **Two negative controls.** (1) An all-text page is **byte-identical** at the two settings —
      `Guilford_Psychometric Methods` p1, all four dumped files identical, background 115 px both of a
      920 px source, `layered` 29,174 B on both rows — because `bgFactor` is `max(caller, 8)`. That is
      what bounds this to the 109 rather than the 182. (2) The 1/2 total reproduces
      `INKBAR-2026-08-19.tsv`'s committed `838,569 -> 3,804,222 B` for these same sixteen pages digit
      for digit.
      **The seam**: `PHOTODETAIL=maximum|balanced|smallest` on `Tools/score-text-route.swift`, from
      `Prefs.PhotoDetail.downsample` and never a literal; **background only**, because `Model.swift`
      leaves `foregroundDownsample` at 4 at every setting; `PHOTODETAIL=maximum` **with `INKBAR` exits
      2** (`keepEveryPixel` makes every bar inert, so every row would print `same`); non-default
      settings suffix dumped filenames `-d<factor>` so two settings in one directory cannot overwrite
      each other; and the file's replica of the shipped guard now mirrors `keepEveryPixel` too, which it
      did not need to while the factor was always 2. **Three self-test checks, all three watched
      failing** — the load-bearing one pins `PhotoDetail.balanced.downsample == mrcBackgroundDownsample`,
      i.e. that **every row this tool has ever printed, all 2,129 of `INKBAR-2026-08-19.tsv`, is a
      Balanced row**. Nothing else in the tree said so.
      ⚠️ **Instrument facts, and the out-of-stencil map is worse than the last sub-step recorded**: its
      largest component was a **scan artefact on 5 of the pages tried** — fingertips holding the book
      open (`Broadhead - 1994` p8), the gutter shadow (`Riesman - 1954` p16, which nearly cost that
      page's verdict), page edges (p8, p18), `fillHoles` ghost residue (`1944_Options` p1) — and on
      `_1973_CAR` p4 it found **no component at all** at `area-threshold=150` until a
      `Close Octagon:3` + `Dilate Rectangle:9x1` joined letters into lines, because unrecognised prose
      is scattered letter-blobs. **Locate lines, not letters.** A 1/2-against-1/3 difference map is a
      usable **locator** and a refused **verdict**: it ranks `_1973_CAR` p4 top at 1.2527% (legible) and
      the only real loser SIXTH of sixteen at 0.1825%. `magick montage` dies with
      `unable to read font ''` here — use `+append`/`-append`. And ⛔ **swiftc rejects this tool unless
      the copied file is named `main.swift`**: 19 `statements are not allowed at the top level` errors
      that look like a build problem, which is how all three mutants failed on the first attempt and
      would have counted as killed.
      ✅ **DECIDED by the owner 2026-08-21, so this is no longer left**: `PhotoDetail.smallest`'s blurb
      promised photographs at a third resolution *"look noticeably soft up close, though nothing is lost
      from them"*, which p20 makes false. The clause is DELETED and nothing replaces it; the exact
      replacement text, the comment that goes with it and the reason it must ride a suite-paying commit
      are in the `C28` box above, which is where the session doing it is already reading.
      (context: BUGS.md C28 `#### The same loss at 1/3, RENDERED over 16 of the 109`)
- [x] **c28-shapeterm** — **DONE 2026-08-21. C28's question 3 has its first measurement and a shape term
      SEPARATES.** Do not re-run it. `Tools/score-shape-term.swift` is new: it drives production
      (`renderGrey`, `otsuThreshold`, `sauvolaMask`, `textRegionMask`, `inkOutsideText`) and adds only a
      run-based connected-component pass plus a shape rule whose five numbers are **ratios against the
      page's own recognised text** — the stencil's own components are the calibration, so no constant is
      chosen for a corpus. Over **13 labelled pages** the **count of accepted text lines** is `≥ 1` on
      **6 of 6** pages measured to lose typeset content and `0` on **6 of 6** that lose nothing: the
      first quantity in this entry that does not interleave, after `inkOutsideText`, `extent`, the
      out-of-stencil pixel count, the source width and (now) `txtShare` were all refused.
      ⚠️ **Read `lineN`, never the share** — `Riesman - 1954` p16's drawn bracket reads `txtShare`
      **0.0173** against p18's **0.0500** on the same scan, so a bar on the share inverts that pair.
      ⛔ **The one miss is the class, not a page**: a rule calibrated on type reads 0 on a hand-made
      mark, measured 1 of 1 (2 of 2 after this commit's own review), and the campaign has 6 such pages —
      so whatever ships on this protects prose and table data and must SAY what it does about the marks.
      ⛔ **This was published as blindness "by construction" and `c28-pictures` REFUTED it the same day**:
      the term fires 17 and 11 groups on a pen ornament, so it is unreliable on hand-made marks in
      **both** directions. Read that sub-box before quoting this one.
      ⛔ **And it is not validated**: 8 of the 73 plus 5 of the 16 C26's bar move rescued (so 5 of them are not degraded in production today), a labelled convenience sample, 4 of its 6
      non-losers pages of one scan, and **no plate, halftone or line drawing in the sample at all** —
      the class `textRegionMask` exists to keep out. "Reads 0 on scanner edges" is not "reads 0 on a
      picture", and that is the next measurement rather than a caveat to note.
      ⛔ **THAT MEASUREMENT RAN 2026-08-21 AND THE ANSWER IS NO — see the `c28-pictures` sub-box
      below.** `lineN` is ≥ 1 on **6 of 10** picture pages and every accepted group is a picture read
      at 1:1. Do not re-run it; and do not build on `lineN` alone without reading that box's bound (all
      ten are already `barVerdict=picture`, so the cost of those false positives is zero, at a **1.10x**
      margin) and its warning that `lineShare` is a post-hoc fit driven by its own denominator.
      ✅ **It also settles `score-text-route`'s open instrument question** (its header said the shell
      map's 0.56x–16.0x spread against `inkOutsideText` was "not established", naming three
      candidates). This tool holds `region` itself, so its map IS the guard's set — asserted on every
      printed row, exit **6** otherwise, and `inkOut` reproduced `INKBAR-2026-08-19.tsv` on all 13
      rows. Measured: the dumped stencil standing in for `region` inflates the fraction
      **1.00x–3.17x** (5 of 13 read exactly 1.0000x, so the Sauvola rim is per-page), the published
      `Disk:3` dilation lands **0.721x–1.007x** (worst on the page of small numerals), and
      ImageMagick's `-auto-threshold OTSU` is **identical to `Flattener.otsuThreshold` on 13 of 13**
      pages over a 69-grey-level range. So the recipe is bounded on pages with ink to divide by; its
      extremes all sit on `inkOut` 0.0001–0.0051 and a small-denominator artefact is the obvious
      unmeasured candidate. Do not read this as retracting sub-step 3's figures.
      ⛔ **It corrected the register from the crops**: `Atkinson_1939` p3's largest accepted group is
      not the signature but two lines of **typescript** sub-step 1's inventory never listed, illegible
      in that page's shipped background and legible in its un-shrunk one — so the campaign's split is
      **19 type and 6 hand-made over 24 pages with one page in both**, not the exclusive 18 + 6, and
      the 73's is 12 + 5 over 16. Both page counts are unchanged. Corrected in nine places; the review of this diff found five more that still said 18, 11 or 10 and they are corrected too.
      ⚠️ **Question 4 is still owed and this makes it cheap to ask, but the numbers here are AREAS and
      not bytes**: `linePx` is 0.12%–1.04% of the page on the six losers (7,533 px of 4.18 Mpx on
      `Broadhead - 1994` p3; 21,924 of 2.10 Mpx on `_1973_CAR` p4). Bounding boxes are bigger and JPEG
      is not linear in area. T15's 1.33x is the stencil total and 1.07x the page total; neither is this.
      Instrument notes: `--self-test` is 5 checks, **all watched failing at `-Onone`** with one
      mutation each (4-connectivity for 8, the interior window removed, `lineMinimumMembers` 4→3), and
      the map is built by **one function shared by `main` and the check** because the first draft built
      it inline in both — a check that could not have failed if `main`'s copy drifted. `SHAPEDUMP=`
      writes four PNGs a page, **all in the page's own frame and never interior-cropped**, which is
      what makes the coordinate-frame trap sub-step 4 recorded unreachable. `lineMinimumMembers = 4`
      costs content, measured: it drops `0.09`, `0.04` and the diagonal `1` from `Xin Qu` p20's
      thirteen values (three components each), so the term names 10 of the 13 — ⚠️ this box, and
      `BUGS.md`'s own positive-control bullet, both said "two" while saying "10 of 13", which does not
      add up; corrected 2026-08-21. And nothing is wired — `Sources/` is untouched.
      (context: BUGS.md C28 `#### A shape term, MEASURED over 13 labelled pages`)
- [x] **c28-pictures** — **DONE 2026-08-21. C28's question 3b: the shape term ERRS IN BOTH DIRECTIONS
      on pictures.** Do not re-run it. `Tools/score-shape-term.swift` unchanged, run over **10 picture
      pages in four documents** (a fifth contributed only a SKIP); result committed as
      `SHAPETERM-PICTURES-2026-08-21.tsv` (10 measured rows + 1 SKIP, the section's 22 columns with
      `document` and `arm` prepended).
      **`lineN` is ≥ 1 on 6 of 10** and none of the six accepted groups is type — halftone screen dots
      (`Ibson_2006` p61), photograph grain inside a plate (`Ibson_2006` p122, 12 groups), a pen
      ornament's feather strokes (`1881 - Harry Wilcox` p2 and p6, 17 and 11 groups), and **10,438 px of
      page-wide-Otsu speckle in a featureless grey endpaper** whose rect reads mean 107.5 / sd 2.88
      against a page Otsu of 107 (`Riesman - 1954` p2).
      ⛔ **BUT THE RESULT THAT MATTERS IS THE OTHER DIRECTION: it reads 0 on TWO pages whose content loss
      this register measured at 1:1.** `1954 - Why` p6 and p7 are C26's own founding cartoons; over each
      page's published drawing rect the map holds 4,467 px (92% of that page's `outPx`) and 7,057 px
      (100%), `textish` accepts 372 and 785 of them, and **0** reach a line group. So the miss is
      `lineMinimumMembers = 4` / `lineGapFactor = 3.0`, not the component test — and **p4's single group
      is a HIT on its lost cartoon**, `27x17+1121+685` inside the published `254x240+970+595`, so it must
      not be counted as a false positive.
      ⛔ **AND THIS REFUTES "blind to a hand-made mark by construction"**, in the exact case the previous
      review predicted (*"four blobs of a broken pen stroke on a diagonal"*): 17 and 11 groups on a pen
      ornament. Measured, the term reads 0 on **four** hand-made marks (p16's bracket, `Atkinson_1939`
      p3's signature, `1954 - Why` p6 and p7) and fires on **three** (`Wilcox` p2/p6, `1954 - Why` p4).
      ⚠️ **The phrase survives in `Tools/score-shape-term.swift`'s header and `Tools/README.md`** — both
      match the pre-commit suite regex, so a docs-only commit cannot carry them; they are owed on the
      next suite-paying commit **alongside the settings blurb** in the `C28` box above.
      ⛔ **On `Wilcox` p2 the term is wrong in both directions**: a `620x220+2180+540` crop of
      `-lines.png` over the ribbon's hand-lettered *"Harry W. Wilcox"* holds **0** accepted pixels while
      1,694 land on the decoration page-wide. ⚠️ That crop covers one of the page's **two** lettered
      ribbons, so the direction is measured on one word. And `Ibson_2006` p122's real caption *was*
      recognised — its rows hold 0 map pixels — so none of the twelve groups is on it; that whole-page
      mask is the location control.
      ⛔ **Four more scalars refused.** `glyphN` interleaves (2,468 fires, 2,255 does not; 68 fires, 54
      does not), so **"too little recognised type to calibrate on" is NOT the mechanism**; `txtShare`
      interleaves with the highest of the ten reading 0 (⚠️ a draft said it "inverts at both ends" — the
      two *lowest* also read 0, so that ordinal was wrong and was corrected before commit); absolute
      `linePx` 10,438 on endpaper speckle exceeds the 7,533 px of `Broadhead - 1994` p3's two genuinely
      lost prose lines; `topLine` width 202 px exceeds `Xin Qu` p20's 95 px (⚠️ and that 95-px group is
      **not** one of the thirteen matrix values — its rect is disjoint from the published
      `62x233+741+378`).
      ✅ **THE BOUND, AND IT COVERS ONLY ONE OF THE TWO SEAMS THIS ENTRY NAMES.** All ten pages are
      `barVerdict=picture`, so a term wired as a second condition inside `pageIsAllText()`'s true branch
      (`inkOut < 0.045 AND lineN == 0`) is never consulted on them — byte cost zero, **derived from the
      sweep's verdict column rather than measured, because nothing is wired**, and on a **1.10x** margin
      (lowest `inkOut` of the ten 0.0493 against the shipped 0.045). ⛔ **Under `textRegionMask` — the
      seam question 3's own sentence names — there is NO bound**: it is called unconditionally on every
      layered page (`Sources/Flattener.swift:2696`), so those six pages would admit halftone dots,
      photograph grain and pen strokes into the 1-bit JBIG2 stencil, which is R57's failure mode and
      verbatim what that function's comment exists to prevent. **Unpriced, and now the more expensive of
      the two seams.**
      ⚠️ **The absence that would bound the sub-bar population is over the wrong set**: a plate can
      survive 8x (this entry's own p6: an 8x blur keeps solid black), so a plate on a sub-bar page would
      never appear among the 73's 16 losers, and the 57 non-losers were never inventoried for plates.
      **Unmeasured, not empty.** ✅ **INVENTORIED 2026-08-22 and it holds no printed plate** — see the
      `c28-subbarpix` sub-box: 0 printed plates, 0 printed figures, largest non-text mark ≤3% of a page.
      ⛔ **But only THREE of this box's four substrates are absent** — halftone dots, pen-ornament strokes
      and printed photograph grain occur nowhere in the 73, and **continuous tone does**, as camera
      photography: `1976 - Regis McKenna Papers` p4's `txtShare` is 0.2157 with `lineN` 0.
      ⚠️ **`lineShare` is the only column that separates, and it is the SEVENTH SHARE in a register that
      has refused six** — 0.0002–0.0099 on the six firings, 0.0000 on the six labelled non-losers,
      0.2332–0.9937 on the six labelled type-losers, so a bar in (0.0099, 0.2332) separates 22 of the
      **23** pages the term has been run on. Recorded because it is what the columns do, **not** as a
      candidate: it is `txtShare` with a narrower numerator and the same denominator; it separates *type*
      loss and leaves **four known content-losers** on the safe side (p16's bracket at 0.0000 is the 23rd
      page, and `1954 - Why` p4/p6/p7 read 0.0099 / 0.0000 / 0.0000); it was chosen after seeing the
      data; 7 of the 10 pages read `inkOut` > 0.9 so any numerator is a small share by construction; and
      the case a wiring would meet — a plate in the map of a page otherwise read as all text, below the
      bar — has **zero pages** here.
      Instrument controls: `inkOut` reproduces `INKBAR-2026-08-19.tsv` on **10 of 10** rows, `mapFrac ==
      inkOut` and `stenFrac >= mapFrac` on all ten (exit 6 never fired, `rc=0` on all five invocations),
      `--self-test` 5/5 on the binary that produced the rows. ⚠️ Traps met: the first cross-check read
      **0 of 10** because the lookup keyed `"p" + page` against a column already reading `p6` — the
      instrument, not the tool; `magick -threshold 50%` diverges from `linePx` by **1.00x–1.32x** across
      the six firing pages (worst on `Riesman - 1954` p2, 13,781 against 10,438), so use it for "is
      anything accepted in this rect", never as a total; the 3-per-document cap in arm A **never bound**
      (the uncapped top 8 is the same list); and the top row of `INKBAR` by `inkOut` is a page with **no
      recognised words** (`Levy and Temin - 2007` p6, 1.0000 by degeneracy when `region` is empty), which
      the tool SKIPs — so arm A measured 7 pages, not 8.
      ⚠️ **One label in the first draft was wrong and the review of this diff caught it**: `1954 - Why`
      p10 was called a "full-page photograph" on the strength of `tone` 0.992, and the render is a
      near-blank back cover (mean 195.5, sd 24.1) with a boxed "NFI" logo and show-through. **A tone
      fraction is not a picture detector.**
      No `Sources/` and no `Tools/` **code** change, so no mutant and no `fault-inject.sh` case is owed;
      `testdocs/` read-only, artefacts under /tmp.
      (context: BUGS.md C28 `#### The same shape term on PICTURES`)
- [x] **c28-all73** — **DONE 2026-08-21. The shape term over the WHOLE 73-page sub-bar population, and
      question 4's first page-level byte price out of the same run.** Do not re-run either;
      `SHAPETERM-73-2026-08-21.tsv` (73 rows, 27 columns) and `BUGS.md` C28
      `#### The same shape term over ALL 73` carry both. **The population is machine-readable** — the
      rows of `INKBAR-2026-08-19.tsv` with `verdict=all-text` AND `barVerdict=all-text` are exactly the
      73 the four sub-steps rendered and labelled — so the convenience sample was replaced by the
      population rather than extended. Constants unchanged, same binary, **65 of the 73 never measured
      before**, and the eight calibration pages are marked `sample=calibration` in the TSV.
      **Result**: `lineN` ≥ 1 on **12 of 12** pages that lose typeset content (8 of 8 out of sample),
      **1 of 4** losing only a hand-made mark, **0 of 6** degraded-but-legible, **3 of 51** that lose
      nothing. ⛔ **All three of those firings are the RIM of recognised type** — read at 1:1 from
      `-lines.png` cropped at the group's own rect, they are glyph tops falling outside Vision's word
      boxes on lines that ARE in the text layer (`Herbert Marks` p12 `AGE Corp. - Em…`,
      `_1939_Former students` p9 `am not`, `_1967_Yearly Increase` p1 newsprint ascenders); two of the
      three pages hold only **437** and **381** out-of-stencil pixels page-wide, which is why their
      `lineShare` reads 0.88 and 0.80. ✅ **A signature DOES fire** — `_1939_Former students` p6's only
      group is the cursive signature itself — the **fourth** hand-made mark the term is measured firing
      on (after `Wilcox` p2, `Wilcox` p6 and `1954 - Why` p4) and the second on a page of measured loss. ⛔ **One of the three misses is not the rule's**:
      `_1939_Former students` p2 has `outPx` **0**, an empty map, which is the page-wide Otsu's known
      blindness to pale pencil. The other two are the grouping, not the glyph filter
      (`Doermann_1967` p21 is `txtShare` 0.9946 with `txtN` 4 and no group).
      ⛔ **`linePx` refused a second time and harder**: `Jones et al_2010` p2 is a real loss at 147 px,
      below all three false positives, so no floor removes a rim without dropping a measured loss.
      **Question 4**: the wiring (`inkOut < 0.045 AND lineN == 0`) refuses the shrink on **16 of 73**
      pages — 789,825 → 3,152,450 B, **+2,362,625 B, 3.99x**, 15.5% of it on pages that lose nothing —
      against the cheapest page-wide bar rescuing the same 13 (`inkOut >= 0.0008`), which refuses **41
      of 73**: 1,915,380 → 8,117,445 B, **+6,202,065 B, 4.24x**, **58.5%** of it on pages that do not
      lose content. **38.1% of
      the bytes.** ⛔ Not equal protection — the bar rescues **15 of 16** losers and the term **13**, the
      two extra being hand-made marks at +575,066 B, and neither reaches `_1939_Former students` p2.
      Controls: `inkOut` reproduced `INKBAR-2026-08-19.tsv` on **73 of 73** rows; `mapFrac == inkOut` on
      73 of 73 (exit 6 never fired); `rc=0` on all 22 tool invocations and all 21 byte invocations
      (11 documents in the 16-page arm, 10 in the 25-page one, 19 distinct);
      `barVerdict=picture` on **41 of 41** priced pages with a byte-identical stencil at both bars;
      `--self-test` 5/5. ⚠️ Bytes are at the default Photo detail, page by page through
      `score-text-route`; the *local* variant would be cheaper, so +2,362,625 B is an **upper** bound.
      The three ride-along documentation debts (the settings blurb, the tool header, the
      `Tools/README.md` row) landed on this commit, and the blurb gained a check watched failing.
      ⚠️ Nothing is wired; no mutant is owed. **Next**: ~~the rim fix (subtract a dilated `region`
      before grouping)~~ — DONE: refused as a REPLACEMENT, best-measured as a SECOND CONDITION, see
      `c28-rimfix` — or the `textRegionMask` seam's price.
      (context: BUGS.md C28 `#### The same shape term over ALL 73`)
- [x] **c28-rimfix** — **DONE 2026-08-21, and the answer is TWO answers.** The rim fix the all-73 run
      named — subtract a *dilated* `region` before grouping — is in `Tools/score-shape-term.swift` as a
      **sweep** (`rim1N`/`rim2N`/`rim3N`, radii 1/2/3 in one pass) and was read over the same 73 pages,
      same constants, one binary. `SHAPETERM-RIM-2026-08-21.tsv`, 73 rows, 22 documents, 36 fields.
      **Type-losers firing / non-losers firing: r=0 12/12, 3/51; r=1 12/12, 2/51; r=2 11/12, 1/51;
      r=3 9/12, 1/51.**
      ⛔ **AS A REPLACEMENT IT IS REFUSED. r=1 is the only radius that keeps every real typeset loss, and
      it clears TWO rims of the three while ADDING ONE OF ITS OWN**: on `Xin Qu et al_2018` p28 the rim
      of a recognised `469.` is *three* accepted components at r=0, one short of `lineMinimumMembers`,
      and a 1-px collar splits the middle one (`8x8` → `4x6` + `3x6`) into four — the non-monotonicity
      the tool's comment predicted before the run. ⚠️ `rim1N` is **2** there: two groups are
      manufactured, and only the larger was located and read at 1:1. **The rim that survives every radius
      is `Herbert Marks papers` p12**, still the rim at r=3 (4-px flecks off the tops of `Corp.`, 64 px
      = `rim3Px`, read at 1:1). **And from r=2 it destroys real losses**: `Williams_1958` p1
      (`linePx` 1780 → 1487 → 0), then `Scott_TK` p3 and `Merriam_1913` p2 at r=3.
      ✅ **AS A SECOND CONDITION IT IS THE BEST RULE THIS CAMPAIGN HAS MEASURED**: `lineN >= 1 AND
      rim1N >= 1` reads **12 of 12 type-losers, 1 of 4 hand, 0 of 6 degraded, 1 of 51 non-losers**, on
      **14 of 73** pages rather than 16, and p28 cannot enter it (`lineN` 0 there). Both dropped pages
      are non-losers, so the wiring's price can only fall from +2,362,625 B — ⚠️ a direction, not a
      number. ⚠️ **Post-hoc** and hand bucket unmoved. ⛔ **And RUN on the ten picture pages 2026-08-21
      — it buys nothing there**: see the `c28-rimpictures` sub-box below.
      ⚠️ A **ratio**-scaled collar does not rescue the replacement reading: `Scott_TK` p3 loses its last
      group at 0.375x its own `glyphH` (8) while p12 still fires at 0.6x its own (5) — derived from
      radii 1-3, radii above 3 not run. ⛔ **The first draft of this box said the mechanism was that the
      collar "runs backwards" (smallest type at the false positive, largest at the true positives) and
      the adversarial review refuted it from the same file**: `Scott_TK` p3 is destroyed at `glyphH` 8,
      and `Herbert Marks` p11 is a real typeset loser at `glyphH` 5 firing at every radius.
      ⚠️ **Worse for the LOCAL variant than any boolean shows**: at r=1 `Scott_TK` p3 keeps 278 of 1,796
      accepted line pixels and its largest group MOVES to a different part of the page.
      Controls: all **27** shared columns reproduce `SHAPETERM-73-2026-08-21.tsv` on **73 of 73** pages
      (`lineShare` included); `inkOut == sweepInkOut` on 73 of 73; `rc=0` on 22 invocations;
      `verdict=ok` on every row (identity held, exit 6 never fired); `--self-test` **6/6**, the new
      check two-sided on one synthetic scene and **watched failing on four mutants of `rimSubtract`**.
      ⛔ **One of those four, `radius: r - 1`, passed 6 of 6 until the check gained a direct assertion on
      the collar's WIDTH** (10/20/30 px removed at r=1/2/3) — a collar one pixel small would have
      relabelled the whole sweep by a column. ⛔ **And the review found a real defect in the diff**:
      `SHAPEDUMP`'s new `-rim<r>-lines.png` were painted through the untrimmed map; fixed in the same
      commit and the p12 crop re-read on the fixed build (unchanged, 64 px).
      ⚠️ The first stub did not compile, so it tested nothing and was rebuilt.
      ⚠️ Nothing is wired; `Sources/` untouched, no mutant and no `fault-inject.sh` case owed.
      (context: BUGS.md C28 `#### The rim fix, MEASURED`)
- [x] **c28-rimpictures** — **DONE 2026-08-21, and the answer is that the collar does nothing at all on
      a picture page.** The one run `c28-rimfix` left owed: the rim columns over the same ten pages as
      `SHAPETERM-PICTURES-2026-08-21.tsv`, same five constants, same `rimRadii`, same five
      invocations, from the same binary as the 73-page rim sweep (the tool as committed at `a98fdd0`)
      — ⚠️ **not** the same binary as the pictures file, which had no rim sweep in it at all; that
      difference is what makes the control below span a real code change, and calling it "the same
      binary" was this box's own first-draft error. Do NOT re-run it;
      `SHAPETERM-PICTURES-RIM-2026-08-21.tsv` (11 rows, 33 fields) and
      `BUGS.md` C28 `#### The conjunction on a PICTURE page` carry it.
      **`rim1N == rim2N == rim3N == lineN` on 10 of 10 pages**, and the **largest** accepted-line rect
      (`topLine`, `rim1Top`, `rim2Top`, `rim3Top`) is identical at every radius on all six firing pages
      — ⚠️ the largest and not every one: the tool prints one rect per page, and on `Wilcox` p2 a
      *non-largest* group did change (the removed pixels at x 2596–2598 sit outside that page's printed
      `60x41+2771+1015`). So
      ⛔ **`lineN >= 1 AND rim1N >= 1` fires on the same 6 of 10 the shipped r=0 rule does — zero of the
      five picture false positives removed — and the two false negatives on pages of measured cartoon
      loss (`1954 - Why` p6, p7) are unchanged at 0.** A 3-px collar removes **4 accepted-line pixels of
      16,294 page-wide, 0.02%, all four on `Wilcox` p2** (1,694 → 1,692 → 1,691 → 1,690); every other
      page moves by 0. **So the sub-bar 3/51 → 1/51 improvement is specific to the rim failure mode and
      does not generalise**: at the `textRegionMask` seam six of these ten pages would still admit
      halftone dots, photograph grain, pen strokes and 10,438 px of page-wide-Otsu speckle into the
      1-bit stencil, exactly as at r=0 — plus, on `1954 - Why` p4, the lost cartoon itself, which at
      *that* seam is the admission wanted. ⚠️ **And "10 of 10" carries less than it sounds**: four of the
      ten read `lineN` 0, where a collar can only be tested for *manufacture* (which the 73-page arm
      proved it can do, and it did not here), so the removal question is asked on the **six** that fire
      and exactly **one** of those six moves at all.
      ⛔ **The mechanism is structural rather than a property of this sample**: the collar is
      `dilate(region, r) \ region`, so it can only act on a map pixel within `r` px of a recognised word
      box's boundary — which is what a *rim* is and what a halftone dot in the middle of a plate is not.
      `dilate` is a `(2r+1)`-**square**, so that distance is Chebyshev.
      Two internal controls, both measured: ✅ the collar is **live** in this run (on `Wilcox` p2 the
      removed set reads `1x11+2596+1538`, `2x11+2596+1538`, `3x12+2596+1537` — **left edge pinned at
      `x` 2596, widening by exactly one pixel per radius**, the signature of a `region` rectangle whose
      last true column is 2595, and ⚠️ not the interior blanking, whose bounds on that 3,642-px-wide
      page are x ∈ [227, 3415); the `-map.png` there is empty to the left of that edge, read at 1:1 and
      at 6x, the removed pixels being the left end of a hatch stroke that starts where the box
      ends); ✅ and it is **not idle for want of a `region` to dilate** (`1954 - Why` p4 has `glyphN`
      2,468 and `inkOut` 0.0540, so `1 - inkOut` puts the padded region over 94.6% of its interior ink, and its accepted
      group — 59 px at `27x17+1121+685`, inside the published cartoon rect `254x240+970+595` — is
      unchanged in count, area *and* rect at r=1/2/3, because the group is in the middle of the drawing).
      Controls: all **23** columns shared with `SHAPETERM-PICTURES-2026-08-21.tsv` plus `verdict` are
      **byte-identical on 11 of 11 rows**, the SKIP row included — ✅ **and that is a stronger additivity
      control than the 73-page arm's**, because that file was produced by a binary with no rim sweep in
      it at all, so this says adding the sweep moved no printed column across a real code change.
      `--self-test` **6/6** on the exact binary; `rc=0` on all five invocations; `verdict=ok` on 10 of 10
      measured rows (identity held, exit 6 never fired); the same page SKIPs again with the same text.
      ⚠️ **Instrument trap met again, same direction as 3b and WIDER in ratio**: `magick -threshold 0`
      on the dumps counts **3 / 6 / 10** changed pixels at r=1/2/3 where the columns read cumulative
      deltas of **2 / 3 / 4** — **1.5x/2.0x/2.5x** against 3b's 1.00x–1.32x over totals in the
      thousands, which is what a small count does to a ratio. ✅ **And the cause 3b left "not
      established" is in the tool's own code**: `paint` unions each accepted component's **bounding box
      ∩ mask**, so a rejected neighbour's pixels inside an accepted bbox are painted — `-lines.png` is an
      upper bound on `linePx` (1,784 against 1,694 on `Wilcox` p2) and its deltas noisier still. Both
      come from the same `rimResult`, so it is not two computations disagreeing. Location from the shell,
      totals from the columns. ⚠️ A draft of this box called it "the same 1.00x–1.32x divergence"; it is
      not in that band.
      ⚠️ Not settled: the tool prints the collar's effect on accepted LINES and never on the map, so
      "0 accepted-line pixels removed" is not "0 map pixels removed" on the **nine** pages whose columns
      did not move — `linePx == rim3Px` on 9 of 10, and 27 of the 30 `-rim<r>-lines.png` dumps are
      byte-identical to their `-lines.png` (⚠️ a draft said "the four pages where nothing moved", which
      is the count of pages accepting nothing); radii above 3 are still unrun; the sample is still
      3 true plates in 10 pages across 4 documents, against a seam of ~181 layered pages of which the
      collar has now been asked about **83**; and **no bytes** — all ten are `barVerdict=picture`, so the
      layering seam still never consults the term on them, at a 1.0956x margin ⚠️ **derived from the
      sweep's verdict column, not measured**, and the `textRegionMask` seam is **still unpriced**.
      ⚠️ **The LOCAL variant is no way out either**: a per-group exemption trusting the collar would
      still admit 16,290 of 16,294 accepted-line pixels — 99.98% — on these ten pages. ⚠️ Nothing is wired; `Sources/` untouched, so no mutant and no
      `fault-inject.sh` case owed — `Tools/score-shape-term.swift` changed only in comments.
      ✅ **One sibling find, in the same file**: `dilate`'s own doc comment still said a 7x7 square and
      `Disk:3` "differ only at the corners", which that file's HEADER already records as refuted at
      **20 of 49 cells (41%)**. Two comments in one file disagreeing, with the wrong one next to the
      code; corrected here.
      (context: BUGS.md C28 `#### The conjunction on a PICTURE page`)
- [x] **c28-corpus** — **DONE 2026-08-21. C28 question 4's CORPUS figure at the layering seam, which was
      the last owed number there.** Do not re-derive it. New tool `Tools/stratify-corpus.py` plus a new
      committed record `SHAPETERM-BYTES-2026-08-21.tsv` (41 rows, 11 columns); `BUGS.md` C28
      `#### The corpus figure` is the section.
      **Per document over all 16,987 corpus pages**: still shrunk 8x/16x **127.17** (24 exact),
      **losing content 19.42 — 0.11% of the corpus** (7 exact), the shape term's wiring refusing
      **18.42** for **+2,694,515 B** (7 pages and +1,291,409 B exact) and rescuing **14.67** of the
      19.42, and the cheapest page-wide bar refusing **59.67** for **+8,289,863 B** (16 pages and
      +2,736,780 B exact) and rescuing **17.92**. Both prices are
      **incremental to C26's shipped ~4.0 MB**: the term is two thirds of a fix this project has already
      decided it could afford, the page-wide alternative 2.1x its whole bill.
      ✅ **The instrument asserts eleven of C26's published band figures before being asked anything
      new** (`--control`, over the committed `INKBAR-2026-08-19.tsv`): 16 pages, 10 documents,
      +2,965,653 B, 16,987 corpus pages, 2,129 sample rows, 86 documents sampled completely, ~21 pages,
      ~4.0 MB, 8 pages and 1,489,670 B exact, and pooled at 5.96x. ⚠️ **Only five of the eleven are
      estimator-sensitive** (measured: a pooled factor kills 3, an all-exact subtotal kills 2); the
      other six are input-file facts. ⚠️ And **`5.96x` was never published** — the register says "6x" —
      so it is a pinned regression value, not a reproduced figure.
      `--self-test` is **54** checks and **seven mutants were watched failing**: a pooled factor in
      place of the per-document one kills 9 (3 of them control checks), the mandatory rows-⊆-sample
      identity check disabled kills 1, an exact subtotal counting every document kills 5 (2 control
      checks), and the four below kill 2/1/1/1. ✅ **The pre-commit hook DOES run it** — it greps every
      staged `Tools/*.py` for `add_argument('--self-test'` — which this box denied in draft, having
      reasoned from `check-tools-compile.sh` (`py_compile` only) and stopped one file short.
      ⛔ **THE REVIEW OF THIS DIFF FOUND FOUR CHECKS THAT COULD NOT FAIL, and one carried every pooled
      figure above.** A mutant taking the pooled denominator from the **rows** file instead of the
      **sample** passed 42 of 42 while turning 582.46 into 16987.00 and 4.58x into 133.58x, because
      every fixture and the whole control block call `run(sample, sample, …)` where the two are equal by
      construction. The other three were the output layer — `report()` and `--tsv` had no check at all,
      and every number published here was read off `report()`. All four are pinned now and watched
      failing. ⚠️ Six of the eight refusal guards are still one-check-each, the
      `C24-override-nil-means-fallback` pattern.
      ✅ **And the byte table it needed had never been committed.** It was re-measured from a binary
      built at `ab55cd7`, one invocation per document, `INKBAR=0.00001`, Photo detail Balanced, and
      **both previously published totals reproduce digit for digit** — `lineN >= 1` 789,825 →
      3,152,450 B (+2,362,625, 3.99x, 15.5%) and all 41 1,915,380 → 8,117,445 B (+6,202,065, 4.24x,
      58.5%) — with `barVerdict=picture` and a byte-identical stencil on 41 of 41 and every row's
      `inkOut` asserted equal to its `SHAPETERM-73` value. ⚠️ **That is a determinism re-run, not a
      control across a code change**: `git diff 5a929ec..ab55cd7 -- Sources/ Tools/score-text-route.swift`
      is empty. The independent control is `layered` matching `INKBAR-2026-08-19.tsv` on 41 of 41 rows —
      a different binary, a different bar, two days earlier.
      ⛔ **Three pairs of ratios this queue and the register published are now superseded**, and the
      reason is worth more than the numbers: **a ratio is a claim about its own set.** Term against bar
      is 30.9% of pages and 32.5% of bytes corpus-wide against 39.0% and 38.1% sampled — the term gets
      *cheaper*, and the mechanism is the mean scale factor (1.15 vs 1.46 by page, 1.14 vs 1.34 by
      byte). ⛔ **Do not explain the byte ratio with `Xin Qu et al_2018`, which a draft of this box
      did**: it is 26.8% of the bar's PAGE estimate and only 8.9% of its bytes, and the largest byte
      contributor is `Broadhead - 1994` (+1,438,260 B, 17.3%), which the term *does* fire on. The
      overpay share goes the other way, 15.5% → 18.0% and 58.5% → 61.0%. And the pooled-over-stratified
      factor is **not** a corpus constant: 4.58x / 5.48x / 6.57x / 6.93x over four arms of one
      population, so C26's 5.96x is its band's number and is not a correction factor.
      ⚠️ **What it does not measure**: the estimator's one assumption — that a document's unsampled
      pages behave like its sampled ones — is nowhere measured. All 41 pages were measured, so the
      scaling adds 2.42 pages and 12.3% of the bytes to the term's arm; separately, 47.9% of that byte
      estimate needs no assumption about an unsampled page at all (the fully-sampled documents).
      ⛔ A draft said "7 measured, 11.42 extrapolated", which is wrong by ~5x — sixteen were measured.
      The labels are still the campaign's eyeball verdicts with the `Atkinson_1939` p3
      circularity the all-73 arm records; the census is `CORPUS-2026-08-15.tsv`'s; the bytes are 41
      scaled pages rather than a corpus rebuild, at the default Photo detail, and an **upper** bound on
      the local variant. **Nothing is wired** — `Sources/` untouched, so no mutant and no
      `fault-inject.sh` case owed — and the `textRegionMask` seam is still unpriced at **any** scale.
      (context: BUGS.md C28 `#### The corpus figure`)
- [x] **c28-decide-and-wire** — **DONE 2026-08-22. C28's decision was taken and the shape term is WIRED
      into `pageIsAllText()` as a third refusal condition.** Do not re-decide it; `BUGS.md` C28
      `#### THE DECISION` and `#### The wiring, SHIPPED` carry the reasoning, the three rejected
      alternatives and every measurement. The entry is now `HALF FIXED`, which is why the **C28 box above
      stays `[ ]`**: three hand-made marks are still unprotected and one of them
      (`_1939_Former students` p2, `outPx` 0) is unreachable from this seam at any value of any constant.
      **The seam is the LAYERING one, not `textRegionMask`.** The argument is the direction of failure and
      not the price: `bgFactor = allText ? max(caller, 8) : caller`, so a term that only ever refuses the
      verdict can only ever store a page at *more* resolution — worst case bytes, never content. The
      1,020x cheaper stencil widening fails the other way in three measured directions (R57's blob on a
      pen ornament, 50.03% of the protection, and it *lowers* `inkOutsideText` so it pushes pages toward
      the very verdict it is fixing).
      ⛔ **The negative control is the thing to read before touching any of this**: two binaries differing
      in exactly the third term put the fixture's background at **153 px against a ceiling of 154**
      without it and **612 px** with it, and the same PDF with one more box is **153 / shrunk on both** —
      so the flip is the term's and not the fixture leaving the all-text class.
      ⛔ **AND THE PORT CHECK IS NOW A GATE ON THIS TOOL**: every figure C28 published came from
      `score-shape-term.swift`'s copy of the five functions, and what ships is a port, so the tool calls
      `Flattener.textLineGroupsOutsideText` on its own surfaces on every measured page, prints
      `port agreed on N`, and **exits 7** on disagreement. ✅ It was RUN: `port agreed on 5` over
      `Jones et al_2010` p2/p3/p5/p7/p9 (firing on three), with `lineN` reproducing
      `SHAPETERM-73-2026-08-21.tsv` digit for digit — **1 / 0 / 4 / 3 / 0**. ⚠️ Five pages of 73. ⚠️ Its `--self-test` check 10 **could not
      fail** in its first version (it reused check 8's single-block fixture, and one component can never
      reach `lineMinimumMembers`) — found by building a sabotaged port and running it, which is the tenth
      such check in this project's history. It has its own five-mark fixture now and the sabotage goes red.
      ⚠️ **What is still owed, and neither is a blocker**: (1) the mutant campaign — three mutants were
      added (catalogue 97 → 100, all three verified as APPLIED) and **none was run**, because a scoped run
      is a baseline suite plus 44-58 min a mutant; the by-hand equivalent above was executed instead.
      (2) `SHAPETERM-73` has **not** been re-run under the port check, so "12 of 12 type-losers" remains
      the tool's 2026-08-21 figure with a live guard over it rather than a figure re-derived from shipped
      code. Re-running it is cheap and is the way to convert the guard into a measurement.
      (context: BUGS.md C28 `#### THE DECISION`)
- [x] **c28-owedfixture** — **DONE 2026-08-22. The fixture `Tools/mutate.py` said was owed now exists, and
      `shapeRunHigh` is no longer a KNOWN SURVIVOR.** Do not redo it; `BUGS.md` C28
      `#### The owed fixture` carries every number. **No shipped behaviour moves** — this is
      `Tests/main.swift`, `Tools/mutate.py` and two comments.
      Why it was owed: every non-type-shaped fixture the suite had was **one 8-connected component**, and
      one component can never reach `lineMinimumMembers` = 4, so `c28GroupsBar` and `c28GroupsC26` read 0 at
      *every* value of `shapeRunHigh` and the **grouping** did all the refusing. The catalogue named the
      fixture it wanted — *"four short solid dashes on a baseline"* — and there are three now, in the clear
      strip below the last padded word box, at an **asserted** `glyphHeight` 25.0 / `glyphRun` 5.0: four
      5x30 strokes are **1 group** (the positive control), four 20x30 are **0** (`shapeRunHigh`), four 5x120
      are **0** (`shapeHeightHigh`, new mutant, catalogue 100 → **101**).
      ⛔ **The thing to quote is that the two refusals carry the SAME out-of-region ink by construction** —
      4x20x30 and 4x5x120 are both 2,400 px, both `inkOut` 0.0205 — **while the control that fires has a
      quarter of it**, so quantity does not separate them and is *inverted* against the one that fires.
      ✅ **Both mutants were watched failing, and each fixture is attributable to ONE constant**: at
      `shapeRunHigh` = 99.0 the wide one goes 0 → 1 and the tall one stays 0; at `shapeHeightHigh` = 99.0
      the reverse. Both substitutions verified APPLIED by running `catalogue()`'s own anchored regex.
      ⛔ **But "watched failing" is a BINARY here, not a red check**: neither ran through `mutate.py`
      (baseline suite + ~45 min a mutant), the probe carried its own copy of **both** `makeScannedPDF` and
      the surface construction, and `mutate.py --self-test` never touches `CONSTANTS`. What the suite adds
      is that the type scale and all three `inkOut` values are asserted **in bands** — a first draft
      asserted only the scale-free ratios while claiming the literals were pinned, which the review of the
      diff refuted. ⚠️ The calibration check is a **mirror** of the term's own calibration step, so it pins
      the fixture and is blind to a change in the calibration itself.
      ✅ **THE SIBLING WAS FIXED IN THE SAME COMMIT and it is the sharper half.**
      `Tools/score-shape-term.swift`'s **port check** — the gate comparing its copy of the five functions
      against the shipped ones, in the file every published C28 figure came from — had a fixture of five
      3x10 marks against a 3x10 calibration, the **middle** of every band, so loosening the tool's own
      `shapeRunHigh`, `shapeHeightHigh` or `shapeHeightLow` left both copies at one group and the self-test
      passed over a drifted port. **Three** refused baselines added, one per constant (four 8x10 on run,
      four 3x36 on the height ceiling, four 3x3 on the floor) plus **two complementary guards**: the group
      count pinned at exactly **1** and the map's component count at **17**. ⛔ Both, because neither
      catches the other's failure — the count is blind to a baseline clipped from an END (still four
      components) and the exact-1 is what catches a baseline that started being ACCEPTED. A first draft had
      `< 1` and 13; the second adversarial pass refuted both from a worked example. ✅ Run **four** ways:
      shipped `self-test ok (10 checks)` exit 0; the tool's `shapeRunHigh` = 99.0,
      `shapeHeightHigh` = 99.0 and `shapeHeightLow` = 0.0 each exit **5** on a port divergence. All three
      passed before. ⚠️ Printed count stays **10** — the guards went inside group 10 and the literal counts
      groups; `Tools/README.md`'s copy said **9** while the tool printed 10 and is corrected here.
      ⛔ **Of the seven new suite checks, only the two group-count refusals have watched-failing
      evidence**; the calibration, band, below-bar, equality and positive-control checks are executed for
      the first time by this commit's hook run. Said out loud rather than left to be assumed.
      ✅ **It also answers the previous session's item 1**: `score-mrc`'s `--self-test`, which asserts this
      same verdict on a real-Vision-boxes fixture and is gated by nothing, is **GREEN** — measured, exit 0.
      ⛔ **But green by CONSTRUCTION**: `selftest-alltext`'s `inkOutsideText` is **exactly 0.0**, read to ten
      decimal places by a probe that forced that assertion to print its own detail, so the term's
      `guard outside > 0` answers 0 before labelling anything. That fixture pins terms 1 and 2 and is blind
      to the third — it pins the guard's FIRST term, is silent about the second, and the tool now says so.
      ⚠️ **`shapeMinimumArea` is left unpinned on a NARROW argument**: at its shipped value, in
      `textShaped`, an 8-connected component's area is at least its height and the height test already
      demands `h ≥ shapeHeightLow * glyphHeight`, so above a median glyph of **8 px** the area guard is
      satisfied before it is asked. ⛔ That does not license three things the first draft implied: it is
      conditional on the 8 px (72-DPI corpus scans can fall under it), it says nothing about *raising* the
      constant (4 → 99 refuses tall thin marks, which is not the height bar renamed), and the constant is
      separately live in `textLineGroupsOutsideText`'s **calibration** filter, which these fixtures do run
      through — so whether they would kill such a mutant is **unmeasured**. `shapeHeightLow` and
      `lineGapFactor` stay one-sided.
      (context: BUGS.md C28 `#### The owed fixture`)
- [x] **c28-stencilseam** — **DONE 2026-08-22. Question 4's last owed number: what it costs to let the
      accepted line groups into the 1-bit stencil, and it is 1,020x cheaper than the layering seam over
      the same 16 pages.** Do not re-run it; `WIDEN-STENCIL-2026-08-22.tsv` (26 rows, 44 columns) and
      `BUGS.md` C28 `#### The price at the textRegionMask seam` carry it. **This closes the last thing
      under C28 that was unpriced at any scale, so all five of its questions are measured and what
      remains is the decision and the wiring.**
      **The instrument is production, unmodified**: `mrcLayers` reads `boxes` only to refuse an empty
      list (`Flattener.swift:2664`) and to build `textRegionMask` (`:2696`), so `WIDENBYTES=1` on
      `Tools/score-shape-term.swift` hands it **one synthetic box per accepted line group** and calls it
      twice a page, differing in that one property. **No new override seam, nothing in `Sources/`.**
      **The numbers**: 16 sub-bar pages (`lineN >= 1`, exactly the population the layering wiring
      refuses) **789,825 → 792,140 B, +2,315 B, 1.0029x, +145 B/page**, against the layering seam's
      +2,362,625 B / 3.99x / +147,664 B per page — **0.098%**. 13 content-losers +2,266 B, 3 rims
      +49 B, so **2.12%** of the spend buys nothing against 15.5% and the bar's 58.5%. Range **−218 to
      +999 B**, and **6 of 16 get cheaper** — measured mechanism: stencil **+4,391 B**, tone layers
      **−2,076 B**, because `fillHoles` fills what the stencil covers. Per document (`stratify-corpus.py`,
      same census) **18.42 pages for +2,728 B**, 7 pages / +412 B exact.
      ✅ **Positive control at 1:1, two-sided**: `Jones et al_2010` p7's estimating equation is blank
      white in `-stencil-ship.png` and fully legible in `-stencil-wide.png` over one crop, for +369 B —
      and `Wilcox` p2's pen ornament is blank shipped and **hard-edged black** widened, which is R57's
      failure mode on a page that loses nothing.
      ⛔ **The hazard, which is worth more than the price**: a widened region lowers `inkOutsideText`, so
      widening pushes every page **toward** the all-text verdict that shrinks backgrounds 8x.
      `shipBg == wideBg` on 26 of 26 here, but `1954 - Why` p4 moves 0.0540 → **0.0524** against a bar of
      0.045 — ⚠️ 0.0016 bought against 0.0074 needed (⚠️ **this read 0.0079 until 2026-08-22**; a
      subtraction slip, and 0.0079 is the same page's gap *without* `mrcBoxPadding`'s collar, at 0.0529 —
      see C28 `#### The same price without the collar`), so about 5x this effect, and p6 at 0.0493 has
      `lineN` 0 and cannot move at all — a more generous rule flips p4 and re-destroys the cartoon C26's
      bar move rescued. Wire `pageIsAllText`'s region at the **recognised** one, or measure it.
      **The cross-tool control**: `shipBytes` is byte-identical to
      `SHAPETERM-BYTES-2026-08-21.tsv`'s `layered` on **16 of 16** rows — a *different tool*
      (`score-text-route`) with its own `mrcLayers` call site and its own jbig2 handling, reproducing the
      published 789,825 B as a sum and page for page. ⚠️ It spans two binaries, two processes and the
      encoders' determinism — **not** `mrcLayers`, `textRegionMask` or `JBIG2`, which are the same
      shipped code in both; a first draft over-ranked it as "the strongest control this campaign has"
      and the review refused that. 806 shared cells over 26 of 26 rows reproduce the four
      `SHAPETERM-*` files, 0 differences — ⚠️ but only `SHAPETERM-PICTURES-RIM` is a column *prefix* of
      this file, which a first draft claimed of all four.
      ⚠️ **What it does not settle**: no searchability (a synthetic box carries no string); Balanced only;
      the 57 non-firing sub-bar pages cost 0 **by construction**, asserted by the tool's check 7 rather
      than measured; picture arm +4,694 B over ten pages with 2 of the 6 firings admitting **zero**
      pixels (Otsu found the ink, Sauvola did not). The tool is **9** self-test checks (6 → 9), the three
      new ones watched failing under a `lineBoxes` y-flip (kills 3, including the mirrored-rows half) and
      `lineBoxes` returning `[]` (kills 3, including "the widened region is no larger"). No `mutate.py`
      entry is owed: nothing in `Sources/` changed.
- [x] **c28-subbarpix** — **DONE 2026-08-22. The sub-bar 73 are inventoried for pictures: the population
      holds NO PRINTED PLATE, and the bound the shape term relies on turns out to be the GROUPING rather
      than the component test.** Do not re-run it; `SUBBARPIX-2026-08-22.tsv` (80 rows, 16 columns) and
      `BUGS.md` C28 `#### Are there PICTURES in the sub-bar 73?` carry it. This is the absence
      `c28-pictures` said it could not supply.
      **The population is the same 73, re-derived machine-readably** (`INKBAR-2026-08-19.tsv` rows with
      `verdict=all-text AND barVerdict=all-text`) and asserted identical to
      `SHAPETERM-73-2026-08-21.tsv`'s `(document, page)` pairs on **73 of 73**.
      **The instrument**: one `pdftoppm -f N -l N -png -scale-to 1400` render of the SOURCE page each, the
      73 plus **7 controls**, read by **two independent passes** of eight subagents — pass 1 under a class
      rubric, pass 2 framed to **over-flag**. **6 of 6 positive controls found in both passes**, and both
      called the hard negative `none`.
      ✅ **THE CLAIM TO QUOTE, because it survives every boundary choice: 0 printed plates and 0 printed
      figures over the 73, and the largest non-text mark anywhere in the population is ≤3% of a page.**
      Beyond it the counts are **floors, not a census**: ≥3 printed devices (a script masthead with
      stippled ornament bands, a `Digitized by Google` scan wordmark, a Great Northern Railway roundel),
      ≥1 page that is itself a colour photograph, ≥7 with reader pen marks, ≤62 with nothing.
      ⛔ **THE PART WORTH MORE THAN THE HEADLINE — three of 3b's four picture substrates are absent from
      the 73 and the FOURTH IS NOT.** Halftone dots, pen-ornament strokes and printed photograph grain
      occur nowhere, but **continuous tone does**, as camera photography: `1976 - Regis McKenna Papers` p4
      is a colour photograph of a memo on a desk and from the committed sweep its `outPx` is **7,569**,
      `txtN` **45**, `txtPx` **1,633**, `txtShare` **0.2157** — the component test accepts **21.6%** of
      that page's out-of-stencil map — and only `lineN = 0` refuses it. A printer's-ornament rect on
      `_1967_Yearly Increase … Boxoffice` p1 says the same: map **666** px, accepted components **664**,
      grouped **0**. ⛔ **So `lineMinimumMembers` / `lineGapFactor` carry the whole bound, and they are the
      same two constants behind the term's false negatives on C26's cartoons** (`textish` 372 and 785 px,
      0 groups); `lineMinimumMembers = 4` already costs three of `Xin Qu` p20's thirteen values, so
      lowering it to 3 rescues three matrix values and admits 664 px of ornament. **First measurement that
      prices both sides.**
      ✅ **The register's "all three false positives are the RIM of recognised type" is confirmed
      independently**: `_1967_Yearly Increase` p1's two accepted groups, read at 1:1 off a freshly built
      binary, are the glyph tops of `Century-Fox.` and `handle "Dolittle"`.
      ⛔ **It corrected a description of this campaign's**: `Gitlin_2000` p1's "photograph frame" is a
      ProQuest *"Blocked due to copyright. See full page image or microfilm."* placeholder box — **there is
      no photograph on that page** — fixed in `BUGS.md` in the **two** places it was published; the page's
      verdict (loses nothing) does not move.
      ⚠️ **What the adversarial review of this diff found, all corrected before commit**: `207/109` on the
      Scott footer strip was truncation and is **208/110**; "all 666" was read off a mask that paints
      `bbox ∩ map` and the accepted set is **664**; "the one device rect that reaches the map" was two of
      three; `CLAUDE.md`'s enumeration summed to 72 of 73; "the floor is ~3%" is refuted by pass 2's own
      1% findings; the hard negative is a photographed copyright page with a thumb in frame, not a
      "featureless grey endpaper"; the Scott y-list named components where it meant line groups and said
      "top half" of a band at 53.5% depth; ⛔ and **"none of 3b's four substrates occurs" was a claim that
      could not fail**, protected by a `plate`-means-printed-on-the-sheet boundary drawn after the reads.
      ⚠️ **Limits**: there is **no plate control below 40%** of a page, so "0 plates" is a claim about
      plates the size of the three plate controls; the two passes disagree on **9 of 73**, every one pass 1
      saying `none`, so read pass 2 and treat pass 1 as a second opinion; pass 1's prompt was **not
      preserved on disk**; the file names carry the page number, so the three plate controls are
      identifiable from the filename and the scatter blinds the order rather than the identity; and
      `Riesman - 1954` p20, a register-known content loss, sits in the `none` bucket.
      **No tool added and nothing wired** — `Sources/` and `Tools/` untouched, so no mutant and no
      `fault-inject.sh` case owed, and no 45-90 minute suite bought for a one-shot driver. Reproducible
      from the `awk` filter above, one `pdftoppm` per page, and `score-shape-term`'s `SHAPEDUMP`.
      Determinism controls: `_1967_Yearly Increase` p1 and `Scott_TK` p3 reproduce
      `SHAPETERM-73-2026-08-21.tsv` on `inkOut`/`lineN`/`linePx`/`topLine` to every digit, `--self-test`
      6 of 6, and the review independently reproduced a third row (Regis p4). ⚠️ A re-run of unchanged
      code, not a control across a change.
      (context: BUGS.md C28 `#### Are there PICTURES in the sub-bar 73?`)
- [ ] **text-layer-recall** — whole blocks of clean body text come out with no text layer over them: on
      the document this was found on, **30% of the inked height sits in runs of 20+ rows with no word box**,
      43% on its first page, largest void 171 rows of crisp 1951 type read by eye. ✅ **STEP 1, THE FORK, IS
      SETTLED ON THE WHOLE DOCUMENT — page 1 on 2026-08-22 and PAGE 5 ON 2026-08-23. It is RECOGNISER
      RECALL and not the writer, C30 is ONE mechanism, and DO NOT RE-RUN ANY OF IT.** ⚠️ **What that does
      NOT say: that the writer drops nothing.** The pipeline's own observations were never captured and
      `deduplicated` (`SearchableWriter.swift:706-733`) is an unmeasured removing path, so a PARTIAL drop
      on top is not excluded — what the page-5 run moved is the ceiling on BAND-VISIBLE loss, from "order of
      ten lines" to three. ⛔ At `VOID_MIN_ROWS` 20 against a ~13-row line pitch, one dropped line raises
      no band, so scattered single-line drops are not bounded by this instrument at all. The evidence is in
      the two ticked sub-boxes below, in `BUGS.md` C30 `#### The fork, settled 2026-08-22` and
      `#### Page 5, settled 2026-08-23`, and in `C30-FORK-2026-08-22.tsv` and `C30-PAGE5-2026-08-23.tsv`.
      This line used to say page 5 was open and to name its control as the first thing to do; that control
      ran, and it also said the mechanism was undiagnosed, which is false.
      ⛔ **THE ONE THING FROM PAGE 5 THAT CHANGES HOW YOU WORK HERE: production recognises
      `Flattener.flatten`'s REBUILT BITMAPS (`Sources/Model.swift:1919`/`:1922`), and `make-observations`
      recognises a PLAIN RENDER of the source page.** Same geometry, different pixels — so every
      instrument this entry has used measures a different image than the app does, and a new one that
      starts from `make-observations` inherits that. ⛔ **And do not quote `bareShare` as a content
      measure**: on page 5 one 115-px observation reading the single word `ASSAME` accounts for 98 of the
      146-row published-vs-fresh gap, and removing it moves the fresh share 0.2470 → 0.3866. It credits a
      box, not a reading. ⛔ **What the fork LEAVES is a different job from the one this box
      was written for**: the loss is a property of the image handed to ONE REQUEST (page 1's bottom half goes
      84.81% bare → 8.61% purely by being its own request), so the candidate fix is TILING — which
      `Recogniser` has no seam for and which nothing has priced in time. And if the mechanism is a
      working-resolution downscale inside `VNRecognizeTextRequest`, **"render at a higher DPI" is refuted in
      advance**: do not spend a session on it. ⛔ **AND DO NOT TRUST `words=`, `start=`,
      `end=`, `probe-line-coverage` OR `probe-line-edges` HERE**: all four count only the words Vision
      returned, so they read 100% on a page that lost a third of its text. Any new instrument must be able
      to fail a page while `words=` passes it, or it has inherited the same blind spot. A generated fixture
      is the standing preference; `testdocs/` holds nothing of this shape and the document itself is not in
      it. (origin: BUGS.md C30)
      ⚠️ Placed straight after `C28` because it is the same root cause seen from the other side — C28 is the
      subset where the missed ink is also DESTROYED at 1/8, this is the general case where it is merely
      unsearchable. C28 is mid-campaign so it keeps its place, but this may deserve to jump it: it is the
      app's central promise and the owner reports seeing it on other documents too. Owner's call.
  - [x] **c30-fork** — **DONE 2026-08-22. The fork is settled on the block it was opened on: page 1's void
        is RECOGNISER RECALL, not the writer — and the loss is a property of the image handed to one
        request, not of the type.** Do not re-run that part; ✅ **page 5 was the exception and it is
        settled too, 2026-08-23 — see the `c30-page5` sub-box below**; this line read "is NOT settled,
        and is the umbrella item's first step" until then.
        `C30-FORK-2026-08-22.tsv` (18 rows, 15 columns) and `BUGS.md` C30
        `#### The fork, settled 2026-08-22` carry it. Three things say the recogniser never returned the
        text: the published layer holds **2,101** word boxes against **2,002** words in 235 observations
        from a fresh run (document-wide the writer publishes MORE than the recogniser returns, so nothing
        block-scale is dropped between them at that scale — ⚠️ **page 5 inverts it, 277 against 295**); the
        five named missing strings read **0 in the observations and 0 in the published layer**; and the void
        measure over the recogniser's OWN boxes reads bare 0.4446 / 0.2457 /
        0.3296 / 0.4271 / 0.2470 / 0.2664 on pages 1-6. ✅ The instrument reproduced the entry's own
        headline before it was asked anything new — longest ink void on page 1 = **171** rows from both box
        sets **digit for digit**, document floor **31.56%** against the entry's "30%"; ⚠️ its per-page table
        is close but exact on NONE of the six (two within a point), and the figures quoted are the published
        layer's, which a draft did not say. ⛔ The mechanism measurement: over the
        same pixels at 400 dpi, page 1's bottom half goes **84.81% bare → 8.61%, 9.85x less, purely by
        being its own request**, and the two halves return **1.88x** the whole page's words. Controls: the
        page as a PNG reproduces the PDF path (45 obs / 286 words vs 42 / 273), and three independent
        whole-page runs leave the same void. ⚠️ Not settled: no crop size is sufficient (a gradient, not a
        threshold), one document and one page for the scope test, and the *why* is untested.
        ⛔ **C30 STAYS OPEN and its umbrella box stays `[ ]`** — the fork is not the fix.
        ⚠️ **This was ADOPTED, not run here**: the work was done by a session the owner stopped mid-flight
        on 2026-08-22 (`vo-20260822-073825-10384`), and its BUGS.md was single-copy in `/private/tmp` for
        five hours. **TWO adversarial review passes over the adoption diff found 9 defects in the draft's
        prose and 12 more in the revision that fixed them; all 21 are fixed in what landed**, which is why
        this box reads more cautiously than the draft did. The list below is the first pass and is **not
        exhaustive** — pass 2's are in the entry, and the sharpest of them is a check that could not fail
        (a `grep` for a two-word phrase in `pdftotext -bbox` XML always returns 0, because every word is
        its own element):
        page 5's inversion unreported and "the layer is as good as the recognition it was handed" refuted by
        the same two rows; "the fork is settled" flat, where only page 1 is; "the void alone returns 277
        words, more than the whole page's 286" (277 < 286 — the surviving claim is words-per-pixel);
        "digit for digit" over a per-page table that reproduces two of six; a word-diff pair (160/253) that
        reproduces by no method; **412** rows quoted as a column when no column holds it; "one day after the
        run" for the same day; "an independent extractor" for the same `pdftotext` pass (2,096 words against
        2,101 `<word>` elements); and a `$STATE/c30-instrument/` that did not exist until the adoption
        created it. ⚠️ Two limits the review also established and the entry now records: the crop step of the
        mechanism experiment is **not reproducible** from the surviving record (no crop script, and the PNGs
        are 3308 px where the recogniser's own render is 3307), and `artefact.py` **alone** regenerates the
        TSV byte-identically — the other two scripts are the earlier exploratory pass.
        (context: BUGS.md C30 `#### The fork, settled 2026-08-22`)
  - [x] **c30-page5** — **DONE 2026-08-23. The control the fork owed was run and page 5 settles the same
        way page 1 did: the gap is two recognitions of two DIFFERENT IMAGES, not the writer, so C30 is ONE
        mechanism.** Do not re-run it. `C30-PAGE5-2026-08-23.tsv` (11 rows, 15 columns, the fork file's
        shape) and `BUGS.md` C30 `#### Page 5, settled 2026-08-23` carry it. **(1)** Three consecutive
        whole-document `make-observations` runs are **byte-identical** (one sha256 for all three), so run
        variance on this path is **0.0000** — and page 1's published 0.0143 is therefore not run noise
        either: its three members are three different *paths*. **(2)** A full
        `makeSearchablePDF(rebuild:true, .auto)` today reproduces the shipped `.ocr.pdf`'s layer on all
        nine measure columns of **both** pages, so no build or settings drift is in the way. **(3)** The
        146-row gap decomposes: **98 rows** are a band the fresh run "covers" with ONE 115-px observation
        reading the single word `ASSAME` (seven lines of type at 1:1, lost by **both** paths); **46 rows**
        are the one band where the layer is genuinely worse, three prose lines with the published layer's
        own lines running straight from `yMin` 423 to 483; the rest is boundary jitter. Removing the junk
        box moves the fresh share 0.2470 → **0.3866** and the gap to **2.995x** page 1's, not 12.729x (off the integer counts; the 4-dp shares round to a falsely exact 3.00).
        **(4)** The published layer holds a line — `PROVIDING FACTS AND FIGURES FOR COLLECTIVE
        BARGAINING-THE`, verified at 1:1 — that **no** fresh observation contains, and a writer can only
        remove — ⛔ NOT because "a writer can only remove", a maxim this diff's own review refuted from
        `SearchableWriter.swift:889-892`, but because those WORDS are absent from page 5's fresh text
        altogether, so no regrouping or hyphen join reaches them. **(5)** `Sources/Model.swift:1919`
        and `:1922` say why, and the bitmap arm is MEASURED to have run rather than
        `Recogniser.swift:141`'s render fallback (`pdfimages` reads `jbig2` on all six pages):
        production recognises `Flattener.flatten`'s
        rebuilt bitmaps, `make-observations` a plain render.
        ⚠️ **Not claimed**: that the writer drops nothing (the pipeline's own observations were not
        captured — replicating the recognition step in an instrument is the `alltext-replica` mistake), so
        a partial drop on top is not excluded; what moved is the ceiling, from "order of ten lines" to
        **three**. And "byte-identical" is three runs of one build on one machine.
        ⚠️ Instrument at `$STATE/c30-instrument/page5.py`, not in `Tools/` for the same reason the fork's
        pass is not; it `exec`s `artefact.py`'s function block instead of copying it, and exits non-zero
        if the cut line or the junk observation it re-scores without is gone.
        ✅ Page 5 also turns out to be a **second instance of C30's founding symptom**: **23** lines of
        crisp 1951 type have no text layer over them, **13** of them missed by *both* paths, counted by
        eye on exact crops band by band (5 / 7 / 3 / 4 / 4). ⚠️ Count per band and by eye: at 100 dpi the
        interline gaps clear `INK_ROW_FRACTION`, so every band reads as one run, and a draft that lumped
        two bands together counted a line **both** paths recognised.
        (context: BUGS.md C30 `#### Page 5, settled 2026-08-23`)
- [ ] **obs-drift-comment** — **one comment, and it is the most-read statement of a belief measured false
      on 2026-08-23.** `Tools/make-observations.swift:16-22` says going through `Recogniser.extract` means
      "the instrument's input and the product's output **cannot drift apart**". True of Extract Text ▸
      JSON, FALSE of the searchable pipeline: production recognises `Flattener.flatten`'s rebuilt bitmaps
      (`Sources/Model.swift:1919`/`:1922`) and `extract` recognises `Recogniser.render`'s plain render of
      the source page — same geometry, different pixels. Every C30 instrument is built on this tool, so
      the comment is what a next reader trusts. ⚠️ **It is a `Tools/` file, so the commit pays the FULL
      SUITE (40-90 min)** — which is why 2026-08-23's docs-only page-5 commit could not carry it and put
      the correction in `BUGS.md`, `ARCHITECTURE.md` and `CLAUDE.md` instead. Ride it along on the next
      commit that runs the suite for another reason rather than paying a suite for a comment.
      (context: BUGS.md C30 `#### Page 5, settled 2026-08-23`)
- [ ] **born-digital-page** — a born-digital cover page is rasterised to 1-bit and re-OCR'd because the
      digital-text test votes per DOCUMENT. On the JSTOR download this was found on, page 1's vector text,
      its embedded fonts and a 197x267 colour JPEG became one 1-bit raster, and the text layer went from
      exact to `AMFAKAN FOCAX ONCAL ASSOXUTION` — so a search that worked on the input fails on the output.
      ⛔ **Read the entry before touching `sampleIndices`**: the sharp finding is that page 1 is NEVER
      sampled on a document of 5+ pages, but the fix is a per-page decision, not a change to the sampling.
      `pageIsAnImage` is already per-page, so the signal exists. ⛔ **And the file being 1.55x BIGGER is
      NOT this item** — that is the JBIG2 generic-vs-symbol encoder mode, it is measured in the entry, and
      the lossless remedy is refused by jbig2enc 0.32. Do not reach for `-s`. Needs a FIXTURE first:
      `testdocs/` has no born-digital-cover document. (origin: BUGS.md C29)
      ⛔ **BOUND: decide FIRST whether this is one code commit or two, and write the answer here before
      starting.** It looks like two — the fixture, then the per-page routing — and two code commits is two
      suite runs, 1.5-3 h by the ledger, which does not fit one session safely. But they may not be
      separable: a fixture committed alone must not leave a check RED, because a red suite refuses every
      later commit through the hook (see `gutter-floor`'s sub-step 0 for the same trap and the way out —
      pin current behaviour, flip it in the second commit). So either the fixture pins today's wrong
      behaviour and the routing commit flips it, or both are one commit and the session must be told to
      expect a single long one. Whichever it is, one session does ONE of them.
      ⚠️ Placed ahead of `C27` by the owner 2026-08-20 on this project's own precedence — content loss
      outranks fidelity, the same call that put C26 before C27 — and behind `C28`, which is mid-campaign.
- [ ] **gutter-floor** — the reading-order DECLINE rests on "0.19% of observations cross a gutter", and
      the population that produced it excludes the pages that fail. `score-reading-order.swift`'s ink test
      needs a quiet run of `0.035 * width`; a page without one is counted `singleColumn` and `continue`d,
      so it is dropped from both halves of the ratio before any observation is read. A JSTOR article whose
      gutter is about one wide word space welds its columns into single strings — quoted from the content
      stream in `FEATURES.md` item 3's reopen note. ⛔ **MEASUREMENT ONLY. Do NOT build a reorder**: the
      decline's strongest finding is that a column-wise sort damages tables and contents pages, and a weld
      cannot be repaired by sorting because the halves are already one string. Three bounded sub-steps, in
      order, and STOP after each:
        1. Reconcile the instrument. A poppler+python reimplementation of the ink test scored **43** pages
           with a qualifying gutter where the recorded Swift run scored **59**, over comparable samples
           (644 vs 638 pages). Find out why before trusting any number below it — `samplePages`,
           `displayBox`/`cropBox` vs `pdftoppm`'s default box, and `renderGrey` are the candidates.
        2. Run the real `score-reading-order --gutter` with the floor lowered (0.02) over the corpus, and
           report crossing separately for the 3.5%+ band and the 2.0-3.5% band. The screen says ~27 pages
           in 18 documents sit in that lower band — `Kristol_1962`, `Freud_Fetishism`, `WITTE_1978`,
           `Berle_1940`, `Canby_1929`, `Kazin_1955`, `Hyman_2012`, `Maclean_2008`, `Jones et al_2010`.
           **The class is already in the corpus and simply is not counted**, so this needs no new files.
        3. Report the two rates to the owner. The DECLINE stands or falls on that, and it is the owner's
           call, not a session's. If it falls, THEN a register entry gets opened.
      ⛔ **SUB-STEP 0, AND THE OWNER PUT IT FIRST (2026-08-20): the narrow-gutter FIXTURE, before any
      sweep.** The existing `ENGINE ASSUMPTION` fixture's gutter is 52 pt of 612 = 8.5%, and its own
      comment calls that "far wider than any word space" — which is exactly why it is green while a real
      page welds. A second fixture at ~2.5% is the check that would have caught this, and it is cheap,
      committable and needs no corpus.
      ⛔⛔ **BUT DO NOT WRITE IT AS AN ASSERTION THAT FAILS. A red suite refuses EVERY commit through
      `.githooks/pre-commit`, including yours, and there is no fix to pair it with** — the remedy is
      declined and, per this item, upstream rather than a sort. The project's own idiom is the way out:
      these checks are named `ENGINE ASSUMPTION` and they PIN engine behaviour. So pin what is true —
      *"ENGINE ASSUMPTION: at a ~2.5% gutter Vision welds across it"* — with the measured count in the
      failure detail. That is green today, it records where the engine's competence ends, and it goes RED
      if Vision ever improves, which is good news and is precisely when this feature should be reopened.
      Watch it fail by planting a wide gutter, the same way the existing pair was watched.
      ⚠️ This is a `Tests/main.swift` change, so it runs the full suite and is its own commit. Budget it
      as one commit, not a free one.
      ⛔ **NO CORPUS ADDITIONS — owner's decision 2026-08-20.** 18 corpus documents already carry this
      shape and are simply not being counted, so the class needs no acquisition to be measured. Adding a
      specimen was priced and deferred: `testdocs/manifest.tsv`'s 12 columns are gate outputs that cannot
      be hand-written, 22 files quote the corpus size, and `testdocs/README.md` says re-cutting "moves
      every published figure at once, and that is a decision to take with the numbers rather than instead
      of them". Those numbers are what sub-steps 1-3 produce, so do not propose a corpus write before
      then. ⛔ **Corrected 2026-08-22: writing `testdocs/` is NO LONGER the owner's call** — that hold now
      covers his Zotero library only, because the corpus is a sample OF the library and the library is the
      irreplaceable half. What still holds, and is the actual point of this paragraph, is that a re-cut
      "moves every published figure at once": there is no replay-by-key mode, so a rebuild is a fresh
      sample and the dated measurements stop being reproducible. Have the numbers first, then decide — see
      the `corpus-write` line at the foot of this file for the full reasoning.
      ⚠️ **AND THE TWO TOKENS THAT MARK A HOLD MUST NOT APPEAR IN THIS BOX.** `next-item.sh:100` is
      `held = (cur_span ~ /\[hold\]/ || cur_span ~ /needs:[[:space:]]*owner/)`, matched over the item's
      WHOLE greedy span — so merely *writing about* another item's hold, in either spelling, silently
      converts this actionable item into an owner-only one. That happened to this box on 2026-08-20 and
      `next-item.sh` reported `hold gutter-floor` until the sentence above was rephrased. Same family as
      the sub-box span trap in this file's header.
      (context: FEATURES.md item 3, reopened 2026-08-20; Tests/main.swift:5196)
      ⚠️ This and `born-digital-page` are the same document class and share a fixture, so they sit
      together. **`C27` has now been passed by two items** — if the owner wants C27 first, move it up.
- [ ] **C27** — spot colour is discarded because `pictureSaturationThreshold` is a bar on the page's
      MEAN saturation: the corpus's deliberately chosen two-ink fixture keeps its red on 1 page of 10.
      Fidelity, not content loss — no word or mark is lost — but the copy misrepresents how the
      document was printed, and inconsistently within itself. Read the entry; it has the per-page
      red-pixel measurements and the reason the mean cannot answer this question.
      ⚠️ **C26's sweep RAN on 2026-08-18 and it does NOT size this population** — the shared-sweep
      plan on this line was wrong, for the reason the entry itself gives: `sat` is a mean, so a page
      at 0.045 may be two-ink or uniformly tinted and no bar on a mean separates them. What the
      sweep gives is a bound and ~~a candidate list~~: **13 pages of 441 sit in 0.03–0.06**, against 13
      that clear 0.06. ⛔ **RETRACTED 2026-08-19 as a candidate list — the band is wrong in both
      directions** (`BUGS.md` C27 `#### The population, swept`): one of its 13 reads below what the
      column can resolve and 8 pages above 0.003 sit outside it. 9 of its 13 have now been looked at
      or measured; the four left are `Ford_1941` p3, `Atkinson_1939` p3 and `Stanford_1891` p2/p3.
      **Do not re-run the
      sweep.** Sizing this population needs a per-page **saturated-pixel fraction** — what the
      owner's own C27 measurement used (`in red%`) — and no tool in this repo prints it over the
      corpus. That column, added to `score-threshold-loss` or beside it, is sub-step 1 now.
      ✅ **SUB-STEP 1 IS DONE, 2026-08-19: the column exists and the sweep is what is left.**
      `Flattener.saturatedFraction` + `score-threshold-loss`'s `satFrac`/`satFloor` columns
      (`SATFLOOR=n`, default 0.25), taken from the same thumbnail `sat` comes from so the two
      statistics are of one population. Nothing shipped reads it; the app is unchanged.
      ⛔ **Do not re-derive the validation.** It reproduces the entry's own 50-DPI red-pixel count on
      all 7 pages that count covers (**0.93x–1.49x, median 1.12x, over 0.1%–24%, at `SATFLOOR=0.15`** —
      at the default 0.25 they read 0.42x–1.08x, so quote the floor with the ratio) and reproduces
      `THRESHOLD-LOSS-2026-08-18.tsv`'s 12 pre-existing columns digit for digit including `sat`. Three
      results are in the entry's `#### The population instrument` section: `p5`/`p8`, which the entry
      never measured, are in the same population (`p8` third of the ten); ⛔ **the column has a noise
      floor ABOVE the smallest real marks** — ⚠️ **superseded 2026-08-19: that floor is one page's and
      not a constant, so "a bar has to sit above it" has no value to name; a 1938 magazine scan reads
      2.0% with no ink of its own** — a page with no spot colour reads ~0.5% at a 0.15 floor
      and ~0.12% at 0.25, so `p1` (0.1% red by hand) ranks *below* `p3` (none), which is also why the floor that reproduces the hand count is not the one
      that separates best; and ⛔ **the mean gates the ROUTE as well as the colour** (C9's "same number
      charged twice"), so `p8` and `p9` are 1-bit today while holding as much saturated ink as the
      picture pages `p6`/`p7` (`p5` a little less), and a fraction inside `isPicture` moves their bytes
      too.
      ✅ **THE SWEEP RAN 2026-08-19 AND IS `SATFRAC-2026-08-19.tsv`. DO NOT RE-RUN IT.** 233
      documents, 441 pages, 12.2 min, every document `rc=0`; the 12 columns of the previous day's file
      reproduce digit for digit over all 441 rows. **428 of 441 pages are published in grey (they
      fail the 0.06 mean bar; 401 of them have nothing measurable to lose), and 10 pages in 7
      documents of 233 carry as much saturated ink as the page the owner watched lose real red ink**,
      ~220 pages of 16,987 stratified — bounded **both** ways, and not the result. The results are:
      the mean **mis-orders** colour (24 discarded pages hold more than the least-coloured page that
      keeps its colour; 58 of 5,564 pairs inverted); **eight of the ten were dumped and read by eye**
      (the other two are the owner's own verdicts) and **three of the eight real ones are colour
      PHOTOGRAPHS or illustrations on pages of type**, not spot colour; and **two carry no ink of
      their own** (a 1938 scan reads 2.0% from a page-wide cast the paper correction left standing,
      48x what another page of that scan reads; a 1941 typescript's 4.08% is 88% photographed surround
      from outside the sheet). ⛔ **So the noise floor is per-page, no bar on the fraction separates
      the populations, and the single locality test first proposed for it would rank that scan-border
      page top of the corpus — TWO terms, not one.** R56's lesson in a second place.
      Read `#### The population, swept` and `#### ⛔ And the ten pages were LOOKED AT`.
      ⛔ **NEXT, and each is one bounded item:** (a) the **two mask terms measured separately** —
      discarding saturation outside the sheet, and a locality term (`Flattener.pageMarks` has an
      8-connected component routine already) — over the 40 pages above the noise band, and including
      `1954 - Why` p4, which defines the headline bar and is the one page of the ten never dumped;
      (b) **the byte price** of keeping colour on those pages, unpriced and the reason this cannot
      close on the harm alone (R49/R50's trade); (c) **split the one number** that gates both
      `isPicture` and `shouldKeepColour`, because nothing can be given back to the colour decision
      while a change to it also moves the route (C9). The constant is still not a
      session's to move.
      ⚠️ **Instrument fact from the sweep, before re-measuring any single page:** `saturation(of:)`
      is **not** a pure function of the page — read cold it differs from read after a full-resolution
      render of the same page (`1954 - Why` p7: satFrac 0.02831 warm, 0.03033 cold, +7.1%; five of
      seven pages identical). Production renders grey first and so does the tool.
      ~~It is probably a ONE-SESSION job, unlike C26's sweeps~~ — it was, and the estimate below held:
      measured, ten
      page-measurements of `1954 - Why` took **4 s** with an `-O` build (0.4 s a page; this path runs
      no OCR). ⛔ **Do not extrapolate that to the corpus** — page area dominates, this pamphlet is
      887,616 cells against the widest **3.84 M** (not the 2.85 M this line said until 2026-08-19 —
      that was the file's first data row; 40 of its 441 rows are bigger) in
      `THRESHOLD-LOSS-2026-08-18.tsv`, that run's own
      duration was never recorded, and the Vision-running tool measured 0.54–3.83 s a page. Time three
      documents first, then size it. The tool has no resume; `sweep-ink-bar.py` is the shape if one is
      wanted, but ⚠️ **its `CONFIG_EXITS = {2, 3}` does not transfer** — for its own target 3 is "no
      `jbig2`", and for this tool 3 is "measured no pages", a recordable per-document outcome that as a
      config exit would abort the sweep on the first unmeasurable document. Here the set is **{2, 4}**.
      ~~Until the count exists this is still one document~~ — **the count exists as of 2026-08-19 (10
      pages, 7 documents), so this is no longer one document.** What is still missing before anything
      could close is the **byte price**, so it is not yet a campaign that can be closed on
      arithmetic (R55's shape) — and the constant is not a
      session's to move either way.
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
- [ ] **rescue-adopt** — a session that dies before it commits leaves its work in `$STATE/rescue/*.patch`,
      and **nothing ever tells the next session to look**. `vision-ocr-autonomous.sh` writes the patch and
      logs *"a later session can finish it, or rescue it by hand"*, but `resume-prompt.txt` contains no
      occurrence of `rescue`, `stranded` or `orphan` — so the next session pulls `origin/main` into a fresh
      `auto/<stamp>` worktree, reads a queue box the dead session never got to tick, and reimplements from
      scratch. The log line is addressed to nobody.
      ⚠️ **MEASURED 2026-08-21 at an owner check-in, not estimated**: `$STATE/rescue/` holds **four**
      `SUPERSEDED-by-*` sets against five `LANDED-as-*`, and the fourth was filed that morning —
      `vo-20260820-230443-5696`, 207 insertions adding an `MRC_BG=<factor>` knob to `score-text-route`,
      superseded by `69ebf0e`'s `PHOTODETAIL=` two hours later. Its session died rc=1 at 23:35 with the
      usage window, 26 minutes after its last file write. And the one orphan that WAS handled well,
      `19f4131`, says in its own first line that it happened *"from an owner check-in"* — so the net only
      discharges when the owner empties it, at roughly one duplicated session a night.
      ⛔ **BOUND — write the paragraph, do not widen the daemon.** ONE paragraph in
      `ops/autonomous/resume-prompt.txt`: before starting, check for a `$STATE/rescue/*.patch` not already
      renamed `LANDED-as-*` / `SUPERSEDED-by-*`, and if there is one, do the **file-by-file supersession
      check `19f4131` modelled** — that commit is the specification. ⛔ Adopt-or-delete on the strength of
      "the item landed" is REFUSED: `55b650b` landed the same item by a different implementation and the
      stranded copy still held a `HANDOFF.md` paragraph `main` genuinely lacked, whose cited symbol
      (`OCRModel.textOnlyShrinkSummary`) does not exist on `main`. Copying is refused for the same reason.
      ⚠️ **Both halves or neither**: `daemon.sh` renders the template into `$STATE/resume-prompt.txt` only
      at `start`, so a repo-only edit does nothing to the running daemon — render it in and `mv` it
      atomically, and keep the phrase *"autonomous maintenance session for Vision OCR"* verbatim, because
      `daemon.sh stop`'s pkill matches on it.
      ⚠️ Prompt-and-queue only, no `Sources/`, so **no suite** — one free commit.
      ⛔ **PARTLY LANDED 2026-08-22 (`c25933f`), AND WHAT IS LEFT IS NARROWER AND SHARPER — do NOT tick this
      box yet.** The daemon now snapshots each stranded worktree and writes `$STATE/triage/<wt>.md`, and
      `resume-prompt.txt` STEP 1.5 drains that inbox ahead of the queue with the file-by-file supersession
      procedure spelled out. So the LIVE-WORKTREE case is covered. **The residue is a rescue patch with no
      worktree**, and this change made it more likely rather than less: `housekeeping()` GCs a triage
      assignment once its worktree is gone from `/private/tmp` (macOS sweeps it) and deliberately KEEPS the
      patch — so exactly then, a `$STATE/rescue/*.patch` exists that nothing points any session at, which is
      this item's original complaint in the one case the new mechanism creates. STEP 1.5 keys on
      `triage/*.md`, not on `rescue/*.patch`. What is left: have STEP 1.5 also notice a patch that is neither
      `LANDED-as-*` nor `SUPERSEDED-by-*` nor matched by a live worktree. Still one free commit.
      (context: the rescue lines in `$STATE/daemon.log`, and `19f4131` as the worked example)
- [ ] **mrc-endtoend** — nothing in the suite runs a document end-to-end through `makeSearchablePDF` down
      the MRC route. The three `.mrc` tests call `Flattener.mrcLayers` directly and assemble by hand, so
      `Model.swift`'s whole adoption loop — the `after < before` guard, the JBIG2 encode-failure branch and
      `shrunkTextPageSummary`'s wiring — has no end-to-end check. Pre-existing, and wider than the C28
      report that surfaced it.
      ⛔ **BOUND, and the owner's call 2026-08-20 was MEASURE FIRST rather than build-and-accept:**
        1. Build the **smallest** page that `isPicture` routes to the picture path and `pageIsAllText()`
           then accepts. The suite has the second half of that (`r50text`) and not the first, and
           `Mode.grayscale` is refused by `canUseJBIG2` so it is not a shortcut.
           `Tools/make-plate-fixtures.swift` is the precedent for generating one.
        2. Record the suite duration from `$STATE/suite-timings.tsv` before and after, and report the delta.
        3. Keep or revert on that number — that decision is the owner's, not a session's.
      ⚠️ **Do NOT quote the outbox entry's "at least one more full layering plus a jbig2 and qpdf pass" as
      the cost.** It is an estimate, and every duration estimate in this repo has turned out to be a
      reading of the machine's load; a minimal fixture may cost seconds. Step 1 is one code commit and
      therefore one suite run; steps 2-3 are free.
      (context: BUGS.md C28 §"The report, SHIPPED", and the outbox entry drained 2026-08-20)
- [ ] **tools-compile** — run `Tools/check-tools-compile.sh` over *every* tool, not just the staged ones,
      and REPORT what does not build. ⛔ **BOUND: the sweep and its report are ONE free commit; each tool
      you then fix is its own commit and its own suite run, so fix at most ONE per session and leave the
      rest listed here.** *"Fix or delete what does not build"* was this line until 2026-08-20; if the
      sweep finds four broken tools, that reading is four suite runs, which is a stranded worktree.
      It is a standing gate that today only runs on the
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
      `Tools/mutation-log.tsv`.
      ⛔ **BOUND: ONE mutant per session, and commit its row before starting another.** A baseline suite
      plus ~45 min per mutant means two can exceed the 4 h `MAXRUN` on a busy machine, and a scoped run
      that matches more mutants than you counted is the shape that strands a worktree — five took
      **4h27m** end to end against the 20-55 minutes the tool predicted. Check the match count with
      `--list` BEFORE running; if your substring matches more than one, narrow it or take the first.
      (context: BUGS.md T5 — CLOSED; it records how to tell a real gap from a
      value nothing depends on)
- [ ] **fault-inject** — confirm each sabotage is still refused by the real build step. It builds into a
      scratch copy of the tree, so it is safe unattended.
      ⛔ **BOUND: the case list is `FAULTS` at the foot of the script — 7 as of 2026-08-20, read it rather
      than trusting that number. Take ONE case per session** until a run proves they are cheap on this
      machine, and record the per-case cost here the first time so the next session can size itself. Each
      case builds the tree, and the resume prompt lists this among the five gates needing the
      detached-plus-poll shape — a foreground run can be killed at the 120 s ceiling with no output, which
      a session cannot tell from a hang. *"Over all its cases"* was the whole of this box until 2026-08-20
      and it is exactly the unbounded verb §"How to size an item" rule 4 is about.
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
- [ ] **zotero-2** — the Zotero library sweep. ⚠️ Step 1 wants re-running first; the survey it produced is
      dated. Reads a Zotero library, so copy `zotero.sqlite` before querying it — Zotero holds a lock on it.
      ⛔ **BOUND: ONE step per session, starting with the re-run of step 1, and commit its output before
      taking the next.** *"Steps 2-4"* was this box until 2026-08-20 — three steps over a whole library,
      which is both a multi-hour job and an unbounded verb. Read the steps in `TODO.md` §"2. The Zotero
      library sweep" and treat each as its own box; if one is over an hour of compute it is a detached
      driver under §"How to size an item" rule 3, not a session.
      (origin: TODO.md §"2. The Zotero library sweep")
- [ ] **corpus-restore** — give `Tools/sample-zotero.py` a `--from-manifest` mode that rebuilds the EXACT
      corpus from `testdocs/manifest.tsv` by `zotero_key`, instead of drawing a fresh sample. Today there is
      no replay path at all: the flags are `--per-bucket`/`--seed`/`--added-since`/`--exclude-manifest`, and
      `--exclude-manifest` does the OPPOSITE of replay (it excludes prior picks so you can sample new ones).
      So a rebuild is `random.seed(7)` over the buckets as they stand, and the tool's own docstring promises
      only an *"equivalent sample"* — same seed against an unchanged library reproduces the 233, a library
      that has grown since does not.
      ⛔ **WHY IT MATTERS, and it is the whole point: the corpus is the evidence base for every open entry.**
      `INKBAR-2026-08-19.tsv` (2,129 page rows), `SHAPETERM-73`/`-RIM`/`-PICTURES-*`, `SATFRAC-2026-08-19`,
      `THRESHOLD-LOSS-2026-08-18`, `CORPUS-2026-08-15.md` and the whole C26/C27/C28 campaign are keyed to
      specific documents AND page numbers. If a rebuild returns different picks those rows stop being
      reproducible, which `testdocs/README.md` already states as a re-cut "moves every published figure at
      once". A replay mode converts that from a risk into a non-event, and it is why the owner's corpus is
      recoverable in principle but not yet in practice.
      ✅ The information needed is already committed: the manifest's 233 rows each carry a `zotero_key`, and
      the sampler already resolves keys to attachment paths, so this is a second entry point over machinery
      that exists — not new sampling logic.
      ⚠️ **BOUND: the replay mode only.** Do NOT re-cut the corpus, do not change the sampling defaults, and
      do not touch `--exclude-manifest`. Verify by restoring into a scratch `--dest` and diffing the file
      list against `manifest.tsv`, not by overwriting `testdocs/`.
      ⚠️ `Tools/` is inside the pre-commit suite regex, so this is a FULL-HOOK commit (~40 min), unlike the
      ops-only work around it. It also needs the `--self-test` both Python tools here carry — `py_compile`
      is the whole gate a Python tool used to get, and it cannot see a parser that accepts a malformed row.
      Reading the Zotero library is fine; writing it is the `corpus-write` hold, which this does not touch.
      (origin: CLAUDE.md §"Not committed"; `Tools/sample-zotero.py` docstring)
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
- [x] **alltext-replica** — **DONE 2026-08-23.** ✅ **The column stopped being a replica: it reads
      `Flattener.MRCLayers.shrunkAsAllText` back from production**, and the hand-written expression survives
      only as the answer on a page that never layered and as a **printed** cross-check
      (`layeringVerdict(production:replica:)`, a `disagrees` flag, a `VERDICT p<n>:` line on stderr, and a
      summary count printed on every run *including zero*). ⛔ **Measured on `Ford_1941_Speech_.pdf`, all
      six sampled pages, two binaries differing in exactly this tool: p6 goes `all-text` → `picture` and
      p1–p5 do not move**, with `verdict` the only one of the thirteen fields differing on any row — ⚠️ not
      "twelve columns": `page` is the row key and three bar columns are the literal `-` with no `INKBAR`
      set, so **eight** carry information — the label moved
      and nothing else, because the bytes were always production's. The flip is term 3's alone from the row
      itself (`inkOut` 0.0056 against 0.045, `extent` 0.01498 against 0.05). ⚠️ p1 is the sharper control:
      labelled `loses` too and correctly unmoved, its loss being a hand-made mark at `lineN` 0.
      ⛔ **Two consequences bigger than the column.** The all-text aggregate — the summary line
      `Tools/README.md` points at as pricing TODO item 1, ⚠️ whose own cited 8.2 KB/page that cell already
      records as unreproducible (C25) — fell **436,633 → 224,977 B**, so **48.5%** of it was a page
      production never shrinks. ⚠️ That share is a six-page sample's, not the corpus's: the un-shrunk page
      necessarily dominates such an aggregate, and no corpus version exists. And the priced-bar **per-page
      cost was out by exactly 2x** while the row beside it disagreed: `INKBAR=0.0005` over p4/p6 read `2 of
      2 … 100,626 B/page`, now `1 of 2 … 201,252 B/page`, because p6 is `picture` at both bars and its own
      `barDelta` printed `same` in the same output — one unchanged delta divided by two pages instead of
      one. ⚠️ A draft said "out by 3.2x" from 5.76/1.79; the review of the diff refused it as a ratio of
      ratios over two different sets. The absolute delta is identical (+201,252 B) — `layeredAtBar` was
      always production's bytes.
      ✅ Watched failing: sabotaging the function's second `return` (the `nil` guard left intact) exits **5**
      naming row 3 of the new six-row table, whose case count is itself asserted. ⚠️ The loop exits on the
      first mismatch, so rows 1–2 are measured passing and 4–6 unreached — row 4 breaks by inspection, not
      by measurement. ⛔ **And the table pins the RESOLVER, not the column**: reintroduce the historical
      defect at the call site and all six rows still pass, and nothing in the suite could catch it, so what
      the design buys is harmlessness plus disclosure rather than detection. Said in place.
      ⛔ **Both verdict columns are reported; a first version discarded the bar side's flag**, which is where
      the divergence lives under a lower `INKBAR` — there is now a `VERDICT-AT-BAR` line and a second count.
      ⛔ **The `REPLICA-DISAGREES` tripwire had to be deliberately kept on the replica's own pair** — against
      the read-back it would compare production with itself, and a dead override moves neither side, so it
      would have gone quiet in the one case it exists for. ⚠️ **It is also now NOISY on C28's population**:
      the replica cannot mirror the shape term, so a disagreement is expected on the 16 of 73, and a draft
      offered one such firing as proof the dead-seam detector survived while the override was demonstrably
      alive in that run. The `VERDICT` / `VERDICT-AT-BAR` lines are what separate the two, and the code
      comment and end-of-run warning both say so now. ✅ Sibling sweep: nobody else replicates the
      guard (`score-mrc` asserts the constant on fixtures and already reads production's factor back;
      `score-threshold-loss`'s header says it cannot print this verdict; `score-shape-term`'s `verdict` is a
      status string; `sweep-ink-bar.py` only consumes the column, `--self-test` run and green at 71 checks —
      a no-op control, since the diff does not touch it).
      ⚠️ **One correction to this box's own instructions**: the tool has **no `--self-test` flag** — its
      self-tests are unconditional and exit 5, so nothing gates them (the hook self-tests Python tools
      only). `BUGS.md` C28 `#### The replica retired` carries all of it.
      The defect as it stood:
      ⛔ **`Tools/score-text-route.swift`'s hand-written copy of `pageIsAllText()`
      had TWO terms and the shipped guard has THREE.** Found 2026-08-23 by the adversarial review of
      `6d0caa1`, and verified by reading both: line 678 is
      `!keepEveryPixel && inkOut < Flattener.textPageInkOutsideThreshold && noPaleDrawing`, while
      `Sources/Flattener.swift` grew `textLineGroupsOutsideText` as a third refusal condition in `fbf6d87`
      (C28's wiring, 2026-08-22) and this was never updated. ⛔ **This is the THIRD repair of the SAME
      expression** — the comment directly above it records the first (a replica missing R56's pale-drawing
      clause, found by C26's own sibling sweep) and the second (`keepEveryPixel`) — so it is CONTRIBUTING
      4b's shape three times in one `let`. **Failure**: the tool now prints `verdict=all-text` and counts
      pages into `allTextLayered` / `allTextBilevel` / `allTextPages` on exactly the sub-bar pages the
      shape term refuses — the 16-of-73 population C28 exists for — so the instrument is wrong in the
      direction that HIDES C28. ⚠️ **No published figure moves**: every committed TSV pre-dates `fbf6d87`.
      ⚠️ `sweep-ink-bar.py` consumes this tool, so it inherits the same wrong verdict.
      ✅ **The fix is probably free and already in the tree**: `Flattener.MRCLayers.shrunkAsAllText` is
      production's own verdict and the tool already holds `shippedLayers` — read the verdict back rather
      than replicating it a fourth time, which is the remedy `WIDEN-LAYERS-2026-08-22.tsv` already used.
      ⚠️ `Tools/` is in the suite regex, so this is a FULL-HOOK commit; and a failing check first, since
      the tool has a `--self-test`. (context: BUGS.md C28 `#### The wiring, SHIPPED`; `Tools/score-text-route.swift:672-683`)
- [x] **c28-comment-fixes** — DONE 2026-08-23. ⚠️ **It was SIX claims, not three** — seven if the header's
      two retracted figures are counted apart. All three below are corrected in place, and claim 1's
      replacement mechanism is **measured** rather than reasoned: three binaries one `let` apart, and the
      rim failure survives the 3x3 baseline being emptied out, which is the control that proves the two
      scenes are unconnected. The sibling sweep (CONTRIBUTING 4b) then found three more that `2de4e50`,
      the docs-only follow-up — **2026-08-23 01:28, not 2026-08-22; the text it missed did not exist until
      `6d0caa1` at 00:10 the same morning** — did not reach, all in `BUGS.md`: (4) the same
      truncation-vs-splitting direction
      confusion as claim 3, in the register's own copy of the clearance argument; (5) the file **header**
      still carrying two of `#### The replica retired`'s own retracted draft figures ("twelve other
      columns" and "out by 3.2x"), in the load-bearing status summary; and (6) "all seven checks call
      `textLineGroupsOutsideText` through `c28Groups`", where two go through `c28Groups` alone, one through
      both, three through `c28InkOut` alone and one through `c28Calibration` — loose in exactly the place
      claim 2 is about.
      ⚠️ The review of this item's own diff then refuted two of its corrections and improved a third:
      "the fourth instance in this section" was a claim ordinal masquerading as an instance count (there
      are **two**); the follow-up's date was wrong; and the missed-word fixture's "the verdict below is the
      third term's" — which a draft of this box called simply correct — is a LIVE attribution that this
      commit now argues rather than asserts, because `paleDrawing` reads the render and not the boxes, so
      the positive control (same PDF, one more box, IS shrunk) is what rules term 2 out. Drop that control
      and the attribution is unpinned.
      ⚠️ Checked and NOT affected: `Tests/main.swift`'s "term 1 was reached and answered" is right, because
      `c28Missed` is the one fixture that does reach `mrcLayers` → `pageIsAllText()`; and
      `Tools/README.md` never published either mechanism.
      **The item as filed:**
      three prose claims inside `6d0caa1` that the review caught after the commit
      was already in flight, all verified wrong by reading and none affecting behaviour or any check.
      Correct them where they sit, in the code comments the docs-only follow-up could not reach.
      1. **`Tools/score-shape-term.swift:874-877` states a false mechanism.** It says the new 3x3 baseline
         "is in the **rim check's** scene as well", so a `shapeHeightLow` loosening trips two checks. It is
         not: the rim check builds its own 128x128 `rimMap` at lines 700-708 and `pGrey` is not declared
         until line 845. The *observation* is right and so is the quoted diagnostic — the real cause is the
         rim scene's own five 2x6 stubs losing three rows to the r=3 collar, becoming 2x3, which
         `shapeHeightLow = 0.0` then lets clear a floor of 5. Someone editing the 3x3 baseline would expect
         the rim check to move with it, and it will not.
      2. **`Tests/main.swift:2394-2396` claims a protection the architecture does not provide.** The
         below-bar check's comment says that otherwise "term 1 refuses the page and the third term is never
         consulted", making every check above green over unreached code. Every new check calls
         `Flattener.textLineGroupsOutsideText` **directly** through `c28Groups`; `pageIsAllText()` is never
         invoked, so term 1 cannot gate anything. The check's real value is fixture *realism* — that
         production would consult term 3 on such a page — and it should say so.
      3. **`Tests/main.swift:2371-2372` has the direction backwards.** "At 5x200 the bar starts three rows
         INSIDE the region" — it starts three rows **above** it (bar rows 1184-1383, padded region
         1187-1259), which is *why* each bar splits in two; one starting inside could only be truncated.
         The number 3 and the eight-components conclusion are right.
      ⚠️ 1 and 2 are also published in `BUGS.md` and in this file, and **those copies were corrected in the
      docs-only follow-up** — so the register and the code disagreed until this landed (they agree now;
      that disagreement was the reason this item was not optional). ⚠️ `Tests/`/`Tools/` are both in the
      suite regex: FULL-HOOK commit, comment-only, so `1,223/1,223` is the expected result.
      (context: BUGS.md C28 `#### The owed fixture`)
- [x] **queue-cite-rule** — **DONE 2026-08-23.** ⛔ **This file's own sub-box rule asserted the OPPOSITE of
      what `check-queue-coherence.sh` does about `(context: …)`, and stood wrong from 2026-08-19 to
      2026-08-23 while sixteen TICKED boxes depended on the real behaviour.** Nominated by the previous
      session's log as "worth an item" after it read the two and found they disagreed. ✅ **The measurement
      settled which side was wrong, on this file at `ad5861d` with one line of `cited()` widened**: shipped
      it reads `OK 56 items 6 cited`, exit 0; harvesting `context:` as well it reads **24 findings — 16 `TICKED-OPEN`,
      8 `WOULD-REDO`** over 31 cited items, and every one is correct bookkeeping — **fourteen of the sixteen
      are the `c28-*` sub-boxes the wrong rule's own section tells you how to write**, and two are
      `tools-compile` and `mutants`, the pair the `origin:`/`context:` bullets exist for, **each of which
      says CLOSED inside its own cite text** — two different strings, so do not quote one for both. So the
      prose moved, not the script. ✅ **The fix is a GATE**:
      `check-queue-coherence.sh --self-test`, fifteen checks in six deliberately different kinds (positive
      controls, negative controls on the rule, the two AGREEING quadrants, the `N_CITED` count, and an
      inverted row that VANISHES under the sabotage, and the CITE-MISSING and non-register-cite rows the review
      added), watched failing against **seven** `shasum`-distinct
      sabotages, all exit 5 with kill sets no other sabotage's set contains — 7 of 15 widening `cited()` to
      `context:`, 7 of 15 stopping it harvesting `origin:`, **2 of 15 loosening `TICKED-OPEN`'s
      `-gt 0` to `-ge 0`** and 3 of 15 stubbing `status_of()` closed. ⛔ **That third sabotage SURVIVED the
      first version of this self-test at 0 red and exit 0** — every ticked row it had either carried an open
      cite or no cite at all, so nothing could tell "has an open cite" from "cites anything"; the fix is the
      2x2 of {`[x]`,`[ ]`} against {cite OPEN, cite CLOSED} per CONTRIBUTING §4d, two cells of which had
      never been written down. Wired **warn-only** into
      `health-gate.sh` ahead of the check it protects, on the direction of failure: a hard step would park
      the run over a self-test on a checker that is itself warn-only. ⚠️ It pins the cite-word
      discrimination and the two verdicts, and **not** the greedy span rule, the fence skipping,
      `DUPLICATE-TAG`, or the mirror-`next-item.sh` property the header calls load-bearing — what is missing
      there is another KIND of row, not another cite-word row. Ops-only commit, so no suite.
      (origin: ops/autonomous/README.md D18)
- [ ] **register-dup-tag** — `BUGS.md` carries **two `### R63` headings** (lines 12145 and 12618), so the two
      register readers disagree about the register's size: `ops/autonomous/bugs-entry.sh --list` emits **169**
      rows and `check-queue-coherence.sh`'s inline fallback **168**, the fallback deduping via `seen[tag]`.
      Measured 2026-08-23 by the adversarial review of `queue-cite-rule`, which also corrected that script's
      comment claiming the fallback was a *"verbatim copy"* of the same rules. ⚠️ **No live consequence
      today** — both headings are `FIXED` and `status_of` takes the first match — but the answer becomes
      dependent on whether `bugs-entry.sh` happens to be executable the moment the two statuses diverge, and
      a duplicate REGISTER tag is the one class `check-queue-coherence.sh` flags in `QUEUE.md` and never in
      `BUGS.md`. Decide whether the second `R63` is a distinct entry needing its own tag or a stray heading,
      then consider whether either reader should REPORT a duplicate register tag rather than silently pick
      one. ⚠️ `check-queue-coherence.sh --self-test` is structurally blind to this (its fixture register has
      no duplicate tag and only `FIXED`/`OPEN`), so a fix wants its own fixture row.
      (context: ops/autonomous/README.md D18)
- [ ] **lock-reentrancy** — ⛔ **`test-lock.sh`'s reentrancy escape is in the `run` branch ONLY, so wrapping
      a `git commit` in the lock DEADLOCKS against its own pre-commit hook.** Measured 2026-08-22: a session
      ran `test-lock.sh run --label session -- git commit`. `run` exports `VISIONOCR_TEST_LOCK_HELD=1`
      (line 426) and honours it (line 400) — but `.githooks/pre-commit` line 129 calls
      `"$LOCK_SH" acquire`, and the `acquire` dispatch at line 393 never reads that variable. The hook then
      waited on a lock its own parent held, with **no `tests` process running at all**, and was refused at
      its 60-minute stuck-lock guard. `suite-timings.tsv` has the corpse: `pre-commit 19199  3994  143` —
      66 minutes, killed. Net ~80 minutes of suite time for nothing, and the strand it stranded is what
      `6d0caa1` finally landed.
      ⛔ **THE OBVIOUS FIX IS THE DANGEROUS ONE, which is why this is an item and not a one-liner.** Simply
      honouring the variable in `acquire` means any stale or exported `VISIONOCR_TEST_LOCK_HELD` lets a
      SECOND suite start — the one failure this lock exists to prevent (882/883 -> 877/879, two failures
      unrelated to any change, because both suites share `~/Library/Preferences/tests.plist`). A correct
      fix needs the paired `release` to become a reentrant no-op in the same breath, and the variable
      trusted only when the lock is genuinely held by a live ancestor — `lock-report`'s ancestry
      classification is the machinery that already exists for that. Watch it fail first: the deadlock
      reproduces in seconds with a `--wait 10`.
      ⚠️ Until it lands, the mitigation is documentation, and `resume-prompt.txt` STEP 4 now carries it:
      never wrap `git commit` in the lock. (context: `ops/autonomous/test-lock.sh:393-402,426`;
      `.githooks/pre-commit:129`; RUN.md's 2026-08-22 session entry)
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
      the full suite. Budget a commit, not a check.
      ⛔ **BOUND: the two halves are two sessions, and within each, ONE tool per commit.** *"Both halves"*
      reads as one item and is not one — each tool touched is a suite run. Survey both halves first in a
      free commit listing the tools and the verdict per tool, then fix them one at a time.
      (context: the sibling sweep in `BUGS.md` C26's
      instrument commit, 2026-08-18 — C26 is CLOSED and this is provenance, not a status claim; the
      rule is CONTRIBUTING §5)
- [ ] **argv-shape** — **the SIX that mis-measure, after the two that could destroy were fixed.** The
      sibling sweep of C26's driver commit classified the argument parse of all 29 `.swift` tools
      (2026-08-19, in `BUGS.md` C26's `Sub-step 3b, the driver` section). Eleven take a path list;
      **eight take one pdf and read argv[2..] as something else**, so a corpus glob is silently
      mis-measured. ⛔ **The two WRITERS are done — see the sub-box below and `BUGS.md` T19; do not
      re-open them.** What is left is the six that mis-measure and do not destroy, which is a different
      severity and was deliberately left by the owner (2026-08-19) to be *recorded* rather than swept:
      `score-text-route` (page numbers via `compactMap { Int($0) }`, line 88, and the only one that
      documents its own trap), `score-corpus` and `score-line-separation` (a label then three
      `SearchableWriter` factors via `if let Double`), `score-routing` and `picture-signals` (a label,
      rest unread), `score-annotations` (a second pdf).
      `score-rebuild-dpi` lines 70-72 is the counter-pattern to copy, and its comment already argues
      the case: *"Refused, not dropped… the row that never appears is indistinguishable from a
      resolution that was never asked for"*. `score-illumination` is a half-trap worth a line too — it
      DOES take a path list, but argv[1] is the population label, so a glob measures 232 of 233 and
      names the population after document 1. It has published no committed TSV, so nothing on disk is
      known to be wrong from it yet.
      ⚠️ Triage before coding: some of these are single-document utilities that are right as they are,
      and the answer per tool belongs in the commit. Any tool you touch is staged, so budget a commit
      (a full suite) rather than a check.
      ⛔ **BOUND: the triage of all six is ONE free commit — it is a judgement written down, no code —
      and then ONE tool per session.** Six guarded tools is six suite runs, 1.5 to 9 hours by the ledger,
      and reading *"the SIX that mis-measure"* as one session's work is the shape §"How to size an item"
      rule 4 exists to stop. Tick nothing until the sixth lands; give each tool its own sub-box under this
      one, following §"How to write an item"'s three constraints.
      (context: the sibling sweep in `BUGS.md` C26 — CLOSED
      2026-08-20; it is where this was found, not the work. Was `origin:` until C26 closed and the
      coherence check read it as a status claim, which is the mistake §"How to write an item" records
      `tools-compile` and `mutants` making)
- [x] **argv-writers** — **DONE 2026-08-20.** The two tools that WRITE argv[2], which is the half of
      `argv-shape` that could destroy `testdocs/`: FOCUS item 4 and the owner's decision of 2026-08-19.
      Measured on scratch fixtures, never on the corpus — the pre-fix `pdf-extract-pages` given three
      paths took **710,796 B to 809 B** on argv[2], exit 0, `extracted 0 pages`, with the third path
      dropped unreported. Both tools refuse now, by construction rather than by heuristic, and the
      guards are exercised mechanically by `Tools/fault-inject.sh argv_writers` — **13 checks, one per
      refusal, 3 passed / 10 failed against the pre-fix tools and 13 / 0 against the fix**. (Its first
      version had 7, four of which reached two guards; two rounds of adversarial review on the diff
      found the headline refusal could be deleted with every check still green — and then found the
      same defect again in the rows round one had added.) The refusal differs per tool
      on purpose:
      `pdf-extract-pages` writes the file type it reads, so existence is its only signal and
      `OVERWRITE=1` is the escape; `make-observations` writes JSON, so requiring `.json` separates the
      accident from a re-run with no override needed.
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
      wrong way round. (context: the sibling sweep in `BUGS.md` C26 — CLOSED
      2026-08-20; it is where this was found, not the work. Was `origin:` until C26 closed and the
      coherence check read it as a status claim, which is the mistake §"How to write an item" records
      `tools-compile` and `mutants` making)
- [ ] **sweep-exit5** — `Tools/sweep-ink-bar.py`'s `CONFIG_EXITS` does not include
      `score-text-route`'s exit **5** (self-test failed, nothing measured), added 2026-08-19 by C26's
      sub-step (4). A systematic self-test failure would therefore be **recorded as 233 failed
      documents** instead of aborting the sweep on the first one — the same class of silent-garbage run
      the constant exists to prevent. Named rather than fixed by the session that added the exit.
      ⚠️ **Three edits, not one**, and the tool's header says one: the constant, its `--self-test`
      assertion, and `EXPECTED_CHECKS`. A staged `Tools/*.py` carrying `--self-test` is hook-enforced,
      so the self-test runs; the suite runs too because the file is under `Tools/`.
      (context: the sibling sweep in `BUGS.md` C26 — CLOSED
      2026-08-20; it is where this was found, not the work. Was `origin:` until C26 closed and the
      coherence check read it as a status claim, which is the mistake §"How to write an item" records
      `tools-compile` and `mutants` making)
- [ ] **paledraw-term** — **UNTRIAGED, and carried out of C26 so it is not closed by silence.**
      `pageIsAllText()`'s SECOND term still ships blind: `paleDrawing(pageMarks(…)).extent` reads
      **0.00000** on p4 and p6 and 0.00029 on p7, so the guard's search finds *nothing* rather than
      finding something too small, and **no value of `paleDrawingThreshold` protects them**. C26 closed
      because its FIRST term (`inkOutsideText`, bar 0.045 since 2026-08-19) now refuses those three
      pages; the second term was never repaired and what it costs elsewhere is **unmeasured** — that is
      the whole of the claim here, and nothing is asserted beyond it. ⛔ **Do NOT tune
      `paleDrawingThreshold`** — refused on this document (R55, R56) and again on the 2026-08-18 corpus
      sweep, where 0.05 sits in a 4.9x gap, the useful range below it is one page wide, and none of it
      reaches 0.00000. So a fix, if there is one, is in what `pageMarks`/`paleDrawing` *find*, and the
      first honest step is triage rather than code: does the blind term lose anything the first term
      does not already refuse? Read C26 §"The drawings are INK" and §"What C26's close does NOT cover"
      before starting. (context: `BUGS.md` C26 — FIXED 2026-08-20; it is the evidence, not the work)

## HOLD — owner-only, never auto-executed

These are offered to nobody. `next-item.sh` prints them as `hold` so they stay visible without ever being
picked, and the resume prompt surfaces them to the run log instead of acting on them.

- [ ] **taborder** — the tab-order walk is still by hand. [hold] needs: owner — it needs
      `AppleKeyboardUIMode` set in the guest and reads focus rings out of pixel diffs between captures,
      and the owner accepted it as a known gap on 2026-08-13 rather than queueing it.
      (origin: TODO.md, the one open checkbox there)
- [ ] **release** — cutting a release: a version bump, `./build.sh --dmg`, `hdiutil`, a tag, a GitHub
      release. [hold] needs: owner — judgement about what is fit to ship. Last released: **1.13.1**,
      tagged `v1.13.1` and in `Info.plist` (this line said 1.12.0 until 2026-08-19 and was stale by one
      release, so it is now moved by the release itself rather than after it). **`1.13.1` was cut by
      the owner on 2026-08-20** — bumped, tagged, DMG built and verified, GitHub release published —
      with `C27` and `C28` open and sequenced into 1.14.0. This item stays `[hold]`: it is the standing
      release item, not a one-off, and nothing about cutting 1.13.1 makes a session fit to cut 1.14.0. The owner decided at the 2026-08-19 check-in that **`1.13.1` is cut by hand once C26's
      bar move has landed and he has read its gate** — ⚠️ **the bar move LANDED 2026-08-19 and no fresh
      corpus gate was run with it.** What is offered in its place is `INKBAR-2026-08-19.tsv`, which
      already holds the page-by-page comparison of exactly these two states over 233 documents, plus a
      grep establishing the constant has one read site and therefore cannot move a route. ✅ **The owner
      ACCEPTED that substitution as "its gate" at the 2026-08-19 check-in, so this precondition is now
      MET** and the item waits only on the release work itself, which stays owner-only; a fresh
      `score-gate` run is ~10 GB and hours, and R50 — the entry that introduced this constant — was
      accepted on one — C26 is invariant-1 content destruction on the
      shipped default and `v1.13.0` is the build carrying it; C27 is fidelity and rides in 1.14.0. That
      decision does NOT unhold this item: no session prepares, bumps, tags or builds a DMG.
      (origin: CHANGELOG.md, TECHNICAL.md)
- [ ] **corpus-write** — anything that WRITES the owner's **Zotero library**. [hold] needs: owner — it is
      his data and the one irreplaceable thing in this project. Reading it is fine and is how the corpus is
      built: `sample-zotero.py` copies `zotero.sqlite` because Zotero locks the original.
      ⛔ **`testdocs/` CAME OFF THIS HOLD ON 2026-08-22, owner's correction.** This line read "1.2 GB of
      third-party copyrighted PDFs … not regenerable without the source library", which is true and was
      being read as if the library were unavailable. It is not: *"Isn't the corpus easily regenerated? It's
      all just stuff from my zotero. As long as we're not touching my zotero library, we're fine, no?"* The
      corpus is a SAMPLE of the library, so the library is what needs protecting and the sample does not.
      ⚠️ **But `testdocs/` still is not something to rewrite casually, for a reason that is about EVIDENCE
      rather than permission.** `sample-zotero.py` has **no replay-by-key mode** — `--exclude-manifest` does
      the opposite, and there is no `--from-manifest` — so a rebuild is a fresh `random.seed(7)` stratified
      sample, and the tool's own docstring promises only an *equivalent* corpus, not the same 233 documents.
      A library that has grown since gives different picks, and every dated measurement keyed to specific
      documents and pages then stops being reproducible: `INKBAR-2026-08-19.tsv`'s 2,129 page rows,
      `SHAPETERM-*`, `CORPUS-2026-08-15.md`, the whole C26/C27/C28 campaign. So a session may write
      `testdocs/` when it has a stated reason, must never re-sample as a side effect of something else, and
      must say so loudly in the SESSION LOG when it does. (origin: CLAUDE.md §"Not committed")
