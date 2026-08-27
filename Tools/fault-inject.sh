#!/bin/bash
# Break something on purpose and check the build notices.
#
# Why this exists: the third review of 2026-08-09 found that three defects
# (R31, R32, H2) all lived in code that only runs when something *else* fails —
# the bundling audit, the detach-on-failure path, the licence count. Every one
# was written carefully and none had ever been executed, because nothing made
# the thing they guard actually go wrong.
#
# The reviewers found R31 by putting a no-op `install_name_tool` on PATH and
# running the real script. That technique was the most valuable thing in the
# review and it existed nowhere in this repo. Now it does.
#
#   ./Tools/fault-inject.sh          # every fault, sequentially
#   ./Tools/fault-inject.sh relocate # one, by name
#   ./Tools/fault-inject.sh --list
#
# Each case sabotages one thing, runs the real build step, and asserts the build
# REFUSES. A case that passes means the build noticed. A case that FAILS means
# the build carried on with something broken — which is the whole point.
#
# Sequential, and it builds into a scratch copy of the tree, so nothing here
# touches your working tree or the real build/ directory.
set -uo pipefail

cd "$(dirname "$0")/.."
REPO="$PWD"
PASS=0; FAIL=0

say()  { printf '  %s\n' "$*"; }
ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL %s — %s\n' "$1" "$2"; }

# A scratch copy of the tree, so a sabotaged build cannot leave debris behind in
# the real one. testdocs is 1.2 GB and irrelevant here.
sandbox() {
  SB="$(mktemp -d)"
  rsync -a --exclude .git --exclude build --exclude testdocs \
        --exclude Tools/mutation-out "$REPO/" "$SB/"
  mkdir -p "$SB/build"
}
cleanup() { [ -n "${SB:-}" ] && rm -rf "$SB"; }
trap cleanup EXIT

# A directory holding a shim that shadows a real tool on PATH.
shim() {
  local name="$1" body="$2"
  SHIMDIR="$(mktemp -d)"
  printf '#!/bin/bash\n%s\n' "$body" > "$SHIMDIR/$name"
  chmod +x "$SHIMDIR/$name"
  echo "$SHIMDIR"
}

# ---------------------------------------------------------------- the faults

# R31. A relocation that silently does nothing. The audit must catch it, and —
# the half that actually shipped broken — the bundle must not be left holding
# the unrelocated copies while the build reports "not bundled".
fault_relocate() {
  local name="a failed relocation is fatal and leaves nothing behind"
  sandbox
  local app="$SB/build/VisionOCR.app"
  mkdir -p "$app/Contents/Resources"
  local sd; sd="$(shim install_name_tool 'exit 0')"        # accepts, changes nothing
  local out rc
  out="$(cd "$SB" && PATH="$sd:$PATH" python3 Tools/bundle-libs.py "$app" jbig2 qpdf 2>&1)"; rc=$?
  rm -rf "$sd"

  if [ "$rc" -eq 0 ]; then
    bad "$name" "bundle-libs.py returned 0 with every install name unrewritten"
  else
    local left
    left=$(find "$app/Contents/Resources" \( -name jbig2 -o -name qpdf -o -name '*.dylib' \) 2>/dev/null | wc -l | tr -d ' ')
    if [ "$left" != "0" ]; then
      bad "$name" "exited $rc but left $left copied file(s) in the bundle"
    else
      ok "$name"
    fi
    # And the exit code has to be distinguishable from "tool not installed",
    # or build.sh cannot tell a benign skip from a broken bundle.
    [ "$rc" -eq 3 ] || bad "$name (exit code)" "audit failure exited $rc; build.sh treats 1 as benign"
  fi
}

# R31, the other half: build.sh itself must stop, not print "not bundled" and
# carry on signing what the audit rejected.
fault_build_continues() {
  local name="build.sh stops when bundling fails rather than shipping it"
  sandbox
  local sd; sd="$(shim install_name_tool 'exit 0')"
  local out rc
  out="$(cd "$SB" && PATH="$sd:$PATH" ./build.sh 2>&1)"; rc=$?
  rm -rf "$sd"
  if [ "$rc" -eq 0 ]; then
    bad "$name" "build.sh exited 0 after the audit rejected the bundle"
  elif grep -q 'not bundled' <<<"$out" && [ "$rc" -eq 0 ]; then
    bad "$name" "printed 'not bundled' and continued"
  else
    ok "$name"
  fi
}

# H2. A package in the closure with no licence file must be reported, not
# counted. Simulated by asking for a licence directory we then check honestly.
fault_missing_licence() {
  local name="a bundled package with no licence is reported, not counted"
  sandbox
  local app="$SB/build/VisionOCR.app"
  mkdir -p "$app/Contents/Resources"
  local out rc
  out="$(cd "$SB" && python3 Tools/bundle-libs.py "$app" jbig2 qpdf 2>&1)"; rc=$?
  if [ "$rc" -ne 0 ]; then
    bad "$name" "bundling failed outright: $(tail -1 <<<"$out")"
    return
  fi
  # Every dylib that came from a Cellar formula should have a notice whose name
  # starts with that formula.
  local missing=0 f base
  for f in "$app/Contents/Resources/lib/"*.dylib; do
    base=$(basename "$f")
    case "$base" in
      libleptonica*) grep -qil leptonica <<<"$(ls "$app/Contents/Resources/third-party-licences" 2>/dev/null)" || missing=$((missing+1));;
    esac
  done
  if [ "$missing" -ne 0 ]; then
    bad "$name" "leptonica is bundled with no licence notice"
  else
    ok "$name"
  fi
}

# R32. A detach that fails must not swallow the diagnostic explaining why the
# image was rejected in the first place.
fault_detach_fails() {
  local name="a failing detach does not swallow the verification diagnostic"
  sandbox
  # BOTH halves have to be broken, or this cannot fail. The first version of
  # this case only broke detach; verification then succeeded, the failure branch
  # never ran, and the check passed while testing nothing — the T6 shape, in a
  # case written to prevent it. So: `attach` yields an EMPTY mount, which makes
  # the engine check fail, and `detach` then fails the way Disk Arbitration
  # makes it fail on a freshly mounted volume.
  local sd; sd="$(shim hdiutil '
case "$1" in
  attach)
    for a in "$@"; do [ "$prev" = "-mountpoint" ] && mkdir -p "$a" && exit 0; prev="$a"; done
    exit 0 ;;
  detach) exit 16 ;;
esac
exec /usr/bin/hdiutil "$@"')"
  local out rc
  out="$(cd "$SB" && PATH="$sd:$PATH" ./build.sh --dmg 2>&1)"; rc=$?
  rm -rf "$sd"
  if [ "$rc" -eq 0 ]; then
    bad "$name" "build succeeded despite a failing detach"
  elif grep -qE 'did not run from the image|Engine|runs from the image' <<<"$out"; then
    ok "$name"
  else
    bad "$name" "exited $rc with no diagnostic: $(tail -2 <<<"$out" | tr '\n' ' ')"
  fi
}

# R40. The recognition helper is compiled by build.sh out of the app's own
# sources. Both halves matter and only one of them is obvious:
#
#  - A helper that will not compile must STOP the build. An app with no helper
#    still works — recognition falls back into the app — so this is precisely
#    the failure that ships quietly, and shipping it costs the 2.5x that R40
#    exists to remove.
#  - The inverse row (CONTRIBUTING 4d): a clean build must actually produce a
#    helper that RUNS. A case that only checks the sabotaged build would pass on
#    a build.sh that had stopped emitting a helper at all.
fault_helper() {
  local name="build.sh stops when the recognition helper will not compile"
  sandbox
  cp "$SB/Helper/main.swift" "$SB/Helper/main.swift.good"
  printf '\nlet brokenOnPurpose: Int = "not an Int"\n' >> "$SB/Helper/main.swift"
  local out rc
  out="$(cd "$SB" && ./build.sh 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ]; then
    bad "$name" "build.sh exited 0 with a helper that does not compile"
  else
    ok "$name"
  fi

  name="…and a clean build leaves a helper that runs with no environment"
  mv "$SB/Helper/main.swift.good" "$SB/Helper/main.swift"
  out="$(cd "$SB" && ./build.sh 2>&1)"; rc=$?
  local h="$SB/build/VisionOCR.app/Contents/Resources/visionocr-recognise"
  if [ "$rc" -ne 0 ]; then
    bad "$name" "the restored build failed: $(tail -1 <<<"$out")"
  elif [ ! -x "$h" ]; then
    bad "$name" "no helper in Contents/Resources"
  elif ! env -i PATH=/usr/bin:/bin "$h" --version 2>&1 | grep -q "revision"; then
    bad "$name" "the bundled helper did not answer --version"
  else
    ok "$name"
  fi
}

# `score-mrc` refuses to measure anything without jbig2 or qpdf, because the app
# only layers pages on the JBIG2 route — a ratio measured without them describes a
# route the machine cannot take. Neither refusal can be reached by editing PATH:
# `Runner.locateTool` checks `/opt/homebrew/bin` and friends by absolute path, on
# purpose (a GUI-launched app has almost no PATH). So the only way to watch these
# branches fail is to make the binary unrunnable, which is what this does — and puts
# it back, including on failure, which is what the trap is for.
#
# CONTRIBUTING §4c: an error branch nothing has ever executed is not a safeguard.
# R31, R32 and H2 were all careful code in branches that had never run.
fault_mrc_refuses() {
  local name tool restored=0
  tool="$(command -v jbig2 || true)"
  if [ -z "$tool" ]; then
    say "jbig2 is not installed, so there is nothing to take away — skipping."
    return
  fi
  sandbox
  # Build the tool inside the sandbox, so nothing here touches build/.
  mkdir -p "$SB/h" && cp "$SB/Tools/score-mrc.swift" "$SB/h/main.swift"
  local sources=()
  for f in "$SB"/Sources/*.swift; do
    [ "$(basename "$f")" = "App.swift" ] && continue
    sources+=("$f")
  done
  if ! swiftc -O -o "$SB/score-mrc" -target "$(uname -m)-apple-macos13.0" \
       "${sources[@]}" "$SB/h/main.swift" >"$SB/build.log" 2>&1; then
    bad "score-mrc builds" "$(grep -m1 'error:' "$SB/build.log" || echo 'see build.log')"
    return
  fi

  # Restore on every exit path, not just the happy one: leaving a user's jbig2
  # non-executable would silently take the app's JBIG2 route away.
  restore() { [ "$restored" -eq 0 ] && chmod +x "$tool" 2>/dev/null; restored=1; }
  trap 'restore' EXIT INT TERM

  name="score-mrc refuses to measure with jbig2 unrunnable"
  chmod -x "$tool"
  local out rc
  out="$("$SB/score-mrc" 2>&1)"; rc=$?
  restore
  trap - EXIT INT TERM
  if [ "$rc" -eq 3 ] && grep -q "jbig2 is not on PATH" <<<"$out"; then
    ok "$name"
  else
    bad "$name" "exit $rc, said: $(head -1 <<<"$out")"
  fi

  name="…and measures again once it is back"
  out="$("$SB/score-mrc" 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ] && grep -q "picture pages" <<<"$out"; then
    ok "$name"
  else
    bad "$name" "exit $rc after restoring jbig2, said: $(tail -1 <<<"$out")"
  fi

  # C27 (b)'s two knobs, and the debt the commit that added them recorded: all six of
  # their refusals were watched BY HAND, which is the state CONTRIBUTING §4c exists to
  # get out of. They are exit **2** — "nothing was measured and the self-test is not
  # what refused" — and unlike the two above they need nothing taken away, so they ride
  # on the binary this case has already built rather than paying a second ~80 s compile.
  #
  # ✅ **That parenthetical is MEASURED, 2026-08-26, and it is what stops these rows
  # passing for the wrong reason: a FAILED SELF-TEST EXITS 4.** So a build whose
  # self-test is broken — which is exactly the state the `Set` guard's own sabotage puts
  # it in — cannot satisfy a row asserting 2, and "refused this value" stays
  # distinguishable from "refused to run at all". Verified by running the sabotaged
  # binary, not by reading the source.
  #
  # ⚠️ Every row asserts the CODE **and** greps the message, the discipline the two
  # rows above keep: a tool that exits 2 for the wrong reason is indistinguishable from
  # one that exits 2 for the right one, and exit 2 is this file's most crowded code.
  #
  # ⛔ **AND THE MESSAGE HAS TO NAME THE GUARD, NOT THE KNOB — the first version of this
  # block failed that and the review of the diff measured it.** All five `MRC_PAGES` rows
  # grepped one string that every `MRC_PAGES` refusal printed, so a sabotage swapping the
  # repeat guard for `numbers.allSatisfy { $0 >= 2 }` left all eight rows green: `1,1,1`
  # was still refused, `4,7` still accepted, and nothing here could tell WHICH guard had
  # spoken. `parseRequestedPages` now returns a three-case result and the repeat gets its
  # own sentence, so the `1,1,1` row greps `names page 1 more than once` and that
  # sabotage reds it.
  #
  # ⚠️ And every row runs with NO document argument, so a refusal that did not fire
  # would exit 0 over zero pages rather than measuring a corpus page — this case must
  # never open `testdocs/`, for the same reason `argv_writers` must not.
  local pair label
  for pair in \
    'MRC_COLOUR=bogus|one of shipped, colour, grey' \
    'MRC_COLOUR=|one of shipped, colour, grey' \
    'MRC_PAGES=|comma-separated list of' \
    'MRC_PAGES=0|comma-separated list of' \
    'MRC_PAGES=x|comma-separated list of' \
    'MRC_PAGES=4,,7|comma-separated list of' \
    'MRC_PAGES=1,1,1|names page 1 more than once'
  do
    label="${pair%%|*}"
    name="score-mrc refuses $label"
    out="$(env "$label" "$SB/score-mrc" 2>&1)"; rc=$?
    if [ "$rc" -eq 2 ] && grep -qF "${pair#*|}" <<<"$out"; then
      ok "$name"
    else
      bad "$name" "exit $rc, said: $(head -1 <<<"$out")"
    fi
  done

  # The inverse row (CONTRIBUTING 4d): a guard that refused every value would pass all
  # seven rows above and make both knobs useless. `MRC_PAGES=4,7` and
  # `MRC_COLOUR=grey` together must be ACCEPTED — with no document to measure, that is
  # exit 0 over zero pages, which is what "the configuration was accepted" looks like
  # here.
  #
  # ⛔ `MRC_PAGES=1,1,1` is the row this block was added for. It is not a malformed
  # value: it parsed, and then measured page 1 three times into `pages`, `nowTotal` and
  # `publishedTotal`, printing a summary indistinguishable from three distinct pages —
  # A12.8's defect in `score-text-route`, reproduced in the tool whose own comment said
  # it did not have it.
  #
  # ⛔ **It greps the ARM BANNER and not just `picture pages`, because the weaker form
  # could not tell "accepted" from "never read at all"** — a build with both knobs
  # deleted exits 0 over zero pages and prints `picture pages` too, which makes the row a
  # near-duplicate of the plain one at the top of this case. The banner only appears when
  # `MRC_COLOUR` reached the tool and parsed, so it is the value's own footprint. Found by
  # the review of the diff that added this row.
  name="…and a well-formed pair of knobs is accepted"
  out="$(env MRC_PAGES=4,7 MRC_COLOUR=grey "$SB/score-mrc" 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ] && grep -q "picture pages" <<<"$out" \
     && grep -qF "[MRC_COLOUR=grey" <<<"$out"; then
    ok "$name"
  else
    bad "$name" "exit $rc, said: $(tail -1 <<<"$out")"
  fi
}

# T19. The two tools in `Tools/` that WRITE argv[2] — `pdf-extract-pages` and
# `make-observations`. A shell glob lands a corpus document in that slot, so these
# refusals are the only thing between `testdocs/*/*.pdf` and 1.2 GB of third-party
# PDFs that is not committed and cannot be rebuilt without the owner's Zotero
# library. Latent, not observed: nobody had run it, and until 2026-08-20 nothing
# would have stopped them.
#
# ⚠️ THIS CASE MUST NEVER OPEN `testdocs/`. The victims are built here by the
# suite's own fixture generator — a case that reached for the corpus to prove the
# corpus is safe would be the defect it is testing for.
#
# Both halves, per CONTRIBUTING 4d's inverse row: the glob-shaped argv must be
# refused with the destination BYTE IDENTICAL afterwards, and a legitimate
# invocation must still produce its output. A tool that refused everything would
# pass the first half on its own, which is how a guard becomes a silent outage.
#
# ⚠️ THIS CASE SABOTAGES NOTHING — it is the one here that feeds hostile argv to a
# tool rather than breaking the tool's environment, so the file header's "sabotages
# one thing, runs the real build step" describes the other six. It does compile:
# `pdf-extract-pages` alone, `make-observations` against all of `Sources/`, and one
# real Vision recognition for the inverse row.
fault_argv_writers() {
  local name target
  target="$(uname -m)-apple-macos13.0"
  sandbox

  # Real PDFs to point them at. `make-plate-fixtures` is standalone (AppKit only)
  # and is what run_tests.sh builds for the R56/R57 routing checks, so these are
  # the same pages the register's own measurements describe.
  if ! swiftc -o "$SB/plates" -target "$target" \
       "$SB/Tools/make-plate-fixtures.swift" >"$SB/plates.log" 2>&1; then
    bad "make-plate-fixtures builds" "$(grep -m1 'error:' "$SB/plates.log" || echo 'see plates.log')"
    return
  fi
  mkdir -p "$SB/plates.d"
  "$SB/plates" "$SB/plates.d" >/dev/null 2>&1
  local master="$SB/plates.d/halftone.pdf" src="$SB/plates.d/text-only.pdf"
  local third="$SB/plates.d/text-red-ink.pdf" victim="$SB/victim.pdf"
  if [ ! -s "$master" ] || [ ! -s "$src" ] || [ ! -s "$third" ]; then
    bad "the fixture pages exist" "make-plate-fixtures wrote no halftone/text-only/text-red-ink.pdf"
    return
  fi
  local before after out rc

  # A FRESH victim per check, not one `before` for all of them. Sharing it made the
  # unguarded case cascade — the first check's write left every later digest
  # comparison reporting the first check's damage.
  # It sets `victim` as well as copying it, because later rows point `victim` at a
  # different file under threat and this must not follow them there.
  _t19_fresh() {
    victim="$SB/victim.pdf"
    cp "$master" "$victim"
    before="$(shasum -a 256 "$victim" | cut -d' ' -f1)"
  }

  # What a refusal has to be, in one place: exit 2 (every guard in both tools uses
  # it), a diagnostic that says so, and the destination BYTE IDENTICAL. `rc != 0`
  # alone would read green on a refusal for an unrelated reason — the sibling
  # `mrc_refuses` asserts an exact code and greps the message, and so does this.
  _t19_refused() {   # name, rc, output
    after="$(shasum -a 256 "$victim" | cut -d' ' -f1)"
    if [ "$2" -eq 0 ]; then
      bad "$1" "exit 0, said: $(head -1 <<<"$3")"
    elif [ "$after" != "$before" ]; then
      bad "$1" "refused with exit $2 AFTER writing the destination"
    elif [ "$2" -ne 2 ]; then
      bad "$1" "exit $2, wanted 2 (a refusal): $(head -1 <<<"$3")"
    elif ! grep -qE 'REFUSED|usage:' <<<"$3"; then
      bad "$1" "exit 2 with no refusal diagnostic: $(head -1 <<<"$3")"
    else
      ok "$1"
    fi
  }

  # ---- pdf-extract-pages. Standalone: PDFKit and Foundation only.
  if ! swiftc -o "$SB/extract" -target "$target" \
       "$SB/Tools/pdf-extract-pages.swift" >"$SB/extract.log" 2>&1; then
    bad "pdf-extract-pages builds" "$(grep -m1 'error:' "$SB/extract.log" || echo 'see extract.log')"
    return
  fi
  # ⚠️ ONE ROW PER GUARD, and the count is the point. The first version of this case
  # had four refusal rows reaching two guards of the seven `pdf-extract-pages` now
  # has: deleting the overwrite guard — the one every document presents as the
  # headline refusal — left all of them green, and the accident that is not a glob
  # (two hand-typed corpus paths and a valid page) appeared nowhere. Two rounds of
  # adversarial review on this diff found that and then found a guard with no row
  # again. If you add a refusal to either tool, add its row here and watch the row
  # fail without it.

  # Guard 1, the page parse. Three or more paths: argv[3] is a path, and the old
  # loop's `continue` dropped it and every path after it.
  _t19_fresh
  name="pdf-extract-pages refuses a glob rather than overwriting argv[2]"
  out="$("$SB/extract" "$src" "$victim" "$third" 2>&1)"; rc=$?
  _t19_refused "$name" "$rc" "$out"

  # Guard 2, the usage guard. Exactly two paths — a two-document glob, where there is
  # no page argument to refuse. This used to write an empty PDF and print
  # `extracted 0 pages`.
  _t19_fresh
  name="…and refuses two paths with no page list, which used to write an empty PDF"
  out="$("$SB/extract" "$src" "$victim" 2>&1)"; rc=$?
  _t19_refused "$name" "$rc" "$out"

  # Guard 3, the overwrite guard, and THE ACCIDENT THAT IS NOT A GLOB: two corpus
  # paths typed by hand with a page number that parses. Nothing else in this case
  # reaches this guard, and pre-fix this is a destroyed document with exit 0.
  _t19_fresh
  name="…and refuses an existing destination even with a valid page number"
  out="$("$SB/extract" "$src" "$victim" 1 2>&1)"; rc=$?
  _t19_refused "$name" "$rc" "$out"

  # Guard 4, self-overwrite, and it must hold THROUGH the escape hatch: OVERWRITE=1
  # means "replace my own fixture", never "write the file you are reading". Routed
  # through the same assertion by pointing `victim` at the file under threat — the
  # helper is the only place that knows what a refusal has to look like.
  cp "$src" "$SB/self.pdf"
  victim="$SB/self.pdf"; before="$(shasum -a 256 "$victim" | cut -d' ' -f1)"
  name="…and OVERWRITE=1 still refuses to write the file it is reading"
  out="$(OVERWRITE=1 "$SB/extract" "$victim" "$victim" 1 2>&1)"; rc=$?
  _t19_refused "$name" "$rc" "$out"

  # Guard 5, a DIRECTORY destination, and it must hold through the escape hatch too:
  # `replaceItemAt` would swap a file in for the directory and take its contents. The
  # round-two review of this diff called that a hazard the staged write had created,
  # reasoning that the old `write(to: <directory>)` just failed. This row says
  # otherwise, which is why it is a row and not a paragraph: against the PRE-FIX tool
  # it fails with "the directory is gone" — PDFKit replaced the directory, and its
  # `keepme.pdf` with it, on exit 0.
  mkdir -p "$SB/adir" && cp "$src" "$SB/adir/keepme.pdf"
  victim="$SB/adir/keepme.pdf"; before="$(shasum -a 256 "$victim" | cut -d' ' -f1)"
  name="…and OVERWRITE=1 still refuses a directory as the destination"
  out="$(OVERWRITE=1 "$SB/extract" "$src" "$SB/adir" 1 2>&1)"; rc=$?
  if [ ! -d "$SB/adir" ]; then
    bad "$name" "the directory is gone"
  else
    _t19_refused "$name" "$rc" "$out"
  fi

  # Guard 6, a page asked for twice. Nothing else passes this tool a repeated page,
  # so without this row the refusal could be deleted with every check still green.
  victim="$SB/twice.pdf"; before="absent"
  name="…and refuses the same page twice rather than building a short document"
  out="$("$SB/extract" "$src" "$victim" 1 1 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ]; then
    bad "$name" "exit 0, said: $(head -1 <<<"$out")"
  elif [ -e "$victim" ]; then
    bad "$name" "refused with exit $rc and left a file at the destination"
  elif [ "$rc" -ne 2 ]; then
    bad "$name" "exit $rc, wanted 2 (a refusal): $(head -1 <<<"$out")"
  else
    ok "$name"
  fi

  # Guard 7, the page range. A page outside the source used to `continue`, so
  # `… 4 6 7` over a five-page document wrote a short fixture and reported success.
  # Nothing may be published at all — no destination and no staging debris, which is
  # the only row that checks the staged write cleans up after itself. The staging name
  # carries a pid, hence the glob.
  name="…and refuses a page outside the source, publishing nothing"
  out="$("$SB/extract" "$src" "$SB/oor.pdf" 999 2>&1)"; rc=$?
  local debris; debris="$(ls "$SB"/oor.pdf.visionocr-staging-* 2>/dev/null | head -1)"
  if [ "$rc" -eq 0 ]; then
    bad "$name" "exit 0, said: $(head -1 <<<"$out")"
  elif [ -e "$SB/oor.pdf" ] || [ -n "$debris" ]; then
    bad "$name" "refused with exit $rc and left a file or staging debris behind"
  elif [ "$rc" -ne 2 ]; then
    bad "$name" "exit $rc, wanted 2 (a refusal): $(head -1 <<<"$out")"
  elif ! grep -qE 'REFUSED|usage:' <<<"$out"; then
    bad "$name" "exit 2 with no refusal diagnostic: $(head -1 <<<"$out")"
  else
    ok "$name"
  fi

  # The inverse rows. A tool that refused everything would pass all five above.
  name="…and still extracts a page to a destination of its own"
  out="$("$SB/extract" "$src" "$SB/fixture.pdf" 1 2>&1)"; rc=$?
  if [ "$rc" -ne 0 ]; then
    bad "$name" "exit $rc: $(head -1 <<<"$out")"
  elif [ ! -s "$SB/fixture.pdf" ]; then
    bad "$name" "exit 0 and no fixture.pdf"
  else
    ok "$name"
  fi

  # Guarded on the precondition, or a broken row above turns this into "the tool
  # exits 0 on a fresh destination" — which is the row above, tested twice.
  name="…and OVERWRITE=1 is the way to mean it"
  if [ ! -s "$SB/fixture.pdf" ]; then
    bad "$name" "no fixture.pdf to overwrite — the previous row did not produce one"
  else
    out="$(OVERWRITE=1 "$SB/extract" "$src" "$SB/fixture.pdf" 1 2>&1)"; rc=$?
    if [ "$rc" -eq 0 ] && [ -s "$SB/fixture.pdf" ]; then ok "$name"
    else bad "$name" "exit $rc: $(head -1 <<<"$out")"; fi
  fi

  # ---- make-observations. Needs Sources/, like score-mrc above.
  # Count-guarded expansion: an EMPTY array under `set -u` is a fatal "unbound
  # variable" on macOS's bash 3.2, which is the defect check-tools-compile.sh's own
  # header records shipping. A non-matching glob here yields a literal element rather
  # than an empty array, so this is belt and braces — and that file says the guards
  # are not decoration.
  local sources=()
  for f in "$SB"/Sources/*.swift; do
    [ "$(basename "$f")" = "App.swift" ] && continue
    sources+=("$f")
  done
  if [ "${#sources[@]}" -eq 0 ]; then
    bad "make-observations builds" "no Sources/*.swift in the sandbox"
    return
  fi
  mkdir -p "$SB/mo" && cp "$SB/Tools/make-observations.swift" "$SB/mo/main.swift"
  if ! swiftc -o "$SB/make-observations" -target "$target" \
       "${sources[@]}" "$SB/mo/main.swift" >"$SB/mo.log" 2>&1; then
    bad "make-observations builds" "$(grep -m1 'error:' "$SB/mo.log" || echo 'see mo.log')"
    return
  fi

  # Guard 1, the extension guard. Three paths — argv[3] becomes the "password".
  _t19_fresh
  name="make-observations refuses a glob rather than writing JSON over argv[2]"
  out="$("$SB/make-observations" "$src" "$victim" "$third" 2>&1)"; rc=$?
  _t19_refused "$name" "$rc" "$out"

  # Still guard 1 — a different shape, the same guard, and saying so is the point of
  # the comment above: two paths is `arguments.count == 3`, which the count guard
  # permits.
  _t19_fresh
  name="…and refuses two paths, where the destination is a PDF and not a .json"
  out="$("$SB/make-observations" "$src" "$victim" 2>&1)"; rc=$?
  _t19_refused "$name" "$rc" "$out"

  # Guard 2, the argument count, which needs FOUR arguments to fire and had no row
  # until the review of this diff. The destination is a legal `.json` on purpose, so
  # the extension guard cannot answer this one.
  _t19_fresh
  name="…and refuses a fourth argument, which the extension guard cannot see"
  out="$("$SB/make-observations" "$src" "$SB/obs-extra.json" "$victim" "$third" 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ]; then
    bad "$name" "exit 0, said: $(head -1 <<<"$out")"
  elif [ -e "$SB/obs-extra.json" ]; then
    bad "$name" "refused with exit $rc after writing the destination"
  elif [ "$rc" -ne 2 ]; then
    bad "$name" "exit $rc, wanted 2 (a refusal): $(head -1 <<<"$out")"
  else
    ok "$name"
  fi

  # The inverse row, and it is the expensive one: real recognition over a
  # synthesised page of type. `make-observations` exits 3 on zero observations, so
  # this asserts the guard let a legitimate run through AND that the run measured
  # something — the two ways this instrument has been able to report nothing.
  name="…and still writes the observation JSON the invariant-3 probes read"
  out="$("$SB/make-observations" "$src" "$SB/obs.json" 2>&1)"; rc=$?
  if [ "$rc" -ne 0 ]; then
    bad "$name" "exit $rc: $(head -1 <<<"$out")"
  elif [ ! -s "$SB/obs.json" ]; then
    bad "$name" "exit 0 and no obs.json"
  elif ! grep -q "observations" <<<"$out"; then
    bad "$name" "wrote a file but reported no observation count: $(head -1 <<<"$out")"
  else
    ok "$name"
  fi

  # Its own cleanup, because `fault_mrc_refuses` above does `trap - EXIT INT TERM`
  # and takes the script's `cleanup` trap with it — so on a full run nothing would
  # remove this sandbox, and it holds a whole-repo rsync plus a binary linked against
  # all of `Sources/`. Named rather than fixed at the source: restoring that trap is
  # a change to another case's error handling, and this case is not the place for it.
  # Only on the paths that get this far — a build failure keeps the sandbox, because
  # the log its `bad` message names lives inside it.
  rm -rf "$SB"
}

# C30. `Tools/score-text-voids.swift`'s refusals. The crop experiment (2026-08-25)
# added three `exit(2)` guards and two new ways to reach `exit(7)`, and its own
# section named the debt: the `exit(2)`s had been "exercised by hand only", and of
# exit 7's three branches only TILE-IDENTITY had ever been watched going red. An
# error branch nobody has executed is not a safeguard — CONTRIBUTING §4c, and R31,
# R32 and H2 are why this file exists.
#
# ⚠️ WHAT IT SABOTAGES, precisely, because the file header says "sabotages one thing,
# runs the real build step" and neither half is true here. It runs no build step: the
# subject is a `Tools/` tool, as in `mrc_refuses` and `argv_writers`. And only ONE of
# its eight rows sabotages anything — the read-only dump directory, which is this
# file's `chmod -x` technique pointed at a destination instead of a program. The
# other seven feed hostile argv and environment, `argv_writers`-style, or assert the
# inverse.
#
# ⛔ Why a 12x12 pt page has to be built here. `bandFailed` fires when a band will
# not crop or its request throws, and Vision refuses an image with a dimension of
# 2 px or less. `TILES` is capped at 64, so provoking it on a 3300-row fixture
# would need ~1,650 bands and cannot be asked for: the page has to be small enough
# that a 64-way split lands under Vision's floor. 12x12 pt rebuilds to 50x50 px at
# 300 dpi, and 64 bands of a 50-row sheet are 50 one-row bands.
#
# ⚠️ THE BAND ROW DEPENDS ON A VISION BEHAVIOUR, not on this repo. If Apple lets a
# 1-row image through, that row goes red — which is the right signal (the branch
# no longer fires and nobody is watching it) and not a build failure. This file is
# not in the pre-commit hook, so a red row here refuses no commit.
fault_text_voids() {
  local name target out rc
  target="$(uname -m)-apple-macos13.0"
  sandbox

  # Built in the sandbox against `Sources/`, the way `mrc_refuses` builds `score-mrc`:
  # this tool takes its pixels from `Flattener.flatten` and its boxes from
  # `Recogniser`, so it cannot be compiled alone.
  mkdir -p "$SB/h" && cp "$SB/Tools/score-text-voids.swift" "$SB/h/main.swift"
  local sources=()
  for f in "$SB"/Sources/*.swift; do
    [ "$(basename "$f")" = "App.swift" ] && continue
    sources+=("$f")
  done
  # `argv_writers` carries this guard and the first draft of this case dropped it:
  # under `set -u` on bash 3.2 an empty array expansion is a fatal *unbound
  # variable*, which aborts the whole run mid-case instead of reporting a red row.
  if [ "${#sources[@]}" -eq 0 ]; then
    bad "Sources/ has Swift files to build against" "no Sources/*.swift in the sandbox"
    return
  fi
  if ! swiftc -O -o "$SB/score-text-voids" -target "$target" \
       "${sources[@]}" "$SB/h/main.swift" >"$SB/voids-build.log" 2>&1; then
    bad "score-text-voids builds" \
        "$(grep -m1 'error:' "$SB/voids-build.log" || echo "see $SB/voids-build.log")"
    return
  fi
  local tool="$SB/score-text-voids"

  # A real page of type, from the suite's own fixture generator. ⚠️ NEVER `testdocs/`
  # — the same rule `argv_writers` carries, for the same reason.
  # ⚠️ Neither of these two failures removes the sandbox, and `argv_writers` records
  # the reason: the `bad` message names a log that lives inside it. Deleting it here
  # would point a maintainer at a path that no longer exists.
  if ! swiftc -o "$SB/plates" -target "$target" \
       "$SB/Tools/make-plate-fixtures.swift" >"$SB/plates.log" 2>&1; then
    bad "make-plate-fixtures builds" \
        "$(grep -m1 'error:' "$SB/plates.log" || echo "see $SB/plates.log")"
    return
  fi
  mkdir -p "$SB/plates.d"
  "$SB/plates" "$SB/plates.d" >/dev/null 2>&1
  local page="$SB/plates.d/text-only.pdf"
  if [ ! -s "$page" ]; then
    bad "the fixture page exists" "make-plate-fixtures wrote no text-only.pdf"
    return
  fi

  # The smallest legal PDF that PDFKit will open, at the page size argued for above.
  # Hand-written because nothing in the tree makes a page this small, and validated
  # by the band row itself: a malformed file exits 1 at `cannot open`, which that
  # row reports as a failure rather than passing quietly.
  /usr/bin/python3 - "$SB/tiny.pdf" <<'PY'
import sys
w = h = 12
body = b"0 0 0 rg 1 1 %d %d re f\n" % (w - 2, h - 2)
objs = [b"<< /Type /Catalog /Pages 2 0 R >>",
        b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 %d %d] /Contents 4 0 R "
        b"/Resources << >> >>" % (w, h),
        b"<< /Length %d >>\nstream\n" % len(body) + body + b"endstream"]
out, offs = b"%PDF-1.4\n", []
for i, o in enumerate(objs, 1):
    offs.append(len(out))
    out += b"%d 0 obj\n" % i + o + b"\nendobj\n"
xref = len(out)
out += b"xref\n0 %d\n0000000000 65535 f \n" % (len(objs) + 1)
for o in offs:
    out += b"%010d 00000 n \n" % o
out += b"trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n" % (
    len(objs) + 1, xref)
open(sys.argv[1], "wb").write(out)
PY

  # --- the exit(2) refusals the crop experiment added -------------------------
  # None of these opens the PDF: the guards run before `PDFDocument(url:)`, so the
  # page argument is a placeholder and these rows cost nothing.

  # ⛔ The one the section calls out by name. `TILETEXT` alone used to create the
  # directory, write nothing and exit 0 — a missing dump reading exactly like "the
  # strings matched nothing".
  #
  # ⚠️ TWO ROWS, NOT ONE, and the split is the point. Written as a single `elif`
  # chain the exit-code clause short-circuits, so restoring the old behaviour reddens
  # it on the code alone and the directory clause is never evaluated — an assertion
  # nobody has watched, inside a case whose whole purpose is that they get watched.
  # Apart, one sabotage reddens both.
  local dumpdir="$SB/never-made"
  out="$(TILETEXT="$dumpdir" "$tool" "$page" 1 2>&1 >/dev/null)"; rc=$?

  name="TILETEXT without TILES is refused, and says why"
  if [ "$rc" -ne 2 ]; then
    bad "$name" "exit $rc, wanted 2: $(head -1 <<<"$out")"
  elif ! grep -q "needs TILES=n" <<<"$out"; then
    bad "$name" "exit 2 with the wrong diagnostic: $(head -1 <<<"$out")"
  else
    ok "$name"
  fi

  # ⚠️ Green whenever the tool exits BEFORE `createDirectory` — a self-test failure, a
  # usage refusal, a `VOIDMININCH` refusal — so it is only meaningful while the row
  # above is green. Left unguarded rather than gated on `rc == 2`, because gating it
  # would make it SKIP under the sabotage it exists to catch instead of going red.
  name="…and leaves no dump directory behind for a later run to read as this run's"
  if [ -e "$dumpdir" ]; then
    bad "$name" "$dumpdir exists after a refusal"
  else
    ok "$name"
  fi

  name="TILETEXT at an unwritable path is refused before anything is measured"
  out="$(TILES=1 TILETEXT=/dev/null/nope "$tool" "$page" 1 2>&1 >/dev/null)"; rc=$?
  if [ "$rc" -eq 2 ] && grep -q "is not a writable directory" <<<"$out"; then
    ok "$name"
  else
    bad "$name" "exit $rc, said: $(head -1 <<<"$out")"
  fi

  # Both ends of the range and a non-number. The ceiling is what stops a typo
  # starting ten thousand requests, so it is asserted rather than assumed.
  name="TILES outside 1…64, and TILES that is not a number, are refused"
  local bads=0 t
  for t in 0 65 two -1; do
    out="$(TILES="$t" "$tool" "$page" 1 2>&1 >/dev/null)"; rc=$?
    if [ "$rc" -ne 2 ] || ! grep -q "whole number of bands" <<<"$out"; then
      bads=$((bads+1)); say "TILES=$t gave exit $rc: $(head -1 <<<"$out")"
    fi
  done
  if [ "$bads" -eq 0 ]; then ok "$name"; else bad "$name" "$bads of 4 values were not refused"; fi

  name="VOIDMININCH that is not a positive number of inches is refused"
  out="$(VOIDMININCH=0 "$tool" "$page" 1 2>&1 >/dev/null)"; rc=$?
  if [ "$rc" -eq 2 ] && grep -q "positive number of inches" <<<"$out"; then
    ok "$name"
  else
    bad "$name" "exit $rc, said: $(head -1 <<<"$out")"
  fi

  # --- exit 7's two never-watched branches ------------------------------------

  # ⛔ The dump write, failed for real rather than simulated. The directory EXISTS,
  # so `createDirectory(withIntermediateDirectories: true)` succeeds at startup and
  # the exit-2 guard above cannot answer this; the write inside `dumpText` is what
  # fails, which is the branch the two silent image writers in `Tools/` get wrong.
  # ⚠️ No restore trap, unlike `mrc_refuses`: `chmod 755` is unconditional and there
  # is no `return` between, and the subject is a directory inside a throwaway sandbox
  # rather than a user's own `jbig2`. An interrupt here leaks a 555 directory under
  # `mktemp -d` and nothing else.
  name="a dump directory that cannot be written is exit 7, not a quiet zero"
  local rodir="$SB/readonly-dump"
  mkdir -p "$rodir" && chmod 555 "$rodir"
  out="$(TILES=1 TILETEXT="$rodir" "$tool" "$page" 1 2>&1)"; rc=$?
  chmod 755 "$rodir"
  if [ "$rc" -ne 7 ]; then
    bad "$name" "exit $rc, wanted 7: $(tail -1 <<<"$out")"
  elif ! grep -q "TEXT DUMPS FAILED TO WRITE" <<<"$out"; then
    bad "$name" "exit 7 without naming the failed dumps: $(tail -1 <<<"$out")"
  elif ! grep -q "could not write p1-whole.txt" <<<"$out"; then
    bad "$name" "exit 7 but the row does not name the file it could not write"
  else
    ok "$name"
  fi

  # ⛔ A band that contributes no boxes, and it must be the `bandFailed` arm of
  # `tileBandFailures` rather than the `bands.isEmpty` one. The third clause is what
  # discriminates: `bands contributed no boxes` is emitted ONLY from `bandFailed > 0`,
  # where the empty-bands arm says `produced no bands on a <h>-row page`. So matching
  # on exit 7 alone would be green on either arm and this is not.
  #
  # ⚠️ A fourth clause asserting the empty-bands string is ABSENT was written and
  # REMOVED: `bandFailed` is counted inside `for band in bands`, so `bands.isEmpty`
  # implies `bandFailed == 0` and the two are mutually exclusive — with clause three
  # green, that assertion is forced and could not fail. A fifth, `grep "^p1<TAB>"`,
  # went the same way: its message said "the tiny fixture never opened", but a
  # fixture that will not open exits 1 at `cannot open` and clause one already has
  # it, while reaching here at all means the row was printed. Both found by the
  # adversarial review of this diff — the twelve checks in this register that could
  # not fail are why it is run.
  name="bands that contribute no boxes are exit 7, and it is bandFailed not empty-bands"
  out="$(TILES=64 "$tool" "$SB/tiny.pdf" 1 2>&1)"; rc=$?
  if [ "$rc" -ne 7 ]; then
    bad "$name" "exit $rc, wanted 7: $(tail -1 <<<"$out")"
  elif ! grep -q "BANDS PRODUCED NOTHING" <<<"$out"; then
    bad "$name" "exit 7 without the band summary: $(tail -1 <<<"$out")"
  elif ! grep -q "bands contributed no boxes" <<<"$out"; then
    bad "$name" "exit 7, but by the empty-bands arm rather than bandFailed: $(tail -1 <<<"$out")"
  else
    ok "$name"
  fi

  # --- the inverse row, CONTRIBUTING §4d --------------------------------------
  # A tool that refused everything would pass every row above.
  #
  # ⛔ IT ASSERTS `obsN`, NOT "a row was printed", and the difference is the whole
  # value of the row. A build whose recognition returned NOTHING still exits 0
  # (`measured` is incremented before any observation test), still prints a `p1` row
  # (verdict `no-words`), and still writes both dumps — `dumpText` joins zero strings
  # into a 1-byte file, so even `[ -s ]` is satisfied. So the three obvious clauses
  # were all green on a tool that had stopped working, which the adversarial review
  # of this diff found. `obsN > 0` is the one that is not.
  name="…and a writable dump directory still recognises the page and writes both arms"
  local okdir="$SB/good-dump" obs
  mkdir -p "$okdir"
  out="$(TILES=1 TILETEXT="$okdir" "$tool" "$page" 1 2>&1)"; rc=$?
  obs="$(awk -F'\t' '$1 == "p1" { print $9 }' <<<"$out")"
  if [ "$rc" -ne 0 ]; then
    bad "$name" "exit $rc: $(tail -1 <<<"$out")"
  elif [ -z "$obs" ]; then
    bad "$name" "exit 0 and no p1 row to read obsN from"
  elif [ "$obs" -le 0 ]; then
    bad "$name" "exit 0 with obsN $obs — the page was measured and nothing was read"
  elif [ ! -s "$okdir/p1-whole.txt" ] || [ ! -s "$okdir/p1-tiled-1.txt" ]; then
    bad "$name" "exit 0 with $(ls "$okdir" | wc -l | tr -d ' ') of 2 dumps written"
  else
    ok "$name"
  fi

  # Same reason as `argv_writers`: `mrc_refuses` clears the script's EXIT trap, so
  # on a full run nothing else removes this sandbox — and it holds a whole-repo
  # rsync plus two binaries linked against all of `Sources/`.
  rm -rf "$SB"
}

# `score-drawn-images`'s form-nesting census, added 2026-08-26 with the census itself.
#
# The census is a SECOND implementation of `drawnLargestImage`'s traversal — the queue's
# `bare-form-reach` needed depths that neither shipped walk exposes — so the thing worth
# watching is not that it refuses bad input but that **its self-test is in front of every
# sweep and pins production's caps rather than its own model of them**. Rows 3 and 4 are
# that claim, and they are why this case is worth its build time: row 4 sabotages
# `Sources/Flattener.swift` and requires the TOOL to notice.
#
# ⛔ Exit 5 has NO row and cannot get one from here. It fires when a page reads `diverges`
# while `largestImage` found nothing, which means the census's model of the dictionary
# walk's reach is wrong — and every sabotage that produces that also reds the self-test,
# which runs first and exits 4 (row 2 is exactly such a sabotage, and it exits 4). So exit 5
# is a backstop for a corpus shape the nine fixture pages do not have; reaching it needs a
# page nobody in the tree can build, and `argv_writers`' rule forbids reaching for
# `testdocs/`. Recorded, not watched. Exit 1 (production disagreeing with the drawn arm) is
# pre-existing and equally unwatched.
fault_drawn_census() {
  local name target out rc tool fields f
  target="$(uname -m)-apple-macos13.0"
  sandbox

  # One page: the page's own dictionary holds both the image and a BARE form that draws it,
  # so the census must answer formDepth 1 / bareDepth 1 and both shipped walks must answer
  # 900. A page of plain type would read `flat 0 0`, and the inverse row would then pass over
  # a census that had stopped traversing anything — which is what `text_voids`' own inverse
  # row was rewritten for.
  /usr/bin/python3 - "$SB/bare-form.pdf" <<'PY'
import sys
draw = b"q 1 0 0 1 0 0 cm /F Do Q\n"
inner = draw.replace(b"/F ", b"/Im ")
objs = [b"<< /Type /Catalog /Pages 2 0 R >>",
        b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R "
        b"/Resources << /XObject << /Im 5 0 R /F 6 0 R >> >> >>",
        b"<< /Length %d >>\nstream\n" % len(draw) + draw + b"endstream",
        b"<< /Type /XObject /Subtype /Image /Width 900 /Height 900 /ColorSpace /DeviceGray "
        b"/BitsPerComponent 8 /Length 3 >>\nstream\nabc\nendstream",
        # No /Resources: that is the whole subject.
        b"<< /Type /XObject /Subtype /Form /BBox [0 0 612 792] /Length %d >>\nstream\n"
        % len(inner) + inner + b"endstream"]
out, offs = b"%PDF-1.4\n", []
for i, o in enumerate(objs, 1):
    offs.append(len(out))
    out += b"%d 0 obj\n" % i + o + b"\nendobj\n"
xref = len(out)
out += b"xref\n0 %d\n0000000000 65535 f \n" % (len(objs) + 1)
for o in offs:
    out += b"%010d 00000 n \n" % o
out += b"trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n" % (
    len(objs) + 1, xref)
open(sys.argv[1], "wb").write(out)
PY
  if [ ! -s "$SB/bare-form.pdf" ]; then
    bad "the bare-form fixture was written" "no bare-form.pdf in the sandbox"
    return
  fi

  # `argv_writers` carries this guard and `text_voids`' first draft dropped it: under
  # `set -u` on bash 3.2 an empty array expansion is a fatal unbound variable, which aborts
  # the run mid-case instead of reporting a red row.
  local sources=()
  for f in "$SB"/Sources/*.swift; do
    [ "$(basename "$f")" = "App.swift" ] && continue
    sources+=("$f")
  done
  if [ "${#sources[@]}" -eq 0 ]; then
    bad "Sources/ has Swift files to build against" "no Sources/*.swift in the sandbox"
    return
  fi

  mkdir -p "$SB/h" && cp "$SB/Tools/score-drawn-images.swift" "$SB/h/main.swift"
  if ! swiftc -O -o "$SB/drawn" -target "$target" "${sources[@]}" "$SB/h/main.swift" \
       >"$SB/drawn.log" 2>&1; then
    bad "score-drawn-images builds" \
        "$(grep -m1 'error:' "$SB/drawn.log" || echo "see $SB/drawn.log")"
    return
  fi
  tool="$SB/drawn"

  # --- 1. the usage refusal ---------------------------------------------------
  name="score-drawn-images with no argument is exit 2 and names the census columns"
  out="$("$tool" 2>&1 >/dev/null)"; rc=$?
  if [ "$rc" -ne 2 ]; then
    bad "$name" "exit $rc, wanted 2: $(head -1 <<<"$out")"
  elif ! grep -q 'Columns 14-16' <<<"$out"; then
    bad "$name" "exit 2 without pointing at the census: $(head -1 <<<"$out")"
  else
    ok "$name"
  fi

  # --- 2/3. a sabotaged CENSUS, on both entry points --------------------------
  # `r <= 3` -> `r <= 4` makes the divergence test fire on a chain of four
  # resource-carrying forms, where `r = 4` and NEITHER walk reaches — fixture page 5. One
  # token, and the smallest wrong answer the arithmetic can give.
  mkdir -p "$SB/hs"
  sed 's|if r <= 3 { s.out.divergent = true }|if r <= 4 { s.out.divergent = true }|' \
      "$SB/h/main.swift" > "$SB/hs/main.swift"
  if cmp -s "$SB/hs/main.swift" "$SB/h/main.swift"; then
    bad "the census sabotage applies" "the r <= 3 test was not found in the tool"
    return
  fi
  if ! swiftc -O -o "$SB/drawn-sab" -target "$target" "${sources[@]}" "$SB/hs/main.swift" \
       >"$SB/drawn-sab.log" 2>&1; then
    bad "the census-sabotaged build compiles" \
        "$(grep -m1 'error:' "$SB/drawn-sab.log" || echo "see $SB/drawn-sab.log")"
    return
  fi

  name="a census that mis-reads the dictionary walk's reach is exit 4, naming the page"
  out="$("$SB/drawn-sab" --self-test 2>&1 >/dev/null)"; rc=$?
  if [ "$rc" -ne 4 ]; then
    bad "$name" "exit $rc, wanted 4: $(tail -1 <<<"$out")"
  elif ! grep -q 'census p5 reads bothBlind' <<<"$out"; then
    bad "$name" "exit 4 without naming p5: $(head -2 <<<"$out" | tr '\n' ' ')"
  else
    ok "$name"
  fi

  # ⛔ The row the "runs on every invocation" claim rests on, and it asserts the ABSENCE of
  # the header rather than the exit code alone. A build that exited 4 *after* printing the
  # TSV header would satisfy an exit-code-only row while having already emitted something a
  # caller redirects and keeps — a truncated sweep that looks like a sweep, invariant 1's
  # shape in an instrument.
  name="…and it refuses the SWEEP path too, before any TSV reaches stdout"
  out="$("$SB/drawn-sab" "$SB/bare-form.pdf" 2>/dev/null)"; rc=$?
  if [ "$rc" -ne 4 ]; then
    bad "$name" "exit $rc, wanted 4"
  elif [ -n "$out" ]; then
    bad "$name" "exit 4 but $(wc -l <<<"$out" | tr -d ' ') line(s) reached stdout"
  else
    ok "$name"
  fi

  # --- 4. PRODUCTION's cap, which is why this case is worth its build time ----
  # The census is deliberately uncapped and cannot see either shipped cap, so if the
  # self-test still passed when `largestImage`'s reach moved, the whole table would be the
  # census agreeing with itself. It does not: exactly one row moves, page 5's, whose `r = 4`
  # dictionary becomes reachable at `depth < 5`.
  mkdir -p "$SB/psrc" && cp "$SB"/Sources/*.swift "$SB/psrc/" && rm -f "$SB/psrc/App.swift"
  sed -i '' 's|            guard depth < 4 else { return }|            guard depth < 5 else { return }|' \
      "$SB/psrc/Flattener.swift"
  if cmp -s "$SB/psrc/Flattener.swift" "$SB/Sources/Flattener.swift"; then
    bad "the largestImage cap sabotage applies" "the depth < 4 guard was not found"
    return
  fi
  local psources=()
  for f in "$SB"/psrc/*.swift; do psources+=("$f"); done
  if ! swiftc -O -o "$SB/drawn-prod" -target "$target" "${psources[@]}" "$SB/h/main.swift" \
       >"$SB/drawn-prod.log" 2>&1; then
    bad "the cap-sabotaged build compiles" \
        "$(grep -m1 'error:' "$SB/drawn-prod.log" || echo "see $SB/drawn-prod.log")"
    return
  fi

  name="loosening largestImage's own depth cap reds the tool's self-test, at p5 alone"
  out="$("$SB/drawn-prod" --self-test 2>&1 >/dev/null)"; rc=$?
  if [ "$rc" -ne 4 ]; then
    bad "$name" "exit $rc, wanted 4: $(tail -1 <<<"$out")"
  elif ! grep -q 'census p5 largestImage answers nothing' <<<"$out"; then
    bad "$name" "exit 4 but not by p5's dictionary answer: $(head -2 <<<"$out" | tr '\n' ' ')"
  # ⚠️ ANCHORED, and the first draft of this row was not: a bare `grep -c FAIL` also matches
  # the tool's own `SELF-TEST FAILED: 1 of 46 checks` summary line, so it read 2 and reported
  # a defect that was its own. Measured by hitting it — suspect the instrument first.
  elif [ "$(grep -c '^  FAIL' <<<"$out")" -ne 1 ]; then
    bad "$name" "$(grep -c '^  FAIL' <<<"$out") rows red, wanted exactly 1"
  else
    ok "$name"
  fi

  # --- 5. the inverse row, CONTRIBUTING §4d -----------------------------------
  # A tool that refused everything would pass every row above. This asserts the census
  # produced a NON-TRIVIAL answer on a real file: `withinCap 1 1` on a page whose only
  # structure is one bare form, with both shipped walks answering 900 beside it.
  name="…and a clean build reads the bare-form page as withinCap, formDepth 1, bareDepth 1"
  out="$("$tool" "$SB/bare-form.pdf" 2>/dev/null)"; rc=$?
  fields="$(awk -F'\t' 'NR==2 { print NF"|"$14"|"$15"|"$16"|"$4"|"$8 }' <<<"$out")"
  if [ "$rc" -ne 0 ]; then
    bad "$name" "exit $rc"
  elif [ "$fields" != "16|1|1|withinCap|900|900" ]; then
    bad "$name" "NF|formDepth|bareDepth|nestVerdict|dictWidth|drawnWidth read \"$fields\", wanted 16|1|1|withinCap|900|900"
  else
    ok "$name"
  fi

  # Same reason as `argv_writers` and `text_voids`: `mrc_refuses` clears the script's EXIT
  # trap, so on a full run nothing else removes this sandbox — and it holds a whole-repo
  # rsync plus three binaries linked against all of `Sources/`.
  rm -rf "$SB"
}

FAULTS="relocate build_continues missing_licence detach_fails helper mrc_refuses argv_writers text_voids drawn_census"

if [ "${1:-}" = "--list" ]; then
  for f in $FAULTS; do echo "  $f"; done; exit 0
fi

WANTED="${1:-}"
echo "fault injection — each case breaks one thing and checks the build notices"
for f in $FAULTS; do
  [ -n "$WANTED" ] && [ "$f" != "$WANTED" ] && continue
  printf '\n%s\n' "$f:"
  "fault_$f"
done

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
