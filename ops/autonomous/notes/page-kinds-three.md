# page-kinds-three — round notes

## 2026-10-14 — pk-photo-pages (Opus 5.5, medium)

`PK-PHOTO-SAMPLE-2026-10-14.tsv`: 36 files in `$STATE/photo-sample/` (copies; the archive was only read).
Tags were read from the `_kMDItemUserTags` xattr over all 100,064 files (Spotlight's index held a third of
them: Clippings 368 of 1,140, Handwritten 0 of 286). Seeded draw, one per folder where the form allowed:
7 typed, 6 Clippings, 5 Statistics, 5 Handwritten, 2 Notes, 10 PDFs, plus Baker. 26 images carry camera
EXIF (iPad, iPad mini 2, one iPhone 11 HEIC); pk09 is PNG data under a .jpg name with none, a natural
stripped case. `stripped/` holds EXIF-stripped copies of all 26. Of the PDFs, 5 are photos with no EXIF
(FineReader-cropped) and 5 are scans kept as negatives (Image Access, flatbed, 1-bit Pdf-It, ScanSnap
S1500, and an SV600 overhead scan, which flattens like a phone-scanner app and should read as a scan).
The form tag often names the folder, not the page: of 5 Statistics, 1 is a table to look at; pk20 is blank.

Truth: one band of up to 4 lines a page, read by eye from full-resolution crops, then read again blind by
a second reader; 901 words on 30 pages, 21 contested (17 of them handwriting).
Not done: procedure v2's word-crop check step, which needs Vision's reading to
find spots; two blind readers stand in for it, a weaker check on handwriting.

## 2026-10-14 — pk-photo-detect (Opus 5.5, medium)

`Recogniser.isPhotograph(cameraExposed:image:)`: an image whose tags name a Make or Model and an exposure
(`Flattener.cameraExposed`; a scanner naming itself has no f-number) is a photo; anything else is judged
from five signals at 1,600 px (`photoSignals`): paper level <= 235, cast spread >= 4, border dark >= 0.05,
fall-off >= 0.06, and then noise >= 1 or border >= 0.1 or cast >= 10. Not yet called by the pipeline
(pk-settings wires it). `Tools/score-page-photo` over 217 pages (`PK-PHOTO-DETECT-2026-10-14.tsv`): 58
photographs, all called on pixels alone; 159 others, none. Measured, by running the production code.
- s62 (Riesman 1954, p16) relabelled photo: each page one ~2,600 px image at 370-480 nominal dpi, cropped
  by FineReader, curved lines, light falling off. As first labelled the criterion would fail on it.
- Thin: s04 (Why p9, a colour booklet scan) passes the four main cues and only the second test holds it
  out; pk26p1's cast is 4.2 against 4. Small sample; expect misses on pages unlike these.
- Rejected: Vision's document segmentation (no edge on 10 of 32 photos, an edge on 29 of 159 others);
  camera pixel sizes (FineReader's crop removes them; an iPad screenshot is 4:3); grid lighting spread
  without a paper mask (a halftone cell reads as shadow: xm43 0.996).
- Review (subagent, verified by running): a flat colour scan in a dark surround with a solid block read
  the block as paper in shadow and was called a photo; a paper cell must now sit within `paperShadow`
  (0.6) of the page's paper level, and fall-off is capped at 1. Calls on the 217 unchanged. Tests now pin
  each cue with a fixture that fails on it alone (three mutants checked red: border+second test, fall-off,
  paper level; the block fixture is a photo with the guard at 0). Verifier: criterion PASS with s62
  relabelled, FAIL as first labelled (s62 alone).
- For pk-settings: a phone-scanner app's JPEG that keeps the phone's EXIF is a photo by its tags alone.
