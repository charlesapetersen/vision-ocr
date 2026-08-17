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

## The queue

<!-- SEEDED 2026-08-16 when the daemon was built, from CLAUDE.md's status paragraph, BUGS.md's headings,
     TODO.md and HANDOFF-2026-08-17.md. Every item below is a POINTER that was true at seeding time and
     has NOT been re-verified by running anything. The first thing a session does with an item is read its
     cited material and confirm the work is still open and still described correctly — this project's own
     rule is that an entry without evidence is a rumour, and a queue line is at best a rumour about an
     entry. Delete an item that turns out to be already done, and say so in the commit. -->

- [ ] **C24b** — the remaining half of C24: the 45 pages that draw a *different* image than the shared
      `/Resources` dictionary holds still take the shared plate's resolution. The measurements and the two
      already-refused repairs are in the entry; read both refusals before proposing a third.
      MEASURED 2026-08-16 (still open): `Flattener.drawnLargestImage` + `Tools/score-drawn-images.swift`
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
      `Flattener.rebuildDPIOverride`): 92.8% word retention against the page's own embedded text at its
      own 70.6 DPI, 93.8% at the 300 fallback, 94.2% at the 369.6 it accidentally gets today — for 87%
      fewer published bytes. So `minimumScanPixelWidth` is right about all three pages it faces, needs no
      recalibration, and "rendering a page of type at 70 DPI is C9 again" was reasoned and is false.
      Note the trap: **counting characters, which this line asked for, reads 1,961 at every resolution
      from 70.6 to 369.6** and would have said "no difference" while being right by accident.
      **What is left is ONE thing**: wire the drawn walk into `rebuildDPI` behind a corpus gate run,
      because it moves 45 pages. Expect `score-drawn-images`'s sweep unchanged and `score-routing`'s two
      refused rows to come back.
      Read the entry's `C24b` section first, not this line. (origin: BUGS.md C24, HALF FIXED)
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
- [ ] **tools-compile** — run `Tools/check-tools-compile.sh` over *every* tool, not just the staged ones
      (~26 s), and fix or delete what does not build. It is a standing gate that today only runs on the
      files a commit happens to touch: `score-text-route` had never compiled in any commit, and an
      annotation change silently broke `score-skew` and `score-reading-order` eleven days later.
      (context: BUGS.md C25 and T16 — both CLOSED; they are why this gate matters, not the work itself)
- [ ] **mutants** — work the survivors in `Tools/mutation-log.tsv`. A surviving mutant is either a gap in
      the checks or a value nothing depends on, and `BUGS.md` T5 records how to tell those apart. Run it
      scoped (`python3 Tools/mutate.py --only <substring>`), never the full catalogue — that is ~65 hours
      at the C24b campaign's measured ~45 min per mutant over 89 mutants, not the ~55 hours this line
      claimed off a 39m30s sample nor the ~70 minutes it claimed before that; read the estimate the tool
      prints at startup instead, and note it was 4.22x low the one time anyone checked it out of sample —
      and never
      while `Sources/` is being edited. The work item is the live survivor list in
      `Tools/mutation-log.tsv`. (context: BUGS.md T5 — CLOSED; it records how to tell a real gap from a
      value nothing depends on)
- [ ] **fault-inject** — run `Tools/fault-inject.sh` over all its cases and confirm each sabotage is still
      refused by the real build step. It builds into a scratch copy of the tree, so it is safe unattended.
      (origin: Tools/fault-inject.sh)
- [ ] **A1.4** — the outstanding finding in review area 1. Read the entry before assuming it is still
      live: findings that graduated into `BUGS.md` are struck through in place there.
      (origin: REVIEW-2026-08-14.md A1.4)
- [ ] **A13.4** — the remainder of A13.4. Same caution as A1.4 about what has already graduated.
      (origin: REVIEW-2026-08-14.md A13.4)
- [ ] **A3.5** — observed but never triaged. Triage it: either it becomes a `BUGS.md` entry with
      measurements, or it is closed in place with the reason. (origin: REVIEW-2026-08-14.md A3.5)
- [ ] **annot-r3** — the third adversarial review round on the annotation-preservation feature. Rounds one
      and two are recorded; this is the round that has not been run.
      (origin: TODO.md §"Preserving annotations through re-OCR")
- [ ] **zotero-2** — the Zotero library sweep, steps 2-4. ⚠️ Step 1 wants re-running first; the survey it
      produced is dated. Reads a Zotero library, so copy `zotero.sqlite` before querying it — Zotero holds
      a lock on it. (origin: TODO.md §"2. The Zotero library sweep")

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
