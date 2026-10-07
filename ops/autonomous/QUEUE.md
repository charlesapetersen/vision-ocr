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
   `Sources/` or `Helper/`, the next session ships the best fix the evidence supports. It does not open
   another sub-step. A technical call is the session's to make; record the option rejected. Closing the
   entry `WONTFIX` instead is governed by rule 8.
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

6. **Done means verified as the reader sees it.** A box is ticked, and an entry closed, only after the
   item's DONE WHEN is checked on the published output through PDFKit, which is what Preview uses, by the
   session and then by a separate verifying subagent (resume prompt STEP 3.5).
7. **Attempts and effort.** The daemon counts the sessions it runs on an item that end with the item
   still open and no box ticked; a session that ticks a sub-box for a finished part is not a failed
   attempt, nor is one that opened at 85% or more of the usage window (owner, 2026-10-01). It adds the item's `(attempts: N)` marker, which records failures found later, by the
   owner or a check. From the third attempt the session runs at `max` effort instead of the default
   `medium`, with a $140 budget cap instead of $70 and an 8-hour time limit instead of 4. `(effort: <level>)` on an item sets its effort outright. When a ticked item is found not
   fixed, reopen it or queue its successor with `(attempts: N)` carried over.
8. **No `WONTFIX` before two max-effort sessions (owner, 2026-09-26).** An unattended session may close an
   entry `WONTFIX` only if it runs at `max` and an earlier max-effort session has already tried the item.
   A session that concludes `WONTFIX` sooner writes its case in the entry, leaves the box open and commits
   the rest; the attempt count then brings the item back at `max`. The pre-commit hook refuses a commit
   that breaks this. Wording in an item that says "close it `WONTFIX`" means "make the case for it" until
   then.
9. **The regression set must not get worse (2026-09-28).** An item that changes `Sources/` or `Helper/` is
   done only when `Tools/ux-regression.sh` reports nothing worse on `ops/ux-regression/set.tsv`, or the
   item's `BUGS.md` entry states each regression it reports and why it is accepted. A commit that makes a
   set page better, or accepts a regression, refreshes the baseline with `--baseline` and says so. Exit 3
   (the owner's files or the corpus absent) is not a pass. It runs the pipeline: run it alone, like the suite.

10. **Bounds are sessions, in two rounds (owner, 2026-10-02).** A product item may take up to four
   sessions in its first round, with any number of code commits in each; a session counts when it works on
   the item, whether it commits or not, and adds a dated line to the item saying which session of which
   round it was. If the item is still open after four, it moves behind the untried items. When it comes
   back it gets a second round of up to four sessions, all at `max` (add `(effort: max)`). If it is still
   open after the second round it leaves the queue: the session closes it `WONTFIX` with the case in its
   `BUGS.md` entry (rule 8 is met by then), or moves it to Parked with what was tried and what blocks it.
   Parked items come back only by the owner's hand. Rule 4 still applies inside a round. This replaces the
   one-code-commit bounds, which stopped a session that had a second real fix to make.
11. **Size an item before queuing it (owner, 2026-10-04).** Every new item states an ESTIMATE in sessions.
   One estimated at more than four sessions is split until each piece fits a round, and each piece is cut
   into sub-boxes (rule 5) small enough that one medium session can finish one and tick it. Long unattended
   computing (a model over a sample, a corpus run) goes into a detached, resumable job that holds
   `$STATE/engine.lock` while it runs, so the daemon starts no session to wait on it. Max effort is for work
   medium cannot do: the daemon raises an item after two counted attempts (rule 7), and with parts sized
   this way a counted attempt means a medium session that finished nothing. Outside rule 10's second round,
   do not mark an item `(effort: max)`, and use `(effort: medium)` only where escalation cannot help.

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
- [x] **c36-sideways-text** — give text that reads sideways on the published page a text layer that lies
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
- [x] **c37-keep-jbig2** — publish a page whose source image is already 1-bit JBIG2 with that stream
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
- [x] **c38-preview-text** — make the text on layered pages as legible in Preview as it is in the source.
      Today it is sharp in poppler and a blur in PDFKit, which is what the owner reads with (`BUGS.md` C38).
      C31 was closed on a poppler render, and C32 then moved three more pages of `1954 - Why.pdf` onto the
      route, so the owner's file got worse. (attempts: 1) — C31's fix was the first attempt.
      THE INSTRUMENT IS PDFKIT. Render the published page with `PDFPage.draw` into a bitmap, at 1x and 2x,
      and look at it beside the source rendered the same way. `pdftoppm` is not evidence for this item.
      A renderer is in `$STATE/owner-supplied/renders-2026-09-26/r.swift`.
      WHAT A FIX HAS TO DO. Confirm the mechanism in the code and in PDFKit first. The obvious routes: paint
      the text through the stencil at the stencil's own resolution (an `/ImageMask`, or the stencil as a
      clip over the foreground) instead of as an `/SMask` on a small image; raise the foreground to the
      stencil's resolution; or send text pages back to the 1-bit route. The choice is yours, with the
      rejected ones recorded in one line each.
      DONE WHEN, on the published PDF rendered through PDFKit at 1:1 and 2x and looked at:
        * the body text on every layered page of `1954 - Why.pdf` is as legible as the source, and the red
          headings are still red;
        * the same holds on a sample of other layered pages that you name, Schwaller photographs, the
          Surani map and Raskin included;
        * the same pages are no worse in poppler;
        * the corpus byte cost is measured and stated;
        * a new check that renders through PDFKit goes red without the change.
      Then C38 closes `FIXED`, with a `CHANGELOG.md` line under `## Unreleased`.
      BOUND: one code commit, plus free docs commits for measurements.
      (origin: BUGS.md C38)
- [x] **c39-newspaper-page** — make a large newspaper page readable and selectable, or show that it cannot
      be done at a reasonable cost. On `Raskin - 1956` (one NYT page, 1,067 x 1,547 pt, 300 ppi source) the
      rebuild is 125 ppi and the text layer is misread, crosses columns and has runs 1.6 pt tall
      (`BUGS.md` C39). The owner asks for an attempt and accepts that it may fail.
      Find out first why the rebuild is 125 ppi, and what Vision reads at the source's own resolution, as a
      whole page and in tiles. Then fix what the evidence supports.
      DONE WHEN, on the published PDF, through PDFKit:
        * three paragraphs you name, checked by hand against the source, are selectable and read correctly
          apart from a stated number of misread words;
        * selecting down one column never takes text from the next, and no run crosses a column;
        * time for the page, and bytes, are stated before and after;
        * a new check goes red without the change.
      If the page cannot be made usable at a reasonable cost, ship the best improvement the evidence
      supports and state what is left, or close C39 `WONTFIX` with the measurement.
      BOUND: one code commit, plus free docs commits.
      2026-09-26: the code commit is spent. Strips are read one at a time at 301 DPI and no run crosses a
      column, but drag selection in PDFKit still leaks between columns (C39 "Left"). Open for that alone;
      the next session should close it `WONTFIX` for selection unless it has a new idea about PDFKit's blocks.
      2026-09-26: closed `WONTFIX` for selection; Form XObjects per column and a Tagged PDF structure
      tree were tried on the real file and PDFKit ignores both (C39).
      2026-09-26, owner: REOPENED, because it was closed at medium effort (rule 8), and WIDENED from
      Raskin to full newspaper pages in general. (attempts: 1) — the medium session that closed it; with
      the one the daemon counted, the next session runs at max. Read C39's "Left" and what was tried
      before starting, and try something else.
      MORE THAN ONE PAGE. Newspaper pages differ a lot in how hard they are, and progress on the easier
      ones is worth shipping even if Raskin stays hard. Work on Raskin and at least six other full pages
      from `testdocs/`, covering both kinds the corpus has:
        * ProQuest paste-ups: `newspaperArticle/Zipkin_2000_Management.pdf`, the two Newsday pages
          (`_1973_Other 67 …` and `Berendzen_1981 …`), and `JOURNAL_1969_Giving the Boss a Raise …` p1;
        * whole-page scans of small-town papers: `_1941_Fiedler's hiring …_Helena Independent.pdf`,
          `_1926_Clapp defends Cox_Billings Gazette.pdf`, `_1939_Kalispell resident …`,
          `_1950_Comic_Independent Record.pdf`, and `document/October_2,_1960_(Page_24_of_25.pdf`.
      For each page, before and after, through PDFKit: misread words in one paragraph checked by hand,
      runs that cross a column, and the share of a drag down each column that stays in it. Rank the
      pages from easiest to hardest in the entry.
      DONE WHEN, restated for this reopening: the table above is in C39, every page that can be improved
      is, and each page that cannot is named with what was tried. A gain on some pages ships on its own.
      `WONTFIX` applies only to what no max-effort session could improve, under rule 8.
      2026-09-26, first max-effort session: the ten-page table is in C39, with what PDFKit does and what was
      tried on drag selection; no page is improved yet. Drag selection: C39 makes the case for `WONTFIX`,
      for the next max-effort session to decide (rule 8). Reading: a swap of the bands' cleaner reading on
      whole-page scans (up to five points more words in a dictionary) is parked in `$STATE/rescue/` with the
      five defects the review found; finish it against those before shipping it.
      2026-09-27, max effort: a layered page's type is published at its mask's resolution and read where
      it was. Reading the 1-bit pages there too gained 4,876 dictionary words on 35 documents but lost 14
      lines; it waits for a merge of the two readings (C39). The drag and cross measures used so far are
      unsound (`characterBounds`); re-measure with one-character selections before deciding `WONTFIX`.
      2026-09-27, max effort: drag re-measured with `Tools/pdfkit-drag` (one-character selections) and
      closed `WONTFIX` under rule 8, with what was tried in C39. A raised 1-bit page's lines come from the
      copy and their words from the page (`finerReading`): +2,722 dictionary words on 32 documents, no line
      lost, 28% more time; WSJ 1969's named paragraph 8 -> 4 misread words. Adopted from a session stopped
      by its usage limit, after a review that tightened the guards. The parked band swap redone as
      `finerReading` over clean band lines buys at most 0.3 points on the five whole-page scans (C39
      "Left"). Still open: the rows fused across columns on
      the whole-page scans (6 to 30 a page), and a layered picture page's finer reading (Berendzen).
      2026-09-27, owner: SPLIT. Closed on what shipped; the whole-page scans' reading is `c41-newspaper-scans`.
      (origin: BUGS.md C39)
- [x] **c40-columns-figure** — split the four rows on Hughes p5 that still join the two columns
      (`BUGS.md` C40). Use the owner's Desktop copy in `$STATE/owner-supplied/`. Find why C34's gutter
      detection misses this page before changing it.
      DONE WHEN, through PDFKit on the published PDF: no run on p5 crosses the gutter, a drag down either
      column stays in it, and the 206 pages C34 measured as unchanged are still unchanged
      (`Tools/pdfkit-lines --diff`); invariant 3 holds; a new check goes red without the change.
      BOUND: one code commit.
      (origin: BUGS.md C40)
- [x] **c37-owner-files** — measure the owner's two grown files after C37 and shrink them if C37 did not.
      Delton (954,409 → 2,487,160 B) and the Desktop copy of Hughes (490,599 → 947,326 B) were built from
      `24a8f6a`, before C37 landed. Both are Acrobat Paper Capture scans with 600 dpi 1-bit JBIG2 pages
      (`BUGS.md` C35). Re-publish both Hughes copies and Delton, and state bytes per page against the source.
      If a page does not keep its stream, find which of C37's conditions refused it, and fix it if the
      refusal is not needed.
      DONE WHEN: each file is no larger than its source plus its text layer, or the entry states what the
      extra bytes buy; a new check goes red without a fix, if one is made.
      BOUND: one docs commit, and one code commit if a fix follows.
      (context: BUGS.md C35 and C37 — both closed; the owner reported the size 2026-09-26)
- [x] **ux-harness** — build the instrument for a usability stress test measured the way a reader meets
      the file: opened in Preview. PDFKit and CoreGraphics are the only renderers and text readers that
      count. `pdftoppm`, `pdftotext` and poppler word boxes are not evidence, because C31 was closed on a
      poppler render that looked nothing like Preview (`BUGS.md` C38).
      WHAT IT MEASURES, per page, comparing the published PDF with its source:
        * legibility: render both through PDFKit at 1x and 2x. Run Vision on the two renders and compare
          the words it reads, as a proxy for whether a person can read the output as well as the source.
          Also compare how dark and solid the strokes are. Save the renders, so a page can be looked at.
        * colour: whether colour visible in the source's render is visible in the output's.
        * find: take a sample of words Vision reads from a high-resolution render of the source, search for
          them with `PDFDocument.findString`, and check that each hit's bounds lie over that word's ink.
        * selection: for each column seen in the source render, drag from its top to its bottom with
          `PDFPage.selection(from:to:)`. Record whether the selection stays inside the column, covers
          every line in it, and whether its boxes lie over the ink.
        * copy: the selection's `string` against the words read from the source: word error rate, words
          split by stray spaces, hyphen joins that are wrong or missed, and line breaks in mid-sentence.
        * orientation and size: the page's displayed rotation, media and crop boxes against the source's.
        * time: PDFKit render time per page at 1x.
      And per document: the time to open it, and whether it opens without complaint (`PDFDocument` loads,
      `qpdf --check` is clean); the outline, page labels, links, annotations and document title against
      the source's; the page count; bytes against the source's.
      IT MUST BE SHOWN TO CATCH WHAT THE OWNER CAUGHT. Before it is used, it goes red on each of these,
      all in `$STATE/owner-supplied/`: Why at `24a8f6a` pp5-6 (legibility), Why at 1.14.0 p5 (colour of the
      red headings), Raskin at `24a8f6a` (selection, columns, misread words), and Hughes (Desktop copy)
      at `24a8f6a` p5 (a selection that leaves its column). It stays green on a named sample of pages
      that look right in Preview. Record each of those results.
      BOUND: one commit for the tool and its self-test.
      DONE 2026-09-27: `Tools/ux-harness.swift`, `Tools/ux-harness-selftest.sh`; results per page in
      `UX-HARNESS-SELFTEST-2026-09-27.tsv`. Red on all four reports for the named reason; green on Why
      pp3-8, Briefer pp1-6 and Hughes pp1-3, 5, 7-9 from the current pipeline, and on a rotated fixture.
      Found on the current pipeline while calibrating, for `ux-read`: Why p9 and Hughes p6 drags take
      the other column (inside 0.77, 0.54); Briefer loses its page labels (A-F become 1-6); Hughes loses
      its document title; Hughes p4's diagram labels are not findable; Why p10's logo is grey (C38);
      Briefer's copy echoes a hyphenated word's tail ("practices tices"). About 8 s a page: `ux-run`
      over 17,000 pages needs a page sample per document.
      (context: owner request 2026-09-26, after the defects the first stress test missed)
- [x] **ux-run** — run `ux-harness` over every document in `testdocs/` and every file the owner has
      supplied, at default settings, through the production pipeline. The owner's Desktop folder hung on
      TCC last time, so use `$STATE/owner-supplied/`, and list each owner file with the result it got.
      A file that is skipped or fails is a row in the output, not an omission.
      OUTPUT: a TSV committed at the root, one row per page, plus the per-document table.
      BOUND: one session, with its output committed. (blocked-on: ux-harness)
      (context: owner request 2026-09-26)
      DONE 2026-09-27: `UX-RUN-2026-09-27-pages.tsv` (931 pages) and `UX-RUN-2026-09-27-documents.tsv`
      (248 rows). `Tools/score-gate.swift` and `Tools/ux-harness.swift` at `b17ff79` ran 233/233 corpus
      documents and the 11 owner sources at default settings. The 4 earlier app outputs the owner
      supplied are rows marked not-scored. Pages sampled: every page of owner files of 28 pages or fewer,
      and pages 1, n/4, n/2 and 3n/4 otherwise (`ops/autonomous/ux-run/`). Documents: 36 green, 207 red,
      1 harness crash. Red pages 259/931: selection 137, colour 92, find 58, legibility 31, copy 30.
      Document flags: links 92, title 60, labels 21, annots 21, qpdf 2. 68 red documents have no red page.
      For `ux-read`, first: a drag on `newspaperArticle/___ 2.pdf` p1's output traps CoreGraphics
      (`PDFPage selectionFromPoint:toPoint:` → `PageLayout::convertRTLTextRangeIndexToStringRangeIndex`).
      Vision read Arabic letters, Arabic-Indic digits and U+202B into its text layer. Preview uses the
      same call; untested there because nothing may draw on the display. Also: `score-gate` spun at
      100% CPU after printing "233 of 233 succeeded" and had to be killed.
- [x] **ux-read** — read the `ux-run` output and turn what it finds into queued work. Look at the worst
      pages on each measure, and also at a random sample of pages drawn from the whole run, because a
      defect that no number catches is found only by looking. Look at them the way a reader would: the
      PDFKit render at 1x beside the source's, with a drag selection and a Find shown on it.
      Do not explain away a bad reading as the instrument's fault without showing it. The first stress
      test recorded C38 as a quirk of CoreGraphics.
      OUTPUT: for each confirmed defect class, a short `BUGS.md` entry and a queue item placed above
      `c28-first-principles`, ranked by how much of a reader's text or content it costs them.
      A finding that is already queued gets one line in its existing entry.
      BOUND: one session. (blocked-on: ux-run)
      (context: owner request 2026-09-26)
      DONE 2026-09-27: C42-C52 entered and queued below, ranked by what a reader loses: a whole document's
      text misplaced, whole pages unsearchable, lines unfindable, every copy corrupted, a crash, marks
      dropped unreported, drags that jump columns, misread words, lost colour meaning, lost page labels,
      then bytes. One line each in C28, C29, C33, C34, C37, C40, C41. All sit above `c28-first-principles`
      and `c41-newspaper-scans`, as FOCUS asks for the stress test's findings. The reader's own marks dropped at default are C45; wrapper `Link`s dropped by
      design were left alone.
- [x] **ux-regression-set** — make a fixed set of pages that every product item's check must pass, so a
      fix cannot make another page worse without anyone seeing it, as C32 did to C31's pages. Pick about
      30 pages from the `ux-run` output: every page the owner has reported, plus one page for each route
      and each defect class. `ux-harness` scores the set in minutes, and records a baseline. Add one line to
      this file's rules: an item that changes `Sources/` is done only when that set is no worse on any
      measure, or the regression is stated and accepted in the item's `BUGS.md` entry.
      What `ux-read` found the harness gets wrong, so pick pages and read columns with it in mind:
      `legibility` was red on 15 of 19 pages that read as well as the source when looked at, and green on
      the one with broken strokes (`_1939_Former students` p9); `find` strips all punctuation before
      searching (`norm()`, line 206), so "Supply-Side" or "delegate's" can never hit; `echoes` cannot see
      C44; `colour` counts C45's highlight pixels; `selection`'s `inside` goes red on tables and where the
      drag's end sits near a narrow gutter, and the sources' own text layers score the same there.
      BOUND: one commit. (blocked-on: ux-run)
      (context: owner request 2026-09-26)
      DONE 2026-09-28: `ops/ux-regression/set.tsv`, 43 pages of 30 documents, and `Tools/ux-regression.sh`,
      about 5 minutes; rule 9 above. Large documents are cut to their pages, which scored identically to
      the whole-document run on all 34 pages both measured. A second run on unchanged code read 0 worse.
      `___ 2.pdf` p1 is a harness crash in the baseline (C46), so it guards only its crash; C28 names no page.
- [x] **c42-spread-offset** — put Boltanski's text layer back on its ink: the text form must reach qpdf's
      overlay without the crop box, or be merged so the crop cannot centre it.
      DONE WHEN, through PDFKit on the published file: Find hits on Boltanski p51, p102 and p153 and on
      Zarifa p92-p94 lie over their words in the source (within 2 pt); a drag down each page of p51's spread stays on that page;
      a regression check with a cropped, two-size, rotated fixture goes red without the fix.
      BOUND: one code commit. (origin: BUGS.md C42)
- [x] **c43-digital-verdict** — make the born-digital verdict read a page's pixels as well as its text:
      a page whose visible ink is mostly a scan (narrow strips included) is OCR'd; a page whose body text
      is vector is kept, whatever images sit on it.
      DONE WHEN: Newsday p1's scanned body is selectable and findable in the output; Silicon Valley
      Transcript and Surani keep their own vector text and figures on every page (render compared at 2x);
      no corpus document's route changes elsewhere without a stated reason.
      BOUND: one code commit. (origin: BUGS.md C43)
- [x] **c51-missing-lines** — find why Bird p5's footnote lines and Xin Qu p24's coefficient column never
      reach the text layer, and put them there.
      DONE WHEN, through PDFKit on the published file: Find "Monograph" hits on Bird p5 over its line, and
      1.228, 3.724, 2.045 and 0.906 hit on Xin Qu p24 over their cells; a drag over each selects them; a
      check goes red without the fix.
      BOUND: one code commit. (origin: BUGS.md C51)
- [x] **c44-hyphen-echo** — stop copied text from repeating hyphenated tails while Find still matches the
      whole word. Consider `/ActualText` spans, writing the tail's run as part of the joined word's
      string, or dropping the join; test what PDFKit's copy and Find actually do with each.
      DONE WHEN, through PDFKit on Berger p18 and Glazer p1: a drag's copy has no "word ord" echoes, Find
      for "difference" and "automation" still hits over the head fragment, and the tail's ink is still
      selectable; the four text-layer properties of invariant 3 still hold.
      BOUND: one code commit. (origin: BUGS.md C44)
- [x] **c46-rtl-noise** — keep Vision's misread Arabic/Hebrew out of the text layers of pages that are
      otherwise Latin, and never write a zero-size run a click can land on.
      DONE WHEN: `___ 2.pdf` p1's output survives a click grid over the whole page, including x≈738,
      y 5-48, in a separate process; the 59 outputs with RTL letters are recounted and each remaining one
      is a page whose source really shows that script.
      BOUND: one code commit. (origin: BUGS.md C46)
- [x] **c45-marks-reported** — when *Keep highlights and notes* is off and the source has a reader's
      marks, say so on the outcome and in the run report ("left 121 highlights and notes"), the way the
      transplant's own summary does. Do not advertise the setting: `annot-r3`, which rules on whether the
      feature is fit to turn on, is parked.
      DONE WHEN: converting Hyman at default settings reports the marks it left, by type; a document with
      only wrapper `Link`s reports nothing; a check goes red without it.
      BOUND: one code commit. (origin: BUGS.md C45)
- [x] **c49-meaningful-colour** — keep colour on a mostly black page when it separates chart series, and
      never let light coloured type binarise to nothing.
      DONE WHEN: AI 2027 p54's three curves are distinguishable at 1x and Kristol p1's pink notice is
      legible in the output; pages that lose only paper tint stay grey; bytes stated.
      BOUND: one code commit. (origin: BUGS.md C49)
- [x] **c48-labels-title** — carry `/PageLabels` onto every output page and the source's `/Title` and
      `/Author` into the output's info dictionary.
      DONE WHEN: `PDFPage.label` on the outputs of Hobsbawm, Bird and Cohen equals the source's on every
      page, and `documentAttributes` Title equals the source's on Countryman and Friedman.
      BOUND: one code commit. (origin: BUGS.md C48)
- [x] **c50-typewriter-reads** — find out whether recognising the grey source instead of the 1-bit
      rebuild reads typewritten and low-resolution pages better, and ship it if it does.
      DONE WHEN: on Ries p54, NYSE p110, GELFAND p106 and Xin Qu p24, dictionary words in the output's
      text layer are measured before and after, and the change ships only if none gets worse and the
      named misreads ("suall", "Coeflicient") are gone, and Find "1.228" hits on Xin Qu p24 over its
      cell (moved from C51, where the cell reads `- 1228`). If nothing helps, make the case in C50 (rule 8).
      2026-09-28: the grey reading shipped and its bound is spent; moved behind the unattempted items.
      What is left is Find "1.228" on Xin Qu p24, which C50 shows is not binarisation but
      `finerReading`'s number guard. Next: make the case in C50, or let a table cell's reading gain a
      decimal point its column's other cells have. BOUND: one code commit.
      2026-09-29: done. The cell was two cells in one box; the grey reading now splits it and fixes
      garbled numbers, and Find 1.228 hits over its cell.
      (origin: BUGS.md C50)
- [x] **c47-compact-sources** — keep a compact source's image streams when the rebuild would be larger:
      JBIG2 in a Form XObject (Stiglitz, Keyssar), and JPX layers (Berendzen).
      DONE WHEN: Keyssar, Stiglitz, w5093 and Berendzen publish no larger than their sources plus the size
      of the text layer the app adds (state both), with PDFKit
      renders at 2x not visibly worse; corpus bytes before and after are stated.
      2026-09-29: the JBIG2 half shipped (Keyssar, Stiglitz, w5093 and Eyal-Cohen pass), and the bound is
      spent, so the item moved behind c50. What is left is Berendzen's layered page (Marth and Levy/Temin
      are the same shape), and the corpus bytes. C47 names the route a subagent proposed. BOUND: one code commit.
      2026-09-29: done. A page whose own drawing costs no more than its rebuild keeps it, text taken out,
      and is stamped with the app's text layer; Berendzen 169,637 B, Marth 145,294, Levy/Temin 2,369,543.
      (origin: BUGS.md C47)
  - [x] **c47-jbig2-forms** — JBIG2 scans drawn through a form, drawn upside down, or hanging off the sheet
        keep their stream, and finished files pack their objects. (context: BUGS.md C47)
- [x] **truth-calibrate** — test the reading procedure on pages whose text is known, and fix it, before any
      truth is made. (effort: medium)
      WHY. Both stress tests so far (`corpus-stress`, `ux-run`) took Vision's reading of the source as the
      reference for Find and Copy, so a word Vision misreads the same way in source and output passes. The
      owner asked for a model's reading as the reference instead. This item and the three `truth-` items
      after it are instruments by the owner's request. Rules 1 and 3 do not apply to them, because
      `truth-read` turns what they find into product work.
      THE PROCEDURE, written to `ops/truth/procedure.md` and used unchanged by `truth-set`:
      * The session renders the page through PDFKit to an image at 400 dpi, or 300 dpi for a page over 14 in
        on a side. The reader is given that image and a crop command. It is never given the PDF, its text
        layer, Vision's output or the app's output, and is told to open nothing else.
      * The session cuts the image into crops that cover all of it, placing the cuts in white space found in
        the pixels. It never uses Vision's layout, so a block Vision skips is still read. Claude Code shows an
        image at most 2,000 px on the long edge (measured 2026-09-29: a 2,560 px image arrived at 2,000), so
        no crop is larger; the Read result states the displayed size, so check it. The reader reads every
        crop in order and may cut closer crops to check a word.
      * The reader writes one line per printed line, with the line's box in the crop's pixels. Words are
        written as printed: no corrections, hyphens and line-end breaks kept, `[?]` for a word it cannot
        read. It then lists the columns in reading order. Text inside figures and tables, and handwriting,
        are transcribed and marked as such.
      * In the same pass it lists everything on the page that is not text: what it is (photograph, drawing,
        diagram, chart series, rule, stamp, seal, signature, handwriting, pencil or pale mark, highlight,
        underline, marginal note, coloured heading or text), its box, its colour by name, whether it is
        faint, and whether its colour carries meaning (a chart series, a red notice, a highlight). It adds
        the paper tint, and lists scanner borders and dust as `ignore`.
      * Cross-check. The transcript is aligned with the readings the source already has: Vision's reading of
        the source render, and the source's own text layer where there is one. Every word where they differ,
        and every line only one of them has, is read again by a fresh reader shown only a tight crop of that
        spot, without the sentence around it and without the candidate readings. That reading stands. A word
        it cannot settle is `contested` and is not scored. Contested applies to words, never to whole pages.
      * Prompts are passed verbatim from `procedure.md`, and each transcript records the version it was made
        with.
      THE TEST. Take about 30 born-digital pages from `testdocs/` whose text layer reads correctly (one and
      several columns, tables, footnotes, small type). Make two scans of each with the text layer removed: a
      clean 300 dpi greyscale one on grey paper, and a hard one at 150 dpi, 1-bit, low-quality JPEG, with a
      slight skew. The text layers are the truth. Run the procedure on the scans, and run the app on the same
      scans at default settings.
      DONE WHEN, committed as `TRUTH-CALIBRATE-<date>.tsv`: the procedure's word error after the cross-check
      and the app's word error, per scan kind and layout, both measured against the known text; the lines the
      reader skipped; and the usage per page. The procedure is fit for a kind of page where its error is a
      quarter of the app's or less, or under 0.2% of words, and it skips no line. Where it is not, change the
      crop size, resolution or prompt and measure again. A kind of page that still fails is scored in
      `truth-set` only for lost lines and blocks, and this item says which. The app's figures are an
      exact-truth result in their own right.
      BOUND: one session, and one more if the procedure has to be changed and measured again.
      (context: owner request 2026-09-29)
      PROGRESS 2026-09-29: the tools, the 64 scans and the app half are done (`ops/truth/STATUS.md`,
      `TRUTH-CALIBRATE-2026-09-29.tsv`). `testdocs/` has only 9 born-digital pages, so 24 are synthetic. The
      reader half is not yet run. Found: clean tables lose 27-35% of cells from the text layer.
      DONE 2026-09-29, second session, one page per kind: procedure v2 is fit for every synthetic layout
      and the magazine page (reader 0-0.66% lost against the app's 0-30.8%, no skipped line; Davis clean
      on a waiver for a scorer artefact). v1's cross-check made readings worse and is replaced. Canby's
      layer is old OCR, so real-book pages are not calibrated: `truth-set` scores them only for lost lines
      and blocks (`ops/truth/STATUS.md`).
- [x] **truth-set** — make the truth for about 220 real pages with the procedure `truth-calibrate` fixed.
      (blocked-on: truth-calibrate) (effort: medium)
      THE PAGES, committed first as `TRUTH-PAGES-<date>.tsv` (document, page, why chosen, status):
      * about 100 drawn at random from `ux-run`'s green pages, spread over the routes (JBIG2, DCT, layered
        colour, newspaper, typewritten, table), because what the old test missed is on pages it passed;
      * about 40 of its red pages, a few from each measure, to show how often it was wrong the other way;
      * every page of `ops/ux-regression/set.tsv`, and every page `Tools/ux-harness-selftest.sh` uses;
      * about 25 chosen for what is not text: photographs, drawings, maps, charts, forms, stamps, signatures,
        highlights, marginal notes, pale pencil on typescript.
      A born-digital page whose own text layer reads correctly is its own truth. One whose layer is garbled
      is read like a scan. Kinds of page `truth-calibrate` found unfit are kept and scored as it says.
      KEEP IT PRIVATE. The corpus is third-party. Transcripts and lists live in `$STATE/truth/<doc>/p<N>/`,
      each stamped with the source file's hash, and are never committed. Delete each page image once its
      page is done: they are large, and the daemon parks below 8 GB of free disk.
      FULL PROCEDURE ONLY (owner, 2026-09-29). Batches 2 and 3 were read in-session with the spots unchecked
      because the window was above 85%. That weaker procedure is not acceptable for this item, and more usage
      is fine. For this item the USAGE WINDOW thresholds in the resume prompt do not apply: use a reader
      subagent for every page and check subagents for every spot, at any usage below the end of the window.
      Never read a page in-session and never leave a spot unchecked. Work page by page and run
      `finish-page.sh` on each before starting the next, so a cut-off by the window costs at most the page in
      hand; the daemon retries after the reset and does not count that as an attempt. A page the full
      procedure cannot read (the content filter) goes in `none.tsv` with its reason; do not substitute.
      REDO FIRST. The eight pages marked `reader_tokens=session-inline` (Why 3, 4, 7; Briefer 2, 5, 6;
      Hughes 2, 8) are read again by the full procedure. Keep the old transcript beside the new one, report
      the word difference between them, and use the new one. Then the rest of the list in order, and Hughes p3
      again.
      DONE WHEN: every listed page has a transcript and a list, or a recorded reason it has none, and the
      contested-word rate is stated by route.
      BOUND: batches sized from `truth-calibrate`'s usage per page, so that one fits a session. Each batch
      commits the page list's updated status column and a ticked sub-box for itself (rule 5). A session that
      commits nothing reads to the daemon as idle, and ten sessions without a ticked box park the run.
      Readers only look at images, so they may run in parallel; rendering and Vision stay one process at a
      time. (context: owner request 2026-09-29)
- [x] **truth-set-b1** — batch 1: the page list (`TRUTH-PAGES-2026-09-29.tsv`, 215 pages) and the 21 owner
      pages of the regression set. 20 have a transcript and a list; Hughes p3 has none (the content filter
      blocked the reader twice). 11,015 words, 57 contested (0.52%; 0.13% without the newspaper page); the
      rate by route is in `ops/truth/STATUS.md`, with the tools, the cost (about 32% of the five-hour window
      for 21 pages) and the next batch. (context: truth-set)
- [x] **truth-set-b2** — batch 2: six of the eight `ux-harness-selftest` pages (Why 3, 4, 7; Briefer 2,
      5, 6). 3,218 words, 14 contested (0.44%), read in-session and with the spots unchecked because the
      session started at 86% of the window (`ops/truth/STATUS.md`). Hughes 2 and 8 move to batch 3.
      (context: truth-set)
- [x] **truth-set-b3** — batch 3: the selftest's last two pages, Hughes 2 and 8, read in-session with the
      spots unchecked (the session started at 92% of the window). 1,400 words, 9 contested (0.64%; 6 are
      ellipsis dots). Every regression owner page and selftest page is done but Hughes p3
      (`ops/truth/STATUS.md`). (context: truth-set)
- [x] **truth-set-b4** — batch 4, full procedure: the eight in-session pages read again, Hughes p3 (read
      this time), and the 16 testdocs pages of the regression set. 25 pages, 22,352 words, 177 contested
      (0.79%; 0.21% without the two small-town newspapers), no spot unchecked. The redone pages match the
      in-session words but one (`E LTON`). The whole regression set and selftest now has truth
      (`ops/truth/STATUS.md`). (context: truth-set)
- [x] **truth-set-b5** — batch 5, full procedure: the first 20 draws of the list (rows 2-21, all jbig2).
      6,437 words, 33 contested (0.51%), no spot unchecked; 7 are a library stamp on CIT 1958's cover,
      and many others are word-crop artefacts at hyphens and footnote marks. 65 of 215 pages done (`ops/truth/STATUS.md`). (context: truth-set)
- [x] **truth-set-b6** — batch 6, full procedure: the next 20 draws (rows 22-41, all jbig2). 6,146 words,
      72 contested (1.17%), no spot unchecked; the two pages of `_1979_Ideology of American Neo-Conservatism_`
      hold 36. 85 of 215 pages done (`ops/truth/STATUS.md`). (context: truth-set)
- [x] **truth-set-b7** — batch 7, full procedure: four draws (rows 42-45, all jbig2), stopped at 99% of the
      window. 1,011 words, 3 contested (0.30%), no spot unchecked. 89 of 215 pages done
      (`ops/truth/STATUS.md`). (context: truth-set)
- [x] **truth-set-b8** — batch 8, full procedure: 44 pages, rows 46-92 (6 jbig2, 24 layered, 11 dct, 3
      no-image). 14,997 words, 37 contested (0.25%), no spot unchecked; 9 are Atkinson 1939's comma-joined
      typescript. `cut-crops` fixed for sheets over about 4x the crop size. 133 of 215 pages done
      (`ops/truth/STATUS.md`). (context: truth-set)
- [x] **truth-set-b9** — batch 9, full procedure: 20 pages, rows 93-114, the last ux-run green draws (6
      no-image, 3 newspaper, 5 other, 6 unknown). 8,775 words, 21 contested (0.24%), no spot unchecked; 15
      are Gitlin's New York Times page. 153 of 215 pages done (`ops/truth/STATUS.md`). (context: truth-set)
- [x] **truth-set-b10** — batch 10, full procedure: 12 pages, rows 115-126, the first ux-run red draws (9
      jbig2, 2 layered, 1 no-image). 7,548 words, 40 contested (0.53%), no spot unchecked; 35 are Xin Qu
      2018 p24. 165 of 215 pages done (`ops/truth/STATUS.md`). (context: truth-set)
- [x] **truth-set-b11** — batch 11, full procedure: 2 pages, rows 128-129 (NYSE 1956 p110, jbig2; Williams 1958
      Manchester Guardian p1, newspaper), started at 91% of the window. 1,735 words, 37 spots, 46 check crops, 5 contested
      (0.29%), none unchecked. 167 of 215 pages done (`ops/truth/STATUS.md`). (context: truth-set)
- [x] **truth-set-b12** — batch 12, full procedure: 16 ux-run red draws, rows 130-152 (12 jbig2, 4 layered).
      9,644 words, 331 check crops, 165 contested (1.71%), none unchecked; 113 are Scott p1 and p7's dotted
      leaders and Gelfand p106's word crops, the known crop artefact. 183 of 215 pages done
      (`ops/truth/STATUS.md`). (context: truth-set)
- [x] **truth-set-b13** — batch 13, full procedure: 13 more ux-run red draws, rows 134-160 (9 jbig2, 2 layered,
      2 newspaper). 15,123 words, 509 check crops, 171 contested (1.13%), none unchecked; CIT 1958 p21's table
      holds 51. 196 of 215 pages done (`ops/truth/STATUS.md`). (context: truth-set)
- [x] **truth-set-b14** — batch 14, full procedure: rows 200-216, the non-text candidates and the photograph
      book (13 layered, 3 jbig2, 1 dct). 4,766 words, 85 check crops, 40 contested (0.84%), none unchecked; 24
      are a handwritten 1939 letter. 213 of 215 pages done; rows 127 and 137 remain, and 127 needs about 1,700
      check crops, because Vision misses whole columns of it (1,612 spots of 4,199 words) (`ops/truth/STATUS.md`). (context: truth-set)
- [x] **truth-set-b15** — batch 15, full procedure: rows 127 and 137, the two small-town newspapers. 9,565
      words, 2,244 check crops, 1,034 contested, none unchecked; row 127 holds 865 (21.4%, 450 `?` on 42 px
      crops of worn newsprint). All 215 pages done; contested rate by route in `ops/truth/STATUS.md`
      (newspaper 4.64%, every other route under 1%). (context: truth-set)
- [x] **truth-second-reader** — have Gemini read the most-contested truth-set pages, to settle contested
      words and to measure how often the Claude transcripts are wrong on old print. (effort: medium)
      WHY. `truth-calibrate` could not calibrate old print: the only real book had an OCR layer, not a true
      one. Two Claude readers share one model's blind spots, and 1,855 of the set's 118,757 words are
      contested, most on newspapers (4.64%; the 1926 Anaconda Standard page alone 21%). Gemini is a
      different model family and leads a February 2026 benchmark of historical and degraded documents
      (socOCRbench: Gemini 3 and 3.1 Pro about 0.70, Claude 4.6 about 0.56–0.58; Claude 5.x was not
      tested). The owner authorised the API spend on 2026-09-30.
      WHAT. Take the ten pages with the most contested words (the newspapers, Raskin and the worst of the
      rest; list them in the output first). (a) Every contested word's crop, read blind by Gemini with the
      CHECK prompt. (b) An independent Gemini transcript of each of the ten pages, made from the same crops
      with the READER prompt, aligned with the Claude transcript. Call Gemini only through
      `ops/truth/gemini-read.sh <prompt-file> <image>...`, which reads the key from the Keychain itself, logs
      every call's tokens and cost to `$STATE/truth/gemini-usage.tsv`, and refuses calls once the logged spend
      reaches $3 (`--spent` prints it). Never read the key or call the API any other way. Model
      `gemini-3.1-flash-lite` with minimal thinking (owner, 2026-09-30: the quality difference from Pro is
      small). The script prices calls at Pro's rates, which overstate Flash Lite's, so the logged spend is an
      upper bound. One word crop is about 1,100 input tokens, so put about 40 numbered crops on one
      contact-sheet image per call, as the check briefs do, and ask for one numbered line per crop. An aborted
      first run on Pro (29 calls, about $0.15, counted in the log) left `$STATE/truth/second-reader-pro-aborted/`;
      do not use its readings.
      RULES. Gemini never overrules on its own, the lesson of `truth-calibrate`'s v1 cross-check. A contested
      word is settled when Gemini's blind reading agrees with the Claude reader's or check's reading;
      otherwise it stays contested. Where Gemini's transcript disagrees with a settled Claude word, a fresh
      Claude check reads a tight crop; if it still disagrees, the word becomes contested. A `Recitation` or
      other refusal (copyrighted text) is counted and the page kept as it is. Spend cap $3 (owner, 2026-09-30), tracked from each response's token counts: do (a) first, then (b) page by page from the most contested, and stop and record
      if it is reached. Nothing is committed but counts; transcripts stay in `$STATE/truth/`.
      DONE WHEN, committed as `TRUTH-SECOND-READER-<date>.tsv`, per page: contested before and after,
      Gemini-Claude disagreement on words Claude had settled (the estimate of Claude's error on old print),
      refusals, and the spend. If that disagreement is above 1% on some kind of page, say so in
      `ops/truth/STATUS.md` for `truth-harness` and `truth-read`; do not extend this to more pages
      without the owner. BOUND: one session. (context: owner request 2026-09-30)
- [x] **truth-harness** — measure published outputs against the truth set, text and everything else alike,
      and run it on today's pipeline. (blocked-on: truth-set)
      TEXT, in `Tools/ux-harness.swift --truth <dir>`. (a) Copy: drag each column the transcript lists, from
      its line boxes, so a column Vision never found is still dragged, and align the selection's `string`
      word by word with that column's transcript: words wrong, missing and added, split words, wrong hyphen
      joins. (b) Find: search for words drawn from the transcript; each occurrence must have a hit inside its
      line box. (c) Column order. Figure text and handwriting are scored apart from body text, and contested
      words are not scored. Also report, per page, how far Vision's reading of the source is from the
      transcript. Without `--truth` the tool is unchanged.
      BEFORE A WORD COUNTS AGAINST THE APP, the session has it read again blind on a tight crop, as in the
      cross-check. Where that shows the transcript was wrong, the transcript is corrected in place and the
      correction logged.
      EVERYTHING ELSE, AND LEGIBILITY. The tool renders source and output through PDFKit at the same scale and
      writes matching crop pairs. A Swift tool cannot call a model, so the session gives each page's pairs to
      one judge subagent, with the page's element list as a checklist. Each pair is shown as A and B in
      random order, and the judge is not told which is the output. It says what is in one and missing,
      faded, harder to read or changed in colour in the other, and its answer is the verdict. Text and
      non-text losses are reported side by side and never merged into one score, so a change that gains
      words by losing a drawing shows as a loss.
      SHOWN TO WORK FIRST: red on the owner's reports (Raskin p1 and Why pp5-6 at `24a8f6a`, Why p5 at 1.14.0
      for the red headings, Hughes p5 at `24a8f6a`), green on the pages the 2026-09-27 self-test named green.
      THEN: run it on the truth pages' outputs from the current pipeline at default settings, with the old
      measures run on the same outputs. Commit `TRUTH-RUN-<date>-pages.tsv` and a per-document table, numbers
      only, with the pages the old measures pass and the truth fails, and the reverse, by route. Last, make
      `Tools/ux-regression.sh` score Copy and Find against the transcripts of the set's pages, and check each
      listed element's box for ink and colour. The regression check makes no model calls, so it gives the
      same answer every time.
      BOUND: one commit for the tool, its self-test and the regression change; then the run, in batches like
      `truth-set`'s. (context: owner request 2026-09-29)
- [x] **truth-harness-tool** — `Tools/ux-harness.swift --truth <doc-dir>` and its self-test, 2026-09-30.
      Copy, Find, column order, figure and handwriting apart, `visMiss`/`layerMiss`, `truth-words.tsv` for
      the blind re-read, crop pairs for the judge. Self-test PASS (measured): `tcopy` red on Raskin p1 (copy
      error 4.17), Hughes p5 at 24a8f6a (0.85) and Why p5 at 1.14.0 (0.69); green on Why pp3-8, Hughes
      pp1-3, 5, 7-9, Briefer pp5-6 (at most 0.048). Briefer pp1-4, green on every old measure, are red: the
      output's layer lacks 3-10% of their words, whole clean lines, which Vision's reading of the source lacks
      too. That is `truth-read`'s. Judges on Why p5's pairs, blind (measured): the current output passes,
      1.14.0 loses the red headings, and 24a8f6a's headings are an illegible smear. One judge found the colour
      loss but named the wrong image on 4 of 5 pairs, so the run's judge prompt must describe A and B apart
      before it gives a verdict. NOT DONE: the `ux-regression.sh` change (its `pages` mode renumbers pages,
      so the truth's `p<N>` must be mapped) and the ink and colour check for each element's box; then the run.
      (context: owner request 2026-09-29)
- [x] **truth-harness-regress** — the element ink and colour check (`elInk`, `elCol`, `tink`, `tcolour`) and
      `truth` rows in `Tools/ux-regression.sh` and its baseline (43 pages), 2026-09-30. Self-test PASS; see
      `ops/truth/STATUS.md`. Left for `truth-harness`: the run. (context: owner request 2026-09-29)
- [x] **truth-harness-run1** — the run with no model, 2026-09-30: `ops/truth/run-harness.sh` over all 215 pages
      at `832b7ac`, old measures and truth on the same output, 0 crashes; `TRUTH-RUN-2026-09-30-pages.tsv` and
      `-docs.tsv`. 42 pages pass the old measures and fail the truth (35 on text alone), 10 the reverse; by
      route in `ops/truth/STATUS.md`. Left for `truth-harness`: the blind re-read of each `truth-words.tsv`
      and the judges on `pairs/`, from `$STATE/truth-run-2026-09-30/`. (context: owner request 2026-09-29)
- [x] **truth-harness-run2** — the blind re-read, the judges' first round and the rescore, 2026-10-01: 3,753 rows
      of `truth-words.tsv` re-read on tight crops (3,304 confirmed; 427 words on 59 pages contested and no longer
      scored), 659 crop pairs judged blind, all 215 pages scored again with Find fixed (it searched `high-school`
      as `highschool`, and its sample moved when words were contested). The DONE WHEN check failed the judges on
      the self-test's green Why pages (shades of red, staple marks); the sharpened prompt, tried on those pages and
      the controls, keeps 17 of 17 controls and only real losses (C28's cartoons and pencil marks). Left for
      `truth-harness`: that prompt over the other 221 pairs, briefs written; `ops/truth/STATUS.md` says how.
      (context: owner request 2026-09-29)
- [x] **truth-harness-run3** — the judges' second round over the other 221 non-`same` pairs, 2026-10-01: 659 judged
      pairs read same 472, worse 173, better 14; controls 17 of 17 `worse`. Classes: 109 green, 49 red, 9 old-only,
      48 truth-only (25 on text alone, 12 on the judges alone). Round 2 made four right verdicts wrong, all losses
      of ink or colour that the element check also flags; measured in `ops/truth/STATUS.md`. The DONE WHEN check
      then failed Copy: a loose line is selected over the middle half of its box, so one set a third of a line off
      counts all missing (Wilson 1975 p1 and five more pages). (context: owner request 2026-09-29)
- [x] **truth-harness-copyfix** — Copy no longer misses a loose line set off its box, nor runs a column drag on
      through the next column from a last line boxed into it, 2026-10-01. Self-test PASS with three new cases; all
      215 pages rescored: 412 fewer words missing, `tcopy` on 61 pages, not 70; 116 green, 49 red, 9 old-only, 41
      truth-only. Left for `truth-harness`: the DONE WHEN check, from a fresh window (this session ended at 89%
      of it). (context: owner request 2026-09-29)
- [x] **truth-harness-inkfix** — Copy drags each column from its line boxes' ends and from their ink's, and keeps
      the nearer the transcript; a loose line keeps the text nearest its ink, 2026-10-01. The DONE WHEN check had
      failed Copy again: boxes off their ink made Delton p2 and Cooley 2008 p94 red for the harness's sake. All
      215 pages rescored: those two, Briefer p2 and 1979 Ideology p8 go green, none red; 119 green, 48 red, 10
      old-only, 38 truth-only. Self-test PASS with a `raised` case. The DONE WHEN check then failed Copy narrowly:
      CAMFIELD p1 and Banks 2006 p101 are red by one glyph at a drag's end. Left for `truth-harness`: the fix in
      `ops/truth/STATUS.md` (NEXT), a rescore, the check. (context: owner request 2026-09-29)
- [x] **truth-harness-fullink** — a third column drag from the ink's ends over the line's full height, 2026-10-01:
      CAMFIELD p1 and Banks 2006 p101 score what a reader's drag scores and go green; all 215 pages rescored
      (`final5`): 15 better, none worse, 121 green, 48 red, 10 old-only, 36 truth-only. The DONE WHEN check passed
      every criterion, so `truth-harness` is ticked. (context: owner request 2026-09-29)
- [x] **truth-read** — read `truth-harness`'s output and turn what it finds into queued work.
      (blocked-on: truth-harness)
      Start with the pages the old measures pass and the truth fails, since those hold the defects the old
      test could not see. Then look at the worst pages on each measure, and at a random sample of the whole
      run, the way a reader would: PDFKit at 1x beside the source, with a drag and a Find shown on it. A lost
      drawing, pale mark, image or meaningful colour ranks with lost words. Do not blame a bad result on the
      transcript without showing the page.
      OUTPUT: for each confirmed defect class not already in `BUGS.md`, a short entry and a queue item, ranked
      by what a reader loses and placed above `c28-first-principles`. A finding already queued gets one line
      in its entry. State how many words Vision misread the same way in source and output, since the old
      test could not have found any of them.
      BOUND: one session. (context: owner request 2026-09-29)
      DONE 2026-10-01: C53-C56 entered and queued below, ranked by what a reader loses: clean lines missing
      silently, a whole page's typing broken, drags copying the line above, heavier type. One line each in
      C28 (unboxed marks soft or lost on layered pages), C41, C43, C45, C47 (photos halved, not queued), C50
      and C52. Of 8,693 wrongly copied words, 467 repeat Vision's misread of the source (C50). Harness
      artefacts are in `ops/truth/STATUS.md`.
- [x] **c53-skipped-lines** — get the clean lines Vision skips into the text layer, or report them.
      THE PAGES: `1951 - Briefer Book Notes` pp1, 3, 4 (the owner's file), `Banks 2006` p101,
      `Riesman_1942` p14, `Jensen` p429 (`BUGS.md` C53 names the lines). Start by capturing production's
      observations and bitmaps (C51 did it with a wrapper around `visionocr-recognise`) and finding why the
      bands do not run over these rows.
      DONE WHEN, through PDFKit on the published files: every line C53 names can be found with Find and
      copies its own words; a page whose lines still cannot be read reports them; `ux-regression.sh` no worse;
      a new check goes red without the change.
      BOUND: one code commit. (origin: BUGS.md C53)
- [x] **ocr-lab-setup** — set up a guarded local environment for open OCR models and find out which ones
      fit this Mac.
      WHY. On the truth set the app gets 2.7% of words wrong outside newspapers and 25% on newspapers, against
      under 1% for a model's reading, and most of the gap is Vision's own misreading, which no fix queued so far
      touches (`TRUTH-RUN-2026-09-30-pages.tsv`; 467 of 8,693 wrong words repeat Vision's misread of the
      source). Small open OCR models may read better. The owner asked on 2026-10-02 for a measured comparison
      ahead of the current fixes, with integration alongside Vision if it pays. Licences are set aside for now.
      THE MACHINE. Apple M3 Pro, 18 GB of memory, on 2026-10-02 about 54 GB free by `df` and 83 GB as Finder
      counts it (purgeable space macOS frees on demand); the daemon parks below 8 GB free by `df`, and this Mac has a wired-memory leak that grows over weeks. Whatever is built must run here.
      THE GUARD, built first: `ops/ocrlab/run-guarded.sh` runs one model process, samples its resident memory and
      `memory_pressure` every 2 s, and kills it (logging why) if its memory passes 12 GB (owner, 2026-10-02), pressure reaches
      critical, or swap grows by more than 2 GB. Only one model process at any time, never while a suite,
      `ux-harness`, `ux-regression.sh` or another PDFKit/Vision corpus job runs (check `test.lock` and
      `pgrep -x tests`). Quantise to 4 or 8 bit wherever a checkpoint allows.
      THE ENVIRONMENT, outside the repo: a `uv` venv and `HF_HOME` under `~/.local/share/visionocr-ocrlab/`.
      Install with `uv pip` (MLX through `mlx-vlm`, else PyTorch on MPS) and download weights with the Hugging
      Face CLI; sessions may not run `curl` or `wget`. The framework `python3` has no root certificates, so use
      the venv's Python. Download one candidate at a time, prefer a 4- or 8-bit build (MLX or GGUF) to full weights, and if
      only full weights exist quantise them and delete the originals. A candidate that does not fit is deleted
      at once. Keep every candidate that fits and reads correctly through the bake-off and the 4-bit/8-bit runs, so nothing is
      downloaded twice (owner, 2026-10-04); delete only those that fail to run or do not fit. Keep the lab under
      50 GB in all. Before each download check that the space available stays above
      20 GB afterwards, counted as Finder counts it (`ops/ocrlab/free-mb.sh`: macOS's available capacity for
      important use, which includes purgeable space such as Time Machine's local snapshots, freed on demand).
      Owner, 2026-10-05: Finder showed 70 GB available while `df` showed 17 GB, and the `df` rule had held the
      fit tests back all day.
      THE CANDIDATES. Refresh this list with a short web search first; small models have been arriving monthly.
      As of 2026-10-02: PaddleOCR-VL 1.5 and 1.6 (0.9-1.2B), GLM-OCR (0.9B), LightOnOCR-2-1B (has bbox
      variants), TeleOCR (1.2B), NaviDC-OCR (1.2B, 2026-08-17), MinerU2.5 (1.2B), HunyuanOCR, dots.ocr-1.5 and
      dots.mocr (3B), DeepSeek-OCR-2 (about 3B), Qianfan-OCR (4B, an MLX 4-bit build exists; leads olmOCR-Bench's
      old scans among end-to-end models), Chandra OCR 2 (5B, word boxes), Surya OCR 2 (line boxes), and the
      general Qwen3.5 small models (2B, 4B, 9B; Qwen3.5-27B scored 0.54 on socOCRbench, near Claude 4.6, but
      is too large here). Skip Tesseract (0.10 on socOCRbench).
      DONE WHEN, committed as `OCR-MODELS-<date>.tsv` with the scripts in `ops/ocrlab/`: one row per candidate
      with size, quantisation, runtime, whether it gives line or word boxes, peak memory and seconds for one
      ordinary page and one newspaper page through the guard, and fits (peak under 12 GB) or why not. Speed is
      recorded but does not decide fit here: the owner dropped the 90 s rule on 2026-10-04, when no candidate
      read a newspaper page in under 145 s, and will decide on time later. The lab folder is excluded from Time
      Machine (owner, 2026-10-04), so deleted weights now free disk; retry the candidates the disk rule refused.
      No model crashed the Mac or tripped the guard twice.
      ESTIMATE: 2-3 sessions. Tick a sub-box for the guard and environment, then one per four candidates.
      BOUND: rule 10. (context: owner request 2026-10-02)
      Round 1, session 1, 2026-10-04: guard, lab (`~/.local/share/visionocr-ocrlab/`, mlx-vlm 0.7.4, brew llama.cpp)
      and 13 builds measured, in a PARTIAL `OCR-MODELS-2026-10-04.tsv`. Read both pages to the end under 12 GB: GLM-OCR,
      HunyuanOCR, Qwen3.5-2B and -4B (rough newspaper-crop recall 0.86-0.92 against Vision's 0.77); none under 90 s
      on the newspaper (145-302 s). LEFT: chandra-ocr-2-oQ8 and Qwen3.5-9B (refused by the disk rule; deleted weights
      stay held by Time Machine local snapshots for up to a day, so delete early); Surya 2 through `surya-ocr`
      (layout then block OCR); TeleOCR (teleocr-rs) and NaviDC (patched llama.cpp), or a stated reason;
      DeepSeek-OCR-2's processor fails to load in mlx-vlm 0.7.4; LightOnOCR has one guarded try left.
      Round 1, session 2, 2026-10-04: a session killed by a daemon restart had run LightOnOCR at `--max-side 1540`,
      Chandra 2 as GGUF Q4_K_M and DeepSeek-OCR-2 with `--no-remote-code`; all three read both pages under 12 GB.
      `fits` no longer counts speed. The Time Machine snapshots aged out mid-session (`df` 22 -> 77 GB), so the
      disk-refused two were retried: Chandra 2 oQ8 fits (7.8 GB); Qwen3.5-9B tripped the guard once on swap with
      only 5.9 GB reclaimable. Surya 2 through `surya-ocr` 0.22.1 (`$OCRLAB/venv-surya`, text by `surya-text.py`)
      reads where the bare GGUF did not: recall 0.914 ordinary, 0.891 newspaper crops, peak 4.9 GB. Eight models
      fit: GLM-OCR, DeepSeek-OCR-2, HunyuanOCR, Qwen3.5-2B, -4B, LightOnOCR, Chandra 2, Surya 2. TeleOCR, NaviDC
      with stated reasons. Ticked: every candidate has fits or a reason.
- [x] **ocr-lab-round2** — fit-test the candidates the 2026-10-05 survey found, so the bake-off reads the
      ones that fit when it resumes. (blocked-on: ocr-lab-setup) (effort: medium) — owner, 2026-10-05: its
      attempts were sessions the disk rule turned to other items, not failures of a hard item, so they must not
      raise it to max.
      WHY. Owner, 2026-10-05: "make sure we're testing the best available models ... Consider all of the
      LightOnOCR model variants ... If we need to set up a model to be usable with this mac, and that's
      possible, let's consider doing that. Include the Churro project." A three-part web survey that day
      (the LightOnOCR family, Churro, the wider field). Every repo below was checked to exist on Hugging Face,
      and each architecture is in this lab's mlx-vlm 0.7.4 (`qwen2_5_vl`, `qwen3_5`, `qwen3_vl`, `mistral3`,
      `falcon_ocr`). Benchmark figures are the vendors' or one paper's; measure here.
      THE CANDIDATES, best first; stop when disk reaches the lab's limits:
      1. `lightonai/LightOnOCR-2-1B-ocr-soup` (Apache-2.0), LightOn's merge for robustness: olmOCR-Bench old
         scans 45.4 against the tested build's 42.2, tiny text 90.3 against 91.4. No MLX build: convert at
         8-bit (`python -m mlx_vlm.convert --hf-path lightonai/LightOnOCR-2-1B-ocr-soup -q --q-bits 8`) and
         delete the bf16 download; noctrex's GGUF Q8_0 is the fallback.
      2. `lightonai/LightOnOCR-2-1B-base`, the same before reinforcement learning: old scans 47.0, best of
         the family; may loop more. Convert the same way.
      3. `mlx-community/LightOnOCR-2-1B-8bit`, a control for the tested 4-bit build.
         All three at `--max-side 1540`, which is LightOnOCR-2's training resolution (its config and processor
         both say 1540), not a handicap. No prompt; allow 4096 output tokens.
      4. Churro 3B (`stanford-oval/churro-3B`; Qwen2.5-VL-3B fine-tuned on 99k historical pages from 155
         collections, American Stories newspapers among them; Qwen research licence, non-commercial, and
         licences are set aside as in ocr-lab-setup). CHURRO-DS printed / handwritten NLS 82.3 / 70.1, against
         GLM-OCR 65.2 / 40.2, dots.mocr 81.2 / 55.0 and DeepSeek-OCR-2 56.1 / 20.0, on a test split from the
         training collections. Run `mradermacher/churro-3B-GGUF` Q8_0 with the f16 mmproj under llama.cpp
         (`llama-mtmd-cli`); for MLX start from the ready 8-bit port `kintopp/churro-mlx` (about 4.3 GB)
         before converting it yourself. System prompt "Transcribe the entirety of this
         historical document to XML format.", no user text, temperature 0, repetition penalty 1.05. It answers
         in XML: take the text the way the repo's `tooling/evaluation/xml_utils.py::extract_actual_text_from_xml`
         does, and strip tags instead when the XML does not parse (a truncated read). It transcribes
         diplomatically (keeps ſ and old spellings). Its image cap is about 4 MP, so newspapers go as crops.
      5. `infly/Infinity-Parser2-Flash` (2B, Qwen3.5 base, Apache-2.0): vendor olmOCR-Bench 86.0; one paper
         ranks its family first on full multi-column newspaper pages. Build: `BotResources/Infinity-Parser2-Flash-mlx-q8`.
      6. `tiiuae/Falcon-OCR` (0.27B, Apache-2.0), loads in mlx-vlm as is: strong on multi-column, weak on
         degraded scans by its own card.
      7. `mlx-community/olmOCR-2-7B-1025-4bit`: strong on single-column old scans; reported to modernise
         spelling and to collapse on whole multi-column pages.
      8. `mlx-community/Qwen3-VL-8B-Instruct-4bit` and `mlx-community/Qwen3-VL-4B-Instruct-8bit`.
      Same rules as ocr-lab-setup: the guard, one model at a time, its two test pages, peak under 12 GB, available
      space above 20 GB after each download, as `ops/ocrlab/free-mb.sh` counts it (owner, 2026-10-05), the lab under 50 GB (24 GB on 2026-10-05), and a build that
      does not fit deleted at once. Fit tests are ordinary work and run while the owner uses the Mac; only the
      bake-off itself waits for the owner (owner, 2026-10-05).
      DONE WHEN: each candidate has a row in a new `OCR-MODELS-<date>.tsv` with fits yes or no and why, and each
      fitting build is a `fitted` row in `ops/ocrlab/bakeoff-models.tsv` with what its reader needs (Churro's
      prompt and XML step), so `bakeoff.sh start` copies it and the job reads it when it resumes.
      ESTIMATE: 2 sessions. BOUND: rule 10. (context: owner request 2026-10-05)
      Round 1, session 1, 2026-10-05: lab2-lighton done, rows in `OCR-MODELS-2026-10-05.tsv`. ocr-soup and base
      converted at 8-bit (`ops/ocrlab/convert-mlx.py`, repo `local/<name>`); both fit and are `fitted` rows.
      The mlx-community 8-bit control was killed once on the crops (swap) and is `no` with its retry owed. NEXT:
      free disk by `df` was 18.5 GB at the end (Time Machine local snapshots hold the deleted bf16 downloads,
      swap files grew), under the 20 GB rule, so Churro's 4.3 GB waits for snapshots to age out (hourly, about a
      day) or for a weight the lab no longer needs to go. `pgrep -f 'tart run'` in a wait loop matches itself and
      held off the guard for 50 minutes; the guard now matches the VM binary.
      Round 1, session 2, 2026-10-05: free disk 21.6 GB, so Churro still could not download (smallest pair,
      GGUF Q4_K_M + mmproj-Q8_0, is 2,648 MB; Q8_0 + mmproj-f16 is 4,409 MB). Deleting does not help the same
      day: the hourly Time Machine local snapshots pin anything deleted for about 24 h (6 GB of day-old
      `/private/tmp` test scratch was removed and `df` did not move); they were left alone, as they may be the
      only copy of recent hours. `kintopp/churro-mlx` is not on the Hub (404), so Churro's MLX route is a
      conversion of `stanford-oval/churro-3B`. Falcon-OCR (1,042 MB) fitted inside the rule and was tested out of
      order: fits, ordinary recall 0.914 / precision 0.964, crops 0.892 / 0.897 at a 4.1 GB peak, the cheapest
      reader yet at LightOnOCR's level; `fitted` row added (prompt `plain`). mlx-vlm's Falcon processor shrinks
      every image to a 1,024 px longest side, so its whole-page reads of dense pages will be weak; judge it on
      crops. NEXT: when `df` is above 23 GB
      (expected from about 2026-10-06 noon), Churro GGUF, then Infinity-Parser2-Flash (2,558 MB).
      2026-10-05 12:20: `df` 19 GB, so neither could download; the session took daemon-gate-fix instead.
      2026-10-05 14:25: `df` 19 GB again (snapshots pin the deletions); the session took c55-low-runs.
      2026-10-05 16:31: `df` 13 GB; the session took c55-low-runs again.
      2026-10-05 20:40: the rule now counts purgeable space (77 GB available against `df`'s 17 GB), so Churro and
      the rest can download; deleted weights count as free at once. NEXT: lab2-churro.
      Round 1, session 3, 2026-10-05: lab2-churro done [measured]. GGUF Q8_0 + mmproj-f16 is out: the guard killed it
      twice on the ordinary page (swap at 4 MP; 15.3 GB at 2 MP), weights deleted. `kintopp/churro-mlx` absent, so
      `stanford-oval/churro-3B` was converted at 8-bit (`local/churro-3B-8bit`, 4.4 GB; bf16 deleted). It fits at
      1600 px: ordinary 0.968 / 0.998 at 5.8 GB in 35 s, best in the lab so far; crops 0.896 / 0.939 at 6.3 GB, cut by
      try-mlx's 600 s limit with 12 of 13 crops read (XML doubles the tokens; the bake-off allows 2,400 s). `fitted` row
      added; `--churro` in read-mlx.py and read-gguf.py gives its system prompt, penalty and XML step (churro_xml.py).
      NEXT: lab2-infinity-falcon (Falcon already fitted; Infinity-Parser2-Flash, 2,558 MB, remains).
      Round 1, session 4, 2026-10-05: lab2-infinity-falcon done [measured]. Infinity-Parser2-Flash (BotResources 8-bit,
      read-mlx.py --infinity: its layout prompt, JSON to text by infinity_json.py) reads the ordinary page at 0.914 / 0.964,
      5.1 GB, 29 s; the guard killed it on the crops (swap grew 2.2 GB at a 4.9 GB footprint, 5.2 GB swap already in use,
      another lab job `method_local.py collect gemma4-12b` running). Row `no`, one retry owed with NEED_GB=8 (two 20-min
      waits got at most 5.4 GB reclaimable); weights kept, lab 48.2 GB, so olmOCR 2 (~5 GB) needs Infinity or another
      build deleted first or the retry done. bakeoff.sh's `owed` path is hard-wired to qwen3.5-9b, so no bake-off row.
      NEXT: lab2-olmocr-qwen3vl.
      2026-10-06 00:03: not started. The resumed bake-off (pid 47316, from 23:59) holds `engine.lock` and the guard,
      reading Qwen3.5-9B's last try (ordinary page fits: 8.9 GB, 0.901 / 0.959), so no fit test may run beside it
      until it ends. Disk is also owed: lab 48.2 GB, and olmOCR 2 plus both Qwen3-VL builds need about 16 GB more
      against the 50 GB limit; delete the out LightOnOCR-8bit control's or Infinity's weights first, once their
      retries are settled. NEXT: lab2-olmocr-qwen3vl after the job ends.
      - [x] **lab2-lighton** — the three LightOnOCR builds.
      - [x] **lab2-churro** — Churro, GGUF and an MLX 8-bit conversion.
      - [x] **lab2-infinity-falcon** — Infinity-Parser2-Flash and Falcon-OCR.
      Round 1, session 5, 2026-10-06: lab2-olmocr-qwen3vl done [measured], bake-off stopped. Qwen3-VL-8B-4bit (already
      in the cache, fetched by Archive Suite's segbench) fits: ordinary 0.914 / 0.967 at 8.4 GB, crops 0.916 / 0.702.
      The LightOnOCR-8bit control and Infinity weights were deleted for room (Infinity's third 20-min wait for 8 GB
      got 5.9 GB; both stay `no`, retries unrun, re-downloadable). olmOCR 2 7B-4bit: killed once (swap +2.7 GB at
      NEED_GB=6 as a VM started), then fits on its retry at 8: ordinary 0.905 / 0.969 at 7.5 GB, crops 0.752 / 0.544.
      Both `fitted` rows, need_gb 8; both ran at least one crop to its token cap. Qwen3-VL-4B-8bit not run: 4.9 GB
      would pass the 50 GB limit (lab 49,715 of try-mlx.sh's 51,200 MB), the item's stop rule; the 8B stands in. Rejected: deleting a fitted
      bake-off build (LightOnOCR base, whose ordinary read equals ocr-soup's) to fit a lower-ranked candidate.
      - [x] **lab2-olmocr-qwen3vl** — olmOCR 2 and the two Qwen3-VL builds.
- [x] **daemon-gate-fix** — a red health gate goes to a fix session before the daemon may park, as Archive
      Suite's daemon has done since 2026-10-05 (its `W34.gate-fix`, commit d45c7cb).
      WHY. Owner, 2026-10-05: "Daemon parked again. Set this up so I don't need to tell you this." This daemon
      parked at 09:25 that day on `tools-compile` — two expressions in `Tools/score-text-route.swift` at the type
      checker's time limit, fixed in 8d71c2c — a fault a session could have repaired, while a parked daemon repairs
      nothing.
      WHAT. Port Archive Suite's mechanism (`ops/autonomous/archive-suite-autonomous.sh`: `GATEFIX`,
      `_gatefix_clear`, `_gatefix_handoff`; its resume prompt's STEP 1.6; `tests/prove-gate-fix.sh`): a red that
      survives the retry writes `$STATE/gate-fix` with the failing steps, each step's gate command and the log's
      tail; the next session takes it as its ONE item ahead of the queue and the triage files; a GREEN gate
      retires it; the run parks only after 3 fix sessions that committed (HEAD moved) leave it red. Fixes never
      weaken a check. Keep this daemon's own gate shape (its `test.lock`, its suite timings).
      DONE WHEN: a prove harness in the gate shows hand-off, retirement on green, the attempt count and the park
      after the last attempt, and a mutant of each turns it red. ESTIMATE: 1-2 sessions. BOUND: rule 10.
      (context: owner request 2026-10-05)
      DONE 2026-10-05: `tests/prove-gate-fix.sh`, gate step `gate-fix-proof`, 25/0; seven mutants (hand-off,
      retirement, count, park, re-run shortcut, fast-forward, idle cap) each turn it red. Beyond the port, two
      fixes the review found: the gate tests the primary checkout, which sessions never move, so the daemon
      fast-forwards a clean main to origin/main before re-gating; and sessions that commit nothing are capped at
      3 in a row. Every red, document steps included, goes to a session (no compactor here). Prompt STEP 1.4.
      Landed by the triage session that adopted the stranded worktree. Its review fixed the idle cap (it ran one
      session too many), clears a request when gating or gate-fix is switched off, and made [5] able to fail (a
      mutant deleting the request at startup now turns it red). Untested: the usage-window `cut` exemption. Known:
      a park after attempts on an un-fast-forwardable primary says "fix sessions committed" of fixes never gated.
      `prove-daemon.sh` [5] (queue edit wakes backoff) fails 125/1 on the base commit too, so it was red before this.
- [x] **mac-heavy-lock** — one heavy job at a time on the Mac, shared with Archive Suite. (effort: medium)
      DONE 2026-10-06. `ops/autonomous/mac-heavy-lock.sh`; its header is the protocol, for Archive Suite to match
      (wait files are `mac-heavy.lock.waiting/<pid>`, and a recycled pid is told apart by `start=`). Taken by
      `test-lock.sh run` (both forms, so the hook too), the gate's build, the hook's UI build, and
      `run-guarded.sh` (bakeoff.sh copies the helper beside its script copies). The daemon stops a gate's or
      session's clocks while it is queued, up to 4 h (`VISIONOCR_HEAVY_PAUSE_MAX`). Proven by
      `tests/prove-mac-heavy-lock.sh` (27 checks, with a built-in take-always-succeeds mutant) and
      `prove-gate-fix.sh` [8]; both are in the gate. Hand-run mutants removing the daemon's pause, the watchdog
      spare, test-lock's take and run-guarded's take each turn a check red.
      WHY. Owner, 2026-10-06, after the Mac froze about 13:30-14:05: "Queue a shared lock, top priority." Measured
      then: 15-minute load average about 28, swap 6.6 of 8 GB, no reboot or panic. Running at once: this daemon's
      full suite (its health gate, two `visionocr-recognise` at 130-150% CPU), Archive Suite's builds and Tart VM
      runs, and CrashPlan. `test.lock` and the engine lock serialise only this project; Archive Suite's
      `heavy.lock` only that one.
      WHAT. The protocol Archive Suite's `W35.machine-lock` uses, identical, with this repo's own copy of a small
      helper (neither repo depends on the other): `~/.local/state/mac-heavy.lock`, a directory taken with `mkdir`,
      holding `owner` (pid, project, label, start time); released by the holder on exit (trap); stale when its pid
      is dead (the next taker removes it and logs that); a taker WAITS, logged once, rather than failing, and the
      wait is not charged to a time limit or counted as a failure. Wrap the suite (`test-lock.sh`, after
      test.lock), the health gate's build-and-suite steps, and guarded model runs (`ops/ocrlab/run-guarded.sh`,
      so the bake-off and fit tests too). Light work (one-page OCR checks, scripts) does not take it.
      DONE WHEN a prove harness shows two takers from different projects never hold it at once, a dead holder is
      reclaimed, a waiting suite does not RED the gate or burn a session's time, and a mutant removing the take
      turns it red; the harness runs in the health gate. ESTIMATE: 1 session. BOUND: rule 10.
      (context: owner request 2026-10-06)
- [x] **two-sessions-design** — decide whether a second session at once would help this daemon, before the larger Claude
      plan arrives. (effort: medium)
      WHY. Owner, 2026-10-06: "We'll be moving up a tier in usage plans shortly so we should prepare for that in
      advance" (the Claude plan). This daemon runs one session at a time; Archive Suite now runs a supervisor with up
      to two workers (its W35.workers / W35.pace, `ops/autonomous/worker-supervisor.py` in that repo), sized from the
      usage readings. With more usage, one session may leave the window unspent.
      WHAT. Measure first: over the last week's `$STATE/usage.tsv` and daemon.log, how often a window ended unspent
      while this daemon was idle or waiting, and how much of each session's wall time is spent holding test.lock or
      mac-heavy.lock (a second session could not run its suite then). Then write the design or the case against it in
      this item: which items could run side by side (docs, analysis, harness work) and which cannot (anything that runs
      the suite), how a second session would claim its item, and what it would borrow from Archive Suite's supervisor.
      Build nothing in this item. DONE WHEN the measurement and the recommendation are written here and a follow-up
      item is queued if the recommendation is to build. ESTIMATE: 1 session. BOUND: rule 10.
      (context: owner request 2026-10-06)
      MEASURED 2026-10-07 [daemon.log, suite-timings.tsv, mac-heavy.log; 2026-09-30 00:00 to 2026-10-07 07:37, 176 h].
      The window readings are `$STATE/usage-window.tsv` (per-session peaks, a `cut` column; there is no `usage.tsv`).
      Sessions 57-59 h (53 launched; 3 ended by a daemon stop). Waiting on a spent window 29 h, 15 waits, each begun
      at 95-116%; 7-8 sessions cut off by it. Bake-off nights holding engine.lock 26 h (the Mac running models;
      nothing else fits in 18 GB). Health gates 2 h. Daemon stopped by the owner about 56 h. No window was seen
      ending unspent while the daemon was free to run: every gap is the window, the bake-off or the owner. Suite
      runs inside sessions (labels session, pre-commit, selftest, c41-measure) held test.lock about 10.5 h, 18% of
      session time; mac-heavy.lock is shared with Archive Suite (29 of the 61 takes in mac-heavy.log), whose two
      workers draw on the same account-wide window.
      RECOMMENDATION: do not build a second session now. On this plan the window is the limit, so a second
      session would spend it twice as fast and finish no more; it would also compete with Archive Suite's workers.
      Of the open items only analysis like this one could run beside another session; c41, c52, c56 and
      attempt-on-worked-item change code, so their commits run the suite in the hook, and the bake-off needs the whole machine. Rejected: a second lane for
      docs-only items now (almost none are queued, by rule 1).
      IF THE LARGER PLAN MAKES THE WINDOW SLACK, the design: the daemon keeps its one product lane and adds one
      lane for items marked `(lane: side)` (analysis, docs, harness work that runs no suite and no Vision process);
      a lane claims its item by `mkdir $STATE/claims/<tag>` with pid and start, stale when the pid is dead, as
      mac-heavy.lock does; `next-item.sh --lane side` skips claimed tags; both lanes pause together on one window
      reading. Borrow from Archive Suite's supervisor its pause rule (never let an older reading cancel a current
      spent window) and its claims coordinator; not its two general workers, since two suite-running sessions
      serialise on test.lock and one Vision process at a time is a hard memory rule here. Follow-up:
      `two-sessions-recheck`.
- [ ] **two-sessions-recheck** — once the larger plan is in use, re-measure and build the side lane if it pays.
      (blocked-on: larger-plan-active)
      WHAT. Over the first week on the new plan, rerun two-sessions-design's measurement. Build the side lane it
      designs only if the daemon spent under a tenth of its running time waiting on the window and at least two
      `(lane: side)`-shaped items are queued; otherwise write that here and tick the box. DONE WHEN the figures and
      the decision are written here, and if built, a harness shows two lanes never claim one item and both pause on
      a spent window. ESTIMATE: 1-2 sessions. BOUND: rule 10. (context: two-sessions-design 2026-10-07)
- [x] **ocr-bakeoff-run** — read the bake-off sample with every candidate that fits, as one long unattended
      job. (blocked-on: ocr-lab-setup, bakeoff-tonight-ok)
      PAUSED AGAIN 2026-10-06 07:55 (owner needs the Mac): `bakeoff.sh stop` during Churro 3B; see the hold.
            PAUSED 2026-10-05 08:05 (owner needs the Mac for the day): stopped with `bakeoff.sh stop` after Surya 2
      finished, 7 of Chandra 2's reads saved; seven candidates are complete. Do NOT restart the job until the owner
      ticks `bakeoff-tonight-ok` in HOLD. What is left: the rest of Chandra 2, then Qwen3.5-9B's last guarded try.
      THE SAMPLE, listed and committed first (`OCR-SAMPLE-<date>.tsv`): the 45 pages of the regression set and
      the self-test, the 11 newspapers, and 20 green pages drawn at random from the truth run, spread over the
      routes. Each candidate reads each page in its plain-text mode, from the same PDFKit render the truth set
      used, whole page and, if that loses lines, as the truth set's crops. Vision reads the same renders.
      THE JOB. `ops/ocrlab/bakeoff.sh`: one model at a time under `run-guarded.sh`, each reading saved to
      `$STATE/ocrlab/readings/<model>/<page>.txt` as it is made, resumable from what is saved, one progress line
      per page in `$STATE/ocrlab/bakeoff.log`, the build (4-bit, 8-bit) a parameter. Start it detached
      (`nohup`, explicit PATH) and check it is alive before the session ends. While it runs it touches
      `$STATE/engine.lock` every 20 s, so the daemon starts no session and no suite runs beside the models; it
      removes the lock when it ends, and a killed job leaves a lock the daemon takes over after 30 minutes. It
      never starts while `test.lock` is held or a suite runs. Keep each candidate's weights for `ocr-bakeoff-bits` and
      `ocr-hybrid-run`. Qwen3.5-9B is owed its last guarded try, when more memory is free (after a reboot; it tripped
      once with 5.9 GB reclaimable); measure it first and add it if it fits. Surya 2 runs through `surya_ocr` in
      `$OCRLAB/venv-surya`, not `try-mlx.sh` (see its row's note in `OCR-MODELS-2026-10-04.tsv`).
      DONE WHEN: every fitting candidate has a reading of every sample page or a logged reason, and a count of
      readings per model is committed. A session that finds the job dead restarts it from where it stopped.
      ESTIMATE: 1-2 sessions, plus about 10-15 hours of unattended job. Sub-boxes: the sample list, the job
      started, the job finished and counted. BOUND: rule 10. (context: owner request 2026-10-02, split 2026-10-04)
      - [x] **bakeoff-run-sample** — the sample list, 2026-10-04: `OCR-SAMPLE-2026-10-04.tsv`, 67 pages (39 regression and self-test, not
            45: TRUTH-PAGES holds 31 + 8; 8 more newspapers; 20 green draws over seven routes), by `make-sample.py`.
      - [x] **bakeoff-run-started** — the job started, 2026-10-04 19:55: `bakeoff.sh start` runs from copies in `$STATE/ocrlab/scripts/`; check
            it with `ops/ocrlab/bakeoff.sh status` (`stop` ends it) and `tail $STATE/ocrlab/bakeoff.log`. Newspapers are read as
            crops only; other pages whole, and as crops too when the whole reading holds under 90% of the
            transcript's words. swiftc refuses (Xcode licence), so `$STATE/ocrlab/bin/` holds the truth run's
            own `render-page`/`cut-crops` builds (2026-09-30); cut-crops changed after some owner pages were cut,
            so their crops differ from the truth set's (logged per page). read-mlx.py no longer stops a crop
            read after the crop that follows one cut at max_tokens, which had shortened ocr-lab-setup's crop
            readings (DeepSeek's 0.541). Smoke run on two pages [measured]: LightOnOCR peaks at 11.3 GB on crops
            and tripped the swap rule once on each of two reads with this session's memory in use.
      - [x] **bakeoff-run-counted** — the job finished and counted, 2026-10-07: `OCR-BAKEOFF-COUNT-2026-10-07.tsv`
        [measured from the saved readings]: 14 candidates complete, 56 whole readings each and every owed crop read
        a reading or a reason (14 reasons, all LightOnOCR base/ocr-soup crops the guard killed twice at 12.3 GB).
        Qwen3.5-9B (8 pages) is `dropped` in bakeoff-models.tsv: bakeoff.sh no longer tries or reads it, and
        ocr-bakeoff-score must skip it.
- [x] **ocr-bakeoff-score** — score the saved readings against the truth set and name the top three.
      OVERNIGHT OPTION (owner, 2026-10-05: "we may want to include an option for models that can basically only be
      used overnight when the computer is in limited use otherwise"): when naming the top three, also name any
      reader too slow or too memory-hungry for daytime use that reads clearly better, with its time per 100 pages
      and peak memory, as a candidate "overnight" engine for the owner's review; do not rule it out on speed alone.
      (blocked-on: ocr-bakeoff-run)
      Score exactly as `truth-harness` scores the app: words wrong and missing against the transcripts,
      contested words unscored, by route; seconds per page and peak memory from the job's log.
      VISION'S SPEED IS NOT IN THAT LOG: the job copied Vision's readings from the truth run and never timed them
      (owner, 2026-10-05: measure it rather than call it "fast"). Time Vision on the same renders, whole and as
      crops, with the recognition settings the app uses, on a quiet machine (the job finished, no suite running),
      and record its seconds per page and peak memory the same way as the models'.
      TWO CANDIDATES WERE TIMED ON A BUSY MACHINE (owner, 2026-10-05, from the job's log): DeepSeek-OCR-2 (20:45-22:37)
      and LightOnOCR (22:37-23:37) read while the owner, an interactive Codex session running VM tests (about 21:18
      and 22:02-22:05) and an interactive Claude session running test harnesses were all on the Mac; all nine of the
      night's memory-guard interruptions fell in that window. Every candidate from GLM (23:37) on read after the owner
      quit everything, with none. Re-time DeepSeek and LightOnOCR on a quiet machine before their speed counts; their
      words are not affected.
      DONE WHEN, committed as `OCR-BAKEOFF-<date>.tsv`: every candidate scored on every sample page or a stated
      reason, Vision beside them with its own measured speed, and the top three named by words right on old print and newspapers at a
      speed this Mac can bear. Delete the weights of candidates outside the top three only if the available space (`ops/ocrlab/free-mb.sh`) would otherwise
      fall below 20 GB. ESTIMATE: 1 session.
      DONE 2026-10-07, `OCR-BAKEOFF-2026-10-07.tsv` (`ops/ocrlab/score-bakeoff.py`, Vision timed by
      `time-reads.sh`). Words missed, old print / newspapers: Falcon-OCR bf16 0.23% / 0.52% at 12 s a page;
      LightOnOCR-2-1B 4-bit 0.35% / 0.77% at 13 s busy (crops peak 11.3 GB, two newspaper runaways; its quiet
      re-time, blocked 23 min at the heavy lock by Archive Suite's VM runs, is ocr-bakeoff-bits'); Chandra-OCR-2
      oQ8 0.24% / 0.47% at 82 s (bearable on lines; overnight for whole documents). Vision on crops 3.1% / 12.9% at 1-2 s; the app's layer
      (832b7ac) 1.9% / 21.8%. The top three are those; the bits item uses them. Weights kept (76 GB free).
      BOUND: rule 10. (context: owner request 2026-10-02)
- [ ] **ocr-lab-round3** — fit-test the 2026-10-07 survey's candidates and score newspapers on NewsBench, so the next
      model night reads them beside the top three. (effort: medium)
      WHY. Owner, 2026-10-07: "Do more research on whether there are other projects like Churro worth considering. Be
      thorough." Findings in `PRIOR-ART-2026-10-07.md`: no open successor to Churro exists, but four independent sources
      find that on dense newspaper pages the layout step decides the result, and nobody has measured Churro on layout
      regions or on NewsBench.
      WHAT, same lab rules as ocr-lab-round2 (the guard, one model at a time, free space by `ops/ocrlab/free-mb.sh`,
      the lab under 50 GB, mac-heavy.lock; fit tests are ordinary work any time):
      - [ ] **lab3-dots** — `mlx-community/dots.mocr-4bit` (MIT, 3B; `dots_ocr` is in mlx-vlm 0.7.4): its two test pages.
      - [ ] **lab3-paddle** — PaddleOCR-VL-1.6 (`PaddlePaddle/PaddleOCR-VL-1.6`, Apache-2.0, 0.96B; mlx-vlm
        `paddleocr_vl` or its official GGUF), as a REGION reader: the newspaper page's crops only.
      - [ ] **lab3-layout** — DocLayout-YOLO (`juliozhao/DocLayout-YOLO-DocStructBench`, Apache-2.0 weights, AGPL code;
        Core ML or PyTorch MPS) and PP-DocLayoutV3 (Apache-2.0; mlx-vlm `pp_doclayout_v3`): regions and reading order
        on the newspaper test page, timed, as candidates for ocr-hybrid-proto's region step.
      - [ ] **lab3-newsbench** — fetch NewsBench (github.com/nealcaren/newsbench, MIT; 15 scored Library of Congress
        pages 1850s-1919 with volunteer gold) into the lab, outside git, and score with its own 1−CER scorer: Churro 3B,
        Qwen3-VL-8B, Qwen3.5-4B and Apple Vision whole-page, and Churro and the fitting round-3 readers on DocLayout-YOLO
        regions. Its scoresheet's published rows (GLM-OCR on DocLayout regions 0.970) are the reference.
      - [ ] **lab3-extras** — `wjbmattingly/nara-qwen-3.5-2b` (Apache-2.0, typescripts and forms, its own prompt.txt);
        NuMarkdown-8B-Thinking only if disk and time allow.
      DONE WHEN each candidate has a row in `OCR-MODELS-<date>.tsv` (fits or why not), each fitting build is a `fitted`
      row in `ops/ocrlab/bakeoff-models.tsv`, and `OCR-NEWSBENCH-<date>.tsv` holds the NewsBench scores. ESTIMATE: 2-3
      sessions. BOUND: rule 10. (context: owner request 2026-10-07)
      Round 1, session 1, 2026-10-07: nothing downloaded. The network failed throughout (HF reads and handshakes
      timing out at about 10 MB a minute, with and without Xet; a shallow NewsBench clone died with `early EOF` after
      16 min), so no sub-box could start. The lab was at 49.7 GB, so dots.mocr's 3,374 MB would have been refused;
      Qwen3.5-9B's weights (dropped, 6.0 GB) were deleted, leaving the lab at 44.0 GB. NOTE for lab3-dots: the survey
      missed that ocr-lab-setup already tried dots.mocr-4bit (`OCR-MODELS-2026-10-04.tsv`: ordinary page fits, 6.4 GB,
      75 s, rough recall 0.903; the guard killed the whole newspaper page once, swap, and the crops were never read).
      So its next read, crops only, is its one remaining try; this session's used `--max-side 2000`, prompt "Extract
      the text content from this image." NEXT: try lab3-dots again when the network is back.
- [ ] **ocr-bakeoff-bits** — run the top three at 4-bit and at 8-bit and compare.
      (blocked-on: ocr-bakeoff-score, ocr-lab-round3)
      The owner's 2026-10-02 request: the same sample through `bakeoff.sh` with the build as the parameter,
      holding the engine lock, scored as `ocr-bakeoff-score` scores. DONE WHEN, committed as
      `OCR-BITS-<date>.tsv`: for each of the three, the difference between 4-bit and 8-bit in words right,
      seconds per page and peak memory, and the build each memory limit from 4 GB to 12 GB should use.
      THE THREE (`OCR-BAKEOFF-2026-10-07.tsv`): falcon-ocr-bf16, lightonocr-2-1b-4bit-1540, chandra-ocr-2-oQ8. Score
      with `ops/ocrlab/score-bakeoff.py`. LightOnOCR-4bit's speed there is the busy machine's: this run's is its first
      quiet timing.
      ESTIMATE: 1-2 sessions, plus about 4-6 hours of unattended job. Sub-boxes: job started, scored.
      BOUND: rule 10. (context: owner request 2026-10-02)
- [ ] **ocr-hybrid-proto** — build the ways of putting a better reader's words into the text layer, behind a
      setting that is off by default. (blocked-on: ocr-bakeoff-bits)
      FROM local-llm-pdf-ocr (MIT; `PRIOR-ART-2026-10-05.md` §4): for arrangement (b), align ONE whole-page model
      reading onto Vision's lines with its monotonic dynamic-programming alignment (area-share character budget,
      asymmetric costs) instead of one model call per line, fall back where alignment confidence is low, and use
      its crop guards. Do not take its text placement or page images.
      ADD AN ARRANGEMENT (2026-10-05 survey): cut newspaper pages by LAYOUT REGION before reading them, with
      DocLayout-YOLO (`juliozhao/DocLayout-YOLO-DocStructBench`, ONNX on CPU or `doclayout-yolo` on MPS) instead
      of fixed crops. On NewsBench (15 dense Library of Congress pages; one author, github.com/nealcaren/newsbench)
      DocLayout-YOLO regions read by GLM-OCR or PaddleOCR-VL score 0.970, against at most 0.82 for any model
      reading the whole page, and its author's finding is that "the detector matters more than the recognizer".
      The Library of Congress's 2025 Chronicling America re-OCR also cuts by layout first. Measure it here.
      Three arrangements, built for the top model first: (a) the model replacing Vision outright, its own line
      or word boxes used directly (a first-class option: owner, 2026-10-02, Intel Macs and download size are
      not constraints, so only accuracy, placement, speed and memory decide); (b) Vision's lines for geometry,
      the model reading each line's crop and its words placed in Vision's boxes (the truth set's crop-and-align
      method); (c) Vision as now, the model only on lines Vision skipped or read with low confidence and on
      newspaper bands. Each needs a check that goes red without it, and invariant 3's four properties hold.
      DONE WHEN each arrangement runs on two sample pages through the production pipeline and its check is in
      the suite. ESTIMATE: 2-3 sessions. Sub-boxes: one per arrangement. BOUND: rule 10.
      (context: owner request 2026-10-02, split 2026-10-04)
- [ ] **ocr-hybrid-run** — run every arrangement with each of the top three over the sample, as one job.
      (blocked-on: ocr-hybrid-proto)
      A detached, resumable job like `bakeoff.sh`, holding the engine lock: the production pipeline on the
      sample for each model and arrangement that suits it, scored with `ux-harness --truth` (Copy, Find, order)
      and the ink and colour check, with time per page and peak memory. DONE WHEN, committed as
      `OCR-HYBRID-<date>.tsv`: every combination scored or a logged reason. ESTIMATE: 1-2 sessions, plus about
      6-10 hours of unattended job. Sub-boxes: job started, finished and scored. BOUND: rule 10.
      (context: owner request 2026-10-02, split 2026-10-04)
- [ ] **ocr-hybrid-pick** — choose the arrangement, model and build for each memory limit.
      (blocked-on: ocr-hybrid-run) (effort: medium)
      A route wins when it cuts words wrong or missing by at least a third on old print or on newspapers, runs
      at no more than three times Vision's time per page, and stays under the guard's 12 GB on this Mac.
      DONE WHEN a new `BUGS.md` entry names the winning arrangement with its gain in words right and its cost in
      time, memory and download size, and the model and build for each memory limit from about 4 GB to 12 GB;
      or says that none wins, in which case the three `ocr-integrate-*` items and `ocr-requeue` are ticked
      with that reason and the queue goes on as before. ESTIMATE: 1 session. BOUND: rule 10.
      (context: owner request 2026-10-02, split 2026-10-04)
- [ ] **ocr-integrate-engine** — run the winning arrangement inside the app. (blocked-on: ocr-hybrid-pick)
      Built, not left as a recommendation (owner, 2026-10-02). The model runs from the app's helper under the
      guard's limits with the chosen maximum as its cap, and falls back to Vision with a message when memory is
      short or the model fails. If arrangement (a) won, the model replaces Vision as the recogniser in this mode,
      Vision kept only as that fallback. Integrate each model `ocr-hybrid-pick` named for a memory limit.
      DONE WHEN the helper produces `ocr-hybrid-run`'s figures for the winner on the sample, the suite passes,
      and nothing crashes on this Mac. ESTIMATE: 2-4 sessions. Sub-boxes: the runtime in the helper, the guard
      and fallback, one per model wired in. BOUND: rule 10. (context: owner request 2026-10-02, split 2026-10-04)
- [ ] **ocr-integrate-settings** — give the accurate mode its settings and downloads.
      (blocked-on: ocr-integrate-engine)
      Off by default until the owner decides. A maximum-memory setting with steps from about 4 GB to 12 GB and a
      default chosen from the Mac's installed memory, and under it a choice among the integrated models and
      builds that fit that limit (owner, 2026-10-02). Each model downloads on first use with its size stated.
      DONE WHEN the settings and downloads work in the built app, `ux-regression.sh` is no worse with the mode
      off, and the suite passes. No release: that stays the owner's. ESTIMATE: 1-2 sessions. Sub-boxes: the
      settings, the downloads. BOUND: rule 10. (context: owner request 2026-10-02, split 2026-10-04)
- [ ] **ocr-requeue** — make the rest of the queue build on the accurate mode.
      (blocked-on: ocr-integrate-settings) (effort: medium)
      Re-measure every later open item's named pages with the mode on. Close an item whose DONE WHEN the mode
      already meets, citing the measurement, and re-scope the rest so their DONE WHEN is checked with the mode
      on as well as off and their fixes work with it. Add the mode's rows to `ops/ux-regression/set.tsv`. Give
      each re-scoped item an ESTIMATE under rule 11. ESTIMATE: 1 session. BOUND: rule 10.
      (context: owner request 2026-10-02)
- [x] **c54-pale-typing** — publish pale typewriting on layered pages as solid as the source shows it.
      2026-10-05: round 1, session 1, FIXED (pale-ink stencil re-cut, `Flattener.paleInkLevels`).
      THE PAGES: `Herbert Marks papers` p12, `_1939_Former students` p9, `Atkinson_1939` p2, `Ford_1941` p2.
      DONE WHEN, on 1x and 2x PDFKit renders of the published pages beside the source: the typed strokes are
      unbroken wherever the source's are; dark-ink pages in `ops/ux-regression/set.tsv` are unchanged or
      better; bytes within 10% of before; a new check goes red without the change.
      BOUND: rule 10. (origin: BUGS.md C54)
- [x] **c55-low-runs** — draw each run over its own ink, so a drag over a line copies that line.
      THE PAGES: `1951 - Briefer Book Notes` p1, `Zipkin_2000` p1, `Banks 2006` p101 (C55 gives the lines and
      their positions).
      DONE WHEN, through PDFKit: a drag from the first to the last glyph of each named line copies that
      line's words and none of the line above; invariant 3's four properties re-measured and holding;
      `ux-regression.sh` no worse; a new check goes red without the change.
      BOUND: rule 10. (origin: BUGS.md C55)
      Session 1, 2026-10-05: squashed runs now rise toward their ink's middle; the named lines and invariant 3
      pass, the checks go red without it. Open: `ux-regression` 7 worse (column drags on Raskin p1, Fiedler p1,
      `___ 2` p1; C55 gives the rows and the gutter-start lead). The baseline was refreshed at this commit.
      Session 2, 2026-10-05 (round 1): six of the seven rows are the harness's start point or better copies;
      one is real, `___ 2`'s ad column now read across with the article beside it (C55). Not yet fixed.
      Session 3, 2026-10-05 (round 1, max): ink-measured tilts; parked by triage (c6cec50), 14 rows worse.
      Session 4, 2026-10-06 (round 1): DONE WHEN checked on unchanged code, ux-regression 0 worse; the ad
      column accepted as PDFKit grouping on a 0.06 pt margin (C55). Closed.
- [x] **c28-first-principles** — fix C28 again, starting from first principles. The owner took it off the
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
      BOUND: rule 10. Rule 4 applies.
      2026-10-06: round 1, sessions 1 and 2. Session 1's uncommitted strand (dark unboxed ink into the
      stencil on all-text pages) was adopted by session 2, which kept it out of the margins. Pencil left.
      2026-10-06: round 1, session 3. Pencil gets a mark layer at 1/3; Ford p1 and Former p2 read; the
      22 sample documents +5.5% (`BUGS.md` C28, session 3).
      (origin: BUGS.md C28)
- [ ] **c41-newspaper-scans** — read whole-page scans of small-town newspapers as well as their print
      allows (`BUGS.md` C41, split from C39). Start from the band swap parked at
      `$STATE/rescue/PARKED-c39-dense-band-swap-2026-09-26.patch` and the eight defects C41 lists; fix
      them, or show that the swap cannot be made safe and try something else. Read C39's record of what
      was tried before starting.
      THE PAGES: the five whole-page scans C41 names. Work on all five; they differ in difficulty, and a
      gain on some of them ships on its own.
      DONE WHEN, on the published PDF, through PDFKit, for each of the five pages before and after: misread
      words in the paragraph C39's table used, counted by hand; rows fused across columns; words in the
      dictionary. Every page that can be improved is, and each that cannot is named with what was tried;
      ordinary pages across a corpus sample are unchanged; invariant 3 holds; a new check goes red without
      the change. Drag selection is not in scope (C39 closed it).
      BOUND: rule 10.
      2026-10-06: round 1, session 1 (opened at 89% of the window). Measured: the published pages are
      within 1.3 points of Vision's best band reading, so the band swap is dropped; fused rows remain (C41).
      Session 2 (docs only): few fused rows in the recogniser's own boxes. 2026-10-07: session 3: rows read
      across a printed column rule now split (Helena 1941 0 -> 4, 1931 1 -> 4). Left: the comic page's gutter
      is not found from its bitmap's lines (`columnGutters`); Billings, Oct 1960 and 1928 as C41 says.
      (origin: BUGS.md C41)
- [ ] **c52-column-jumps** — make a drag down one column stay in it on the pages C34 still misses.
      Riesman p2 is fixed (ff25f3b, 4657cff); Marth p2 and Cong p16 are not. The first bound was spent
      by those two commits, and the item was moved here on 2026-09-28 so the unattempted items above go
      first. Start from C52's recommended next approach (one height and pitch per column).
      DONE WHEN, through PDFKit: a drag down each column of Riesman_1949 p2, Marth_1982 p2 and
      `_1953_99 Cong_ 2` p16 copies that column's lines in order and nothing from its neighbour, checked
      against the source's own text layer's drag; C34's pages are no worse.
      BOUND: rule 10. 
      Round 1, sessions 1-3, were on 2026-09-28 (ff25f3b, 4657cff, e34fb92), so its next session is round 1's
      fourth (rule 10). (origin: BUGS.md C52)

- [ ] **attempt-on-worked-item** — count a session's attempt against the item it worked, not the queue head.
      WHY. Owner, 2026-10-05, asking why a model fit test needed a max session: four sessions found
      ocr-lab-round2 unable to proceed (the disk rule), each took another item, and 3e counted every one against
      the head item, so it rose to max ($140 cap, 8 h) for work that was never hard. The same happens to a head
      item whenever a session adopts a rescue (3e's comment already notes that case).
      WHAT. In `vision-ocr-autonomous.sh` 3e and wherever `attempts.tsv` is written, record the item the session
      actually worked (from its commits' trailer or the item it ticked or noted), and count the head item only
      when it was that item. Keep `(attempts: N)` and `(effort: …)` as they are.
      DONE WHEN: a prove-daemon case where a session works item B while A heads the queue leaves A's count
      unchanged and adds to B's, and a mutant restoring head-counting turns it red. ESTIMATE: 1 session.
      BOUND: rule 10. (context: owner request 2026-10-05)

- [ ] **c56-heavy-type** — keep 1-bit sources' strokes as thin as they arrive.
      THE PAGES: `Luethy_1955` p2, `Gowan and Demos` p1, `Xin Qu_2018` p1, `Ries_Marshall_1955` p54.
      DONE WHEN, on 2x PDFKit renders beside the source: stroke weight matches the source by eye, and
      measured as ink share within 5% of the source's on each page; bytes no larger; `ux-regression.sh` no
      worse; a new check goes red without the change.
      BOUND: rule 10. (effort: max) (origin: BUGS.md C56)
      2026-10-06: round 1, session 1 (strand, not committed) and session 2 (adopted it; plain 1-bit
      route fixed; Gowan's layered page and Xin Qu at 1.06 remain). Session 3: layered route fixed
      (Gowan 1.03); Xin Qu's 1.06 is PDFKit's drawing of a stencil source, see C56's case for closing.
      Session 4: `mrcStencil`'s lift pinned by a check; round 1 spent, so moved behind the untried
      items. Round 2 is at max: judge C56's case for closing (Xin Qu's 2x 1.06 is PDFKit's stencil draw).

## Parked

Potential future work, not queued. Nothing here is offered to a session: the entries have no checkbox,
so `next-item.sh` does not read them. To queue one, move it back into the queue as a `- [ ]` item.
(C28 was parked here from 2026-09-21 until the owner brought it back on 2026-09-25 as
`c28-first-principles`.)

- **annot-r3** — the third adversarial review round on the annotation-preservation feature (on
      `main`, off by default, unadvertised). Rounds one and two are recorded in `TODO.md`. Run the review
      by subagent, fix what it finds that is real, and record the verdict on whether the feature is fit to
      turn on. BOUND: one review round and its fixes.
      Parked by the owner 2026-09-27: potential future work, not queued.
      (origin: TODO.md §"Preserving annotations through re-OCR")
- **zotero-2** — the Zotero library sweep: look for new classes of document the app handles badly.
      Re-run step 1 of `TODO.md` §"2. The Zotero library sweep" first; its survey is dated. Copy
      `zotero.sqlite` before querying it, because Zotero locks it, and never write the library. BOUND: one
      step per session, with its output committed. Each confirmed defect it finds becomes a `BUGS.md` entry
      and a queue item above this one.
      Parked by the owner 2026-09-27: potential future work, not queued.
      (origin: TODO.md §"2. The Zotero library sweep")

## HOLD — owner-only, never auto-executed

- [ ] **larger-plan-active** — the owner says the larger Claude plan is in use. Tick it when it is, with the date;
      `two-sessions-recheck` waits on it. [hold] needs: owner — only the owner knows when the plan changes.
- [x] **bakeoff-tonight-ok** — the owner says the Mac is free, so the bake-off may resume (rest of Chandra 2, then the
      Qwen3.5-9B try). Owner, 2026-10-05: the daemons work through the day, the bake-off waits for tonight. [hold] needs: owner
      TICKED 2026-10-05 about 22:00: owner, "I'm done with the computer for the night." The bake-off was restarted
      with `bakeoff.sh start` by an interactive session after Archive Suite's on-device segmentation runs.
      UNTICKED 2026-10-06 07:55: owner, "I need the mac for the day." Night 2 ran 23:59-07:55: Chandra 2 finished,
      LightOnOCR-2 base and ocr-soup, Falcon-OCR, and Churro 3B to 36 of 56 whole pages. Tick again when the owner
      next frees the Mac; left: the rest of Churro, then Qwen3.5-9B's last guarded try.
      TICKED AGAIN 2026-10-06 23:35: owner, "I'm done with the computer for the night." `bakeoff.sh start` by an
      interactive session; left: the rest of Churro 3B, Qwen3.5-9B's last guarded try, then olmOCR-2-7B and
      Qwen3-VL-8B (fitted 2026-10-06). Its guarded reads now take the shared mac-heavy.lock. Untick when the owner
      next needs the Mac.

These are offered to nobody. `next-item.sh` prints them as `hold` so they stay visible.

      DONE 2026-10-07 07:40: owner, "Let's discard Qwen3.5-9B. The bake-off is then done, correct? We can move on?"
      Night 3 (23:35-07:40) finished Churro 3B, olmOCR-2-7B and Qwen3-VL-8B; Qwen3.5-9B was stopped at 6 of 56
      pages (weak early reads: one whole page 4 characters) and is DROPPED by the owner, not owed another try. No
      further bake-off night is needed for ocr-bakeoff-run; ocr-bakeoff-bits will need its own (4-6 h job).
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
