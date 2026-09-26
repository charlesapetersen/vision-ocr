# Autonomous work queue

The order in which an unattended session picks up work. `ops/autonomous/next-item.sh` resolves it and
`ops/autonomous/check-queue-coherence.sh` cross-checks it against `BUGS.md`.

This queue was reset on 2026-09-24. The previous one (668 KB, 121 items, most of them work on the
project's own tools and documents) is kept verbatim at `docs/history/QUEUE-2026-09-24.md`. Its open items
are not offered. Do not copy one back unless an item below needs it as a direct prerequisite, and then
say so in the commit.

## The rules for this file

1. **Product first.** An item earns a place here by changing what the app does for the person using it:
   text that becomes selectable, content that stops being lost, files that get smaller. Tool, document
   and daemon work belongs here only as a named prerequisite of such an item.
2. **Every item says when it is done**, in terms of the app's output, and how much work it is allowed.
3. **Findings about instruments or prose do not become items.** If a session finds an instrument or a
   sentence is wrong and the error does not change what gets built, it writes one line in the relevant
   `BUGS.md` entry and carries on with its item.
4. **Three sessions, then decide.** If an item citing a `BUGS.md` entry has taken three sessions without a commit that changes
   `Sources/` or `Helper/`, the next session ships the best fix the evidence supports, or closes the entry
   as `WONTFIX` with the reason. It does not open another sub-step. A technical call is the session's to
   make; record the option rejected.
5. **Format.** One checkbox line per item, then indented prose, ending with the cite:

```
- [ ] **<tag>** — <what to do>. (origin: BUGS.md C30)
- [ ] **<tag>** — <…> (blocked-on: <othertag>)
- [ ] **<tag>** — <…> [hold] needs: owner — <why>
```

   `(origin: BUGS.md X)` means the item is that entry and is done when the entry closes; the coherence
   check enforces that. `(context: …)` is a footnote with no status claim. Never quote the hold marker
   or the owner marker inside another item's prose: `next-item.sh` would read that item as held. Tick a
   box only in the commit that finishes the work. To record a finished part of a big item, add a separate
   ticked box with its own tag after the parent's cite line, citing `context:` and not `origin:`.

## The queue

- [x] **c30-tiled-recall** — make Vision read the blocks it currently skips, by recognising a page again
      in overlapping horizontal bands when the whole-page pass leaves inked areas with no words.
      THE DEFECT. The owner reported that on JSTOR/ProQuest scans only about half of a page is selectable.
      On `1951 - Briefer Book Notes.pdf` (6 pages, now at
      `~/.local/state/visionocr-autonomous/owner-supplied/`) 15–43% of each page's ink is in long runs with
      no word box, and the missing blocks are clean, legible type. `BUGS.md` C30 settled the cause: it is
      recogniser recall on a request covering the whole page, not the writer.
      THE EVIDENCE FOR THE FIX is `C30-TILES-2026-08-25.tsv`. Recognising the same page in bands, with no
      overlap between them, took the document from 2,080 words to 3,577 at 8 bands, and the tool's void share
      from 21–45% per page to at most 6.8%, three pages at zero. Fewer bands were uneven (4 bands did
      worse than 2 on some pages).
      Non-overlapping bands cut lines at their edges, which is the likely reason, and overlap plus a merge
      is the standard remedy. Do not re-measure the question of whether tiling helps; it does.
      WHAT TO BUILD, as one code commit:
        * a band plan: given a page image's size, the bands to recognise, each overlapping the next by at
          least two line heights so that every line lies whole inside some band. Pick the band height
          from the evidence (8 bands on a ~4,400 px page, about 550 px, did best) and state the rule.
        * a merge: keep every whole-page observation; add a band observation, mapped back to page
          coordinates, only when it does not substantially overlap one already kept. Choose the overlap
          test and threshold and say why in a comment.
        * the trigger: run the bands only on pages where the whole-page result leaves a void (a long run
          of inked rows with no observation), so pages that recognise fully cost nothing extra. If a
          trigger turns out unreliable, running bands on every page is acceptable when the time cost is
          measured and stated.
        * it must run in production's path, on the bitmaps `Flattener.flatten` rebuilds, which is what the
          app recognises. Find the call site from `Sources/Model.swift`'s recognition call.
      TESTS. Unit checks on the band plan (covers the page, overlap holds, two page sizes and a rotated
      page per invariant 5) and on the merge (duplicate in an overlap dropped, novel observation kept,
      whole-page observation wins). Watch each fail against the code without the change.
      DONE WHEN, measured on the PUBLISHED PDF the pipeline writes for the Briefer document, not on a
      tool's own recognition, and written into C30:
        * at least 3,300 selectable words (baseline 2,080), with no line of text duplicated by the
          merge (compare repeated line strings against the whole-page run);
        * the share of inked rows with no text-layer run over them is at or under 0.05 on every page.
          `Tools/score-text-voids` recognises the page itself (it calls `Recogniser.recognise`), so
          as it stands it cannot see the fix. Either teach it to read the output's text layer, or
          have it call the new production entry point; that tool change is part of this item. Mind
          the box padding the entry records as inflating the void figure.
        * the four text-layer properties in `CLAUDE.md` invariant 3 re-checked on that output and on
          two corpus documents, and recognition time per page before and after recorded.
      Then C30 closes `FIXED`, with a `CHANGELOG.md` Unreleased line.
      BOUND: one code commit for the fix and its tests, one for the instrument if it needs changing, and
      free docs commits for measurements. Do not build a setting for it unless the time cost forces one.
      (origin: BUGS.md C30)
- [x] **c29-short-page** — finish C29: a born-digital page with fewer than 120 characters of text is
      still rasterised and re-OCR'd, and no report line names it. Decide the rule for a short page yourself
      from the evidence in `BUGS.md` C29, implement it with a test that fails without it, and close C29
      `FIXED`. The danger runs the other way too: a page wrongly passed through is never recognised, and
      that silently loses text (invariant 1). So the rule must not pass through an already-OCR'd scan:
      exclude invisible text (render mode 3), and cover the two known misses of `pageIsAnImage` that
      C29 records (a scan narrower than 900 px, and an inline `BI/ID/EI` image). If no rule is safe, at
      least name the rasterised short page in the report. The owner's JSTOR example in
      `~/.local/state/visionocr-autonomous/owner-supplied/` has a 1,022-character cover, so it is not a
      short page; the test needs a generated fixture. BOUND: one code commit.
      (origin: BUGS.md C29)
- [ ] **c27-spot-colour** — finish C27: pages printed with a spot colour (a red rule, a red banner) lose
      it, because the colour decision compares the page's MEAN saturation against a bar. The bar's value is
      measured 2026-08-27/28 (`BUGS.md` C27 `#### The window, MEASURED`): no value beats the shipped
      0.06, so leave the constant alone. The route left is a different measure, `sheetFrac`
      (measured in C27 (a)), which fires on exactly the 6 real colour pages among 48 candidates and on
      nothing else, but misses the *New Republic* page's red rule and banner. Add it as a second way for a
      page to keep its colour, alongside the existing bar and never replacing it (a page that keeps colour
      today, `Atkinson_1939` p2, fails `sheetFrac`), or add a refinement of it that also reaches that page
      without admitting paper stains (the 1891
      typescript's brown foxing is the negative case), and ship it with a test. If no rule separates the
      real pages from the stains, close C27 `WONTFIX` with the measurement as the reason. Record the
      corpus byte cost either way. BOUND: one code commit.
      (origin: BUGS.md C27)
- [ ] **annot-r3** — the third adversarial review round on the annotation-preservation feature (on
      `main`, off by default, unadvertised). Rounds one and two are recorded in `TODO.md`. Run the review
      by subagent, fix what it finds that is real, and record the verdict on whether the feature is fit to
      turn on. BOUND: one review round and its fixes.
      (origin: TODO.md §"Preserving annotations through re-OCR")
- [ ] **zotero-2** — the Zotero library sweep: look for new classes of document the app handles badly.
      Re-run step 1 of `TODO.md` §"2. The Zotero library sweep" first; its survey is dated. Copy
      `zotero.sqlite` before querying it, because Zotero locks it, and never write the library. BOUND: one
      step per session, with its output committed. Each confirmed defect it finds becomes a `BUGS.md` entry
      and a queue item above this one.
      (origin: TODO.md §"2. The Zotero library sweep")

## Parked

- [ ] **C28** — [hold] PARKED BY THE OWNER 2026-09-21. The shape-term fix shipped 2026-08-22 and rescues
      13 of 16 measured losses; the campaign afterwards audited its own measurements for a month. The
      remaining decision (whether three hand-made marks are worth six pages that lose nothing) waits for
      the owner. A finished answer to one of its sub-steps, from the stranded worktree
      `vo-20260921-080042-95562`, is filed at `$STATE/rescue/PARKED-C28-vo-20260921-080042-95562.patch.bak`
      (removed from `/private/tmp` 2026-09-24 after proving the patch reproduces it); leave it there.
      (origin: BUGS.md C28)

## HOLD — owner-only, never auto-executed

These are offered to nobody. `next-item.sh` prints them as `hold` so they stay visible.

- [ ] **taborder** — the tab-order walk is still by hand. [hold] needs: owner — accepted by the owner
      as a known gap on 2026-08-13.
      (origin: TODO.md, the one open checkbox there)
- [ ] **release** — cutting a release: a version bump, `./build.sh --dmg`, a tag, a GitHub release.
      [hold] needs: owner — publishing notifies every running copy through `Sources/Updater.swift`. Last
      released: 1.13.1 (2026-08-20). No session prepares, bumps, tags or builds a DMG.
      (origin: CHANGELOG.md, TECHNICAL.md)
- [ ] **corpus-write** — anything that writes the owner's Zotero library. [hold] needs: owner — it is
      the owner's data and the one irreplaceable thing in this project. Reading it is fine. `testdocs/` may be
      written with a stated reason, but never re-sampled as a side effect: the dated measurements are keyed
      to its exact documents and pages.
      (origin: CLAUDE.md §"Not committed")
