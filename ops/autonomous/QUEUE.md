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
- [x] **c27-spot-colour** — finish C27: pages printed with a spot colour (a red rule, a red banner) lose
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
- [x] **c33-unselectable-blocks** — make every printed line on the owner's five reported pages
      selectable in Preview. The owner found these in the released 1.14.0, and making text selectable is
      what the app is for, so this comes first.
      THE DEFECT, which may be two. `BUGS.md` C33 has what was checked. (a) Real voids: on `Bird` p3 two
      blocks of the right-hand column, 14 lines in all, have no text layer at all, so C30's trigger or
      bands did not recover them. (b) Lines present but broken: on `Briefer` p3 and `Leland` p2 and p5,
      poppler finds a word box over every line, but PDFKit's selection drops some lines and returns
      garbage for others. Those lines sit where band observations overlap whole-page ones; that C30's
      merge causes it is inferred. Find the cause of each face in the code before fixing either.
      THE PAGES. `1951 - Briefer Book Notes` p3, `Leland - 1952 - We Believe in Employment on Merit, but`
      p2, p5 and p6, `Bird - 1963 - More Room at the Top …` p3, and the two-line block on
      `Hughes - The Knitting of Racial Groups in Industry` p3. Sources are in
      `~/.local/state/visionocr-autonomous/owner-supplied/`.
      THE INSTRUMENT HAS TO BE PDFKIT. Poppler read these pages as covered, and it is not what the
      owner uses. Measure selection with PDFKit (`PDFPage.selection(for:)`, `selectionsByLine()`),
      checking each line of the page's printed text against what PDFKit returns. That tool is part of
      this item and is reused by `corpus-stress`.
      DONE WHEN, on the published PDF: every printed line on those six pages comes back from PDFKit
      whole and correct; C30's Briefer figures (at least 3,300 words, void share at most 0.05) still
      hold; the four properties of `CLAUDE.md` invariant 3 hold; the new checks go red without the change.
      Then C33 closes `FIXED`, with a `CHANGELOG.md` line under a new `## Unreleased` heading.
      BOUND: one code commit per face if they turn out separate, plus one for the PDFKit tool, plus free
      docs commits.
      2026-09-26: both faces fixed and the tool landed (`Tools/pdfkit-lines`). One pattern is left and
      is the rest of this item: a band's whole line refused beside a half-line fragment the page kept.
      See C33 `#### MOSTLY FIXED`.
      (origin: BUGS.md C33)
- [x] **c31-colour-text** — make body text on a page the layered colour route keeps legible again. This
      is a regression in the released 1.14.0, so it comes before C28.
      THE DEFECT. On `1954 - Why.pdf` (source and 1.14.0 output in
      `~/.local/state/visionocr-autonomous/owner-supplied/`), the pages C27 now keeps in colour print
      their text in a mottled, washed-out fill. The owner calls it illegible. The stencil is complete;
      the 28 ppi foreground layer holds paper-coloured samples mixed in with the ink, so glyphs painted
      through the stencil come out broken and light. `BUGS.md` C31 has what was checked. Why the
      foreground mixes in paper is an inference; confirm the mechanism in the code before fixing it.
      WHAT A FIX HAS TO DO. Text drawn through the stencil should come out as dark and solid as in the
      source, and a coloured heading should stay coloured. A foreground built only from the ink under
      the stencil, a finer foreground, or a flat colour per glyph or region are the obvious routes; the
      choice is yours, with the rejected options recorded in one line each.
      DONE WHEN, measured on the PUBLISHED PDF rendered at 1:1 and at 400 dpi and looked at:
        * the body text on pages 2, 4, 6, 7 and 10 of `1954 - Why.pdf` is as legible as the source,
          the red headings are still red, and the drawings on pages 4 and 6 are unchanged;
        * the same holds on a sample of the other C27 pages you name, Schwaller photographs included,
          so the fix is not tuned to one pamphlet;
        * the corpus byte cost is measured and stated;
        * a new check goes red without the change.
      Then C31 closes `FIXED`, with a `CHANGELOG.md` line under a new `## Unreleased` heading (1.14.0
      has been cut).
      BOUND: one code commit, plus free docs commits for measurements.
      (origin: BUGS.md C31)
- [x] **c32-heading-colour** — keep the colour of red headings on pages that carry little other colour.
      On `1954 - Why.pdf`, pages 5, 8 and 9 have red headings in the source and come out black and
      white (`BUGS.md` C32). Find out why C27's `sheetFrac` route misses them, and change the colour
      decision so that pages like these keep their colour without admitting paper stains (the 1891
      typescript's foxing stays the negative case). Do this after C31, because it moves pages onto the
      layered route whose text fill C31 repairs.
      DONE WHEN: the headings on those three pages are red in the published PDF and the body text is
      as legible as the source; the pages the change newly moves across the corpus are counted, a sample
      is looked at, and the byte cost is stated; a new check goes red without the change. If no rule
      separates them from stains, close C32 `WONTFIX` with the measurement.
      BOUND: one code commit.
      (origin: BUGS.md C32)
- [x] **c34-columns** — write the text layer in reading order, column by column, so a drag selection
      stays inside one column. On `1954 - Why.pdf` p5 (a two-page spread) PDFKit's line order
      interleaves the two pages; on `Hughes - The Knitting of Racial Groups in Industry` p3 three Vision
      lines cross the gutter and join the two columns (`BUGS.md` C34). The owner asks for the columns to
      be distinguished harder. Detect columns from the page's observations (a gutter no line should
      cross), split observations that cross one, and emit runs column by column. `Tools/score-reading-order`
      exists; check what it measures before relying on it.
      DONE WHEN, measured through PDFKit on the published PDF: selecting down one column of those two
      pages never takes text from the other; no run crosses the gutter; single-column pages across a
      corpus sample are unchanged; invariant 3 holds; a new check goes red without the change.
      BOUND: one code commit.
      (origin: BUGS.md C34)
- [x] **c35-file-size** — find out why some already-OCR'd files come out several times larger than they
      went in: Dobbin 2.6 → 17.6 MB, Delton 0.95 → 8.3 MB, Hughes 0.5 → 3.0 MB, all made by Acrobat's
      Paper Capture (`BUGS.md` C35; the outputs are in `~/Desktop/Zotero PDF Transfer folder/` and the three
      sources in `$STATE/owner-supplied/`). Establish which route each
      page took and where the bytes go, and whether the growth buys anything (a better text layer). If
      it buys nothing, fix it in the same item: for example, a page whose rebuilt image is larger than
      the source's own could reuse it, or the rebuild resolution could follow the source. If it does
      buy something, say what and close C35 with the trade stated for the owner.
      DONE WHEN: a per-page table of route and bytes for the three files is committed, and either the
      outputs are no larger than needed with a check that goes red without the fix, or C35 records why
      the size is the price of something wanted.
      BOUND: one docs commit for the investigation, one code commit if a fix follows.
      (origin: BUGS.md C35)
- [x] **corpus-stress** — stress-test the app on the whole corpus and turn what it finds into queued work.
      Run the production pipeline end to end at default settings over every document in `testdocs/`
      (233 files) and the owner's test folder, `~/Desktop/Zotero PDF Transfer folder/` (read only; write
      outputs to scratch). For each page record: route taken, crash or error, time, output bytes against
      source bytes, text selectable through PDFKit against the ink on the page (the tool from
      `c33-unselectable-blocks`, not poppler), whether PDFKit's line order crosses columns, and whether
      colour in the source is lost in the output. Render a sample of the worst pages on each measure at
      1:1 and look at them, because C31 was a defect no number caught.
      OUTPUT: a TSV committed at the root, and for each confirmed defect class a short `BUGS.md` entry and
      a queue item placed above `c28-first-principles`, ranked by how much of a reader's text or content
      it loses. Findings that are already queued get one line in their existing entry, not a new one.
      BOUND: one step per session (the run itself, then the reading of it), each with its output committed.
      (context: owner request 2026-09-25, after the 1.14.0 test folder turned up six defects)
      2026-09-26: the run is done, `STRESS-2026-09-26.tsv` (tools `score-stress`, `stress-join.py`). 233/233
      corpus documents and 7/7 owner files succeeded, 17,397 pages, 161 min. The owner's Desktop folder hung
      on TCC, so the 7 files in `owner-supplied/` stood in for it. Left: the reading step. Crude first
      counts: 882 pages bareText > 0.3, 209 with a line across a gutter, and 64 documents larger than
      their source. Colour loss depends on the floor: 4 pages at srcColour > 0.05 with out < src/3, and
      46-58 at a floor of 0.01-0.02 with out < src/10. `owner/1954 - Why.pdf` is the same file as the
      testdocs copy, so it is counted twice.
      2026-09-26, the reading: about 40 of the worst pages on each measure were rendered and looked at.
      Two defect classes became C36 (sideways text, 21 pages) and C37 (JBIG2 sources re-encoded, 31
      documents grown), queued below; the evidence is `STRESS-READING-2026-09-26.tsv`.
      No new class of unread body text was found after C30/C33. The `bareText` pages that were looked at
      are scanner borders (Boltanski, every page), table rules, dotted plots, photographs and chart marks.
      A few chart and axis labels go unread, and no item was opened for them. What the instruments got
      wrong, one line each:
      - `bareText` and `gutter` are void on layered pages: at 100 dpi CoreGraphics renders the stencil's
        text lighter than 128, so only the picture counts as ink (Ehrenreich p4: 3,955 characters, 100%
        bare).
      - Borders past the 3% margin count as text.
      - `warnDigitalText` is off in the gate, so born-digital files were rasterised, which the app would
        ask about first (the Silicon Valley transcript's colour loss).
      Colour otherwise: the Jane Stanford typescript's paper tint goes to grey, as decided in R33. Tables
      after C34: one line in that entry. Speed: single newspaper pages take 40-60 s, and the median is
      3.7 s a page.
- [ ] **c36-sideways-text** — give text that reads sideways on the published page a text layer that lies
      along the printed line, at the printed size. Today it is drawn flat and squashed to about 1.5 pt,
      so Find works but a drag over the line selects nothing (`BUGS.md` C36). There are two sources:
      Koh 2008's `/Rotate 270` landscape pages (pp71-73, 90-92, 125-129, 168-169), and 8 `rot 0` pages
      with sideways print. Either half alone is an acceptable first commit if the other is recorded as left.
      DONE WHEN, measured on the published PDF:
      * on Koh p127, PDFKit's selection boxes for the sideways lines lie over their printed ink, and the
        text extracts in reading order;
      * re-measured with the squashed-word count of C36, none of the 21 pages is above 10%;
      * upright pages' layers are unchanged on a named sample, and invariant 3 holds;
      * each new check goes red without the change.
      BOUND: one code commit.
      (origin: BUGS.md C36)
- [ ] **c37-keep-jbig2** — publish a page whose source image is already 1-bit JBIG2 with that stream
      (and its `/JBIG2Globals`, if any) kept as it is, when the rebuilt bitmap is provably the same image.
      Today those pages are re-encoded: 51 documents go from 219.9 to 258.8 MB, and 31 of them grow, by up
      to 2.5x (`BUGS.md` C37).
      DONE WHEN:
      * the `jbig2-source` documents are re-published and measured;
      * every kept page's rendered pixels are identical to the source's;
      * no page's image stream grows, and the 31 larger documents shrink, with the total stated;
      * no page whose rebuild differs from its source image (cropped, cleaned, resampled, or turned by
        `/Rotate` without the turn restored) takes the new route;
      * a check goes red without the change.
      BOUND: one code commit.
      (origin: BUGS.md C37)
- [ ] **c28-first-principles** — fix C28 again, starting from first principles. The owner took it off the
      parked list on 2026-09-25 and asked for a fresh attempt, not a continuation of the old campaign.
      THE DEFECT. On the layered (MRC) route, the 1-bit stencil is the page's adaptive binarisation
      intersected with the geometry of the words Vision recognised (`textRegionMask`,
      `Sources/Flattener.swift`). So ink the recogniser did not box as a word is in neither the stencil
      nor the text layer. It survives only in the background, which on a page read as all text is stored
      at 1/8 of the page's resolution and is illegible there. Of the 73 pages the all-text route
      shrinks, 16 lose content. Twelve lose type (numbers from a correlation matrix, lines of prose,
      words, an equation) and five lose a hand-made mark (a signature, pencil annotations, a cartoon);
      one page is in both groups. The `label` column of `SHAPETERM-73-2026-08-21.tsv` names them. The
      shape term that shipped 2026-08-22 routes 13 of the 16 away from the shrink. Three hand-made
      marks are still lost, and the term also fires on pages that lose nothing.
      FIRST PRINCIPLES means this. Read only the C28 entry's opening, up to and including "The
      one-sentence statement", and its `#### The wiring, SHIPPED` section. Do not read or continue the
      measurement sections, mutants or grouping-constant trades after them; they audited a route
      choice for a month and changed no code. Start from the code and ask what a correct stencil would
      hold. Consider fixes at the mechanism, meaning what goes into the stencil or how unboxed ink is
      stored, as well as fixes to the route choice. Keeping, replacing or removing the shape term is
      your call. Record the approaches you rejected in one line each.
      DONE WHEN, measured on the PUBLISHED PDF rendered at 1:1 and looked at, not on a tool's proxy:
        * the content each of the 16 pages loses today is legible, including the three marks the
          shape term misses;
        * pages that lose nothing today are not visibly worse, checked on a sample you name;
        * the corpus byte cost of the change is measured and stated;
        * the four text-layer properties of `CLAUDE.md` invariant 3 still hold, and the new checks go
          red without the change.
      If the three marks cannot be reached at a reasonable cost, ship the version that reaches the
      most and state the price of the rest. If nothing beats the shipped shape term, close C28
      `WONTFIX` with the measurement as the reason. Either way add a `CHANGELOG.md` Unreleased line for
      a shipped change. A sub-step finished before the park is filed at
      `$STATE/rescue/PARKED-C28-vo-20260921-080042-95562.patch.bak`. It belongs to the old campaign; you
      do not have to apply it, and leave the file where it is.
      BOUND: one code commit, plus free docs commits for measurements. Rule 4 applies.
      (origin: BUGS.md C28)
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

Nothing. C28 was parked here from 2026-09-21 until the owner brought it back into the queue on
2026-09-25 as `c28-first-principles`.

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
