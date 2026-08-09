#!/usr/bin/env python3
"""Copy a Homebrew tool and everything it links into the app, and relocate it.

`mac-ocr` could simply be copied: it links nothing but system frameworks. The
compression tools cannot. `jbig2` pulls in leptonica and its image codecs;
`qpdf` pulls in libqpdf and OpenSSL. Copying the executable alone produces a
binary that dies at launch looking for `/opt/homebrew/...`, on exactly the
machines that do not have Homebrew — which is to say the ones this is for.

So: walk the dependency closure, copy it into `Contents/Resources/lib`, and
rewrite every install name to `@loader_path`, so each file finds its neighbours
wherever the app is dragged.

    python3 Tools/bundle-libs.py <path-to-.app> jbig2 qpdf

Exits non-zero if a tool is missing, so `build.sh` can decide whether that is
fatal. It is not: without these the app writes larger files and says so.

Licences are copied in beside the binaries. Everything here is permissive —
Apache-2.0 (qpdf, OpenSSL, jbig2enc), BSD (leptonica, libtiff, libwebp,
openjpeg, zstd, libpng), MIT (giflib), 0BSD (liblzma; the LGPL parts of xz are
the command line tools, which are not shipped). jbig2enc also carries a PATENTS
notice, and it is copied verbatim rather than summarised.
"""
import os, shutil, subprocess, sys

SYSTEM = ("/usr/lib/", "/System/")
HOMEBREW = "/opt/homebrew"

# Where a licence lives, per Cellar formula, when the name is not obvious.
LICENCE_NAMES = ("LICENSE", "LICENSE.txt", "LICENSE.md", "COPYING", "COPYING.txt",
                 "LICENSE.rst", "COPYRIGHT")


def real(path):
    return os.path.realpath(path)


def dependencies(path):
    """Non-system libraries this Mach-O links, as (recorded, resolved) pairs.

    Both halves matter. The resolved path is what to copy; the **recorded** name
    is what `install_name_tool -change` has to match, and the two differ
    routinely — qpdf records `@rpath/libqpdf.30.dylib`, a versioned symlink,
    while the file itself is `libqpdf.30.3.2.dylib`. Matching on the resolved
    name silently changed nothing, and the copied qpdf died at launch looking
    for an @rpath that was no longer there.
    """
    out = subprocess.run(["otool", "-L", path], capture_output=True, text=True).stdout
    found = []
    for line in out.splitlines()[1:]:
        recorded = line.strip().split(" (")[0]
        if recorded.startswith(SYSTEM) or recorded.startswith("@loader_path"):
            continue
        if recorded.startswith("@executable_path"):
            continue
        resolved = recorded
        if recorded.startswith("@rpath/"):
            resolved = os.path.join(HOMEBREW, "lib", recorded[len("@rpath/"):])
        if os.path.exists(resolved):
            found.append((recorded, real(resolved)))
    return found


def closure(binary):
    seen, stack = {}, [real(binary)]
    while stack:
        f = stack.pop()
        if f in seen:
            continue
        seen[f] = True
        stack.extend(r for _, r in dependencies(f) if r not in seen)
    del seen[real(binary)]
    return sorted(seen)


def formula_of(path):
    """The Cellar formula directory a file came from, for its licence."""
    marker = os.path.join(HOMEBREW, "Cellar") + os.sep
    if not path.startswith(marker):
        return None
    rest = path[len(marker):].split(os.sep)
    return os.path.join(marker, rest[0], rest[1]) if len(rest) >= 2 else None


# Packages whose Homebrew keg ships no licence file. The text has to come from
# somewhere, so it lives here, verbatim from the project's own source, rather
# than being silently omitted — which is what happened to leptonica in every
# disk image from 1.5.0 until H2 (BSD-2-Clause clause 2 requires reproducing the
# notice in a binary redistribution).
VENDORED_LICENCES = {
    "leptonica": """Copyright (C) 2001-2020 Leptonica.  All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions
are met:
1. Redistributions of source code must retain the above copyright
   notice, this list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above
   copyright notice, this list of conditions and the following
   disclaimer in the documentation and/or other materials
   provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL ANY
CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY
OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
""",
}


def copy_licences(paths, dest):
    """Returns the formulae for which a notice was actually written.

    Not the formulae *encountered*: the count printed at the end used to be the
    latter, so it could not drop when a notice went missing, and leptonica
    shipped unnoticed in every image from 1.5.0 (H2).
    """
    seen, written = set(), set()
    for p in paths:
        formula = formula_of(p)
        if not formula or formula in seen:
            continue
        seen.add(formula)
        name = os.path.basename(os.path.dirname(formula))
        for entry in sorted(os.listdir(formula)):
            if entry.upper().startswith(("LICENSE", "COPYING", "COPYRIGHT")):
                shutil.copy2(os.path.join(formula, entry),
                             os.path.join(dest, f"{name}-{entry}"))
                written.add(formula)
        if formula not in written and name in VENDORED_LICENCES:
            with open(os.path.join(dest, f"{name}-LICENSE"), "w") as fh:
                fh.write(VENDORED_LICENCES[name])
            written.add(formula)
        # jbig2enc's patent notice travels verbatim; summarising it is not ours
        # to do.
        for root, _, files in os.walk(os.path.join(formula, "share", "doc")):
            for f in files:
                if "PATENT" in f.upper():
                    shutil.copy2(os.path.join(root, f), os.path.join(dest, f"{name}-{f}"))
    return sorted(written), sorted(seen - written)


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 2
    app, tools = argv[1], argv[2:]

    resources = os.path.join(app, "Contents", "Resources")
    libdir = os.path.join(resources, "lib")
    notices = os.path.join(resources, "third-party-licences")

    binaries = {}
    for tool in tools:
        found = shutil.which(tool, path=f"{HOMEBREW}/bin:/usr/local/bin:/opt/local/bin")
        if not found:
            print(f"    {tool}: not installed", file=sys.stderr)
            return 1        # benign: build.sh carries on without them
        binaries[tool] = real(found)

    everything = set()
    for tool, path in binaries.items():
        everything.add(path)
        everything.update(closure(path))

    os.makedirs(libdir, exist_ok=True)
    os.makedirs(notices, exist_ok=True)

    # Copy: executables into Resources, libraries into Resources/lib.
    placed = {}
    for src in sorted(everything):
        tool = next((t for t, p in binaries.items() if p == src), None)
        dst = os.path.join(resources, tool) if tool else os.path.join(libdir, os.path.basename(src))
        shutil.copy2(src, dst)
        os.chmod(dst, 0o755)
        placed[src] = dst

    def rewrite(*args):
        """install_name_tool, with its exit code actually looked at.

        Discarding it via capture_output was how a relocation could fail while
        the copy stayed in the bundle and the build reported success (R31).
        """
        r = subprocess.run(["install_name_tool", *args], capture_output=True, text=True)
        if r.returncode != 0:
            failures.append(" ".join(args[:2]) + ": " + r.stderr.strip().splitlines()[-1:][0]
                            if r.stderr.strip() else " ".join(args[:2]))
        return r.returncode == 0

    failures = []

    # Relocate. An executable's libraries sit in lib/ beside it; a library's
    # neighbours sit next to itself. @loader_path means "relative to whoever is
    # doing the loading", which is right in both cases.
    for src, dst in placed.items():
        is_tool = os.path.dirname(dst) == resources
        rewrite("-id", os.path.basename(dst), dst)
        for recorded, dep in dependencies(src):
            if dep not in placed:
                continue
            prefix = "@loader_path/lib/" if is_tool else "@loader_path/"
            new = prefix + os.path.basename(placed[dep])
            rewrite("-change", recorded, new, dst)
        # An LC_RPATH pointing into Homebrew would let a machine that HAS
        # Homebrew load those copies instead of ours, so the bundle would behave
        # differently on the developer's machine than on anyone else's.
        out = subprocess.run(["otool", "-l", dst], capture_output=True, text=True).stdout
        for line in out.splitlines():
            line = line.strip()
            if line.startswith("path ") and HOMEBREW in line:
                rewrite("-delete_rpath", line.split("path ")[1].split(" (")[0], dst)

    # Declared before the licence check, which contributes to it.
    stale = []

    formulae, unlicensed = copy_licences(everything, notices)
    if unlicensed:
        # Redistributing a binary with no notice is a compliance failure, so it
        # stops the build rather than printing a number that looks right.
        for f in unlicensed:
            print(f"    no licence found for {os.path.basename(os.path.dirname(f))} ({f})",
                  file=sys.stderr)
        print("    add its text to VENDORED_LICENCES in Tools/bundle-libs.py",
              file=sys.stderr)
        stale.append("missing licence")

    # Verify rather than assume: nothing may still point at Homebrew.
    for dst in placed.values():
        out = subprocess.run(["otool", "-L", dst], capture_output=True, text=True).stdout
        for line in out.splitlines()[1:]:
            lib = line.strip().split(" (")[0]
            # An unrewritten @rpath is just as fatal as a Homebrew path, and
            # less obvious: it fails only on a machine without the library.
            if HOMEBREW in lib or lib.startswith("@rpath/"):
                stale.append(f"{os.path.basename(dst)} -> {lib}")
    if failures:
        stale = [f"install_name_tool failed: {f}" for f in failures] + stale

    if stale:
        # Take back everything that was copied. Leaving it meant build.sh's
        # handler printed "not bundled" over a bundle that contained broken
        # helpers — and locateTool prefers the bundled copy, so the app used
        # them in preference to a working Homebrew install (R31).
        for dst in placed.values():
            try: os.remove(dst)
            except OSError: pass
        shutil.rmtree(libdir, ignore_errors=True)
        shutil.rmtree(notices, ignore_errors=True)
        print("    bundling failed; removed what had been copied:", file=sys.stderr)
        for s in stale[:8]:
            print("      " + s, file=sys.stderr)
        # 3, not 1: build.sh treats "not installed" (1) as benign and this as
        # fatal. One exit code for both was the other half of R31.
        return 3

    size = sum(os.path.getsize(d) for d in placed.values()) / 1e6
    archs = subprocess.run(["lipo", "-archs", placed[binaries[tools[0]]]],
                           capture_output=True, text=True).stdout.strip()
    print(f"    {len(placed)} file(s), {size:.1f} MB, {archs}")
    print(f"    licences for {len(formulae)} package(s) in third-party-licences/")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
