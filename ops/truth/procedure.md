# The reading procedure — version 1 (2026-09-29, draft, not yet calibrated)

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
   text layer where there is one. For each word where they differ, and each line only one of them has, cut
   a tight crop (the word's box plus 10 px) and give a fresh reader the CHECK prompt. Its reading stands.
   `?` from it marks the word `contested`; contested words are not scored. This applies to words, never to
   pages.

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

## Output

`$STATE/truth/<doc>/p<N>/transcript.txt`, `objects.txt`, `contested.tsv`, and `meta.txt` holding the
procedure version, the source file's SHA-256, the dpi and the reader's usage.
