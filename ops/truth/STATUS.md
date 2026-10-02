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

# truth-harness, the run, batch 2 (re-read and judges) — 2026-10-01

Run 1's outputs (`$STATE/truth-run-2026-09-30/`, W, pipeline `832b7ac`) scored again with the re-read and the judges
in, into `$STATE/truth-run-2026-09-30-final/` (in/ and pub/ link to W; nothing published again). All measured.

RE-READ (`reread.py`). 3,753 of the 12,177 rows of `truth-words.tsv` read blind on a tight crop: every row on the 161
pages a re-read could flip (3,315), and on the 30 pages red on copy whatever it finds, 100 per class and every Find
row (438). 3,719 crops: 45 read one at a time, the rest on 135 contact sheets; 661 `nearest` crops that disagreed
cut again with a word either side (66 sheets). 3,304 confirmed (369 by the wide crop), 449 contested: 427 words on
59 pages, now in each page's `contested-harness.tsv` and not scored. 141 of the 427 read `?`; on General Foods
1958 p21 (48 words, looked at) the crops show the line above, because the reader's line box sits a line off, and
the harness drags from the same box, so those words cannot count either way. The 30 red pages' samples: 8% of
far, 14% of near, 8% of missing and 7% of Find rows contested; their 8,417 other rows (`unread`) were not re-read
and still count.
REJECTED: correcting the transcript in place, as the item says. A single word read off a crop copies broken glyphs
(procedure v2), so a disagreement contests the word instead, and it counts neither way.

JUDGES (`judge.py`). 1,067 pairs on the 215 pages: 408 byte-identical, 659 judged blind on 142 pages (41 more were
`ignore:` elements, now dropped, below). Round 1 (the prompt without the two sentences below): output same 416,
worse 205, better 30, both 8; 17 of 17 control pairs named the output worse (Why p5 at 1.14.0 for colour, Why pp5-6
at 24a8f6a harder). Five pages' pairs were split across 2-4 judges by hand (`brief-<i>a.txt`..).
C4 FAILED ON ROUND 1 (the DONE WHEN check): the judges called the output worse on all six of the self-test's green Why
pages, pp3-8, for a red a shade pinker or deeper (both ways, even on one page), staple marks and the gutter's shadow.
The JUDGE prompt now says a shade of the same colour is `same` and marks of the scanning are not content. ROUND 2 on
those pages and the controls (50 pairs, `judge/out2/brief-1..4.tsv`, measured): 17 of 17 controls still worse, for the
right reasons (headings black; text blurred to illegibility); on the green pages 15 worse, better or both became
`same` and 7 stayed worse, all real and alike: p3's pencil marks thinned or gone to specks, and the cartoons on pp4, 6
and 7 published blurred (j425 looked at: strokes thinner, paler and jagged). That is C28's loss, ink no word box
holds kept only in the low-resolution background, so the harness is right that pp3, 4, 6 and 7 are wrong; pp5 (both
copies) and p8 are now green on the judges.
ROUND 2 FOR THE REST, 2026-10-01 (measured): the other 221 non-`same` pairs on 60 pages (`judge/rejudge/brief-5..17`),
one judge each, every brief complete; round 1's `same` pairs were not judged again (11 of 11 stayed `same` above).
Against round 1 on those 221: of 190 `worse`, 163 stayed, 23 became `same`, 4 `better`; of 24 `better`, 8 stayed, 15
`same`, 1 `worse`; of 7 `both`, 3 `same`, 2 each `better` and `worse`. The 659 judged pairs now read same 472, worse
173, better 14 (408 identical); controls 17 of 17 `worse`. Six pages went truth-only to green (Findlay 1992 p47,
Countryman p218, Ibson pp245, 248, Allen 2011 p8, Robertson 1990 p50: scan rules, page edges, text weight), Luethy 1955
p2 old-only to red (output text near bold), and four red pages and the owner's Why p2 lost their judge failure. Text
weight is judged both ways (heavier is `worse` on Luethy p2, `better` on Allen p8), so look at a page failing on it
alone. The book copy's Why p2, the same scan, keeps its failure: its pencilled `(2)` is `worse` in both rounds (j140),
where the owner copy's judge called the same pixels `same` (j214).
JUDGE ERRORS, from each changed pair's ink and coloured-pixel shares (no model) and a look: round 2 made four right
verdicts wrong, all losses of ink or colour. `same`: Robin Stephens p24's blue JSTOR link published black (j2, an
18 px crop, 0 of 635 coloured pixels kept), Gitlin 2000 p1's rule faded to a trace (j25, 18 px, 16% of its ink), JAH
Review p2's link (j693, whole page); `better`: Morgan 1975 p2's link, the judge seeing the blue on the wrong side
(j582, whole page). The element check flags all four pages, and no class rests on those verdicts. It counts any pixel
of chroma over 60 as coloured, paper included, as the old colour measure does: Stanford 1891 p4's `tcolour` is its
cream paper published grey (the pencilled folio's box, 1,364 of 1,365 pixels coloured, holds no ink), though its
brown ink is published black too. Its `tink` on the owner's Why p2 is a pencilled `21`, legible and a little paler
(j212). A judge cannot know which image is the source, so an output that darkens a pale mark (UN-OCred p20's pencil)
gets `better`. The element check and the judges disagree on 27 pages, so `truth-read` reads both.
DONE WHEN CHECK, 2026-10-01: FAILED C1 (Copy), every other criterion passed. A loose line, and so every line of a
column of one or two lines, is scored by `selection(for:)` over the middle half of its transcript box (`rectText`),
so a line whose text or box sits a third of a line off selects nothing and its words all count missing: Wilson 1975
p1's 18 missing words are all in the output's layer (`layerMiss` 0.0000). The checker names Wilson 1975 p1, Leland
pp2 and 5, Delton p27, 1957 Employment p3 and Banks p202, each truth-only on text alone, and Kelly 2014 p3, whose
column-4 last-line box reaches 31 px into column 5, so that drag ends there (316 added words).
COPY FIXED, 2026-10-01 (measured). A loose line now takes the text over its box grown three quarters of a line up and
down, keeping each line of text whose nearest transcript box is its own (a drag along it took the next column across a
narrow gutter on Leland p5; a fixed band took the line above). A column drag stops at its column's edge only where its
end line's box reaches into a column box beside it: 3 of 499 drags (Kelly p3, Scott p7, Xin Qu p24). A first clamp at
every column edge moved 14 and cut centred headlines (Kristol 1960 p1, Williams 1958 p1); the code review found it.
Self-test PASS with three new cases on Hughes p2 (`truth-moved`, `-widened`, `-narrowed`), which the old harness fails
twice and the first clamp once. All 215 pages rescored with no model into `$STATE/truth-run-2026-09-30-final3`, 0
crashes: 412 fewer words missing, 265 fewer added, 1 more wrong; `tcopy` on 61 pages, not 70. Worse on three pages, all
red either way: Delton p2 (+8 added: its JSTOR boxes sit half a line above the ink and the text a quarter below, so line
37's text is nearer box 38), Scott p7 (+24: overlapping column boxes), Gowan and Demos p1 (+2: a stamp line the
transcript leaves out). Every counted row on a page red on text that a re-read could flip is still confirmed; Kelly
p3's 34 unread rows now sit on a page green on text. `ux-regression.sh --baseline`: 0 worse, 11 better, truth rows only.

FIXED IN THE HARNESS, after the diff review (each would have misled `truth-read`). Find searched a word's letters
alone, so `high-school` was sought as `highschool`: the final run's Find failures are run 1's less 168 such words and
51 contested ones (the second review's count). A word with punctuation inside it is now left out of the sample.
Contesting a word moved every later Find pick (98 new Find rows in a rescore, none re-read); the sample is now drawn
before the re-read's words come out, and every row the final run counts on the 161 pages is one the re-read
confirmed (2,770; 0 new). REJECTED: searching such a word with its punctuation, since which form a reader types is a
guess. A `contested-harness.tsv` row naming another word than the transcript's stops the harness (exit 2; self-test
`truth-stale`), and its rows split at any newline (CRLF). Objects marked `ignore:` were scored and paired. `judge.py
prep` refuses to renumber judged pairs. Left: `same()` accepts a neighbour in a multi-word reading (5 of 3,304
confirmations, the first review's count).

    route      pages  green  red  old-only  truth-only   text  other  judge   (Copy fixed; judges' round 2)
    dct           13     10    0         0           3      1      2      3
    jbig2        107     57   25         8          17     34      9     15
    layered       55     23   14         1          17     12      8     24
    newspaper     11      1    7         0           3     10      1      1
    no-image      11     10    1         0           0      1      1      1
    other          5      4    0         0           1      1      0      0
    unknown       13     11    2         0           0      2      0      0
    all          215    116   49         9          41     61     21     44

Against run 1: 9 pages left `text`, 7 `tcopy` and General Foods p21 (`tcopy,tfind`) by the re-read and Lloyd-Jones
1938 p18 (`tfind`) mostly by the Find fix; ___ 2 p1 lost `tfind` and keeps `tcopy`. With Copy fixed, Wilson 1975
p1, Delton p27, Leland pp2 and 5, Anaconda 1958 p9, Banks p202 and 1957 Employment p3 went truth-only to green. Of
the 41 truth-only pages, 18 fail on text alone, 13 on the judges alone, 1 on the element check alone (Why p2), 9 on
more than one. `TRUTH-RUN-2026-09-30-pages.tsv` and `-docs.tsv` carry the re-read and judge columns.
`ux-regression.sh --baseline`: only truth rows moved, 24 better (22 Find, Delton p2's copyErr, ___ 2 p1's flags) and
2 worse, both Xin Qu p24, an artefact of the smaller population: copyErr is over 1 there (1.32 -> 1.39), so leaving
out a wrong word raises it, and layerMiss rose (0.26 -> 0.30) because contested words the layer held left the count.
Self-test PASS (twice, the second on the final Swift).

DONE WHEN RE-CHECK, 2026-10-01 (ninth session): FAILED C1 again, C2-C8 passed. The pages the last check named are
right, and the Copy fix made no page falsely green (loose lines: the harness credits 2,009 of 2,273 words, the best of
a reader's three drags 2,057; more than the reader on 22 lines, 51 words, all on pages red anyway). But a drag from a
box's end that sits off its ink begins or ends where PDFKit finds the nearest character, on another line: Delton p2
(0.0965) and Cooley 2008 p94 (0.0551) were red for the harness's sake alone. Caveats with the passes: 30 red pages
hold 8,203 rows never re-read, none of which could turn one green (C4); the A/B order is a hash of page and element,
so every whole-page pair of a cut page 1 shows the output as B, which no one judge sees (C5).
INK ANCHORS, 2026-10-01 (measured). Each column drag is made twice, from the boxes' ends and from their ink's in the
output's 2x render (0.3 pt left of the first glyph, 0.3 pt inside the last), and the one nearer the transcript kept, the
boxes' on a tie; a loose line keeps the text lines nearest its ink, not its box. A census on run 1's outputs first
(`$STATE/truth-run-2026-09-30-final3/census-dragends/`, harness code extracted unchanged). REJECTED, measured: ink
anchors alone (Canby 1915 p1's drop capital puts the ink below the text, `ot` for `Not`; one inside the first glyph
began after it, NAYLOR p67 green to red), and ends 0.15 of a line or 0.5 pt outside the ink (Boltanski 2006 p102 0.0368
-> 0.5074, the drag ran on into later text). After the diff review, REJECTED: breaking a loose line's tie by its box
(Hughes p2 with boxes 24 px high: 12 missing and 8 added, against 5 missing untied; the comment states the blind spot).
All 215 pages rescored into `$STATE/truth-run-2026-09-30-final4`, 0 crashes: 49 pages moved, Copy columns only; missing
2,165 -> 2,014, added 85,479 -> 85,178, wrong 8,774 -> 8,711. Red to green on the truth: Delton p2 0.0965 -> 0.0029,
Cooley p94 0.0551 -> 0.0175, Briefer p2 0.0719 -> 0.0344, 1979 Ideology p8 0.0667 -> 0.0409; none to red. Every counted
row on a page a re-read could flip is confirmed. Self-test PASS with a case `raised` (boxes 0.45 of a line high), which
the old harness fails (Hughes p2 607/7/10/0 -> 559/7/58/8); Briefer p2 is green in it now (its layer lacks 3.1% of its
words, as p6's lacks 3.4%), and pp1, 3, 4 stay red.

    route      pages  green  red  old-only  truth-only   text  other  judge   (ink anchors; judges' round 2)
    dct           13     10    0         0           3      1      2      3
    jbig2        107     60   24         9          14     30      9     15
    layered       55     23   14         1          17     12      8     24
    newspaper     11      1    7         0           3     10      1      1
    no-image      11     10    1         0           0      1      1      1
    other          5      4    0         0           1      1      0      0
    unknown       13     11    2         0           0      2      0      0
    all          215    119   48        10          38     57     21     44

DONE WHEN RE-CHECK ON final4, 2026-10-01: FAILED C1 narrowly, C2-C8 passed. The four pages above are what a reader's
drag gets, no page went falsely green, and the 49 changed rows reproduce. Two truth-only pages are still red for the
harness's sake, by one glyph at a drag's end: CAMFIELD p1 (0.0508; both drags begin inside the `T` of `This` and copy
`his`, since the ink's start is taken from the middle of the letter height, where a T's first ink is its stem; a
reader's copy scores 0.0339) and Banks 2006 p101 (0.0559; a raised `40` beginning column 2 copies `0`, and column 1's
last `of` copies `o`, the drag ending 0.3 pt inside the f's stem; a reader's 0.0497). NEXT: take the ink's ends over
the line's full height, or add a third drag just outside both ends to those compared (an end past the last glyph ran on
at Boltanski p102, so it must stay one candidate of three, not replace one); rescore; the DONE WHEN check again.
The `unread` column still counts run 1's selection (8,424), where final4's unconfirmed rows are 8,109 (C4's note).
The diff review found the tie-break flaw above and nits; its result-changing fixes were reverted (the tie-break did
worse), so final4 is this code's run: the committed Swift differs from `final4/h/main.swift` by comments and a guard
against non-finite boxes only (checked by `diff`, by me, not by a second reviewer: the window was past 85%).
`Tools/ux-regression.sh --baseline` (measured): truth rows only, 4 better (Delton p2 0.0965 -> 0.0029 and its `tcopy`,
Xin Qu p24 1.39 -> 1.06, Riesman 1949 p2 figure text 9/45 -> 12/45) and 1 worse, accepted: `___ 2` p1's welds 1 -> 2, the
drag kept there having fewer errors in all; the page is red on copy either way. Baseline refreshed.

FULL-HEIGHT INK, 2026-10-01 (tenth session, measured). A third column drag, from the ink's ends over the line's full
height (ascenders and raised figures in, `yMid` still the core's), joins the boxes' and the core ink's; the fewest errors
wins, ties to box then core. REJECTED: replacing the core's ends, since a drop capital or a touching rule widens the full
height's (Canby p1, the Boltanski run-on). All 215 pages rescored into `$STATE/truth-run-2026-09-30-final5`, 0 crashes:
15 pages moved, all better, wrong 18 fewer, missing and added unchanged. CAMFIELD p1 0.0508 -> 0.0339 and Banks 2006
p101 0.0559 -> 0.0497, each what a reader's own drag scores, truth-only -> green; no other class moved. Self-test PASS
with `truth-tstem` and `truth-raised-figure` (run 1's outputs, both `tcopy` under the old harness). `ux-regression.sh
--baseline`: 0 worse, 0 better, baseline not rewritten.

    route      pages  green  red  old-only  truth-only   text  other  judge   (full-height ink; judges' round 2)
    dct           13     10    0         0           3      1      2      3
    jbig2        107     62   24         9          12     28      9     15
    layered       55     23   14         1          17     12      8     24
    newspaper     11      1    7         0           3     10      1      1
    no-image      11     10    1         0           0      1      1      1
    other          5      4    0         0           1      1      0      0
    unknown       13     11    2         0           0      2      0      0
    all          215    121   48        10          36     55     21     44
DONE WHEN RE-CHECK ON final5, 2026-10-01: every criterion passed (C1 measured: CAMFIELD p1 and Banks p101 copy what the
checker's own drags copy, 0.5-4 pt outside the boxes; the 15 changed rows are 1-3 words wrong -> right each). For
`truth-read`: Banks p101 is green at 0.0497 with 14 words lost from the layer (the footnote's last line and a half
cannot be copied; dragging `Columbia ...` returns the line above), just under the 0.05 threshold.
`truth-harness` TICKED.
