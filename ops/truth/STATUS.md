# truth-calibrate — working status

**Done 2026-09-29 (second session).** The procedure is `procedure.md` v2; the evidence is
`TRUTH-CALIBRATE-2026-09-29.tsv`, whose per-page block holds the reader half.

- Scans: `make-scans.sh` (clean: 300 dpi grey on grey paper; hard: 150 dpi, 1-bit, 0.8° skew, JPEG q20).
  The app half was measured on all 64 scans (first session). The reader was run on 16: one page of each of
  the eight layouts, clean and hard. Cross-checked: five of them, 386 words.
- **Fit, measured on one page per kind:** every synthetic layout (one, two, three columns, table,
  footnotes, 6.5 pt), clean and hard, and the real magazine page (Davis) hard. Reader fair loss 0-0.66%
  against the app's 0-30.8%, no skipped line; without any check it is 0-1.22%, which passes too. Davis
  clean fails as written (0.22% against 0.45%) and is passed on a waiver: both lost words are one scorer
  artefact (`jour-` at a column end) that the app loses too.
- **Real book (Canby) is not calibrated:** its "born-digital" layer is old OCR (`ERACE`, `gUINN 1::`,
  `no` for 110), so it cannot be the truth. The reader's transcript matches the page by eye.
  `testdocs/` has no other born-digital book page. **So in `truth-set`, old-book pages (real books, not
  magazines) are scored only for lost lines and blocks**, until a book page with a correct layer is found
  and measured.
- **v1's cross-check was harmful** and v2 changes it: a check never replaces a word, it only contests it.
  Tiny degraded type is contested heavily (6.5 pt hard: 144 of 900 words; its 0.66% is over the 756 left), so `truth-set` should report
  the contested share next to every score.
- Product findings for `truth-read` (measured; the reader read each of these tables with no error):
  clean ruled tables lose 27% of their words from the app's layer and hard ones 31%. 6.5 pt hard type
  loses 18%. The one-column *clean* scan loses 3.9% against 0.4% for its hard scan, which is backwards
  and unexplained.
- Tools, all in this directory: `render-page`, `img2pdf`, `cut-crops`, `synth-pages` (swiftc -O),
  `score-words.py`, `xcheck.py` (transcript text; reader-vs-Vision spots), `wordcrops.py` (word crops from
  ink gaps), `apply-check.py` (applies checks, v1 or `V2=1`, and the fair score).

# truth-set — working status

The list is `TRUTH-PAGES-2026-09-29.tsv` at the root (`make-list.py`, fixed seed; 215 pages). Its status
column is filled by `page-status.py`, which also prints the contested rate by route. Per page, with
`swiftc -O` builds of `render-page`, `cut-crops`, `vision-read` and `Tools/pdf-page-text.swift` (as
`page-text`) in one bin directory:

1. `prep-page.sh <bin> <document> <page>` (one at a time: it renders and runs Vision).
2. One reader subagent per page, given the READER prompt, the crop list and the crop command (the
   `brief.txt` it writes); many may run at once.
3. `spots-page.sh <page-dir>`, then shuffle every page's `check/<idx>.png` into briefs of about 40 with the
   CHECK prompt, one check subagent each, writing `path<TAB>reading` to `chk-*.out`.
4. `finish-page.sh <page-dir> <checks-dir> <reader-tokens>`, which deletes the page image and crops.
   A page with no transcript goes in `$STATE/truth/none.tsv` with its reason.

Measured cost, batch 1 (21 owner pages of the regression set, 2026-09-29): readers 34-50k tokens a page,
99k for the newspaper page; checks 33-38k per 40 words; the batch used about 32% of the five-hour window,
so a session holds about 40 pages from a fresh window.

**Batch 1 (b1), 2026-09-29:** 20 of 21 pages done, 11,015 words, 57 contested (0.52%); without the
newspaper page 7,826 words, 10 contested (0.13%). Contested rate by route (`page-status.py`): dct 0/182,
jbig2 3/3,910 (0.08%), layered 5/1,929 (0.26%), no-image 1/435 (0.23%), unknown 48/4,202 (1.14%;
Raskin's newspaper page is 47 of them). **Next:** batch 2 = the 8 selftest pages (Why 3, 4, 7; Briefer 2,
5, 6; Hughes 2, 8) and the testdocs pages of the regression set, then the draws in list order; Hughes p3
again; `prep-page.sh` needs `TESTDOCS=/Users/cp1/Claude/vision-ocr/testdocs` when run from a worktree.

- **The grey render hides colour.** `render-page` draws grey, so the OBJECTS lists name every coloured
  heading "dark grey" (Why p5). Kinds and boxes stand; `truth-harness` should take colour from the source's
  pixels inside each object's box, not from the list.
- **Vision on a full page misses most of a newspaper** (Raskin p1, 300 dpi: 1,047 words against the
  reader's 3,315) and half of Briefer p1 and p3 (273 of 631, 302 of 664) — both on a plain render, not the
  app's pipeline. `vision-read` over the crops finds them; noted for `truth-read`, not measured on the app.
- The content filter blocked the reader's output on Hughes p3 twice.
- The contested rate is high on dense newsprint (Raskin) partly from the instrument: where the ink gaps do
  not match the line's word count, `wordcrops.py` cuts the nearest gap, often the word beside the spot.
  Those crops are contested 14 of 41 times against 17 of 182. Safe (the word is not scored), not fixed.

**Batch 2 (b2), 2026-09-29 (a session that started at 86% of the window, so no subagents):** six of
the eight selftest pages: Why 3, 4, 7 and Briefer 2, 5, 6. 3,218 words, 14 contested (0.44%). Two
departures from the procedure, both recorded in each page's `meta.txt` as `reader_tokens=session-inline`:
the session read the crops itself with the READER prompt instead of a reader subagent (it opened only
the crops and never the page's Vision or layer text before writing the transcript), and no check
subagent read the 14 spots, so every one counts as contested, as `contest.py` already does for a spot
with no check. The rate is an upper bound for that reason. Why p4's 7 are two lines page-level Vision
missed and a crop edge split; Briefer's 7 are broken glyphs and `(11" x 17")`. Cost: about 1% of the
window a page. **Next:** Hughes 2 and 8 (the selftest's last two), then the testdocs pages of the
regression set, then the draws in list order; Hughes p3 again.

**Batch 3 (b3), 2026-09-29 (started at 92% of the window, so no subagents):** the selftest's last two
pages, Hughes 2 and 8, read in-session as in b2 (`reader_tokens=session-inline`, spots unchecked, so
counted contested). 1,400 words, 9 contested (0.64%): Hughes 8's 6 are the dots of two ellipses, which
`wordcrops.py` crops as lone `.` tokens; Hughes 2's 3 are `vari-`, `continued` (a stray mark beside it) and
`Work-`/`ers`. All 8 selftest pages are now done. Rate by route over every done page: dct 0/182, jbig2
10/6,131 (0.16%), layered 12/2,926 (0.41%), no-image 1/435 (0.23%), unknown 57/5,602 (1.02%). **Next:** the
16 testdocs pages of the regression set (Zarifa 92 first, in list order), then the draws; Hughes p3 again.

**Batch 4 (b4), 2026-09-29, full procedure (reader and check subagents, every spot checked):** the eight
`session-inline` pages again, Hughes p3, and the 16 testdocs pages of the regression set. 25 pages, 22,352
words, 177 contested (0.79%). The two small-town newspapers hold 143 of them (`___ 2` 74 of 3,144; Fiedler
69 of 3,344); without them it is 34 of 15,864 (0.21%). Hughes p3 got past the content filter, and Allen p8
was blocked once and read on the retry. **The redo:** the old transcripts are in each page's `inline/`.
Order-free, with dashes and quotes folded, the new reading matches the old on every word but Hughes p2's
`E LTON`/`ELTON` (none in the other seven pages, about 4,000 words). As written, the new ones differ in dash and quote glyphs
and in where Hughes p2 puts its footnote. Contested counts moved from 7/0/3/4/0/3/6 to 0/4/1/0/0/0/6
(Why 4, 7; Briefer 2, 5, 6; Hughes 2, 8), because checks now settle spots. Each reader was handed its
`brief.txt` to Read, not the prompt pasted in. The file holds the READER prompt verbatim and no page
text. Checks: 502 crops in 13 shuffled briefs of 39. Cost: readers 41-67k tokens a page, 76k and 111k for
the newspapers; checks about 33k per brief. The batch took about 34% of the window (12% to 46%).
Rate by route over every done page: dct 0/182, jbig2 15/13,339 (0.11%), layered 17/4,863 (0.35%),
newspaper 146/7,841 (1.86%), no-image 1/435 (0.23%), unknown 55/6,350 (0.87%). **Next:** the draws in
list order (row 2 on, `todo`), about 40 a session.

**Batch 5 (b5), 2026-09-29, full procedure, same session as b4:** the first 20 `todo` draws in list order
(rows 2-21, all ux-run green jbig2). 6,437 words, 84 check crops over 81 spots, 33 contested (0.51%), none
unchecked. The rate overstates doubt. CIT 1958's cover holds 7 (six `[?]` in an illegible library stamp,
which perhaps should not count as words). On Naylor p67, 5 of 6 are `wordcrops.py` cutting beside a
line-end hyphen or footnote mark (`pro-`, `necessa`), the artefact noted under b1. Readers used 35-57k tokens a page, and the batch about 21% of the window (46% to
67%). jbig2 over every done page: 48 of 19,776 (0.24%). 65 of 215 pages are done, 150 `todo`. **Next:** the
draws from row 22 on.

**Batch 6 (b6), 2026-09-29, full procedure, same session:** the next 20 `todo` draws (rows 22-41, all
jbig2). 6,146 words, 156 spots, 164 check crops, 72 contested (1.17%), none unchecked. The two pages of
`_1979_Ideology of American Neo-Conservatism_` hold 36 (p4 12 of 508, p8 24 of 490). Cartwright p1 holds 12
of 96, General Foods 1958 p21 10 of 151, and ppf_description p1 8 of 259. Not inspected; the b5 review found
such counts partly crop artefacts. Readers used 33-63k tokens a page. The session ended at 90% of the window
with this batch. jbig2 over every done page: 120 of 25,922 (0.46%). 85 of 215 pages are done, 130 `todo`.
**Next:** the draws from row 42 on.

**Batch 7 (b7), 2026-09-29, full procedure, a session that started at 94% of the window:** four draws,
rows 42-45 (Noble 1977 p104, Anaconda 1958 p9, Hayek 1978 p1, `w7787 2` p1; all jbig2). 1,011 words, 16
spots, 18 check crops, 3 contested (0.30%), none unchecked. Readers used 37-45k tokens a page. The window
reached 99%, so the batch stopped at four. 89 of 215 pages are done, 126 `todo`. **Next:** the draws from
row 46 on.

**Batch 8 (b8), 2026-09-30, full procedure, from a fresh window:** rows 46-92 of the list, the last ux-run green jbig2
draws and the layered, dct and first no-image draws (44 pages; rows 71, 78 and 91 were already done). 14,997
words, 133 check crops, 37 contested (0.25%), none unchecked. Atkinson 1939 p2, a typescript with no space
after its commas, holds 9: the reader writes `Merriam,Mollett,Atkinson` as one token and the word crop
shows part of it. `cut-crops` trapped on the 27 x 36 in sheet of `_1939_Former students` p9 (a side over
about 4x the crop size made an empty cut range); fixed. Readers used 25-58k tokens a page, and 172-179k
on the three 1939-41 typescripts and letters. The batch took about 50% of the window. Rate by route over
every done page: dct 3/3,859 (0.08%), jbig2 124/29,274 (0.42%), layered 49/12,584 (0.39%), newspaper
146/7,841 (1.86%), no-image 2/1,693 (0.12%), unknown 55/6,350 (0.87%). 133 of 215 pages done, 82 `todo`.
**Next:** the draws from row 93 on.

**Batch 9 (b9), 2026-09-30, full procedure, same session as b8:** rows 93-114 (20 pages; rows 108 and 112
were already done): the last ux-run green draws, 6 no-image, 3 newspaper, 5 other, 6 unknown. 8,775 words,
85 check crops, 21 contested (0.24%), none unchecked. Gitlin's New York Times page holds 15 of 1,583 and
Zipkin's 4 of 420. Readers used 27-49k tokens a page; the batch took about 20% of the window (53% to 73%).
Rate by route over every done page: dct 3/3,859 (0.08%), jbig2 124/29,274 (0.42%), layered 49/12,584
(0.39%), newspaper 165/10,063 (1.64%), no-image 2/4,199 (0.05%), other 2/867 (0.23%), unknown 55/9,530
(0.58%). 153 of 215 pages done, 62 `todo`. **Next:** the ux-run red draws from row 115 on.

**Batch 10 (b10), 2026-09-30, full procedure, same session:** rows 115-126, the first 12 ux-run red draws (9
jbig2, 2 layered, 1 no-image). 7,548 words, 120 check crops, 40 contested (0.53%), none unchecked. Xin Qu
2018 p24 holds 35 of its 287 (83 spots on one page, probably a table; not inspected). Readers used 34-58k
tokens a page; the batch took about 15% of the window (75% to 90%). Rate by route over every done page: dct
3/3,859 (0.08%), jbig2 162/34,262 (0.47%), layered 51/13,911 (0.37%), newspaper 165/10,063 (1.64%),
no-image 2/5,432 (0.04%), other 2/867 (0.23%), unknown 55/9,530 (0.58%). 165 of 215 pages done, 50
`todo`. **Next:** the red draws from row 127 on.

**Batch 11 (b11), 2026-09-30, full procedure, a session that started at 91% of the window:** rows 128-129
(NYSE 1956 p110, jbig2, 464 words, 5 contested; Williams 1958 Manchester Guardian p1, newspaper, 1,271 words,
0 contested). 37 spots, 46 check crops in one shuffled brief, none unchecked. Readers used 57k and 44k tokens.
Row 127 (the 1926 Anaconda Standard page) was prepared and its reader started, but the window ran out before
its checks; its directory may hold a transcript with no `words=` line, so it is still `todo` and is redone
from `prep-page.sh`. Rate by route over every done page: dct 3/3,859 (0.08%), jbig2 167/34,726 (0.48%),
layered 51/13,911 (0.37%), newspaper 165/11,334 (1.46%), no-image 2/5,432 (0.04%), other 2/867 (0.23%),
unknown 55/9,530 (0.58%). 167 of 215 pages done, 48 `todo`. **Next:** row 127, then row 130 on.

**Batch 12 (b12), 2026-09-30, full procedure, from a fresh window:** 16 ux-run red draws from rows 130-152
(12 jbig2, 4 layered). 9,644 words, 301 spots, 331 check crops, 165 contested (1.71%), none unchecked. Three
pages hold 113: Scott's contents page (p1, 50 of 827) and p7 (39 of 1,125), where the reader writes a
dotted leader and the name after it as one token (`Profit.......HARRY`) and the check sees only a part,
and Gelfand p106 (24 of 166), where `wordcrops.py` cut beside the word (`form` checked as `BELOW`). Both
are the crop artefact noted under b1; the words are not scored. Readers used 31-76k tokens a page, 115k
for the `___` newspaper (row 134, whose checks are in b13). One reader's Write was refused for the path
`Har - THE NECKLACE OF KALI./p1`; it wrote to `/private/tmp` and the session moved the file into place.
Rate by route over every done page: dct 3/3,859 (0.08%), jbig2 268/41,406 (0.65%), layered 115/16,875
(0.68%), newspaper 165/11,334 (1.46%), no-image 2/5,432 (0.04%), other 2/867 (0.23%), unknown 55/9,530
(0.58%). 183 of 215 pages done, 32 `todo`, all prepared and read or reading in this session.

**Batch 13 (b13), 2026-09-30, full procedure, same session as b12:** 13 more ux-run red draws, rows 134-160
(9 jbig2, 2 layered, 2 newspaper). 15,123 words, 464 spots, 509 check crops, 171 contested (1.13%), none
unchecked. CIT 1958 p21 holds 51 of 304 (a table of figures), Scott p10 49 of 936 (dotted leaders again)
and the UN-OCred spread p20 35 of 583. Not inspected. Readers used 31-60k tokens a page, 70k and 115k for
the two newspapers. Rate by route over every done page: dct 3/3,859 (0.08%), jbig2 369/49,346 (0.75%),
layered 165/18,672 (0.88%), newspaper 185/16,720 (1.11%), no-image 2/5,432 (0.04%), other 2/867 (0.23%),
unknown 55/9,530 (0.58%). 196 of 215 pages done, 19 `todo`.

**Batch 14 (b14), 2026-09-30, full procedure, same session:** rows 200-216, the non-text candidates and the
photograph book (13 layered, 3 jbig2, 1 dct). 4,766 words, 84 spots, 85 check crops, 40 contested (0.84%),
none unchecked. The handwritten 1939 letter (`Former students` p5, 39 words) holds 24; five photograph pages
hold under 15 words each. Readers used 37-54k tokens a page, 196k on the letter, which the reader turned
upright by adding `-rotate -90` to the crop command. Rate by route over every done page: dct 5/4,430
(0.11%), jbig2 371/51,240 (0.72%), layered 201/20,973 (0.96%), newspaper 185/16,720 (1.11%), no-image
2/5,432 (0.04%), other 2/867 (0.23%), unknown 55/9,530 (0.58%). 213 of 215 pages done, 2 `todo`: the
two small-town newspapers, rows 127 and 137. Their transcripts exist (4,199 and 5,676 words).
**Row 127 needs about 1,700 check crops:** `spots-page.sh` made 1,612 spots of its 4,199 words, mostly
plain words (`consider`, `was`, `Missoula`). They are genuine under the procedure. Vision, over the page and
over each crop, misses whole columns (`severe` is in neither reading), and the layer's lines do not align
with the reader's. So the page is a session's worth of checks on its own; the b14 note that the alignment
fails was wrong.

**Batch 15 (b15), 2026-09-30, full procedure, from a fresh window:** rows 127 and 137, the two small-town
newspapers, closed from the transcripts already written. Row 137 (Helena Daily Independent 1931): 5,516
words, 445 spots, 522 check crops, 169 contested (3.06%). Row 127 (Anaconda Standard 1926): 4,049 words,
1,612 spots, 1,722 check crops in 39 briefs, 865 contested (21.4%), 450 of them `?`. None unchecked on
either. The `?`s were looked at: the crops are 42 px tall at 300 dpi of worn newsprint, and some sit
beside their word (`Hasty,`'s crop shows a `J`), the `wordcrops.py` artefact noted under b1 and b12. So
the page's single-word checks cannot confirm much of what its reader read; those words are unscored, and
it scores on 3,184. Check readers used 25-40k tokens per 45 crops; the batch took about half the window.
**All 215 pages are done; none in `none.tsv`.** Contested rate by route: dct 5/4,430 (0.11%), jbig2
371/51,240 (0.72%), layered 201/20,973 (0.96%), newspaper 1,219/26,285 (4.64%; 1.59% without row 127),
no-image 2/5,432 (0.04%), other 2/867 (0.23%), unknown 55/9,530 (0.58%).

# truth-second-reader — 2026-09-30

Gemini (3.1 Flash Lite) read the ten most-contested pages; per page in `TRUTH-SECOND-READER-2026-09-30.tsv`.
**Claude's error on old print, estimated: under 1% on every page**, so nothing changes for `truth-harness` or
`truth-read`. Gemini disagreed with 40 of the 19,944 settled words it aligned (0.20%; highest CiT p21, 1 of
111), at least 6 of them its own hyphen splits. A fresh Claude check backed the reader on 30, and 10 became
contested (0.05%; `Snider`/`Shider`, `CHICACO`/`CHICAGO`). Of the 1,448 contested words, Gemini settled 194
by agreeing with the reader; with the 10 new ones, 1,264 are contested. It agreed with the check alone on 544,
and 227 of those are exactly a word on the same or an adjacent line, because `wordcrops.py` cut the neighbour.
So many contested words are miscut crops, not doubtful readings. They stay contested. 1,136 settled words were
not compared: 704 Gemini left out (Xin Qu p24's table, 87), 236 in misaligned blocks (column slivers at crop
edges), 179 in Fiedler 1941's one refused crop (`RECITATION`), 17 on lines crossing a crop edge. Each page's
`contested-second.tsv` (in `$STATE/truth/`) is `contested.tsv` with this applied; `truth-harness` should read
it where it exists.

# truth-harness, step 2 — 2026-09-30

`ux-harness --truth` now checks each OBJECTS element's box for ink and colour with no model (`elInk`, `elCol`:
the least share of an element's dark or coloured pixels the output keeps; `tink`, `tcolour` under 0.50).
`ux-regression.sh` scores the set's truth pages as `truth` rows keyed `T<N>` (for `pages` mode, `p<N>` is
linked under the renumbered page), and the baseline holds them: 43 pages, 0 worse on the old rows.
Self-test PASS (measured): Why p5 at 1.14.0 `tcolour` (elCol 0.00), Why pp5-6 at 24a8f6a `tink` (0.00, 0.38),
every green page green. On today's pipeline the element check alone reddens Why p10 (`tcolour`, the owner's
grey logo), Hyman p8 (`tink,tcolour`, C45's highlights), Why p2 (`tink` 0.23), Glazer p1 and Kristol p1
(`tcolour`); not looked at, so for `truth-read`. Left for `truth-harness`: the run over the 215 pages.

# truth-harness, the run, batch 1 (no model) — 2026-09-30

`ops/truth/run-harness.sh <W>` cut the 128 documents to their 215 truth pages, published them with the gate
at `832b7ac` (default settings, helper processes, 8 chunks, about 35 minutes) and scored each with
`ux-regression.sh --score-one`: the old measures and `--truth` on the same output. 0 crashes. `run-table.py`
wrote `TRUTH-RUN-2026-09-30-pages.tsv` and `-docs.tsv`. Classes, old measures against the truth (measured):

    route      pages  green  red  old-only  truth-only
    dct           13     10    0         0           3
    jbig2        107     49   27         6          25
    layered       55     31   11         4           9
    newspaper     11      1    7         0           3
    no-image      11     10    1         0           0
    other          5      4    0         0           1
    unknown       13     10    2         0           1
    all          215    115   48        10          42

Of the 42 truth-only pages, 35 fail on text alone (`tcopy`, copyErr 0.05-0.47), 3 on the element check alone
(`tink`: Why p2 in both copies, elInk 0.22 and 0.23; Ford 1941 p2, 0.08), 4 on both. The 10 old-only pages are
the old legibility proxy (6), find (2), selection and colour. Pooled: 115,714 words scored, 8,983 wrong, 2,772
missing, 85,744 added; 75,925 of the added are on the 11 pages whose added exceed their scored words (mostly
newspapers, with Raskin p1), whose column drags take in the next columns (`c52-column-jumps`'s class; not
looked at). Scored words missing from Vision's reading of the source 0.19, from the output's layer 0.076.
NOT YET, both need subagents (this session started at 89% of the window): the blind re-read of each page's
`score/d<N>/truth-words.tsv`, so a `tcopy` still counts unconfirmed words, and the judges on `score/d<N>/pairs/`,
with `pairs-key.tsv` kept from them. Run 1 stays in `$STATE/truth-run-2026-09-30/` (`jobs.txt` maps d<N>).
