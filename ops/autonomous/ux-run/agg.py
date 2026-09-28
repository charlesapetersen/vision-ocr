import os, sys, collections
W = sys.argv[1]; S = os.path.join(W, "scores")
PH = "page\trefWords\tleg1\tleg2\tinkRatio\tinkLum\tsrcCol\tcolKept\tfind\tcols\tinside\tcover\toverInk\twer\tprec\trecall\tsplits\twelds\techoes\thyph\tmidBreaks\tgeom\tmsSrc\tmsOut\tflags"
DH = "pages\tbytes\topenMs\topen\tqpdf\toutline\tlabels\tlinks\tannots\ttitle\tflags"
pages_out = ["set\tdocument\t" + PH]
docs_out = ["set\tdocument\tresult\tsrcPages\tsampled\tredPages\tredReasons\tscoreSec\t" + DH]
SKIPPED = [l.rstrip("\n") for l in open(os.path.join(W, "skipped.txt"))] if os.path.exists(os.path.join(W, "skipped.txt")) else []
for label in sorted(os.listdir(S)):
    if "__" not in label or "\n" in label: continue
    st_path = os.path.join(S, label, "status")
    if not os.path.exists(st_path): continue
    st = open(st_path).read().rstrip("\n").split("\t")
    sset, doc = label.split("__", 1)
    sset = "owner" if sset == "owner" else "testdocs/" + sset
    result, n, sampled = st[1], st[2], st[3]
    secs = st[4] if len(st) > 4 else "-"
    pp = os.path.join(S, label, "pages.tsv"); dp = os.path.join(S, label, "document.tsv")
    red = 0; reasons = collections.Counter(); drow = "\t".join(["-"] * 11)
    if os.path.exists(pp):
        L = open(pp).read().splitlines()
        assert L[0] == PH, (label, L[0])
        for r in L[1:]:
            pages_out.append(f"{sset}\t{doc}\t{r}")
            f = r.split("\t")[-1]
            if f != "-":
                red += 1
                for x in f.split(","): reasons[x] += 1
    if os.path.exists(dp):
        L = open(dp).read().splitlines()
        assert L[0] == DH, (label, L[0]); drow = L[1]
    res = {"EXIT-0": "green", "EXIT-1": "red", "EXIT-2": "harness-refused", "EXIT-133": "harness-crashed: CoreGraphics trapped in PDFPage selectionFromPoint:toPoint: on the output page (its text layer holds Arabic letters, Arabic-Indic digits and U+202B)"}.get(result, result)
    if res != "green" and not os.path.exists(pp): res = res if res != "red" else "red-no-pages"
    rs = ",".join(f"{k}:{v}" for k, v in sorted(reasons.items())) or "-"
    docs_out.append(f"{sset}\t{doc}\t{res}\t{n}\t{sampled}\t{red}\t{rs}\t{secs}\t{drow}")
for s in SKIPPED:
    docs_out.append(f"owner\t{s}\tnot-scored: an earlier app output the owner supplied as evidence, not a source\t-\t-\t-\t-\t-\t" + "\t".join(["-"] * 11))
open(sys.argv[2], "w").write("\n".join(pages_out) + "\n")
open(sys.argv[3], "w").write("\n".join(docs_out) + "\n")
print(len(pages_out) - 1, "page rows,", len(docs_out) - 1, "document rows")
