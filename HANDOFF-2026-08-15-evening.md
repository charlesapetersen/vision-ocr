# Hand-off, 2026-08-15 (evening session)

The third session of 2026-08-15. The overnight one is
[HANDOFF-2026-08-15.md](HANDOFF-2026-08-15.md) and the daytime one is
[HANDOFF-2026-08-15-day.md](HANDOFF-2026-08-15-day.md); **that file's "what is left" list is
still the right one**, minus its item 1, which this session did.

Read this, then `BUGS.md`'s header, then `REVIEW-2026-08-14.md` for anything still open.

## Where the tree is

**Ask git, not this file.** That sentence is in the previous three hand-offs because the
prose went stale behind the work three times in three days.

One commit, merged fast-forward to `main` from `fix/score-mrc-drives-shipped-layers`, suite
green at 1046/1046 with no checks skipped — four new checks, on `Prefs.register(migrate:)`.

**Almost all of it is in `Tools/`, `.githooks/` and the status files, so no release decision
moves.** The one exception is `Sources/Prefs.swift`: `register` grew a `migrate:` parameter and
every tool now passes `false`. That is a two-line change to the app's own path — the app still
migrates — and it is there because a *tool* calling `Prefs.register()` was silently eating the
user's pre-rename settings. See below.

## What landed

| register | what it was |
|---|---|
| **T15** | `score-mrc` mirrored `Flattener.mrcLayers` instead of calling it, and the five drifts did not all push the same way |
| **T16** | nothing checked that a tool compiles; two more had not built since 2026-08-14, and the new checker had three defects of its own |

**Group 2's item 1 is done.** `REVIEW-2026-08-14.md` A12.3 is closed, and the tool now
calls the shipped layering and reads the three files it wrote. The four divergences the
review named all reproduced; a fifth did not appear in it and is the one worth
remembering — the tool called `Prefs.Snapshot.current()` without `Prefs.register()`, so it
recognised with `languageCorrection: false` where every shipped run has it true, and cut
its stencil from boxes the pipeline never sees.

**What the repaired instrument says, over the whole corpus.** 74 sampled picture pages:
88,972 KB today, 20,364 KB as three layers, **4.37x**. Over the 72 pages both versions
measured, the old instrument reported the layered total 43% too high — 18,759 KB against
13,115 KB — and had dropped two more pages entirely on a 60 MP gate belonging to neither
of the app's two bounds, one of them the corpus's largest page at 64.84 MP.

**`FEATURES.md`'s headline MRC figure was worse than stale.** "48 real picture pages:
40,010 KB today, 8,069 KB as MRC — 4.96x" is **the blind segmenter's ratio** — 40,010 /
8,069 = 4.958, and the table two paragraphs below it reads `Sauvola everywhere | 4.96x`
against `inside Vision's word boxes | 5.15x`. The sentence quoted the segmenter that entry
rejects as *"visibly smeared"* as the measurement of the one it ships. Replaced with a fresh
74-page figure and a two-column table.

**And then I got the replacement wrong, which is the part to read.** My first correction said
confinement is "1.35x better, not 1.04x" and called the old pair an order-of-magnitude
understatement. **Both claims were false.** `MRC_BLIND=1` differs from the shipped route in
*three* ways — no confinement, no R50 shrink, grey layers on every page — so a whole-sample
page total compares three changes at once, and **84% of that 1.35x is R50's shrink**. On the
26 grey pages where R50 does not fire, which is the only subset where the two runs differ in
exactly one way, confinement is **1.07x** on page totals and **1.53x** on stencils; over all
74 pages the confined stencil is 1.33x smaller and never larger on a single page. So the
retired 4.96x/5.15x pair was right in magnitude all along, and only the sentence quoting the
blind row was wrong. Caught by the adversarial review of my own diff, which is the third time
in three days that a correction to this project's measurements has itself needed correcting.

## What is left, unchanged from the daytime hand-off except item 1

**Group 2 — the rest of `Tools/`.** `A12.4` (the corpus gate re-implements `pageIsAnImage`
and admitted the two documents the app itself calls born-digital), `R54` (a `LEFT JOIN` in
`sweep-zotero.py`), and the remainder of `A12.8`. `R55` needs its own measurement campaign
against known hand-held material first.

**Group 3 — the text layer and the crop box.** Not started. `A1.2`, then `A1.1`, then
`C23`, in that order. Also open and small: `A1.3`, `A1.4`, `A2.4`, `A3.1` in its narrower
form, `A13.4`, the residue of `A10.6`, `A11.8`.

**`C23` is still the release blocker** and still the only open finding with harm a user
sees today. **`C24`** is open with its measurements and three refused repairs. **`R56`/`R57`**
still wait on the one unbuilt shape signal.

## A new gate, and what it found in its first run

`Tools/check-tools-compile.sh` type-checks every Swift tool, `py_compile`s every Python one and
`bash -n`s every shell one — including itself. The pre-commit hook runs it over the **staged**
tools only, which is seconds; the whole set is 26 seconds on demand.

**Its own first version had three defects, and the first would have refused this commit.**
`"${ARRAY[@]}"` under `set -u` is a fatal "unbound variable" on macOS's bash 3.2 when the array
is empty, and the hook builds exactly that: three staged `.swift`, no `.py`. `wait -n` does not
exist in 3.2 either, so the job pool was serial while printing "6 at a time" — fixing it took the
full run from 1m 59s to 25.6s. And nothing checked the shell tools, which is how a bash bug
shipped in the checker; `bash -n` is in the run now and would have caught it.

It exists because C25 closed a symptom. `score-text-route` had never compiled in any commit
while three documents cited its output, and C25 removed the bad line — but nothing anywhere
compiled a tool, so the door stayed open. **The first run found two more:** `score-skew` and
`score-reading-order` have not built since `9684c3f`, the annotation transplant, which added
`preserveAnnotations` to `Prefs.Snapshot` — a struct both tools transcribed by hand. Twenty-two
commits and eleven days. Confirmed by type-checking at `9684c3f~1` in a worktree, where they
build. Fixed the way T15 was: ask for `Prefs.Snapshot.current()` instead of transcribing it.

**If you add a field to a struct a tool constructs, that is now a gated change** —
CONTRIBUTING §5 has the row.

## Things worth knowing before touching this area

- **A tool's self-test must go through the tool's own path, and one fixture is not enough.**
  The first version of `score-mrc`'s called `Flattener.mrcLayers` directly, and would have
  passed with a mirrored layering sitting in `measure` where the delegation is — the exact
  defect it was written for. It calls `measure` now, with the shipped factors passed explicitly
  so `MRC_BG=1` does not have to be reasoned about. Then the review showed the *second* version
  still green after deleting the colour route outright, because its one fixture was grey. There
  are two now — an all-text page where R50 fires and a colour plate where it must not — and
  three separate mutants are caught, each printing which assertion failed.
- **`exit()` does not run a top-level `defer`.** Three refusals each left a scratch
  directory holding a page's worth of layers behind. Found by looking for them.
- **The all-text picture page is not in `make-plate-fixtures`.** R50's whole population — a
  page routed as a picture whose ink is all text — is missing from the six adversarial
  fixtures, so `score-mrc` builds its own: type on paper at luminance 115, `tone 0.984`,
  `inkOutsideText 0.0000`. 100 through 130 all work; it becomes a text page between 130
  and 148.
- **`tonal-plate` does not route as a picture**, measured at `ink 0.147 tone 0.102` against
  gates of 0.15 and 0.12. That is not a new finding — it is **R57**, open, and the fixture is
  the evidence for it. Do not re-file it.
- **`Runner.locateTool` reads absolute paths**, so `PATH=` cannot hide `jbig2` or `qpdf` from a
  tool. The two "refusing to run without it" branches are therefore *unexercised* — to watch one
  fail you have to `chmod -x /opt/homebrew/bin/jbig2` and put it back. `Tools/fault-inject.sh`
  has a case for it now; it is the only way to reach that branch.
- **A tool calling `Prefs.register()` was eating the user's settings.** A tool has no bundle
  identifier, so its `UserDefaults.standard` is a plist named after the *process* — and
  `migrateFromPreviousName` copies everything out of `com.cp1.VisionReaderGUI`, **deletes it
  from there**, and files it in `score-mrc.plist`, where the app will never look. Nothing was
  lost here (that domain holds only window frames on this machine), and the plists it made are
  real: `bin-score-skew.plist`, `bin-score-corpus.plist` and four others each carry
  `migratedFromVisionReaderGUI = 1`. `Prefs.register(migrate: false)` is the fix, every tool
  passes it, and the suite now checks that it imports nothing and still registers the defaults.
  **This predates today** — `score-corpus` and `score-line-separation` have been doing it since
  2026-08-14.
- **Two of the five things reviewed as defects in my own diff were arithmetic**: a median quoted
  from the row above it, and "three were the script's fault and two were real" summing to six.
  Numbers in prose do not get checked by anything. Recompute them from the TSVs before quoting.

## Environment, unchanged and still true

- **Never run two suites at once, in any two worktrees** — `build/tests` has no bundle id, so
  every worktree shares `~/Library/Preferences/tests.plist`. Check `pgrep -x tests` first.
  **Two runs of the same *tool* share a plist the same way**, which is why they must not migrate;
  two different tools are fine. The sentence that stood here said tools "write no preferences",
  and that was false until `migrate: false`.
- **zsh does not word-split unquoted `$(...)`.** Build an array.
- Tool build line: copy the tool to `<scratch>/main.swift`, then `swiftc -O -o out -target
  "$(uname -m)-apple-macos13.0" <every Sources/*.swift except App.swift> <scratch>/main.swift`.
  Or just run `Tools/check-tools-compile.sh <name>`, which now knows the three shapes.
- **Do not name a build output the same as the directory holding its `main.swift`.** `-o
  $SCRATCH/probe` against `$SCRATCH/probe/main.swift` fails as a link error and then as
  `permission denied`, which reads like a broken toolchain.
- `testdocs/` filenames contain spaces. Glob, quote, never retype.
