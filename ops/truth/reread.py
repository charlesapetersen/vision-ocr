#!/usr/bin/env python3
"""The blind re-read of `truth-harness` (QUEUE.md): a word counts against the app only once a fresh check
reader, shown a tight crop of it and nothing else, reads what the transcript says.

    ops/truth/reread.py select <W>         which rows of <W>/score/d<N>/truth-words.tsv to re-read
    ops/truth/reread.py crops  <W> <bin>   render those pages again (<bin>/render-page) and cut word crops
    ops/truth/reread.py briefs <W>         shuffled briefs of 45 crops, the CHECK prompt verbatim
    ops/truth/reread.py sheets <W>         the crops no brief read, on numbered contact sheets, 4 to a brief
    ops/truth/reread.py wide   <W> <bin>   a `nearest` crop whose reading disagrees: cut it again wider
    ops/truth/reread.py sheets <W> wide    the wide crops on sheets of their own (`reread/wide-sheets/`)
    ops/truth/reread.py apply  <W>         readings -> contested-harness.tsv in each truth page, and a log

<W> is an `ops/truth/run-harness.sh` run. Every row is re-read on a page whose verdict a re-read could
change, and every Find row. A page red on copy whatever the re-read says (even if every wrong and missing
word were contested and each took up one added copy word, copyErr stays over 0.05) has a seeded sample of
100 rows per class re-read instead, so its word counts carry a measured transcript-error rate.
A reading that differs from the transcript (case, punctuation and superscripts folded as `contest.py`
folds them; both halves of a word joined across a line-end hyphen) or is `?`, or a crop with no reading,
contests the word. A `nearest` crop (`wordcrops.py` could not split the line into its words, and cut the
ink run nearest the word's estimated place) disagrees 38% of the time against 6% for an `exact` one, mostly
by cutting the wrong run or half a word, so where one disagrees its word is cut again with a word either
side (`wide`), and that reading decides instead. A contested word goes into `contested-harness.tsv` in the
page's `$STATE/truth/` directory, which `ux-harness --truth` reads beside `contested.tsv`. The check never replaces a word, as in procedure v2: a single
word read off a 1-bit crop copies broken glyphs. Output in <W>/reread/, never committed.
"""
import glob, os, random, re, shutil, subprocess, sys, collections
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import xcheck

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
STATE = os.environ.get("VISIONOCR_STATE", os.path.expanduser("~/.local/state/visionocr-autonomous"))
SAMPLE, BRIEF = 100, 45
SUP = str.maketrans("⁰¹²³⁴⁵⁶⁷⁸⁹", "0123456789")
fold = lambda w: re.sub(r"[^\w]", "", w.translate(xcheck.TR).translate(SUP)).lower()


def jobs(W):
    j = {}
    for line in open(f"{W}/jobs.txt", encoding="utf-8"):
        f = line.rstrip("\n").split("\t")
        j[f"d{f[1]}"] = (f[2], f[4].split(","))
    return j


def truth_rows(W):
    """(doc, original page) -> the truth row of results.tsv, as a dict"""
    TH = "trWords contested scored right wrong missing added splits welds hyph copyErr find order fig hand visMiss layerMiss pairs elInk elCol tflags".split()
    out = {}
    for line in open(f"{W}/results.tsv", encoding="utf-8"):
        f = line.rstrip("\n").split("\t")
        if f[0] == "truth": out[(f[1], f[2][1:])] = dict(zip(TH, f[3:]))
    return out


def certain(T):
    """red on copy whatever a re-read of its words finds"""
    S, W_, M, A = (int(T[k]) for k in ("scored", "wrong", "missing", "added"))
    return "tcopy" in T["tflags"] and A - (W_ + M) > 0.05 * (S - W_ - M)


def wclass(kind, word, copy):
    if kind != "wrong": return kind
    a, b = fold(word), fold(copy)
    if a == b: return "fold"
    return "near" if lev(a, b) <= max(1, int(0.4 * max(len(a), len(b)))) else "far"


def lev(a, b):
    prev = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        cur = [i]
        for j, cb in enumerate(b, 1): cur.append(min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (ca != cb)))
        prev = cur
    return prev[-1]


def words(tr):
    """the transcript's words with line-end hyphens joined, as contest.py, wordcrops.py and ux-harness join
    them: (word, first half or None)"""
    out = []
    for (x, y, w, h), t in xcheck.lines(tr):
        for wd in t.split():
            if out and re.search(r"\w-$", out[-1][0]) and y > out[-1][1] and wd[:1].isalnum():
                out[-1] = (out[-1][0][:-1] + wd, out[-1][1], out[-1][0])
            else:
                out.append((wd, y, None))
    return [(w, h) for w, _, h in out]


def select(W):
    J, T = jobs(W), truth_rows(W)
    rows = []
    for f in sorted(glob.glob(f"{W}/score/d*/truth-words.tsv"), key=lambda s: int(s.split("/")[-2][1:])):
        d = f.split("/")[-2]; doc, plist = J[d]
        for line in open(f, encoding="utf-8").read().splitlines()[1:]:
            p, k, kind, word, copy, px = line.split("\t")
            orig = plist[int(p) - 1]
            tdir = os.path.realpath(f"{W}/score/{d}/truth/p{p}")
            cls = wclass(kind, word, copy)
            rows.append([d, p, orig, k, kind, cls, word, copy, px, tdir, "certain" if certain(T[(doc, orig)]) else "full"])
    rng = random.Random(20260930)
    pick = [r for r in rows if r[10] == "full" or r[4] == "find" or r[5] == "fold"]
    for cls in ("far", "near", "missing"):
        pool = [r for r in rows if r[10] == "certain" and r[4] != "find" and r[5] == cls]
        pick += rng.sample(pool, min(SAMPLE, len(pool)))
    chosen = {id(r) for r in pick}
    os.makedirs(f"{W}/reread", exist_ok=True)
    with open(f"{W}/reread/select.tsv", "w", encoding="utf-8") as fh:
        fh.write("d\tp\torig\tidx\tkind\tclass\tword\tcopy\tpx\ttdir\tpage\treread\n")
        for r in rows: fh.write("\t".join(r + ["yes" if id(r) in chosen else "no"]) + "\n")
    c = collections.Counter((r[10], r[5], id(r) in chosen) for r in rows)
    for k in sorted(c): print(*k, c[k])
    print("rows", len(rows), "re-read", len(pick), "crops", len({(r[9], r[3]) for r in pick}))


def load_select(W, only=True):
    out = []
    for i, line in enumerate(open(f"{W}/reread/select.tsv", encoding="utf-8")):
        f = line.rstrip("\n").split("\t")
        if i and (f[11] == "yes" or not only): out.append(f)
    return out


def render(tdir, rd, bin_):
    """the truth page's source page again, at the transcript's dpi, to <rd>/page.png; exits on a size mismatch"""
    meta = open(f"{tdir}/meta.txt", encoding="utf-8").read()
    src = re.search(r"^source=(.*)$", meta, re.M).group(1)
    page, dpi, px = re.search(r"page=(\d+) dpi=(\d+) px=(\d+x\d+)", meta).groups()
    pdf = f"{STATE}/owner-supplied/{src[6:]}" if src.startswith("owner/") else f"{ROOT}/testdocs/{src}"
    if not os.path.exists(pdf):
        common = subprocess.run(["git", "-C", ROOT, "rev-parse", "--git-common-dir"], capture_output=True, text=True).stdout.strip()
        pdf = os.path.join(os.path.dirname(os.path.abspath(os.path.join(ROOT, common))), "testdocs", src)
    got = subprocess.run([f"{bin_}/render-page", pdf, page, dpi, f"{rd}/page.png"], capture_output=True, text=True).stdout.strip()
    if got != px: sys.exit(f"reread: {tdir}: rendered {got}, the transcript's image was {px}")


def crops(W, bin_):
    """one page at a time: render, check the size against meta.txt, cut the crops, delete the render"""
    J = jobs(W)
    todo = collections.OrderedDict()
    for f in load_select(W): todo.setdefault(f[9], {})[f[3]] = f
    for tdir, sel in todo.items():
        name = tdir[len(f"{STATE}/truth/"):].replace("/", "__")
        rd = f"{W}/reread/pages/{name}"
        if os.path.exists(f"{rd}/check/list.tsv"): continue
        os.makedirs(rd, exist_ok=True)
        render(tdir, rd, bin_)
        for n in ("transcript.txt",):
            if not os.path.exists(f"{rd}/{n}"): os.symlink(f"{tdir}/{n}", f"{rd}/{n}")
        ws = words(f"{tdir}/transcript.txt")
        spots = []
        for k, f in sel.items():
            if ws[int(k)][0] != f[6]: sys.exit(f"reread: {tdir} word {k} is {ws[int(k)][0]!r}, the harness said {f[6]!r}")
            x, y, w, h = f[8].split()
            spots.append(f"{k}\t{f[6]}\t{x}\t{y}\t{w}\t{h}")
        open(f"{rd}/spots.tsv", "w", encoding="utf-8").write("\n".join(spots) + "\n")
        subprocess.run([sys.executable, f"{HERE}/wordcrops.py", rd], check=True, capture_output=True)
        os.remove(f"{rd}/page.png")
        print(name, len(spots), flush=True)


def readings(W, sd="sheets"):
    """crop path -> reading, from the briefs read crop by crop and from sheet dir <sd>'s `number<TAB>reading`
    lines through its map.tsv"""
    reading = {}
    if sd == "sheets":
        for f in glob.glob(f"{W}/reread/briefs/chk-*.out"):
            for line in open(f, encoding="utf-8"):
                if "\t" not in line: continue
                p, r = line.rstrip("\n").split("\t", 1)
                reading[os.path.realpath(p.strip())] = r.strip()
    sd = f"{W}/reread/{sd}"
    if os.path.exists(f"{sd}/map.tsv"):
        where = {}
        for line in open(f"{sd}/map.tsv", encoding="utf-8"):
            b, n, p = line.rstrip("\n").split("\t"); where[(b, n)] = os.path.realpath(p)
        for f in glob.glob(f"{sd}/chk-*.out"):
            b = re.search(r"chk-(\d+)\.out$", f).group(1)
            for line in open(f, encoding="utf-8"):
                if "\t" not in line: continue
                n, r = line.rstrip("\n").split("\t", 1)
                n = n.strip().lstrip("#")
                if (b, n) in where: reading.setdefault(where[(b, n)], r.strip())
    return reading


def kinds(W):
    """crop path -> `exact`, `nearest` or `tail`, from each page's check/list.tsv"""
    out = {}
    for lf in glob.glob(f"{W}/reread/pages/*/check/list.tsv"):
        for line in open(lf, encoding="utf-8"):
            f = line.rstrip("\n").split("\t")
            if len(f) >= 7: out[os.path.realpath(f"{os.path.dirname(lf)}/{f[0]}.png")] = f[6]
    return out


def tight_ok(r, rt, word, head):
    """a reading of the word's crop (and of its second half's, for a word joined across a line end) agrees"""
    if head is None: return same(r, word)
    return same(r, word) or (same(r, head) and same(rt, word[len(head) - 1:]))


def wide(W, bin_):
    """each `nearest` crop whose reading disagrees, cut again wider (`wordcrops.py --wide`), a page at a time"""
    reading, kind, todo, tw = readings(W), kinds(W), collections.OrderedDict(), {}
    for f in load_select(W):
        k, word, tdir = f[3], f[6], f[9]
        name = tdir[len(f"{STATE}/truth/"):].replace("/", "__")
        base = os.path.realpath(f"{W}/reread/pages/{name}/check/{k}")
        if kind.get(base + ".png") != "nearest": continue
        if tdir not in tw: tw[tdir] = words(f"{tdir}/transcript.txt")
        if tight_ok(reading.get(base + ".png"), reading.get(base + "t.png"), word, tw[tdir][int(k)][1]): continue
        todo.setdefault(tdir, set()).add(k)
    n = 0
    for tdir, ks in todo.items():
        name = tdir[len(f"{STATE}/truth/"):].replace("/", "__")
        rd = f"{W}/reread/pages/{name}"
        if os.path.exists(f"{rd}/wide/list.tsv"): n += len(ks); continue
        render(tdir, rd, bin_)
        open(f"{rd}/wide-spots.tsv", "w", encoding="utf-8").write("".join(f"{k}\n" for k in sorted(ks, key=int)))
        subprocess.run([sys.executable, f"{HERE}/wordcrops.py", rd, "--wide"], check=True, capture_output=True)
        os.remove(f"{rd}/page.png")
        n += len(ks)
        print(name, len(ks), flush=True)
    print("wide crops", n, "on", len(todo), "pages")


def briefs(W):
    prompt = []
    on = False
    for line in open(f"{HERE}/procedure.md", encoding="utf-8"):
        if on and line.startswith("## "): break   # before the start test: `## CHECK prompt, sheets` follows
        if line.startswith("## CHECK prompt (verbatim)"): on = True; continue
        if on and line.startswith(">"): prompt.append(line[1:].strip())
    prompt = " ".join(prompt)
    paths = sorted(glob.glob(f"{W}/reread/pages/*/check/*.png"))
    random.Random(930).shuffle(paths)
    bd = f"{W}/reread/briefs"; os.makedirs(bd, exist_ok=True)
    for n in range(0, len(paths), BRIEF):
        i = n // BRIEF + 1
        with open(f"{bd}/brief-{i}.txt", "w", encoding="utf-8") as fh:
            fh.write(f"For each image path below, do this, independently: {prompt}\n\n"
                     f"You may open several of these images in one turn. Write every answer as one line "
                     f"`path<TAB>reading` with the Write tool to {bd}/chk-{i}.out, then reply only 'done'. "
                     f"Open no other file.\n\n")
            fh.write("\n".join(paths[n:n + BRIEF]) + "\n")
    print(len(paths), "crops in", (len(paths) + BRIEF - 1) // BRIEF, "briefs")


SHEET_W, SHEET_H, CELL_W = 1100, 1050, 520   # under 1.2 MP, so no reader-side downscale
MAGICK = "/opt/homebrew/bin/magick"
FONT = "/System/Library/Fonts/Helvetica.ttc"


def sheets(W, which="check", per_brief=4):
    """The crops no brief has read yet, shuffled onto numbered contact sheets, four sheets to a brief: a
    reader that opened 45 crops one at a time took 11 minutes and about 3% of the usage window, most of it
    in reopening crops and deliberating. A sheet stays under 1.2 MP so the reader sees every pixel; a crop
    keeps its pixels (one over 520 px wide gets a row of its own, up to 1,070), framed, with its number in
    blue above it. <which> is `check`, the tight crops, into reread/sheets/, or `wide`, `wide`'s crops,
    into reread/wide-sheets/. Refuses to redraw a sheet directory that already holds readings."""
    done = set()
    if which == "check":
        for f in glob.glob(f"{W}/reread/briefs/chk-*.out"):
            for line in open(f, encoding="utf-8"):
                if "\t" in line: done.add(os.path.realpath(line.split("\t", 1)[0].strip()))
    paths = [p for p in sorted(glob.glob(f"{W}/reread/pages/*/{which}/*.png")) if os.path.realpath(p) not in done]
    random.Random(931 if which == "check" else 932).shuffle(paths)
    sd = f"{W}/reread/{'sheets' if which == 'check' else 'wide-sheets'}"
    if glob.glob(f"{sd}/chk-*.out"): sys.exit(f"reread: {sd} holds readings; move them away first")
    if os.path.exists(sd): shutil.rmtree(sd)
    os.makedirs(f"{sd}/cells")

    sizes = {}
    def size(p):
        if p not in sizes:
            with open(p, "rb") as fh:
                fh.read(16); sizes[p] = (int.from_bytes(fh.read(4), "big"), int.from_bytes(fh.read(4), "big"))
        return sizes[p]

    def fit(w, h, maxw):
        s = min(1.0, maxw / w, 240 / h)
        return max(int(w * s), 1), max(int(h * s), 1)

    def cellsize(w, h, maxw):
        """the cell drawn below: resized to fit maxw x 240, a 3 px frame, at least 60 px wide so its label
        is not clipped, a 30 px label band and a 10 px margin"""
        w2, h2 = fit(w, h, maxw)
        return max(w2 + 6, 60) + 20, h2 + 56

    # lay out first, from the predicted cell sizes: rows of cells up to SHEET_W, sheets up to SHEET_H
    sheets_, rows, row = [], [], []
    def rowh(r): return max(s[1] for _, s in r)
    for p in paths:
        w, h = size(p)
        wide = w > CELL_W
        s = cellsize(w, h, SHEET_W - 30 if wide else CELL_W)
        if row and (wide or sum(x[1][0] for x in row) + s[0] > SHEET_W): rows.append(row); row = []
        if rows and sum(rowh(r) for r in rows) + max([s[1]] + [x[1][1] for x in row]) > SHEET_H:
            if row: rows.append(row); row = []
            sheets_.append(rows); rows = []
        row.append((p, s))
        if wide: rows.append(row); row = []
    if row: rows.append(row)
    if rows: sheets_.append(rows)
    # then number each brief's crops 1.. across its sheets, and draw
    mapping, briefs_ = [], []
    for si, rows in enumerate(sheets_):
        b = si // per_brief + 1
        if si % per_brief == 0: briefs_.append([]); n = 0
        rowimgs = []
        for ri, r in enumerate(rows):
            cells = []
            for p, _ in r:
                n += 1
                c = f"{sd}/cells/b{b}-{n}.png"
                maxw = SHEET_W - 30 if size(p)[0] > CELL_W else CELL_W
                w2, h2 = fit(*size(p), maxw)
                subprocess.run([MAGICK, p, "-resize", f"{w2}x{h2}!", "-bordercolor", "#9a9a9a", "-border", "3",
                                "-background", "white", "-gravity", "center", "-extent", f"{max(w2 + 6, 60)}x{h2 + 6}",
                                "-gravity", "north", "-splice", "0x30", "-font", FONT, "-fill", "#1040ff", "-pointsize", "24",
                                "-annotate", "+0+3", f"#{n}", "-bordercolor", "white", "-border", "10", "+repage", c], check=True)
                cells.append(c); mapping.append((b, n, p))
            ro = f"{sd}/cells/s{si + 1}-r{ri + 1}.png"
            subprocess.run([MAGICK] + cells + ["-background", "white", "-gravity", "north", "+append", "+repage", ro], check=True)
            rowimgs.append(ro)
        sh = f"{sd}/sheet-{si + 1}.png"
        subprocess.run([MAGICK] + rowimgs + ["-background", "white", "-gravity", "west", "-append", "+repage", sh], check=True)
        briefs_[-1].append(sh)
    with open(f"{sd}/map.tsv", "w", encoding="utf-8") as fh:
        for b, n, p in mapping: fh.write(f"{b}\t{n}\t{p}\n")
    prompt = []
    on = False
    for line in open(f"{HERE}/procedure.md", encoding="utf-8"):
        if on and line.startswith("## "): break
        if line.startswith("## CHECK prompt, sheets"): on = True; continue
        if on and line.startswith(">"): prompt.append(line[1:].strip())
    prompt = " ".join(prompt)
    for b, shs in enumerate(briefs_, 1):
        with open(f"{sd}/brief-{b}.txt", "w", encoding="utf-8") as fh:
            fh.write(f"{prompt}\n\nThe sheets:\n" + "\n".join(shs) + "\n\n"
                     f"Write every answer as one line `number<TAB>reading` with the Write tool to {sd}/chk-{b}.out, "
                     f"then reply only 'done'. Open no other file.\n")
    print("sheets", len(sheets_), "briefs", len(briefs_), "crops", len(mapping))


def same(r, word):
    if r is None or r in ("?", "`?`", ""): return False
    if not fold(word): return r.strip() == word
    return any(fold(t) == fold(word) for t in r.split())


def apply(W):
    reading, wread, kind = readings(W), readings(W, "wide-sheets"), kinds(W)
    log, contested = [], collections.defaultdict(dict)
    tally, tw = collections.Counter(), {}
    for f in load_select(W, only=False):
        d, p, orig, k, kind_, cls, word, copy, px, tdir, page, rr = f
        if rr != "yes":
            tally[(page, cls, "not re-read")] += 1; continue
        name = tdir[len(f"{STATE}/truth/"):].replace("/", "__")
        base = os.path.realpath(f"{W}/reread/pages/{name}/check/{k}")
        r, rt = reading.get(base + ".png"), reading.get(base + "t.png")
        if tdir not in tw: tw[tdir] = words(f"{tdir}/transcript.txt")
        head = tw[tdir][int(k)][1]
        ok, by = tight_ok(r, rt, word, head), "tight"
        asCopy = r is not None and same(r, copy) and not ok
        wbase = os.path.realpath(f"{W}/reread/pages/{name}/wide/{k}.png")
        if not ok and kind.get(base + ".png") == "nearest" and wbase in wread:
            r, by, asCopy = wread[wbase], "wide", False   # a wide reading holds the neighbours, so not `copy`
            ok = tight_ok(r, rt, word, head)
        verdict = "confirmed" if ok else "unread" if r is None else "contested"
        if not ok: contested[tdir][k] = (word, r if r is not None else "(no check)")
        tally[(page, cls, verdict)] += 1
        log.append("\t".join([d, p, orig, k, kind_, cls, page, verdict, "copy" if asCopy else "-", by]))
    for tdir in {f[9] for f in load_select(W)}:
        ks, path = contested.get(tdir, {}), f"{tdir}/contested-harness.tsv"
        if not ks:
            if os.path.exists(path): os.remove(path)   # an earlier apply's, now stale
            continue
        with open(path, "w", encoding="utf-8") as fh:
            for k in sorted(ks, key=int): fh.write(f"{k}\t{ks[k][0]}\t{ks[k][1]}\n")
    with open(f"{W}/reread/log.tsv", "w", encoding="utf-8") as fh:
        fh.write("d\tp\torig\tidx\tkind\tclass\tpage\tverdict\treadsAsCopy\tby\n" + "".join(l + "\n" for l in log))
    for key in sorted(tally): print(*key, tally[key], sep="\t")
    print("pages with contested-harness.tsv:", len(contested))


if __name__ == "__main__":
    cmd, W = sys.argv[1], sys.argv[2].rstrip("/")
    {"select": lambda: select(W), "crops": lambda: crops(W, sys.argv[3]), "briefs": lambda: briefs(W),
     "sheets": lambda: sheets(W, sys.argv[3] if len(sys.argv) > 3 else "check"), "wide": lambda: wide(W, sys.argv[3]),
     "apply": lambda: apply(W)}[cmd]()
