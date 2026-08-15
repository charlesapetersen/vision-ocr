# Changelog

Notable changes, newest first. Dates are release dates.

This project keeps its defect history in [BUGS.md](BUGS.md) with the evidence for
each fix; entries below cite those identifiers rather than repeating the
measurements.

**The app was called Vision Reader GUI until 1.1.0.** Entries below that version
use the old name, and deliberately have not been rewritten — a changelog that
edits its own history is worth less than one that reads slightly awkwardly. Where
an older entry mentions "Window ▸ Vision Reader Window", the menu item is now
"Window ▸ Vision OCR Window"; nothing else moved.

## 1.12.0 — 2026-08-13

**A 568-page scan went in at 31 MB and came out at 437 MB. It now comes out at
35 MB — 1.13x its original — with a byte-identical text layer.**

```
                        in      1.11.0 out    1.12.0 out
Blacks in the City    31 MB        437 MB         35 MB
                                   (14.0x)        (1.13x)
text layer                    1,458,486 B    1,458,486 B — identical
pages layered                            0     548 of 568
```

Two fixes, and the second is the one that closed the gap. **`BUGS.md` R49**: colour
pages were the one kind that could not be stored in layers, so a file the app read
as coloured throughout kept every page as a full-resolution three-channel JPEG.
**R50**: even layered, the file was still 2.17x its original, and the whole excess
was the two tone layers — the 1-bit stencil that carries the text already matched
the Internet Archive's own scan of the same book to within 2%, while our tone layers
cost **40.7 MB against their 4.3**.

**Pages whose ink is all text now shrink their tone layers, automatically.** There is
no new setting and nothing to choose: a page with no picture on it has nothing in its
background worth full resolution, and the app can now tell, because layering happens
*after* recognition and ink that falls outside every recognised word is not text.
Text pages drop from 60 KB of tone layers to 7.5 KB; pages carrying pictures are left
exactly as they were.

On the 232-document gate: **721 MB against 792 at 1.11.0**, 232 of 232 succeeded,
characters unmoved, and **209 of the 232 documents byte-for-byte unchanged with not
one larger.** Every photograph-heavy document in it is identical — `Picturing men`,
`America by design`, `Boltanski`, `Findlay`, `Ehrenreich` — while the low-contrast
typescripts that the picture detector misroutes came down hard: a 1941 speech to a
fifth of its size, `Riesman 1954` from 7.3 MB to 2.0.

Layering keeps the page's colour and keeps its text at full resolution in the 1-bit
stencil, and it is still taken only when it is measurably smaller — 20 of the 568
pages declined it and kept the JPEG they had. On the book, 522 pages now carry
shrunk tone layers and 8 — the photogravure plates — carry them at full resolution,
decided per page and without being asked.

**What this does not fix.** The reason those pages were called coloured at all is
that the scan is exposed low: its paper renders at luminance 148 with a grey-green
cast and never reaches the threshold the paper detector uses, so the white-balance
correction that exists for tinted stock never runs. That detector is unchanged,
deliberately — R49 records the fix built for it, measured, and refused, because a
page of text and a tinted plate with a subject on it are the same luminance
histogram. The file is now smaller than it would be if the detector were right, so
the defect costs bytes rather than mattering.

Colour layering costs about 2.5x the time of grey layering per page for about 15%
more bytes than grey.

**Also fixed**, both reported by the user and both in the settings panel: the entire
updates block appeared **twice** (`U29`) — 36 identical lines, harmless because both
copies bound the same state, which is why it survived — and the **Start from** preset
buttons gave no sign they had done anything (`U30`). They now say what changed
("Newspaper applied — changed Photo detail, Uncertain text"), announce it to
VoiceOver rather than hiding it in a mouse-only tooltip, and say so plainly when a
preset changed nothing. They still do not stay clicked, which is deliberate and now
has a test holding it.

The suite gained the check that would have caught `U29` and did not exist: no two
controls in a view may carry the same name.

**Known, not fixed, and not new in this release.** Two ways Automatic can route a
page wrongly were found while measuring something else, and both destroy what is on
it. `BUGS.md` R56: a **pale drawing** — faded ink, light pencil, a wash — can be too
light to count as ink and too light to count as continuous tone, in which case the
page is treated as text and the drawing is rendered as blank paper. `BUGS.md` R57: a
**continuous-tone plate covering roughly a fifth of a page** can miss both routing
thresholds at once and come out as a solid black area. Both are present in 1.11.0 and
earlier; neither is caused by anything in this release. **If a document matters and
carries pale artwork, compare the output against the original**, or use Grayscale,
which routes nothing to 1-bit and cannot do either of these things. A luminance test
for the first was built and refused on measurement — the entries carry the numbers
and what a real fix needs.

## 1.11.0 — 2026-08-13

**The batch speed is back, and then some.** The 232-document release gate:

```
                     1.10.1    1.11.0 before    1.11.0 shipped
                   (baseline)   the R40 fix
documents / ok        232/232       232/232         232/232
characters         34,148,681    34,204,971      34,204,948
output               792 MB        792 MB          792 MB
minutes                  75           187              48
```

48 minutes against a 75-minute baseline, and against the 187 that held this
release back — measured on a machine that was *not* idle, so it is a floor rather
than a best case. Recognition now runs in a small helper program of Vision OCR's
own, one per file being processed; `BUGS.md` R40 has the reasoning and the
measurements behind every choice in it.

*The 23-character difference is recorded rather than explained* — 1 part in 1.5
million, with every direct comparison of the two routes exact to the last digit.
R46 has what was checked and what the gate now records so the next one can be
localised.

**Nothing to install, and nothing bundled to go stale.** Vision OCR used to carry
a copy of a command-line program called mac-ocr inside it to do the recognition —
2.4 MB of someone else's binary, which earlier versions asked you to install
yourself in a Terminal. It now calls Apple's Vision framework directly. If you
installed anything for an older version, you can remove it.

This is mostly invisible, and deliberately so: **the recognised text is the same
text.** Both routes were run over 52 documents and 4,140 pages before the change
was made — 9,211,704 characters against 9,254,956, a difference of +0.47% in
favour of the new one.

*(An earlier draft of this entry also said speed was unchanged, "within a couple
of seconds on a 62-page book". That was measured on one document at a time, which
is the one arrangement where the difference cannot show up. Recognising a **batch**
did get slower, by a lot, and the paragraph at the end of this entry is what came
of finding out.)*

What it fixes, and why it was worth doing:

- **A very large sheet no longer needs a special case.** 1.10.1 fixed a
  safeguard that kept pages inside a 200-megapixel limit. That limit belonged to
  the program that has just been removed, not to Vision — which reads a
  216-megapixel page without complaint. The safeguard and the arithmetic behind
  it are gone.
- **The page that is read is now exactly the page that is written.** The app used
  to render each page, save it into a PDF, and hand that PDF to another program,
  which rendered it *again* at a resolution of its own choosing. That round trip
  was the cause of the 1.10.1 bug. It no longer happens.
- **A photograph that says it is sideways is now read as sideways.** Image files
  carry a rotation flag that was being ignored when extracting text; the text came
  out right but the word positions did not.
- **Language detection works as intended again** when you have not named a
  language, which is the default.

Under the hood this removed about 500 lines whose only purpose was talking to
another program, and the settings panel loses its "mac-ocr path" field — there is
no path to get wrong.

**One cost, found and fixed before release rather than after.** Recognising
a large batch got slower — Vision hands one request most of the machine and makes
concurrent requests wait, where the old arrangement ran a separate program per
file. A 232-document run went from 75 minutes to 187. Single documents were never
affected.

The fix keeps everything above and gets the speed back: **Vision OCR now runs
recognition in a small helper program of its own, one per file being processed.**
It is not the old dependency returning. It is ours, it ships inside the app with
nothing to install, and it is handed page images this app has already drawn —
never a PDF for something else to re-render, which is what caused the bug 1.10.1
had to fix. If it is ever missing or goes wrong, the app simply recognises the
document itself and says so in the log; nothing fails and nothing is lost.

Measured before it was built: the same twelve page images take 14.0 seconds in one
process and 6.3 seconds across six. Inside one process, six at a time saves 8%.



**A very large sheet could fail instead of being read.** Vision refuses to render
a page above 200 megapixels, so this app works out the highest resolution each
document can be recognised at and asks for that instead of letting the whole file
fail. On Automatic that safeguard could not do its job: it was comparing against
the wrong number, and a page whose safe limit landed between 300 DPI and its own
resolution was handed over unprotected. A 20 × 30 inch sheet scanned at 600 DPI
came back as an error rather than as text. Now fixed (BUGS.md R39).

Nothing else changes. No document in the 232-item test library is affected — the
safeguard only speaks up for sheets far larger than a book page — so the output
of every file this app has processed is exactly as it was.

**And a correction to 1.10.0's release note**, which suggested setting Page DPI
to 300 for very high-resolution scans. Measured properly afterwards, over 52
documents and 4,140 pages: **Automatic recovers more text than any fixed value**,
and 300 makes more than half of those documents worse. The note is struck through
below. Leave Page DPI on Automatic.

## 1.10.0 — 2026-08-12

**Files that used to come out bigger now come out smaller.** Some scans grew when
this app processed them — one book went from 16 MB to 156 MB, more than nine
times its original size, and it was not alone. Across the whole 232-document test
library the output was 1,039 MB against 1,198 MB going in; it is now **792 MB**.
The pages this affects lose no detail — they were checked at full size, and
several read more crisply than before.

**One honest caveat, found straight after release and written up as BUGS.md
R39.** Across the whole library the recognised text changed by −0.05%, and most
documents gained. But one book lost 2.7% of its text, concentrated on about a
dozen pages, and the cause is not the change above: on some high-resolution
scans Vision recovers less text than it would at a lower rendering resolution,
and Automatic leaves that choice to the recogniser. The pages that moved to
black-and-white met that behaviour more often than they used to.

~~If you are processing very high-resolution scans and want the old behaviour
for now, set **Settings ▸ Recognition ▸ Page DPI** to 300 explicitly rather than
leaving it on Automatic.~~ **That advice was withdrawn in 1.10.1 and it was
wrong on average.** Measured afterwards over 52 documents and 4,140 pages,
Automatic recovers *more* text than any fixed value — 300 costs 0.17% overall
and makes 26 of 52 documents worse, and the gap is widest on exactly the
high-resolution scans the advice was aimed at. Setting 300 helps a particular
document here and there and hurts more of them than it helps; leave it on
Automatic unless you have measured your own material.

The cause was a page of dense small type being mistaken for a photograph. The app
decides per page whether to store it as sharp black-and-white or as a photographic
image, and one of the three things it looks at is how much ink is on the page. A
broadsheet of eight-point classifieds, or a book of close-set footnotes, is a
great deal of ink — so those pages were being given a photographic layer on top of
the black-and-white one, carrying nothing the sharp version did not already have.
Heavy ink now has to be corroborated by actual photographic tone before a page
takes that route (BUGS.md R38). Real pictures are unaffected: they were checked
page by page at full size, and the two riskiest — a newspaper comic strip and a
dense title spread — are clean.

**A written record of every batch.** The results pane has always shown what
happened to each file, and always lost it when the window closed. Vision OCR now
writes a report for each finished run to `~/Library/Logs/VisionOCR`: every input,
where its output went, what happened to it, the settings that produced it and how
long it took. For an overnight run over material that may not be re-scannable,
that is the difference between "something failed last night" and knowing which
document and why. On by default, with a **Show Reports** button under
**Settings ▸ Behaviour**. Your password is never written into it.

**Retry just the files that failed.** A run that leaves four failures out of
seventy-eight used to mean finding those four and dragging them in again. The
results pane now offers **Retry N Failed**, which narrows the list to exactly
those files and runs them. The previous run's record is safe in its report.

**The language list now comes from your Mac.** The Languages field took BCP-47
codes typed from memory, and a code your Mac does not recognise does not quietly
do nothing — it fails *every file in the batch*. There is now an **Add** menu
listing the languages this Mac actually supports, by name, and a warning under
the field naming any code that will fail before you start the run.

This matters most for one combination nothing warned about: **"Fast" supports far
fewer languages than the normal recogniser** — six against thirty on macOS 26.6.
Turning it on with Japanese, Russian, Chinese, Korean, Arabic or twenty others
selected turned a working setup into a run where nothing succeeded, with no
indication why. It says so now, the moment you tick the box.

## 1.9.0 — 2026-08-11

**Words broken across a line can be searched for.** A word split by a line break
is read as two pieces — *merito-* at the end of one line and *cracy* at the start
of the next — so searching the finished PDF for *meritocracy* found nothing. In
narrow columns that is a lot of words, and they tend to be the long, specific
ones actually worth searching for.

The whole word is now also written into the first line, so a search finds it. The
cost is that the second half appears twice if you copy the text out; nothing is
removed either way. On by default, and switchable under **Settings ▸ Searchable
PDF ▸ Find words broken across two lines**.

It is careful about what counts as a break. An upper-case continuation is left
alone, so *Smith-* / *Jones* stays two names. A figure after the hyphen is left
alone, so *pages 3-* / *7* stays a range. And the continuation has to be in the
same column: joining by vertical position alone welded words to fragments of
unrelated ones on two-column pages, which is worse than the hyphen it replaced.

What it cannot do is tell a broken word from a real compound, so *self-* /
*criticism* becomes *selfcriticism* in the first line. Both halves remain
searchable on their own, and telling the two cases apart needs a dictionary this
app does not have.

**Words broken across a page break are joined too.** A word split at the foot of
one page and continued at the top of the next is now found the same way. This
took two attempts, and the first one is worth recording: it joined nothing and
that was read as the case being rare. It is not — measured across 45 documents
and 1,225 pages, **29 pages, 2.37%, end on a hyphenated line**. The code was
offering the next page's topmost line as the only continuation, and the topmost
thing on a page is the page number or the running head. It now offers the first
few lines and looks past the furniture.

Words broken across a *column* break are deliberately left alone. Joining those
needs to know where the columns are, which this app does not, and the attempt
welded real words to fragments of unrelated ones.

Measured over eight documents with 353 joins firing — 342 within a page, 11
across one: line-start and line-end selectability, text offset, vertical overlap
and word retention all unchanged.

**A copy that comes out larger than the original now says so.** It is uncommon
and it is not a fault, but it was silent, which made it look like one. Across 40
test documents this app is 1.79x smaller overall — 134 MB in, 75 MB out — but 15
of the 40 grew, all of them small files to begin with.

The reason, chased down rather than guessed: those originals were compressed with
*symbol-mode* JBIG2, which reuses one picture of a letter everywhere that letter
appears. It is dramatically smaller — 17 KB against our 95 KB on one page — and
it is the technique behind the photocopiers that silently changed digits in
scanned documents. This app will not use it on your archives. Everything else
was ruled out first: the text layer is a twelfth of the file, nothing is
rendered at a higher resolution than the original, and our black-and-white page
carries the same amount of ink as theirs to three decimal places.

So the finished run now tells you, with both sizes and the reason, rather than
leaving you to notice.

## 1.8.0 — 2026-08-11

**A scanned book that came out twenty-one times larger than it went in now comes
out smaller than it went in.** A 600-page 1964 monograph arrived as 33 MB and
this app turned it into 709 MB. Every page of it was plain text, and every page
was being written as a full-resolution colour photograph.

The cause was the paper. Cream book stock has real colour in it — measured
across that book, a saturation of 0.078 to 0.089 against a threshold of 0.06 —
so the "is there colour on this page?" test said yes on every page, while the
two tests that ask whether a page is text said, clearly and correctly, that it
was. Worse, that one number was charged twice: it took each page off the
black-and-white route *and* gave it three colour channels instead of one.

Colour is now measured against the page's own paper rather than against grey.
Cream paper reads as no colour at all; a coloured illustration on that same
cream page still reads as colour, because it was never the paper's colour. The
book above now comes out at 28 MB. Nothing about genuinely coloured pages
changed — one page in the test corpus moved *to* colour, correctly, because it
carries handwritten blue-ink corrections that the yellowed paper had been
masking. See BUGS.md R33.

**Pages with photographs on them are now stored in layers, and are three to five
times smaller.** A page that mixes text with a picture used to be written as one
big JPEG, which is the wrong shape for it: the text wants to be sharp and the
picture wants to be smooth, and one image cannot be both. Such a page is now
stored as three — the text as a full-resolution stencil, the picture behind it,
and the ink colour — which is how library and commercial scanning software has
done it for years.

Text on those pages is *sharper* than before, not softer, because it no longer
goes through a photographic compressor. Measured over the test corpus: 40 MB of
picture pages down to 8 MB.

**New setting: Photo detail.** Because the trade this makes is real, it is a
choice rather than something done to your files quietly. Under Searchable PDF ▸
Photo detail:

- **Maximum** — photographs keep every pixel.
- **Balanced** *(default)* — photographs keep half their resolution, which on a
  printed halftone is very hard to tell from the original, at about a third the
  size.
- **Smallest files** — a third of their resolution, noticeably soft up close, at
  about a fifth the size.

**Text is stored at full resolution whichever you choose.** This setting only
ever affects pictures, and nothing is cropped or dropped at any level.

Also in this release: JPEG 2000 was investigated as a replacement for the
picture-page codec and rejected on measurement — Apple's encoder targets a fixed
compression ratio rather than a quality level, so 88–98% of pages came out worse
than they do today. The reasoning and the numbers are in BUGS.md R34, along with
the measurement error that made it look promising at first.

## 1.7.0 — 2026-08-10

**Colour pages stay in colour.** Automatic previously answered "grey" for a
colour plate — it could see the colour, since saturation is one of the three
signals that route a page away from black-and-white, and then discarded it. Such
pages now keep their colour, bounded by a measured memory limit
(`maximumColourPageMegapixels`) above which they rebuild grey as before.

*This entry was reconstructed on 2026-08-11 from HANDOFF.md and the register: the
release was tagged and shipped without a changelog entry, and a gap is worse than
a late entry.*

## 1.6.0 — 2026-08-09

**You can watch a batch happen now.** Each file in the list carries its own
state: a dotted circle while it waits, a spinner while it works — with the stage
underneath, *"Rebuilding page 29 of 372"* — a green tick when it lands, a red
triangle if it fails. The count above the list keeps score: *"78 files · 12
done, 3 running"*.

Most of that was already being measured and simply never shown. The model has
tracked a per-file stage all along; nothing displayed it. Until now a long batch
told you nothing about the files already finished, or which of them failed,
until the whole thing was over.

Four shapes rather than four colours, because colour alone is not available to
everyone, and each row reads its state to VoiceOver — *"…, in progress,
Rebuilding page 29 of 372"*.

**The app can now tell you when there is a new version.** Once a day it asks
GitHub whether one exists and, if so, shows a banner with *What's New* and
*Download*. It does not install anything by itself: replacing a running app
bundle properly is Sparkle's job, Sparkle wants a signing identity this app does
not have, and an app that silently replaced itself would drop you back into the
Gatekeeper dialog with no warning.

**This is the app's first network request, and the README has been corrected
rather than left to mislead.** It used to say the app had "no network code in it
at all". That is no longer true. What remains true, and is the part that
matters: your documents, their names and their contents never leave your Mac.
The update check sends no identifiers and no usage data, and
**Settings ▸ Behaviour ▸ Check for new versions** turns it off completely.

Also fixed: `run_tests.sh` compiled a hand-written list of source files while
`build.sh` globbed, so a new file could compile into the app and not into the
suite — the checks would have gone green over code they had never seen. It globs
now.

527 checks, up from 501.

## 1.5.1 — 2026-08-09

**A licence that should have been in 1.5.0.** The disk image bundles leptonica,
2.2 MB of BSD-2-Clause code, and shipped it with no copyright notice — the
licence copier counted *packages it had looked at* rather than notices it had
written, so the reassuring "licences for 12 package(s)" was structurally
incapable of noticing. All twelve are now covered, leptonica's text is carried
verbatim, and a package without a notice stops the build.

**The first-launch instructions were wrong** (U22). Every release since this repo
went public told people to Control-click the app and choose Open. **macOS 15
removed that**, so on any current version the dialog offers only *Move to Trash*
and *Done* — the one instruction between a new user and a working app named a
button that does not exist. The README now describes the route that works:
System Settings ▸ Privacy & Security ▸ **Open Anyway**.

**Three build defects that could have shipped a broken app.** A failed bundling
audit left the rejected binaries in place while the build printed "not bundled"
and signed them — and since the app prefers its bundled copy over Homebrew, it
would have used them. A failed disk-image verification could lose the diagnostic
explaining why, and leave the rejected image on disk. Both fixed, plus a mount
leak found by grep afterwards.

None of this changes what the app does. It changes what can go wrong between the
source and your Mac.

**And three controls, because the honest answer to "why do fixes keep producing
bugs" is that three of the four causes had no mechanical check.**
`Tools/fault-inject.sh` breaks things on purpose — a no-op `install_name_tool`, a
failing `hdiutil detach` — and asserts the build notices; it was written before
the fixes so it could be watched catching them. `Tools/mutate.py` was repaired:
its "matched exactly once" guard was vacuous, and its first act afterwards was to
reveal that a bound it claimed to cover had never been perturbed. And
CONTRIBUTING now requires a sibling sweep before closing anything, which
immediately found a defect the nine-finding review had missed.

Second mutation campaign: 27 mutants, 25 killed, two survivors, both documented
as correct.

478 checks, up from 473.

## 1.5.0 — 2026-08-09

**Compression is included now too, so there is nothing left to install.** 1.4.0
put the recognition engine inside the app; this puts the tools that make the
output small in as well. Searchable PDFs come out about a third the size, with
no Homebrew, no Terminal, nothing.

Harder than bundling the engine, and worth writing down why. `mac-ocr` links
nothing but system frameworks, so it could simply be copied. `jbig2` pulls in
leptonica and its image codecs; `qpdf` pulls in libqpdf and OpenSSL. Copying the
executables alone yields binaries that die at launch looking for
`/opt/homebrew/…`, on precisely the machines that do not have it.
`Tools/bundle-libs.py` walks the dependency closure — 15 files, 13.7 MB — copies
it into `Contents/Resources/lib`, and rewrites every install name to
`@loader_path`. It refuses to finish if anything still points at Homebrew or at
an unrewritten `@rpath`, and it strips any `LC_RPATH` into Homebrew so the
bundle cannot behave one way on the machine that built it and another
everywhere else.

**Apple Silicon only, deliberately and safely.** Homebrew builds for the machine
it is on, so an image built on Apple Silicon carries arm64-only copies of these
two. `isExecutableFile` cannot tell — it says yes to an arm64 binary on an Intel
Mac, which then dies at `exec` with a message nobody can act on. So
`Runner.containsNativeSlice` reads the Mach-O header, and on an Intel Mac the
bundled copies are simply invisible: the search falls through to Homebrew
exactly as before, and without it the app writes Flate-compressed pages that
work identically and are about three times the size. An Intel user is no worse
off than in 1.4.0.

Licences for all twelve bundled packages travel in
`Contents/Resources/third-party-licences` — MIT, Apache-2.0, BSD and 0BSD
throughout. jbig2enc's `PATENTS` notice is copied verbatim rather than
summarised: JBIG2 is a published ISO standard whose encoder records that its
methods may be patented in some countries.

The disk image is 8.3 MB, up from 2.1 MB.

473 checks, up from 468.

## 1.4.0 — 2026-08-09

**There is no Terminal step any more.** The recognition engine ships inside the
app. Download, drag to Applications, open — that is the whole of it.

Until now the README asked a non-technical reader to install Homebrew, then
Node, then an npm package before the app would do anything at all, which was the
single largest barrier to using it. `mac-ocr` turns out to be a 2.4 MB universal
Mach-O linking nothing but system frameworks — verified by running it under
`env -i` with Homebrew and node off `PATH` — so it simply travels with the app.
MIT, Copyright (c) Hiroki Osame; the licence ships beside it and the README
credits it.

The engine is resolved in this order: the explicit Settings path, the bundled
copy, the Homebrew prefixes, then a login shell. **The bundled copy sits above
Homebrew on purpose** — it is the version this release's corpus figures were
measured against. Anyone who wants a different one can point Settings at it, and
an existing Homebrew install is left alone.

`build.sh --dmg` now refuses to package without the engine, and then proves the
claim rather than asserting it: it mounts the finished image and runs the engine
out of it with an empty environment. A build that cannot do that fails.

*Choosing this over calling Vision directly was the point.* Direct Vision would
delete most of the subprocess code and the whole bug class behind seven register
entries — but it changes the recogniser, which would invalidate all 232
documents' measurements. Bundling removed the barrier without touching a single
number. FEATURES.md records the reasoning.

**Optional extras stay optional.** JBIG2 compression still wants `jbig2enc` and
`qpdf`; without them the app writes slightly larger files and says nothing else
about it.

Also: `Tools/mutate.py`, which puts a defect back mechanically and checks that
something goes red. Nine checks in this project's history could not fail, and
every one was found by hand.

453 checks, up from 449. The disk image is 2.1 MB, up from 964 KB.

## 1.3.0 — 2026-08-09

**A second review, run against 1.2.0 minutes after it shipped, found seven more
defects — five of them in the code and tests written to fix the previous
eleven.** That is this project's oldest recorded pattern and it has now happened
twice in one evening. All five register entries are closed.

**The test corpus nearly tripled, and the numbers held.** It was 84 documents
drawn from the previous five years of a Zotero library; it is now **232**, drawn
from the whole of it, with 79% of the new material older than that window and
reaching back to 2013. The scanned-only gate rejected 429 born-digital, 40
photographed and 4 with no page image to find them. Across the new documents:
148/148 process, median 100% line-start, line-end and word retention — within
0.05 of the material the app was calibrated on. The figures describe the app,
not the sample. See [CORPUS-2026-08-09.md](CORPUS-2026-08-09.md).

That corpus is also what made **C22** findable, and it is the one users will
notice: a page with the same text repeated in an aligned column — a table of
figures, a ditto column, a run of *Ibid.* — **lost every row after the first
from the text layer**, and published with a green tick. `deduplicated` treated
the next row down as a duplicate whenever the row pitch was smaller than the box
height, which is ordinary typesetting. It was the only line-dropping path in the
writer that reported nothing.

**Two crashes that took the whole batch.** `saturation` sized its buffer from the
raw page box, outside every guard added in 1.2.0 — a legal `MediaBox [0 0
1000000000000 1000000000000]` killed the process with SIGTRAP (R29). And 1.2.0's
own bug register had recorded that case as *measured and ruled out*; the
measurement used `[0 0 1e300 1e300]`, which PDFKit rejects for **syntax**, not
size. The entry is corrected in place.

**Smaller.** The batch stopped being frozen while the "this PDF already has
text" alert was up, so a folder still being imported could land in a job that had
already been decided — "Done — 1 of 1 succeeded" over a list of 301 (U21). And
1.2.0's new timeout used the wall clock in a file that documents why not, so an
NTP step mid-probe could make the app decide mac-ocr was missing for the rest of
the session (R30).

**Three checks written in 1.2.0 could not fail** (T4) — one read
`Thread.isMainThread` outside the closure it was testing, one compared two
clocks sampled in program order, and one never entered the function it claimed
to cover. All three are rewritten and each replacement was watched failing.

449 checks, up from 418.

## 1.2.0 — 2026-08-09

**Eleven defects, from an adversarial review of 1.1.0.** Four finders over all
nine source files, then a skeptic pass that defaulted to refuting. Fourteen
claims, eleven survived; the three that did not are kept as BUGS.md R28, because
what killed them is worth more than they were — PDFKit buffers a document at
init (a 66 MB PDF still parsed page 40 correctly after being truncated to nine
bytes on disk), and mac-ocr does not touch its `-o` destination until one write
at the very end.

**Scans with a page the app could not read no longer publish quietly** (C19).
"Use Existing Text" appended an empty string for every page with no text layer,
and in a page-break-joined file that is invisible — a 300-page book with a
30-page scanned appendix published 270 pages with a green tick. Those pages are
now named in the log and marked in the file itself, at the point where they
would have been. A blank leaf is still not reported as a loss.

**Line ends on dense scans, again** (C20). `headroom` and `rightLimit` disagreed
about what counts as one visual line, and a fragment pair in the band between
their two answers was shrunk *and* crushed at once — worst case a run drawn
0.71 pt tall against a natural 9.04. Over the 84-document corpus, line-end
selectability goes from a mean of 98.90 to **99.58 with 27 documents better and
none worse**, while line-start, word retention, text-layer offset and vertical
collisions are all unchanged. There is one definition of "the same line" now.

**Three crashes that took the whole batch with them.** The megapixel guard added
in 1.0 to prevent a crash overflowed `Int` and trapped inside itself (R24); the
outline copier had neither of the bounds its mirror function has, so a deeply
nested outline was a SIGBUS (R23); and a page whose forms share one resources
dictionary made the image scan do 13 million lookups where 61 would do (R25).

**Smaller, but each one bit every time it happened.** A file named `text.pdf`
failed deterministically, because it collided with the pipeline's own scratch
name (R27). The "page too large" refusal told you to change a setting that
cannot affect it (R26). Dropping a folder walked the whole tree on the main
thread, so a big or network-mounted folder froze the window with no way out
(U20). Files could still be added, and the output folder still changed, during
the pre-flight — after the batch had been frozen — which brought back the "3 of
3 succeeded" over a list of four that U1 was supposed to have ended (U19). And
the login-shell lookup's three-second timeout sat *after* the call it was meant
to bound, so a wedged shell still hung the app for ever (U18).

**Bookmarks on sideways pages** land in the right place: a half-specified
destination on a quarter-turned page kept the coordinate it had invented rather
than the one it was given, sending the reader to the foot of the page (C21).

418 checks, up from 357.

## 1.1.0 — 2026-08-08

**Renamed to Vision OCR.** The old name described the window; the new one
describes the job. Everything moved with it: the app is `VisionOCR.app` with the
display name *Vision OCR*, the bundle identifier is `com.cp1.VisionOCR`, the
window and the Window-menu item read "Vision OCR", and the repository is
`vision-ocr`.

**Your settings come with you.** A bundle identifier *is* the preferences
domain, so a rename moves it — and without a migration this release would have
silently reset everyone's output folder, language list and mac-ocr path while
claiming to change nothing but a name. `Prefs.migrateFromPreviousName` carries
them over once, gated on an explicit marker that "Reset to Defaults" cannot
clear (or the next launch would re-import the old values over the reset).

The first version of that migration never ran: it was gated on "does this domain
have a `mode` yet", and `object(forKey:)` searches the *registration* domain too,
so once `register()` has run every key looks present. The test caught it. That
test is the only reason this works.

**There is a disk image now** — `./build.sh --dmg` produces `Vision OCR.dmg`,
with the app and a drag-to-Applications target, verified with `hdiutil verify`
rather than assumed. There was never one before; the request to rename it is what
surfaced that.

**The disk image is universal.** `--dmg` implies a new `--universal`, which builds
arm64 and x86_64 and `lipo`s them together; the build then checks both slices are
really there. Until now `build.sh` compiled for `uname -m` only, so the image
would have been arm64-only — and an Intel Mac given a single-slice binary does
not warn, it just refuses to open, which from the other end is indistinguishable
from a corrupt download.

**README is for people who want to use the app**, not build it. Installation,
the Gatekeeper first-launch dance, and what the modes do; the build instructions,
the text-layer design, the measurements and the test inventory moved to
[TECHNICAL.md](TECHNICAL.md) intact.

Also: `Prefs.allKeys` is now the single list of keys this app owns, read by the
migration, by "Reset to Defaults" and by the test harness. There were three
copies, and R6 — a reset that silently omitted four keys — is what that costs.

357 checks.

## 1.0.4 — 2026-08-08

**Newspaper scans: line ends are selectable now** (C18). On dense newsprint the
worst document had nearly a fifth of its lines unselectable to the end. The cause
was one line in `draw`: when a line needs a large font to span its box but sits
close to its neighbours, the code capped the font size — and capping the size
costs *width*, not height, so runs came out 15–30% narrower than the lines they
sat on. 72% of the misses were exactly that.

Fixing it uncovered a fourth property of the text layer that had been holding
**by accident**. Vision splits one visual line of a column into fragments side by
side, and nothing writes a space character between them — PDFKit synthesises it
from the geometric gap and gives up below ~0.15 em. That gap existed only as
slack left over from the size cap. Widening the runs closed it and words welded:
`valuablestudy`, `thatmeasurable`. `reserveEms` now holds it open deliberately,
and CLAUDE.md's invariant 3 says "four properties", not three.

Measured over the 84-document scanned corpus:

| | shipped | now |
|---|---|---|
| line-end worst | **71%** | **91%** |
| word retention median / worst | 99% / 94% | **100% / 97%** |
| documents improved / harmed (line-end) | — | 28 / 1 |
| documents improved / harmed (words) | — | **32 / 0** |
| line-start, text-layer offset | — | unchanged |
| line separation (`score-line-separation`) | — | **byte-identical** |

**An adversarial review caught four real defects in the first version of this
fix**, all verified by running code, all fixed before release: the reserve was
budgeted against the pre-shrink font size, so a one-character fragment kept 21%
of its width; `rightLimit` compared box bottoms instead of drawn baselines, so a
display numeral treated a body line two rows away as its neighbour; a 0.5 pt
tolerance was a cliff that silently dropped the reserve when Vision's boxes
overlapped by more than two pixels; and `reserveEms` was non-monotonic as a
calibration knob.

**It also caught a claim in our own documentation that was circular.** The
"vertical overlap unchanged" figure quoted as evidence here and in BUGS.md is
computed entirely from the reference OCR of the rendered *image*. The text layer
is invisible to it, so it cannot respond to a `SearchableWriter` change at all.
`Tools/README.md` had always called it "source line tightness"; the misreading
was introduced in the previous release's write-up and is corrected in D3, in the
README, in HANDOFF, and with a warning at the point of computation. The evidence
for invariant 3(b) is `score-line-separation`, compiled once per revision.

Also in this release: **Searchable PDF is the first button and the default**, and
the window no longer shows the pipeline's steps while running — just a progress
bar and one line. The per-file outcomes still appear afterwards, because that is
the only place a failure is visible. 350 checks.

## 1.0.3 — 2026-08-08

**The corpus was wrong, so it was replaced.** The accuracy figures this project
has quoted for months came from 78 documents of which only 27 were scans — 40
were born-digital and 10 were photographs of manuscripts. Nothing about the
numbers looked wrong, which is the point: born-digital documents score perfectly,
because OCR of a clean rendering of digital text is an easy problem, and they
were holding every percentile up.

`Tools/sample-zotero.py` now classifies every candidate and keeps only scans,
using the same `Flattener.pageIsAnImage` the app uses to decide whether it is
about to discard someone's text — one rule, not two that drift. `manuscript` and
`letter` are excluded outright as Archive Processor's material.

*(**That last clause was false and stayed false for a week.** The gate compiled against
`Flattener` and then computed its own page-image test from a max over five pages combined
with a median over those pages — two rules, drifting, in the sentence claiming one. Fixed
2026-08-15, `BUGS.md` T17; the corpus it drew is 230 scans, not 233. The counts in this
entry are the old predicate's.)*

New flags:

`--added-since`, `--exclude-manifest`, `--types`, and `--allow-any-kind` for
reproducing an old corpus, which says in its help what that costs.

Rebuilt: **84 documents, all 84 verified scans** (the gate rejected 275
born-digital, 23 photographed). Through the shipped pipeline:

| | |
|---|---|
| processed | 84 / 84 |
| line-start selectability | median 100%, worst 91% |
| line-end selectability | median 100%, worst 71% |
| word retention | median 99%, worst 94% |
| text-layer offset | median 0.10, max 0.10 |
| runs overlapping vertically | 1.33% (74 of 5,564 pairs) |

The medians did not move. The tail got worse and is now true: worst-case line-end
was documented as 86–95% and is 71%. `testdocs/manifest.tsv` carries each
document's scores, so a regression traces to a document rather than a median, and
the overlap figure is published for the first time (D3) — it is the number that
would show a `SearchableWriter` change breaking line-by-line selection.

**Extract Text reads the text that is already there.** C17 fixed the destructive
path; this is the other half. Given a born-digital PDF, Extract Text offers "Use
Existing Text" instead of OCRing a picture of it. Plain text only — `json` and
`jsonl` are Vision's observation schema, and a text layer has no bounding boxes
to put in them.

Also: `explicitOutputDir` deleted — a correct, tested override that nothing
shipping ever called. 330 checks.

## 1.0.2 — 2026-08-08

**Asks before it discards text it cannot replace** (C17). Dropping a
born-digital PDF into Searchable PDF mode used to rebuild its pages as images —
throwing away real embedded text — and replace it with OCR of a picture of that
text, reporting success. Measured on three pages of one such book: 1,031 words
became 938, and only 86.1% of the output's words existed in the original.

It is not refused, because sometimes the embedded text is itself the problem — a
bad export, a mis-mapped font, a publisher's broken layer — and re-OCRing is
exactly what is wanted. What goes is the surprise. A pre-flight flags inputs
whose text sits on no page-sized image (which is what separates real digital text
from an OCR layer over a scan) and offers **OCR Anyway / Skip Those / Cancel**,
with "Don't ask again" and a matching Settings toggle. Only the destructive path
asks; Extract Text writes a new file and leaves the input alone.

The load-bearing case is the one that must *not* warn: a scan that has already
been OCR'd has text too, and stopping to ask about it would put a dialog in front
of this app's main use case. Tested, and verified against the running app in the
VM — 1 of 2 files flagged, nothing started until the alert was answered, and
"Skip Those" ran only the scan.

Found by a corpus run over a fresh sample of real scans, which also found that
**only 27 of the 78 documents in the project's own corpus are scans** — see
[CORPUS-2026-08-08.md](CORPUS-2026-08-08.md). 325 checks.

## 1.0.1 — 2026-08-08

Ran the app for real. The three interface properties that 1.0.0 shipped as
"unverified" were checked against the running app in a headless
[Tart](https://github.com/cirruslabs/tart) macOS VM — its own virtual display, so
nothing on anyone's screen, driven over VNC. All three pass. The pass also found
a defect worse than any of them.

- **Every file opened from Finder spawned another window** (U17), each with its
  own `OCRModel`. Counting on-screen windows by pid: a bare launch gave 1, opening
  three files gave **4**, opening a fourth gave **5** — and every one of them
  listed all the files with its own enabled Start button. Press Start in two and
  two batches race to write the same `scan.ocr.pdf`, because `uniqueOutputs` only
  de-conflicts *within* a batch. That is C8 and R18's class of defect, reachable
  by an ordinary Finder gesture. A `WindowGroup` is a template that macOS
  instantiates once per document; this app has one window by design, so it is a
  single-instance `Window` now, with the `OCRModel` owned by the app rather than
  by whichever window happens to exist — which also means a batch survives its
  window instead of being silently orphaned by a close.
- **The window really does come back after a mid-run close** (U13), showing the
  *live* batch — "27% · 0 of 3 files · 1 running", Cancel available — by both the
  Dock-click event and Window ▸ Vision Reader Window (⌘0).
- **Settings really does fit a short display** (U15): 560x512 on a 1024x640
  screen, Done footer on screen, the ScrollView carrying the overflow.
- **The tab order reaches everything.** Idle: Settings → mode picker → Start OCR
  → Add… → Clear List → remove-file → Save beside each original, cycling.
  Mid-run: Settings → Cancel → Copy — exactly the enabled set, with every
  disabled control correctly skipped.

Still not verified: the VoiceOver announcements have never been *heard*. See
[TODO.md](TODO.md).

Three instruments lied before any of this worked, and they are written down in
BUGS.md because that is the reusable part: a window probe matching
`kCGWindowOwnerName` against `"VisionReader"` when the bundle name is
`Vision Reader GUI`, which reported zero windows while the app had four; a
virtiofs mount serving a 90-minute-old `App.swift`, so the build under test was
not the code under test; and a TCC prompt quietly eating every keystroke, which
produced a clean and entirely fictitious tab-order result.

## 1.0.0 — 2026-08-08

First tagged release. The app already worked before this point — the repository
begins at a commit where the pipeline, the corpus and most of the design
decisions were in place — so this release is not "it now does something", it is
"it now does it reliably enough to depend on, and says so when it cannot".

### What it does

Drag scanned PDFs (or images, or folders) onto the window, choose a destination,
and get either extracted text or a searchable PDF: a visually identical copy with
an invisible, selectable text layer. Recognition is Apple's Vision framework via
the `mac-ocr` CLI; **the searchable-PDF writer is this app's own**, because
mac-ocr's doubles text on re-OCR and loses word spacing. See
[HANDOFF.md](HANDOFF.md) for why.

Measured over a 78-document corpus spanning ten item types and four eras:
78/78 process successfully, median 100% line-start and line-end selectability,
median 0.00 text-layer offset, median 100% word retention.

*(Added 2026-08-08: only 27 of those 78 documents are scans — 40 are
born-digital and 10 were photographed by hand. The figures are true of the
files and weaker evidence about OCR on scanned print than they read as. See
[CORPUS-2026-08-08.md](CORPUS-2026-08-08.md).)*

### Content-loss fixes

The defects that could publish a damaged document while reporting success — the
class this project cares about most.

- **Concurrent files erased each other's lost-line reports** (C8). A shared static
  meant a document that lost lines was published as a clean success; reproduced at
  21 of 40 runs, with an unsynchronised-array crash as a bonus.
- **Pages rebuilt at a logo's resolution** (C9, C14). A born-digital page carrying
  1,846 characters rebuilt as a 16×23 pixel image. The correction distinguishes a
  logo from a genuine coarse scan by pixel width, so real 72 DPI scans are no
  longer upsampled 17× either.
- **mac-ocr renders the crop box, not the media box** (C7, C10, C13). Settled by
  measurement; the whole geometry chain now agrees, the published copy keeps the
  entire sheet, and it still displays exactly as the original did.
- **A page the recogniser skipped published with no text** (C12), invisible to
  every other check because the page itself was still there.
- **Multi-page TIFFs were reduced to their first sheet** (C15) — the standard
  output of every sheet-fed archival scanner.
- **Dropped images were wrapped squashed or sideways** (C11): one DPI axis used
  for both, and EXIF orientation ignored.

### Reliability

- **A file-descriptor leak killed long batches** (R15). One descriptor per page,
  never released, so a batch died at roughly 2,300 pages — against a corpus of
  4,992.
- **Cancel now works** (R2, R14, R16, R17). The read loops are interruptible and
  bounded, SIGTERM escalates to SIGKILL, the JBIG2 route reports cancellation as
  cancellation rather than failure, and a run that cannot be stopped says so
  instead of crashing on an unread exit status.
- **Cancel reaches grandchildren** (R21). `Process.terminate()` already signalled
  the whole process group; the SIGKILL escalation did not, so the one case
  escalation exists for — a child that ignores SIGTERM — was the one case that
  left a descendant running, reparented to launchd, holding its pipe. The
  recorded fix for this was a `posix_spawn` rewrite of the riskiest code in the
  project; measuring it first turned it into two lines.
- **A short text layer could publish as a complete file** (C16). On the JBIG2
  route the page-count check compared the images PDF against a count derived from
  the same list, so it could not fail, and `qpdf --overlay` leaves unmatched pages
  bare — a full-length, valid PDF with no text on its later pages. The composed
  layer is checked before anything is merged.
- **Peak memory for assembly dropped 18×** (R8), from output-sized to one page,
  with byte-identical output.
- The stderr drain is idle rather than waking five times a second for the life of
  every run (R22), and partial stderr now survives a timeout instead of being
  discarded.
- **A batch could overwrite one of its own inputs** (R18) when re-run over a
  folder containing previous results.
- Settings are snapshotted once per batch instead of re-read per file (R5), and
  progress is keyed by URL so two files with the same name no longer collide (R4).

### Fidelity

- **Document outlines survive OCR** (R19), on both output routes, for the 225
  bytes the outline objects themselves occupy — written into the assembled
  catalogue before the merge rather than through a rewrite that would have added
  93 KB to the same file by destroying its JBIG2 compression.
- **Right-to-left text was re-measured and left alone** (C5). The reported defect
  did not reproduce, and every candidate fix was worse; the reasoning and the
  measurements are recorded rather than the change.
- **Fidelity beats file size** (R13). No DPI cap, no silent downscale; a page
  renders at its own resolution or the run refuses and says why.

### The interface

The GUI briefly stopped being the product — this was going to become a headless
OCR backend — and got no review attention while that was true. That decision was
reversed, and an adversarial pass over the front end found these.

- **Quitting mid-run orphaned the OCR children.** A child of a process that exits
  is reparented to launchd rather than killed, so mac-ocr, jbig2 and qpdf kept
  running invisibly. The app now asks, then stops them.
- **The Settings panel accepted edits that could not apply.** A batch snapshots
  its settings, so a mid-run change was silently ignored — and changing the text
  format would have written JSON into a reserved `.txt` path. The panel now says
  a run is in progress and locks.
- **The file list could contradict the run.** `Add…` stayed enabled during a
  batch, so the summary could say "3 of 3 succeeded" with five files on screen.
- **`Save beside each original` could describe the wrong destination** mid-run.
- **Dropping only unsupported files gave no feedback at all** — the notice lived
  in a list that does not appear when nothing was accepted.
- **Extract Text pinned the progress bar at exactly 50%** for a whole single-file
  run, which reads as a hang. There is nothing to measure there, so the bar is
  indeterminate rather than showing an invented number.
- **The log never said where output went**, which with "beside each original"
  leaves no way to find the results of a partly-failed batch.
- **Accessibility**: labels and values across the window and the Settings panel,
  outcome exposed to VoiceOver instead of carried by colour, the full path on
  each file row, a disabled Start that says why, and Cancel on ⌘. Progress is
  also *spoken* now (U16) — the batch starting, each file landing, and the
  summary — rather than merely readable if you go and read it.
- **The window could not be recovered after closing it mid-run** (U13). This is
  the worst of the interface defects and it was hiding as an open question. The
  reopen handler looked for a window that `canBecomeMain`, and a closed SwiftUI
  window reports false for exactly that until something orders it front — so the
  handler did nothing, and a running batch was unreachable: no progress, no log,
  no Cancel. Measured with `Tools/probe-window-reopen.swift`. There is now also a
  **Window ▸ Vision Reader Window (⌘0)** command, the keyboard route back that
  never existed.
- **The command preview told two lies** (U14): it showed a plausible destination
  on a fresh install where Start was disabled, and it hard-coded the name
  `mac-ocr` while never mentioning the two further binaries the compression step
  shells out to — so the setting most likely to be wrong could not be checked
  against the panel that exists for checking settings.
- **"Not added — a run is in progress" outlived the run** (U14), and the Settings
  sheet could not fit on a short display (U15).
- **A folder could be set as the mac-ocr path.** `isExecutableFile` returns true
  for directories, so it validated, claimed to be in use, and then failed every
  file in the batch.
- **The log could not be got out of the app** — selection could not span lines,
  so extracting three failures from a 40-file log meant copying them one at a
  time. It also had no Copy button, and "Clear" wiped it along with the file
  list.

### Verification

- The suite went from 141 checks to 308, and now compiles the view sources so a
  UI-only break cannot pass a green run.
- Six paths that had no coverage at all now have it (T3): concurrent *searchable*
  batches, encrypted PDFs end to end, the non-rebuild route, `makeSearchablePDF`'s
  failure and cancel branches, `publish`, and colour pages. None of them turned up
  a new defect, which is recorded as plainly as a defect would be.
- Dead settings deleted rather than kept as a record of the CLI surface (H1):
  `ocrAllPages` and `strategy` were flags of a subcommand this app has never
  invoked, and a dead setting that looks live is a trap.
- A fixture finally satisfies invariant 5 — differing page sizes *and* rotation,
  through the real pipeline (T1). It took three attempts to make it actually
  detect the bug it exists for.
- `Tools/picture-signals.swift` measures the page production renders, not a
  different one (T2).
- [CONTRIBUTING.md](CONTRIBUTING.md) and a pre-commit hook now enforce the
  process — branch, failing test first, adversarial review — because **every
  review pass over this codebase has found real defects in code written during
  the previous one.** Three of the fixes above were regressions from other fixes
  in the same session, and a pass over the outline work found eight more in code
  written minutes earlier, including an unbounded recursion that could take down
  a whole batch.
- Planning is durable now: [TODO.md](TODO.md) for decided work and
  [FEATURES.md](FEATURES.md) for ideas with their costs and the reasons some are
  parked.

### Known limitations

- Annotations are not carried into the copy; outlines are. Deliberate — see R19.
- `mac-ocr` must be installed separately. `jbig2enc` and `qpdf` are optional and
  the app falls back silently without them, which also means a green test run on a
  machine lacking them means less than it looks.
- Four things could not be settled without a person in front of a running app:
  the keyboard tab order, how the VoiceOver announcements sound over a 78-file
  batch, whether the Settings sheet shrinks on a display shorter than about
  700 pt, and the reopen fix on the real app rather than the probe. Three of them
  were answered in 1.0.1.
