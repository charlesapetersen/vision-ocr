#!/usr/bin/env python3
"""Change something in Sources/ that ought to break a check, and see if one breaks.

Why this exists: **nine checks in this project's history have been unable to
fail.** T1's invariant-5 fixture passed twice against a deliberately reintroduced
bug, the crop-box test asserted a page size the bug could not move, and the
2026-08-09 rounds added six more — R25's depth fixture, U20's timing bound and
main-thread read, U20's clock comparison, U18's "normal case" that never entered
the function, C20's probe twice over. Every one was found by hand, by putting the
defect back and watching. CONTRIBUTING has said to do that since 1.0; doing it
reliably is what a person is worst at.

So: do it mechanically. Each mutant is a single edit that a *correct* suite
should notice. A mutant the suite still passes is either a gap in the checks or a
constant nothing depends on — and knowing which is which is the point.

    python3 Tools/mutate.py --list
    python3 Tools/mutate.py                  # the whole catalogue, sequentially
    python3 Tools/mutate.py --only headroom  # one substring of the mutant id

**Sequential on purpose.** Each run is two to four minutes of real OCR, and the
suite contains real timing assertions (the login-shell bounds, "came back
promptly"). Several suites at once make those flaky, and a flaky check reports a
mutant as KILLED when the suite merely tripped over the load — a false negative
in the one tool whose job is finding false negatives.

Runs against a **copy of the working tree**, so the tree itself is never touched
and an interrupted run leaves nothing behind. It copies what is on disk, not
`HEAD`: the first version used `git worktree add --detach HEAD` and cheerfully
reported eight survivors against the previous commit while the checks written to
kill them sat uncommitted three feet away. A tool that silently measures
something other than what you are holding is worse than no tool.

The baseline is run first and must be green; every verdict is relative to it, and
a mutant whose run reports a different number of checks than the baseline is
flagged rather than believed.

Results append to Tools/mutation-log.tsv; re-running skips mutants already
recorded, so a campaign can be stopped and resumed.
"""
import argparse, json, os, re, shutil, subprocess, sys, time

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOG = os.path.join(REPO, "Tools", "mutation-log.tsv")

# ---------------------------------------------------------------- the catalogue

# Constants whose doc comments say "measured" or "calibrated". If one of these
# can be moved without a check going red, either the calibration is unguarded or
# the constant does not matter — both worth knowing. The replacement is a
# *meaningful* perturbation, not a rounding: enough to change behaviour a person
# would notice, so a survivor cannot be blamed on the step being too small.
CONSTANTS = [
    # SearchableWriter — the text layer, invariant 3's four properties
    ("SearchableWriter.swift", "baselineFraction", "0.22", "0.40"),
    ("SearchableWriter.swift", "headroomFactor", "1.5", "0.95"),
    ("SearchableWriter.swift", "reserveEms", "0.25", "0.0"),
    ("SearchableWriter.swift", "minimumVertical", "0.25", "0.5"),
    ("SearchableWriter.swift", "sameLineBaselineFraction", "0.4", "0.05"),
    ("SearchableWriter.swift", "duplicateBaselineFraction", "0.3", "1.0"),
    ("SearchableWriter.swift", "maximumOutlineDepth", "32", "4000"),
    # Rejoining words broken across a line. edgeOfPage was guessed at 0.18 and
    # admitted nothing — the deepest hyphenated line measured sits at 0.82 and
    # 1 - 0.18 is exactly 0.82 — so it is now measured, and worth guarding.
    ("SearchableWriter.swift", "edgeOfPage", "0.25", "0.02"),
    # -1.0, not 0.0: two columns do not merely fail to overlap, they overlap
    # *negatively*, so a floor of zero still refuses them and the mutant
    # survived while testing nothing.
    ("SearchableWriter.swift", "minimumColumnOverlap", "0.6", "-1.0"),
    ("SearchableWriter.swift", "continuationCandidates", "3", "1"),
    ("Model.swift", "sizeNoteRatio", "1.25", "99.0"),
    # Flattener — routing, resolution and the crash guards
    ("Flattener.swift", "pictureInkThreshold", "0.15", "0.9"),
    ("Flattener.swift", "pictureToneThreshold", "0.12", "0.9"),
    # R38's gate. 0.0, not a large value: the defect it closes is the gate being
    # *absent*, and setting the minimum to zero is exactly the absent gate —
    # every ink-triggered page becomes a picture again, including the four that
    # inflated up to 9.45x. A large value tests the opposite failure and the
    # catalogue wants the one the register records.
    ("Flattener.swift", "pictureInkMinimumTone", "0.03", "0.0"),
    ("Flattener.swift", "pictureSaturationThreshold", "0.06", "0.9"),
    # The paper-colour estimate. Drop the floor and every dark pixel counts as
    # paper, so the "paper" is the page mean and the correction removes whatever
    # cast the *content* had; raise the fraction and the correction never runs at
    # all, which is the 709 MB behaviour restored.
    ("Flattener.swift", "paperLuminanceFloor", "176.0", "10.0"),
    ("Flattener.swift", "minimumPaperFraction", "0.15", "0.99"),
    # Layering holds ~8 bytes a pixel against the render's 5.5, so it needs its
    # own bound. R29 is what happens when a sibling allocation does not get one.
    ("Flattener.swift", "maximumMRCPageMegapixels", "100", "40000"),
    ("Flattener.swift", "minimumPlausibleScanDPI", "150", "10"),
    ("Flattener.swift", "fallbackRebuildDPI", "300", "72"),
    ("Flattener.swift", "minimumScanPixelWidth", "600", "10"),
    ("Flattener.swift", "maximumPageMegapixels", "400", "40000"),
    ("Flattener.swift", "maximumDeclaredImageSide", "200_000", "20_000_000_000"),
    ("Flattener.swift", "maximumThumbnailEdge", "4_000", "4_000_000"),
    # R40. The bound on a silent helper. Made small rather than large: the
    # failure worth guarding is the app giving up on a helper that is merely
    # working, which sends every document round a second time in-process and
    # hands back exactly the 2.5x R40 exists to remove. The parity check notices,
    # because it asserts recognition did *not* fall back.
    ("Recogniser.swift", "helperStallSeconds", "900.0", "0.001"),
]

# Single-token logic edits in code written to close a defect. Each one undoes a
# specific decision the register records, so each SHOULD be caught.
OPERATORS = [
    # Two sites, identical text: readOutline's convert and copyOutline's
    # rebuild. One pattern covered both and silently mutated only the first, so
    # R23's own mirror — the whole point of R23 — was never perturbed (T7). Each
    # is now anchored to its function's return type.
    ("SearchableWriter.swift",
     "-> OutlineItem? {\n            guard depth < maximumOutlineDepth, budget > 0 else { return nil }",
     "-> OutlineItem? {\n            guard depth < 4_000_000, budget > 0 else { return nil }",
     "R19-readOutline-bound"),
    ("SearchableWriter.swift",
     "-> PDFOutline? {\n            guard depth < maximumOutlineDepth, budget > 0 else { return nil }",
     "-> PDFOutline? {\n            guard depth < 4_000_000, budget > 0 else { return nil }",
     "R23-copyOutline-bound"),
    ("SearchableWriter.swift", "guard !isSameVisualLine(me, other, in: box) else { continue }",
     "if false { continue }", "C20-headroom-sameline"),
    ("SearchableWriter.swift", "guard isSameVisualLine(me, other, in: box) else { continue }",
     "if false { continue }", "C20-rightlimit-sameline"),
    # `guard true else` is a compile error in Swift, so the removal has to be
    # spelled as a no-op branch. The first attempt was recorded INVALID, which is
    # the harness reporting honestly rather than scoring an untested mutant.
    ("Flattener.swift", "guard value.isFinite else { return 0 }",
     "if !value.isFinite && false { return 0 }", "R24-safeInt-finite"),
    # MRC. The stencil polarity cannot be reasoned out from the specification —
    # inverted, the foreground shows everywhere except the text and the page
    # floods solid, which no page count can see. In OPERATORS rather than
    # CONSTANTS because the constant pattern anchors on \b, which cannot match
    # after a closing quote: the first attempt was recorded NOT-APPLIED, the
    # harness declining to score a mutant it had not actually planted.
    ("JBIG2.swift", 'static let maskDecode = "[ 1 0 ]"',
     'static let maskDecode = "[ 0 1 ]"', "mrc-stencil-polarity"),
    # R39's mutant lived here, and it is gone with the code it perturbed: the
    # DPI negotiation existed only to talk to a subprocess that re-rasterised our
    # PDF, and recognition is in process now. Its replacement is the language
    # detection flag, which is the one request property where *leaving it alone*
    # is wrong — with no language named, Vision falls back to a default list
    # instead of detecting, which no character count on English material would
    # notice.
    # R40. Which batches get helper processes. Widened rather than removed: a
    # helper for a single file is the case the measurement rejected — it pays
    # Vision's ~0.20s start-up twice and overlaps with nothing — and "always on"
    # is the mistake a reader of this code is most likely to make.
    ("Recogniser.swift", "concurrency > 1 && files > 1", "concurrency > 0 && files > 0",
     "R40-helper-eligibility"),
    ("Recogniser.swift",
     "request.automaticallyDetectsLanguage = languages.isEmpty",
     "request.automaticallyDetectsLanguage = false",
     "detects-language-when-none-named"),
    # R38. The gate itself, not its constant. The drift guard in T5 kills any
    # edit to `pictureInkMinimumTone` for free — it asserts the literal — so a
    # constant mutant proves nothing about whether anything *reads* it. This one
    # plants the original defect: ink alone routes a page to pictures again.
    ("Flattener.swift", "if tone > pictureInkMinimumTone,\n           inkCoverage(",
     "if true,\n           inkCoverage(", "R38-ink-needs-tone"),
    ("Flattener.swift", "if let seen = walkedAt[identity], seen <= depth { return }",
     "if walkedAt[identity] != nil { return }", "R25-depth-aware-prune"),
    ("Model.swift", "guard !isCommitted else { return .refusedRunInProgress }",
     "guard !isRunning else { return .refusedRunInProgress }", "U19-add-guard"),
    # T10 / A11.1. The tenth un-failable check guarded exactly this, and deleting
    # the gate it named left the suite 862/862 green. Run by hand before the
    # catalogue got it: 3 checks red, and the good file at the destination went
    # from 107,847 bytes to 809.
    ("Model.swift",
     "        if let refusal = incompleteRefusal(staged, expecting: expected) {\n"
     "            throw Failure.incompleteResult(refusal)\n        }\n"
     "        try publish(staged, to: output)",
     "        try publish(staged, to: output)", "A11.1-publishVerified-gate"),
    # R60. Content destruction: without the carried-forward reservations a retry
    # claims the path the batch it came from reserved away from it. The unit checks
    # pass `alsoClaimed`/`releasing` explicitly and would survive this, which is
    # why the end-to-end check exists — it is what goes red, on the user's file.
    ("Model.swift", "alsoClaimed: claimedByEarlierAttempts, releasing: releasing)",
     "alsoClaimed: [], releasing: [])", "R60-retry-reservations"),
    ("Model.swift", "defer { self.isPreflighting = false }",
     "self.isPreflighting = false", "U21-committed-across-alert"),
    # R64 / A4.1. Puts the document's own text back into the message that goes into
    # a file the user is invited to mail to someone. Run by hand before the
    # catalogue got it: 2 checks red, and the failure detail printed the excerpt.
    ("Model.swift", '.map { "p\\($0.page) (\\($0.reason))" }',
     '.map { "p\\($0.page) \\"\\($0.text.prefix(24))\\" (\\($0.reason))" }',
     "A4.1-unplaced-carries-text"),
    ("Runner.swift", "guard deadline > now else { return 0 }",
     "guard true else { return 0 }", "R30-monotonic-underflow"),
    # The bundled compression tools are single-architecture, so this check is
    # what keeps an arm64-only jbig2 from being handed to an Intel Mac.
    ("Runner.swift", "return isRunnable(path) && containsNativeSlice(path) ? path : nil",
     "return isRunnable(path) ? path : nil", "bundle-arch-check"),
    ("Runner.swift", "case 0xcffa_edfe, 0xcefa_edfe:                     // little-endian file\n            return word(4, bigEndian: false) == native",
     "case 0xcffa_edfe, 0xcefa_edfe:\n            return word(4, bigEndian: true) == native", "bundle-arch-endianness"),
    # R61. The two conversions safeInt did not cover, and the two clamps around
    # them. Each of these four plants a *trap*, so the check that dies is the
    # `--probe-hostile-numbers` child — which is the point of running the hostile
    # calls out of process: a mutant that takes the suite down instead of failing
    # a check is a mutant whose verdict nobody can read.
    ("Flattener.swift", "let quarterInch = safeInt(dpi / 4)",
     "let quarterInch = Int(dpi / 4)", "A7.1-sauvola-window-safeint"),
    # The fix must not also be a threshold change. This mutant is the first version
    # of the fix as written, caught in review: rounding moves the shipped window by a
    # pixel on about half of all pages, which no trap test would ever notice.
    ("Flattener.swift", "let quarterInch = safeInt(dpi / 4)",
     "let quarterInch = safeInt((dpi / 4).rounded())", "A7.1-sauvola-window-truncates"),
    ("Flattener.swift", "return min(max(quarterInch, 3), ceiling)",
     "return max(quarterInch, 3)", "A7.1-sauvola-window-ceiling"),
    ("Flattener.swift", "let r = min(max(window / 2, 1), max(w, h))",
     "let r = max(window / 2, 1)", "A7.1-sauvola-radius-bound"),
    ("Flattener.swift",
     "guard b.x.isFinite, b.y.isFinite, b.width.isFinite, b.height.isFinite\n            else { continue }",
     "if false { continue }", "A3.2-textregion-finite"),
    # R62. Numerator and denominator from one population. The mutant restores the
    # 10.0-coverage version, which no page count and no routing decision on today's
    # callers would notice — which is why it is here rather than trusted to a
    # caller that happens to protect it.
    ("Flattener.swift", "let pixels = min(grey.count, width * height)",
     "let pixels = grey.count", "A7.2-inkcoverage-population"),
]


def catalogue():
    out = []
    for f, name, old, new in CONSTANTS:
        out.append({
            "id": f"const/{name}", "file": f, "kind": "constant",
            # Anchored to the declaration so a bare number elsewhere is not hit.
            "pattern": rf"(static (?:var|let) {re.escape(name)}[^=\n]*=\s*){re.escape(old)}\b",
            "replacement": rf"\g<1>{new}",
            "note": f"{old} -> {new}",
        })
    for f, old, new, label in OPERATORS:
        out.append({
            "id": f"logic/{label}", "file": f, "kind": "logic",
            "pattern": re.escape(old), "replacement": new.replace("\\", "\\\\"),
            "note": label,
        })
    return out


# ------------------------------------------------------------------- the runner

def already_done():
    if not os.path.exists(LOG):
        return {}
    done = {}
    with open(LOG) as fh:
        for line in fh:
            parts = line.rstrip("\n").split("\t")
            if len(parts) >= 2 and parts[0] != "mutant":
                done[parts[0]] = parts[1]
    return done


def record(mid, verdict, seconds, detail):
    # Empty counts as new, not just absent. Truncating the log to start a fresh
    # campaign (`: > Tools/mutation-log.tsv`) left it headerless, so the first
    # record looked like the header to anything reading it with `tail -n +2`.
    new = not os.path.exists(LOG) or os.path.getsize(LOG) == 0
    with open(LOG, "a") as fh:
        if new:
            fh.write("mutant\tverdict\tseconds\tdetail\n")
        fh.write(f"{mid}\t{verdict}\t{seconds:.0f}\t{detail}\n")


def run(argv=None):
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--list", action="store_true", help="print the catalogue and stop")
    ap.add_argument("--only", default="", help="run mutants whose id contains this")
    ap.add_argument("--rerun", action="store_true", help="ignore the existing log")
    args = ap.parse_args(argv)

    mutants = [m for m in catalogue() if args.only in m["id"]]
    if args.list:
        for m in mutants:
            print(f"{m['id']:52s} {m['file']:24s} {m['note']}")
        print(f"\n{len(mutants)} mutants")
        return 0

    # Only a real verdict counts as done. Treating any logged row as recorded
    # meant a mutant whose pattern stopped matching after a refactor was skipped
    # for ever, and every later run printed a clean bill of health for a
    # catalogue it had quietly stopped applying (T7).
    VERDICTS = ("SURVIVED", "killed")
    done = {} if args.rerun else already_done()
    todo = [m for m in mutants if done.get(m["id"]) not in VERDICTS]
    print(f"{len(mutants)} mutants, {len(mutants) - len(todo)} already recorded, "
          f"{len(todo)} to run — about {len(todo) * 3} minutes")

    # A copy of what is on disk right now. Not `git worktree add HEAD`: that
    # tests the last commit, which is not what anyone means by "does my suite
    # catch this".  testdocs is 1.2 GB and the suite builds its own fixtures.
    work = os.path.abspath(os.path.join(REPO, "..", "vision-ocr-mutants"))
    shutil.rmtree(work, ignore_errors=True)
    os.makedirs(work)
    r = subprocess.run(["rsync", "-a",
                        "--exclude", ".git", "--exclude", "build",
                        "--exclude", "testdocs", "--exclude", "Tools/mutation-out",
                        REPO + "/", work + "/"], capture_output=True, text=True)
    if r.returncode != 0:
        print("could not copy the tree:", r.stderr, file=sys.stderr)
        return 2

    def suite(where):
        proc = subprocess.run(["./run_tests.sh"], cwd=where, capture_output=True, text=True)
        out = proc.stdout + proc.stderr
        total = None
        for line in out.splitlines():
            t = line.strip()
            if t.endswith("passed") and "/" in t:
                try: total = int(t.split("/")[1].split()[0])
                except ValueError: pass
        return proc, out, total

    print("baseline:", end=" ", flush=True)
    _, base_out, baseline = suite(work)
    if baseline is None or "FAIL" in base_out:
        print("the suite is not green before mutating; fix that first", file=sys.stderr)
        shutil.rmtree(work, ignore_errors=True)
        return 2
    print(f"{baseline} checks, green")

    try:
        for i, m in enumerate(todo, 1):
            path = os.path.join(work, "Sources", m["file"])
            original = open(path).read()
            # Count first. `subn(..., count=1)` returns at most 1, so testing its
            # result only ever caught *zero* matches — a pattern hitting two
            # sites mutated the first and reported a normal verdict. That was
            # live: the R23 pattern matched readOutline's bound AND copyOutline's
            # identical one, so the log claimed coverage of a bound that had
            # never been perturbed (T7).
            hits = len(re.findall(m["pattern"], original))
            if hits != 1:
                why = "pattern matched nothing" if hits == 0 else f"pattern matched {hits} sites — ambiguous"
                print(f"[{i}/{len(todo)}] {m['id']:52s} NOT-APPLIED   {why}")
                record(m["id"], "NOT-APPLIED", 0, why)
                continue
            mutated, _ = re.subn(m["pattern"], m["replacement"], original, count=1)

            open(path, "w").write(mutated)
            started = time.time()
            proc, out, total = suite(work)
            took = time.time() - started
            open(path, "w").write(original)
            # Kept for triage: a verdict without the output behind it is the
            # same kind of unfalsifiable claim this tool exists to find.
            os.makedirs(os.path.join(REPO, "Tools", "mutation-out"), exist_ok=True)
            safe = m["id"].replace("/", "_")
            with open(os.path.join(REPO, "Tools", "mutation-out", safe + ".log"), "w") as fh:
                fh.write(f"exit={proc.returncode}\n\n{out}")
            # A *compile* error, specifically. Matching bare "error:" mislabelled
            # a mutant that trapped at runtime — the trap prints "Fatal error:
            # Double value cannot be converted to Int" — as INVALID, i.e. scored
            # a genuine kill as "the mutation was malformed". Wrong in the
            # direction that flatters the suite.
            if re.search(r"\.swift:\d+:\d+: error:", out):
                verdict, detail = "INVALID", "did not compile"
            elif proc.returncode == 0 and total != baseline:
                # The mutant compiled and the suite passed, but a different
                # number of checks ran — so this is not the suite we calibrated
                # against and the verdict means nothing.
                verdict, detail = "MISMATCH", f"{total} checks, baseline was {baseline}"
            elif proc.returncode == 0:
                verdict = "SURVIVED"
                detail = next((l.strip() for l in out.splitlines()
                               if l.strip().endswith("passed")), "suite green")
            else:
                verdict = "killed"
                fails = [l.strip()[5:].strip().split(" — ")[0]
                         for l in out.splitlines() if l.strip().startswith("FAIL")]
                if fails:
                    detail = f"{len(fails)} check(s): " + "; ".join(fails[:3])
                else:
                    # Nonzero exit with no FAIL line is a crash or a hang, which
                    # counts as killed but for a different reason worth seeing.
                    tail = [l.strip() for l in out.splitlines() if l.strip()][-1:]
                    detail = f"exit {proc.returncode}, no FAIL line: " + (tail[0][:60] if tail else "no output")
            mark = "  <-- SURVIVED" if verdict == "SURVIVED" else ""
            print(f"[{i}/{len(todo)}] {m['id']:52s} {verdict:9s} {took:5.0f}s  {detail[:70]}{mark}",
                  flush=True)
            record(m["id"], verdict, took, detail)
    finally:
        shutil.rmtree(work, ignore_errors=True)

    final = already_done()
    survivors = [k for k, v in final.items() if v == "SURVIVED"]
    unevaluated = [k for k, v in final.items() if v not in ("SURVIVED", "killed")]
    print(f"\n{len(survivors)} survivor(s)")
    for k in survivors:
        print(f"   {k}")
    if unevaluated:
        # Loud, because a mutant that never ran is not evidence of anything and
        # must not be read as one.
        print(f"\n{len(unevaluated)} mutant(s) NOT EVALUATED — no verdict, not a clean result:")
        for k in unevaluated:
            print(f"   {k}: {final[k]}")
    return 0


if __name__ == "__main__":
    sys.exit(run())
