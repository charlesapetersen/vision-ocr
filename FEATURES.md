# Ideas not yet committed to

Things worth considering, with what each would cost and what would have to be
true to justify it. Nothing here is scheduled — [TODO.md](TODO.md) is for work
that is decided. An idea that survives here for a while and keeps looking good is
a candidate for promotion; one that keeps being deferred for the same reason
should be deleted along with that reason.

The bar for this project is unusual and worth restating: it processes
irreplaceable archival material, so **a feature that could plausibly damage or
misrepresent a document is not worth its convenience.** Several entries below are
parked for exactly that reason.

---

## Likely worth doing

### Per-page DPI control for picture pages
Photocopies routed to greyscale cost 720–920 KB/page. Capping their resolution
would cut that substantially. **Parked deliberately** — the decision recorded in
`BUGS.md` R13 is that fidelity wins, and a silent downscale is precisely the
"publishing something plausible" that invariant 1 forbids. It becomes worth doing
as an *explicit setting* with a measured default and a clear label, not as a
default behaviour. Needs the cap to exist inside `flatten` before it can be
measured honestly (the first attempt to measure it produced a broken instrument).

### Recognition language selection that reflects the machine
`-l` takes BCP-47 codes typed by hand. mac-ocr's `languages` subcommand lists
what the installed macOS actually supports, and the app never calls it. A picker
populated from that list would stop users guessing at codes that silently do
nothing.

### A way to see what went wrong, after the fact
The log is in-memory and dies with the window. For a long batch over archival
material, a written run report — inputs, outputs, per-file outcome, the settings
used — is the difference between "something failed last night" and knowing which
document and why. Small to build, and it makes every future bug report better.

### Retry the failures from a finished batch
A 78-document run where four files failed currently means re-dropping four files
by hand. The model already knows which they were.

## Plausible, with real caveats

### Direct Vision instead of the mac-ocr subprocess
Measured and written up in `HANDOFF.md`: mac-ocr is one invocation per file, and
~2,430 of 2,960 non-UI lines are already ours. Calling `VNRecognizeTextRequest`
directly would delete most of `Runner.swift`, remove the `PATH`-discovery
problem, skip a redundant rasterise round-trip, and eliminate the bug class that
produced C6, R2, R3, R16 and R17 — all subprocess-management faults, none of them
OCR faults.

**Decided against for now.** Keeping mac-ocr means someone else tracks Vision's
revisions and language lists, and the current arrangement is validated across the
corpus. Revisit only if mac-ocr stops being maintained or starts getting in the
way.

### Preserving annotations
The document outline now survives (R19). Annotations do not, and were explicitly
scoped out: links, highlights and form fields are a much larger surface, each
with its own coordinate space to remap onto rebuilt pages. Worth reconsidering if
a real document turns up where the annotations matter more than the risk of
misplacing them.

### PDF/A output
An obvious ask for an archival tool. It would mean embedding an ICC profile,
fully embedding fonts, and adding XMP metadata — and the text layer's font
handling would need re-examining, which is the most delicate part of the
codebase. Only worth it if something downstream actually requires PDF/A.

### Batch presets
"Newspaper", "typescript", "photograph" as named bundles of the routing and
recognition settings. Cheap to build, but it should follow evidence: the corpus
already shows per-era differences, and presets ought to encode measured settings
rather than guesses.

## Parked, with the reason

### Symbol-mode JBIG2
Compresses several times harder than the generic coding used now. **Never.** It
is the mechanism behind the Xerox scanners that silently swapped digits in
scanned documents, and jbig2enc's supposedly-lossless variant reports itself as
broken. For archival material this is disqualifying, not a trade-off.

### `--roi` region selection
mac-ocr supports it; without a visual region picker it is unusable, and with one
it is a substantial UI feature for a narrow benefit.

### Making the searchable-PDF text visible for debugging
Tempting for diagnosing layer geometry, but `Tools/probe-text-offset.swift` and
`probe-line-edges.swift` already answer those questions numerically, and a
"visible text" mode is a setting users would find and enable by accident.
