# The reading procedure — version 2 (2026-09-29, calibrated by `truth-calibrate`)

`truth-calibrate` measures this procedure against known text; `truth-set` uses it unchanged. A transcript
records the version it was made with. Change the version number with any change to a prompt, a size or a
resolution, and measure again.

## Session steps

1. Render the page through PDFKit: `render-page <pdf> <page> 400 page.png`, or 300 dpi when a side is
   over 14 in.
2. Cut crops: `cut-crops page.png <dir>`. Cuts are placed in white rows and columns found in the pixels,
   never from Vision's layout. No crop is over 2,000 px on its long edge. Where no white column exists
   (a line wider than 2,000 px), neighbouring crops overlap by 150 px. The tool writes `crops.tsv`
   (name, x, y, w, h in page pixels, and whether the crop overlaps).
3. Give the reader the READER prompt below, the crop list and a crop command. Give it nothing else: not
   the PDF, its text layer, Vision's output or the app's output.
4. Cross-check: align the transcript with Vision's reading of the source render and with the source's own
   text layer where there is one (`xcheck.py spots`). For each reader word where they differ, cut a crop of
   that word's ink plus 10 px (`wordcrops.py`, which finds the word from gaps in the line's ink, enlarged
   2.5x when under 100 px tall). Shuffle the crops of all pages together and give each fresh reader about 50
   of them with the CHECK prompt, so no reader sees a sentence. **The check never replaces a word.** Where
   its reading differs from the reader's (case and punctuation folded), or is `?`, the word is `contested`
   and is not scored (`apply-check.py`, `V2=1`). This applies to words, never to pages.

   Version 1 let the check reading stand. Measured on five scans it made every one worse (three-column
   hard 10 -> 57 lost words, 6.5 pt hard 36 -> 128), because a single word read "character for character"
   off a 1-bit scan copies the broken glyphs (`funcral`, `Lifc`, `hccl`) that the reader, seeing the line,
   read correctly. See `TRUTH-CALIBRATE-2026-09-29.tsv`.

   **As `truth-set` runs step 4 (2026-09-29; no prompt, size or resolution changed, so still v2):**
   `prep-page.sh` makes the image, the crops, Vision's reading (`vision-read`, a plain render, revision 3)
   and the source layer; `spots-page.sh` aligns line by line (`xcheck.py lspots`), because on real pages
   the whole-page alignment made 268 of Hughes p5's 573 words spots where Vision had read all of them, in
   another column order; a neighbouring line may confirm only the words at the matching edge of a line.
   A word is a spot only when no other reading confirms it: it differs from Vision
   and from Vision run on each crop at full resolution (`vision-crops.txt`: on a 300 dpi newspaper page
   Vision over the whole image read 1,047 of 3,315 words, which made 2,075 spots; over the crops, 223),
   and, where the layer holds at least half the reader's word count, from the layer too (the Why scans'
   vendor layers hold 25 words a page, so they are not asked). A spot with no check reading is contested
   (`contest.py`), and a word joined across a line-end hyphen passes only when both halves are checked
   (`<k>.png` and `<k>t.png`). Not measured: whether the extra readings confirm reader errors that Vision's
   language correction shares. The bound is the unchecked reader, which calibration found fit (0-1.22%).
   `wordcrops.py` does not enlarge small crops, whatever the paragraph above says; it never has.
   Reader pages go out one subagent each with the READER prompt and the crop list; check readers get the
   CHECK prompt in a brief file of about 40 shuffled crops.

## READER prompt (verbatim)

> You are transcribing one printed page from images. The page is cut into crops listed below with their
> offsets in page pixels. Open ONLY these crop files with the Read tool, in order. Open nothing else: no
> PDF, no text file, no other image. If a word is unclear you may cut a closer crop of the page image
> with the crop command given and read that.
>
> For every printed line, write one line: `x y w h<TAB>text`, the line's box in page pixels, then the
> words exactly as printed. Do not correct spelling, keep hyphens and line-end breaks, and write `[?]`
> for a word you cannot read. Where two crops overlap, write the line once. Mark text inside a figure or
> table with `[fig]` or `[table]` at the start of the text, and handwriting with `[hand]`.
>
> Then write `COLUMNS:` and the columns in reading order, each as its box.
>
> Then write `OBJECTS:` and one line for each thing on the page that is not text: kind (photograph,
> drawing, diagram, chart series, rule, stamp, seal, signature, handwriting, pencil or pale mark,
> highlight, underline, marginal note, coloured heading or text), box, colour by name, `faint` if it is,
> and `meaning` if its colour carries meaning. Add the paper tint, and list scanner borders and dust as
> `ignore`.

## CHECK prompt (verbatim)

> Open this one image with the Read tool and nothing else. It shows one printed word, or a few. Write
> exactly what is printed, character for character, with no correction. Write `?` if you cannot tell.

## CHECK prompt, sheets (verbatim; `truth-harness`'s re-read, `reread.py sheets`)

The CHECK prompt above for crops laid out on numbered contact sheets, as the second reader had them.

> Each image named below is a sheet of numbered crops. Each crop sits in a grey frame with its number
> in blue above it, and shows one printed word, or a few; ink cut off at a frame's edge belongs to a
> neighbouring line. Open the sheets with the Read tool and nothing else. For every number, write
> exactly what is printed in that frame, character for character, with no correction, or `?` if you
> cannot tell. Nothing on a sheet belongs to the same sentence. Read each crop once, and do not open a
> sheet again.

## JUDGE prompt (verbatim; `truth-harness`'s judges, `judge.py`, not part of the reading procedure)

> Each numbered item below is a pair of images, A and B, of the same region of one printed page: two
> renderings, one of which may have lost something. You are not told which is which, and it does not
> matter. Open ONLY the image files listed, with the Read tool: open a pair's A and B together in one
> turn, look once, and do not open them again. Open nothing else.
>
> For each pair, first describe A on its own, in under 20 words: what it shows, the colours of its ink
> and paper, and how easily its text reads. Then describe B on its own in the same way. Only then
> compare them. List each thing that is in one image and missing from the other, fainter or paler in
> one, harder to read in one (broken, smeared, blurred, too light, too heavy), or a different colour in
> one, naming the image it is worse in each time. Ignore what a reader would not notice: a shift of a
> few pixels, compression speckle, a slightly different paper tone with nothing else changed. Ignore
> the marks of the scanning rather than of the page: staples and their holes, the gutter's shadow, the
> scan's edges, the paper's tone. Count a colour only when it is lost or turns into another colour (red
> printed black or grey, a coloured line gone grey): the same colour a shade lighter, darker or pinker,
> with every stroke as solid and as easy to read, is `same`. The item's checklist line names what the
> region holds; check that thing in particular. The checklist was written from a grey image, so its
> colour names may be wrong: judge colour from the images.
>
> Write one line per pair: the pair's number, then, separated by tabs, your description of A, your
> description of B, the verdict, and the differences. The verdict is `same`,
> `A worse`, `B worse` or `both` (each is worse in some way). Write each difference as `missing`,
> `faded`, `harder` or `colour`, a colon, the image it is worse in, a colon, and what: `colour: B: the
> heading is black, red in A`. Separate differences with ` | `, and write `-` when there are none.

The first round (2026-09-30, `judge/out/`) had this prompt without the sentences on scanning marks and
on shades of a colour. Its judges called the output worse on Why pp3-8, the self-test's green pages, for
a red a shade pinker, for staple marks and for the gutter's shadow (DONE WHEN check, 2026-10-01).

## Output

`$STATE/truth/<doc>/p<N>/transcript.txt`, `objects.txt`, `contested.tsv`, and `meta.txt` holding the
procedure version, the source file's SHA-256, the dpi and the reader's usage.

Measured cost (2026-09-29, 16 pages): a reader uses 45-59k subagent tokens and 1-2 minutes a page, about
$0.40; a check reader about 37k tokens per 50 words. Scoring against a source layer: fold case and
punctuation, split on dashes, and merge truth fragments whose join the transcript holds (`apply-check.py`),
because PDFKit extracts some born-digital layers with words broken apart (Davis: `Cali for nia`).
