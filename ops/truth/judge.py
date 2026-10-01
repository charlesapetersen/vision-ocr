#!/usr/bin/env python3
"""The judges of `truth-harness` (QUEUE.md): everything on a page that is not its text layer, judged blind.

    ops/truth/judge.py prep    <W> [<control-dir>...]   briefs of up to 6 pairs, the JUDGE prompt verbatim
    ops/truth/judge.py rejudge <W> <jids-file>...       one brief per file of pair numbers, the prompt as it
                                                        now stands, into judge/rejudge/, verdicts to judge/out2/
    ops/truth/judge.py apply   <W>                      verdicts -> <W>/judge/verdicts.tsv and pages.tsv;
                                                        a pair's out2/ verdict replaces its out/ one

<W> is an `ops/truth/run-harness.sh` run; `ux-harness --truth` wrote each page's crop pairs in
`score/d<N>/pairs/` and which of A and B is the output in `pairs-key.tsv`. A pair whose two images are the
same bytes needs no judge and is `identical`. The rest are copied under neutral names (`j<N>-A.png`) into
<W>/judge/img/, with the key in <W>/judge-keys/, which no judge is told of, and a page's pairs stay together
in one brief, so a page with more than 6 has a brief of its own. A control directory is a `ux-harness
--truth` output whose losses are known (the self-test's Why p5 at 1.14.0, which publishes the red headings
black, and Why pp5-6 at 24a8f6a, illegible): its pairs go into the briefs blind like the rest, and `apply`
reports whether the judges found the output worse. A pair's number comes from its place among all of them,
controls included, so `prep` run again over different inputs would renumber the pairs under the verdicts
already in out/: it refuses when any judged number would name another pair.
A verdict names A or B; `apply` turns it into the output's: `worse` (the output lost something), `better`
(the source is worse), `both`, `same`. An element the transcript marks `ignore` (a scanner border, dust:
not content, and `ux-harness` no longer pairs it) is left out. Output in <W>/judge/, never committed.
"""
import glob, os, random, re, shutil, sys, collections, unicodedata

HERE = os.path.dirname(os.path.abspath(__file__))
PER = 6   # a brief of 24 pairs, opened a pair at a time, stalled after 81 image reads (2026-09-30)
TAGS = ("missing", "faded", "harder", "colour")


def prompt():
    """procedure.md's JUDGE prompt, its paragraphs unwrapped"""
    paras, on = [[]], False
    for line in open(f"{HERE}/procedure.md", encoding="utf-8"):
        if on and line.startswith("## "): break
        if line.startswith("## JUDGE prompt (verbatim"): on = True; continue
        if on and line.startswith(">"):
            t = line[1:].strip()
            if t: paras[-1].append(t)
            elif paras[-1]: paras.append([])
    return "\n\n".join(" ".join(p) for p in paras if p)


def pairs(d, label):
    """(label, page, element, output side, checklist line, A, B) for each row of d/pairs-key.tsv"""
    rows = []
    for i, line in enumerate(open(f"{d}/pairs-key.tsv", encoding="utf-8")):
        f = line.rstrip("\n").split("\t")
        if i == 0 or len(f) < 4: continue
        p, k, out, what = f[0], f[1], f[2], " ".join(f[3:])
        a, b = f"{d}/pairs/p{p}-{k}-A.png", f"{d}/pairs/p{p}-{k}-B.png"
        if os.path.exists(a) and os.path.exists(b): rows.append((label, p, k, out, what, a, b))
    return rows


def ignored(what):
    """`ux-harness`'s rule for an OBJECTS line that is not content: a word `ignore` once Unicode punctuation
    (Swift's `.punctuationCharacters`, the P* categories) is trimmed from its ends"""
    def trim(t):
        i, j = 0, len(t)
        while i < j and unicodedata.category(t[i]).startswith("P"): i += 1
        while j > i and unicodedata.category(t[j - 1]).startswith("P"): j -= 1
        return t[i:j]
    low = what.strip().lower()
    return low.startswith("paper") or any(trim(t) == "ignore" for t in low.split())


def checklist(what):
    """the reader's element line without its box: the judge needs the kind of thing, not page pixels"""
    if what == "whole page": return "the whole page"
    return re.sub(r"\s+", " ", re.sub(r"\b\d+\s+\d+\s+\d+\s+\d+\b", "", what)).strip()


def prep(W, controls):
    J = f"{W}/judge"; K = f"{W}/judge-keys"
    for x in (f"{J}/img", K): os.makedirs(x, exist_ok=True)
    allp = []
    for d in sorted(glob.glob(f"{W}/score/d*/"), key=lambda s: int(s.rstrip("/").split("/")[-1][1:])):
        if os.path.exists(f"{d}/pairs-key.tsv"): allp += pairs(d.rstrip("/"), d.rstrip("/").split("/")[-1])
    for c in controls: allp += [("ctrl:" + os.path.basename(c.rstrip("/")),) + r[1:] for r in pairs(c.rstrip("/"), "")]
    ident, todo = [], collections.OrderedDict()
    for r in allp:
        if not r[0].startswith("ctrl:") and open(r[5], "rb").read() == open(r[6], "rb").read(): ident.append(r)
        else: todo.setdefault((r[0], r[1]), []).append(r)
    pages = list(todo.items())
    random.Random(9301).shuffle(pages)
    # a pair already judged (a line for it in out/) is numbered as before and left out of the briefs
    judged = set()
    for fn in glob.glob(f"{J}/out/*.tsv"):
        judged |= {l.split("\t", 1)[0].strip() for l in open(fn, encoding="utf-8") if "\t" in l}
    judged = {j for j in judged if re.fullmatch(r"j\d+", j)}
    briefs, cur, n = [], [], 0
    keymap, copies = {}, []
    for (label, p), rs in pages:
        mine = []
        for r in rs:
            n += 1
            jid = f"j{n}"
            copies.append((r[5], r[6], jid))
            keymap[jid] = "\t".join([jid, label, p, r[2], r[3], r[4]])
            if jid not in judged: mine.append((jid, checklist(r[4])))
        if cur and len(cur) + len(mine) > PER: briefs.append(cur); cur = []
        cur += mine
    if cur: briefs.append(cur)
    # nothing is written until the verdicts already in out/ are known to keep their pairs
    old = {}
    if os.path.exists(f"{K}/map.tsv"):
        old = {l.split("\t", 1)[0]: l.rstrip("\n") for l in open(f"{K}/map.tsv", encoding="utf-8")}
    moved = sorted(j for j in judged if old.get(j) is None or keymap.get(j) != old[j])
    if moved: sys.exit(f"judge: {len(moved)} judged pairs ({', '.join(moved[:5])} ..) would name other pairs or none; "
                       f"run prep with the inputs it had, or move {J}/out away")
    for a, b, jid in copies:
        shutil.copyfile(a, f"{J}/img/{jid}-A.png"); shutil.copyfile(b, f"{J}/img/{jid}-B.png")
    with open(f"{K}/identical.tsv", "w", encoding="utf-8") as fh:
        for r in ident: fh.write("\t".join(r[:4]) + "\n")
    open(f"{K}/map.tsv", "w", encoding="utf-8").write("jid\tdoc\tpage\telement\toutput\twhat\n" + "\n".join(keymap.values()) + "\n")
    text = prompt()
    for old in glob.glob(f"{J}/brief-*.txt"): os.remove(old)
    os.makedirs(f"{J}/out", exist_ok=True)
    i = 0
    for b in briefs:
        i += 1
        # a re-run never overwrites a brief's verdicts, nor those of one split by hand (`brief-<i>a.tsv` ..)
        while glob.glob(f"{J}/out/brief-{i}.tsv") + glob.glob(f"{J}/out/brief-{i}[a-z].tsv"): i += 1
        with open(f"{J}/brief-{i}.txt", "w", encoding="utf-8") as fh:
            fh.write(text + f"\n\nOpen every image below in one turn, then write all the lines in one Write call to "
                     f"{J}/out/brief-{i}.tsv, and reply only 'done'.\n\n")
            for jid, what in b:
                fh.write(f"{jid}   checklist: {what}\n    A: {J}/img/{jid}-A.png\n    B: {J}/img/{jid}-B.png\n")
    print(f"pairs {len(allp)}: identical {len(ident)}, to judge {n} on {len(pages)} pages, in {len(briefs)} briefs")


def rejudge(W, files):
    """one brief per file of pair numbers (`j<N>` a line), the JUDGE prompt as procedure.md now has it, over
    the images `prep` copied; a number whose out2/ brief exists already is never reused"""
    J = f"{W}/judge"; K = f"{W}/judge-keys"
    key = {}
    for i, line in enumerate(open(f"{K}/map.tsv", encoding="utf-8")):
        f = line.rstrip("\n").split("\t")
        if i: key[f[0]] = f
    rd = f"{J}/rejudge"
    for x in (rd, f"{J}/out2"): os.makedirs(x, exist_ok=True)
    text, i = prompt(), 0
    for fn in files:
        jids = [l.strip() for l in open(fn, encoding="utf-8") if l.strip()]
        bad = [j for j in jids if j not in key or not os.path.exists(f"{J}/img/{j}-A.png")]
        if bad: sys.exit(f"judge: {fn}: no pair {', '.join(bad[:5])}")
        i += 1
        while glob.glob(f"{J}/out2/brief-{i}.tsv") + glob.glob(f"{rd}/brief-{i}.txt"): i += 1
        with open(f"{rd}/brief-{i}.txt", "w", encoding="utf-8") as fh:
            fh.write(text + f"\n\nOpen every image below in one turn, then write all the lines in one Write call to "
                     f"{J}/out2/brief-{i}.tsv, and reply only 'done'.\n\n")
            for j in jids:
                fh.write(f"{j}   checklist: {checklist(key[j][5])}\n    A: {J}/img/{j}-A.png\n    B: {J}/img/{j}-B.png\n")
        print(f"{rd}/brief-{i}.txt", len(jids), "pairs")


def apply(W):
    J = f"{W}/judge"; K = f"{W}/judge-keys"
    key = {}
    for i, line in enumerate(open(f"{K}/map.tsv", encoding="utf-8")):
        f = line.rstrip("\n").split("\t")
        if i: key[f[0]] = f
    # one line per pair: `j<N>.tsv` per pair, `brief-<i>.tsv` per brief; out2/ (the second round) read last
    got, again = {}, set()
    for rnd in ("out", "out2"):
        for fn in glob.glob(f"{J}/{rnd}/*.tsv"):
            for line in open(fn, encoding="utf-8"):
                f = [x.strip() for x in line.rstrip("\n").split("\t")]
                if len(f) >= 4 and re.fullmatch(r"j\d+", f[0]):
                    got[f[0]] = f
                    if rnd == "out2": again.add(f[0])
    rows, per = [], collections.defaultdict(collections.Counter)
    for jid, (_, label, p, k, out, what) in key.items():
        if ignored(what): continue
        per[(label, p)]["rejudged"] += jid in again
        g = got.get(jid)
        if g is None: verdict, tags = "unjudged", collections.Counter()
        else:
            v = g[3].lower().replace("`", "")
            worse = "A" if v.startswith("a worse") else "B" if v.startswith("b worse") else None
            verdict = {"same": "same", "both": "both"}.get(v, None)
            if worse: verdict = "worse" if worse == out else "better"
            if verdict is None: verdict = "unparsed"
            tags = collections.Counter()
            for diff in (g[4] if len(g) > 4 else "-").split("|"):
                m = re.match(r"\s*(missing|faded|harder|colour|color)\s*:\s*([AB])\b", diff, re.I)
                if m and m.group(2).upper() == out: tags[m.group(1).lower().replace("color", "colour")] += 1
        rows.append([label, p, k, out, verdict] + [str(tags[t]) for t in TAGS])
        c = per[(label, p)]; c["judged"] += 1; c[verdict] += 1
        for t in TAGS: c["out-" + t] += bool(tags[t])
    # identical.tsv carries no description: an `ignore` element among them is found in its pairs-key.tsv
    desc = {}
    for line in open(f"{K}/identical.tsv", encoding="utf-8"):
        label, p, k, out = line.rstrip("\n").split("\t")[:4]
        if label not in desc:
            desc[label] = {(r[1], r[2]): r[4] for r in pairs(f"{W}/score/{label}", label)} if os.path.exists(f"{W}/score/{label}/pairs-key.tsv") else {}
        if ignored(desc[label].get((p, k), "")): continue
        rows.append([label, p, k, out, "identical"] + ["0"] * len(TAGS)); per[(label, p)]["identical"] += 1
    with open(f"{J}/verdicts.tsv", "w", encoding="utf-8") as fh:
        fh.write("doc\tpage\telement\toutput\tverdict\t" + "\t".join(TAGS) + "\n")
        for r in sorted(rows, key=lambda r: (r[0], int(r[1]), int(r[2]))): fh.write("\t".join(r) + "\n")
    cols = ["identical", "judged", "same", "worse", "better", "both", "unjudged", "unparsed"] + ["out-" + t for t in TAGS] + ["rejudged"]
    with open(f"{J}/pages.tsv", "w", encoding="utf-8") as fh:
        fh.write("doc\tpage\t" + "\t".join(cols) + "\n")
        for (label, p), c in sorted(per.items(), key=lambda kv: (kv[0][0], int(kv[0][1]))):
            fh.write("\t".join([label, p] + [str(c[x]) for x in cols]) + "\n")
    tot = collections.Counter(r[4] for r in rows if not r[0].startswith("ctrl:"))
    print("run pairs:", dict(tot))
    for r in rows:
        if r[0].startswith("ctrl:"): print("control", *r)


if __name__ == "__main__":
    cmd, W = sys.argv[1], sys.argv[2].rstrip("/")
    {"prep": lambda: prep(W, sys.argv[3:]), "rejudge": lambda: rejudge(W, sys.argv[3:]), "apply": lambda: apply(W)}[cmd]()
