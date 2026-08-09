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

Runs in a throwaway git worktree, so the working tree is never touched and an
interrupted run leaves nothing behind. Results append to Tools/mutation-log.tsv;
re-running skips mutants already recorded, so a campaign can be stopped and
resumed.
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
    # Flattener — routing, resolution and the crash guards
    ("Flattener.swift", "pictureInkThreshold", "0.15", "0.9"),
    ("Flattener.swift", "pictureToneThreshold", "0.12", "0.9"),
    ("Flattener.swift", "pictureSaturationThreshold", "0.06", "0.9"),
    ("Flattener.swift", "minimumPlausibleScanDPI", "150", "10"),
    ("Flattener.swift", "fallbackRebuildDPI", "300", "72"),
    ("Flattener.swift", "minimumScanPixelWidth", "600", "10"),
    ("Flattener.swift", "maximumPageMegapixels", "400", "40000"),
    ("Flattener.swift", "maximumDeclaredImageSide", "200_000", "20_000_000_000"),
    ("Flattener.swift", "maximumThumbnailEdge", "4_000", "4_000_000"),
]

# Single-token logic edits in code written to close a defect. Each one undoes a
# specific decision the register records, so each SHOULD be caught.
OPERATORS = [
    ("SearchableWriter.swift", "guard depth < maximumOutlineDepth, budget > 0 else { return nil }",
     "guard depth < 4_000_000, budget > 0 else { return nil }", "R23-readOutline-bound"),
    ("SearchableWriter.swift", "guard !isSameVisualLine(me, other, in: box) else { continue }",
     "if false { continue }", "C20-headroom-sameline"),
    ("SearchableWriter.swift", "guard isSameVisualLine(me, other, in: box) else { continue }",
     "if false { continue }", "C20-rightlimit-sameline"),
    ("Flattener.swift", "guard value.isFinite else { return 0 }",
     "guard true else { return 0 }", "R24-safeInt-finite"),
    ("Flattener.swift", "if let seen = walkedAt[identity], seen <= depth { return }",
     "if walkedAt[identity] != nil { return }", "R25-depth-aware-prune"),
    ("Model.swift", "guard !isCommitted else { return .refusedRunInProgress }",
     "guard !isRunning else { return .refusedRunInProgress }", "U19-add-guard"),
    ("Model.swift", "defer { self.isPreflighting = false }",
     "self.isPreflighting = false", "U21-committed-across-alert"),
    ("Runner.swift", "guard deadline > now else { return 0 }",
     "guard true else { return 0 }", "R30-monotonic-underflow"),
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
    new = not os.path.exists(LOG)
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

    done = {} if args.rerun else already_done()
    todo = [m for m in mutants if m["id"] not in done]
    print(f"{len(mutants)} mutants, {len(mutants) - len(todo)} already recorded, "
          f"{len(todo)} to run — about {len(todo) * 3} minutes")

    work = os.path.join(REPO, "..", "vision-ocr-mutants")
    work = os.path.abspath(work)
    subprocess.run(["git", "-C", REPO, "worktree", "remove", "--force", work],
                   capture_output=True)
    r = subprocess.run(["git", "-C", REPO, "worktree", "add", "-q", "--detach", work, "HEAD"],
                       capture_output=True, text=True)
    if r.returncode != 0:
        print("could not create the worktree:", r.stderr, file=sys.stderr)
        return 2

    try:
        for i, m in enumerate(todo, 1):
            path = os.path.join(work, "Sources", m["file"])
            original = open(path).read()
            mutated, n = re.subn(m["pattern"], m["replacement"], original, count=1)
            if n != 1:
                print(f"[{i}/{len(todo)}] {m['id']:52s} NOT-APPLIED")
                record(m["id"], "NOT-APPLIED", 0, "pattern did not match exactly once")
                continue

            open(path, "w").write(mutated)
            started = time.time()
            proc = subprocess.run(["./run_tests.sh"], cwd=work,
                                  capture_output=True, text=True)
            took = time.time() - started
            open(path, "w").write(original)

            out = proc.stdout + proc.stderr
            # Kept for triage: a verdict without the output behind it is the
            # same kind of unfalsifiable claim this tool exists to find.
            os.makedirs(os.path.join(REPO, "Tools", "mutation-out"), exist_ok=True)
            safe = m["id"].replace("/", "_")
            with open(os.path.join(REPO, "Tools", "mutation-out", safe + ".log"), "w") as fh:
                fh.write(f"exit={proc.returncode}\n\n{out}")
            if "error:" in out and "passed" not in out:
                verdict, detail = "INVALID", "did not compile"
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
        subprocess.run(["git", "-C", REPO, "worktree", "remove", "--force", work],
                       capture_output=True)

    survivors = [k for k, v in already_done().items() if v == "SURVIVED"]
    print(f"\n{len(survivors)} survivor(s)")
    for s in survivors:
        print(f"   {s}")
    return 0


if __name__ == "__main__":
    sys.exit(run())
