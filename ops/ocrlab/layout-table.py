#!/usr/bin/env python3
"""ops/ocrlab/layout-table.py — layout-compare's tables, from the job's directory and the fit test.

    layout-table.py <H> <fit dir> <out prefix> [tools] [header line]...
        e.g. layout-table.py $STATE/ocrlab/layout /tmp/lc-fit/out LAYOUT-COMPARE-2026-10-16
    `tools` replaces H/bin/commit in the header (a job restarted from a later commit); each further argument is
    one more header line (a run moved aside, a retry), since the tables show only what is under H/runs.

Runs hybrid-table.py over H for <prefix>.tsv, one row per combination (every page is a newspaper, so hybrid-table's
`all` and `newspaper` rows hold the same pages; only `all` is kept), and <prefix>-pages.tsv, one row per combination
and page. To each combination row it adds the detector's own columns: layout, download_MB, licence, order (the
model's own or the app's column sort), fit_detect_s (the detector alone, mean over the pages), fit_peak_mb (the
largest RSS over them) and ink_covered (the script's own measure of the ink its text regions hold, mean over the
pages). <prefix>-fit.tsv is the fit test's per-page rows with a detector column, every threshold tried.
"""
import os
import subprocess
import sys
import tempfile

H, FIT, OUT = sys.argv[1], sys.argv[2], sys.argv[3]
TOOLS = sys.argv[4] if len(sys.argv) > 4 else None
MORE = sys.argv[5:]
here = os.path.dirname(os.path.abspath(__file__))

DETECTORS = {
    "yolo": {"name": "DocLayout-YOLO DocStructBench", "fit": "yolo-0.25", "download_MB": 72,
             "licence": "Apache-2.0 (the weights' card; DocLayout-YOLO's code is AGPL-3.0, which the app neither ships nor runs)",
             "order": "none: the app's column sort",
             "weights": "juliozhao/DocLayout-YOLO-DocStructBench as the app's Core ML model (72 MB installed, a 64.8 MB archive); "
                        "the lab's ONNX build wybxc/DocLayout-YOLO-DocStructBench-onnx (71 MB) is the same net, boxes within 0.0002 px"},
    "pp": {"name": "PP-DocLayoutV3", "fit": "pp-0.3", "download_MB": 128, "licence": "Apache-2.0",
           "order": "the model's own",
           "weights": "PaddlePaddle/PP-DocLayoutV3_safetensors (133 MB) converted to MLX float32 (128 MB), mlx-vlm's pp_doclayout_v3"},
    "heron": {"name": "docling-layout-heron", "fit": "heron-0.3", "download_MB": 164, "licence": "Apache-2.0",
              "order": "none: the app's column sort",
              "weights": "ds4sd/docling-layout-heron (RT-DETRv2, 42.9M parameters, 164 MB safetensors) through transformers "
                         "and torch; no MLX or Core ML build exists, so it needs a torch runtime the app does not ship"},
}
EXTRA = ["layout", "download_MB", "licence", "reading_order", "fit_detect_s", "fit_peak_mb", "ink_covered"]


def rows(path):
    lines = [l for l in open(path, encoding="utf-8").read().splitlines() if l and not l.startswith("#")]
    head = lines[0].split("\t")
    return head, [dict(zip(head, l.split("\t"))) for l in lines[1:]]


def fit_summary(label):
    path = os.path.join(FIT, label + ".tsv")
    if not os.path.exists(path):
        return None
    _, r = rows(path)
    ok = [x for x in r if x["imgsz"] != "failed"]
    if not ok:
        return None
    mean = lambda k: sum(float(x[k]) for x in ok) / len(ok)
    return {"fit_detect_s": f"{mean('detect_s'):.2f}", "fit_peak_mb": str(max(int(x["peak_rss_MB"]) for x in ok)),
            "ink_covered": f"{mean('ink_covered'):.3f}", "pages": len(ok)}


with tempfile.TemporaryDirectory() as tmp:
    main, pages = os.path.join(tmp, "main.tsv"), os.path.join(tmp, "pages.tsv")
    subprocess.run([sys.executable, os.path.join(here, "hybrid-table.py"), H, main, pages], check=True, stdout=subprocess.DEVNULL)
    head, table = rows(main)
    _, page_rows = rows(pages)
    page_head = open(pages, encoding="utf-8").readline().rstrip("\n")

log = [l.split("\t") for l in open(os.path.join(H, "hybrid.log"), encoding="utf-8").read().splitlines() if l]
started, last = (log[0][0] if log else "-"), (log[-1][0] if log else "-")
commit = TOOLS or (open(os.path.join(H, "bin", "commit"), encoding="utf-8").read().strip()
                   if os.path.exists(os.path.join(H, "bin", "commit")) else "-")
n_pages = sum(1 for l in open(os.path.join(H, "sample.rows"), encoding="utf-8") if l.strip())
fits = {k: fit_summary(v["fit"]) for k, v in DETECTORS.items()}

header = [
    f"# layout-compare, {started} to {last}: hybrid-run.sh in {H}, tools from {commit}, the {n_pages} pages of",
    "# ops/ocrlab/layout-sample.tsv (the 11 newspaper pages of OCR-SAMPLE-2026-10-04.tsv, and C41's four other whole-page scans",
    "# c01-c04, which have no truth transcript, so they are published and counted in `pages`/`ok` and `unscored`, not in the word",
    "# counts), each published by score-gate and scored by ux-harness --truth; made by layout-table.py over hybrid-table.py",
    "# (column meanings in its docstring). Each combination is one layout detector's regions read by one reader; the",
    "# regions arrangement aligns the reader's words onto Vision's lines (Recogniser.regionAligned), so what differs between",
    "# detectors is which lines get a model's words. vision-off is Vision alone on the same pages, the baseline wm_cut is against.",
    "# Detectors (layout-regions.py, then dedupe-regions.py and reader-regions.sh's 2 px filter for all three alike):",
]
for k, v in DETECTORS.items():
    f = fits[k] or {}
    header.append(f"#   {k}: {v['name']}, {v['weights']}; licence {v['licence']}; conf {v['fit'].split('-')[1]}; "
                  f"reading order {v['order']}; fit test over {f.get('pages', '-')} pages: detect {f.get('fit_detect_s', '-')} s a page "
                  f"on the CPU, peak RSS {f.get('fit_peak_mb', '-')} MB, ink in text regions {f.get('ink_covered', '-')}")
header += [
    "# download_MB is the weights alone. PP and YOLO run in the lab's MLX/onnxruntime venv (the app runs YOLO through Core ML);",
    "# heron needs torch and transformers (the lab's venv-surya), a runtime of its own. fit_* and ink_covered are from",
    "# layout-fit.sh on 300 dpi renders (LAYOUT-COMPARE-*-fit.tsv), the detector alone, each page a fresh process; peak_mb is",
    "# the guard's sample of the reader's processes during the job. On the *-vision rows that reader is the detector alone,",
    "# done in seconds, which the guard's 2 s sample mostly missed (2 MB on most pages, as OCR-COMPARE-2026-10-13 noted):",
    "# fit_peak_mb is the detector's own peak. A run moved out of H/runs (runs-superseded/) is not in these tables.",
] + ["# " + line for line in MORE]

with open(OUT + ".tsv", "w", encoding="utf-8") as f:
    f.write("\n".join(header) + "\n")
    f.write("\t".join(head + EXTRA) + "\n")
    for r in table:
        if r["group"] != "all":
            continue
        det = r["combo"].split("-")[0]
        d, fit = DETECTORS.get(det), fits.get(det)
        extra = ([det, str(d["download_MB"]), d["licence"].split(" (")[0], d["order"]] + [fit[k] if fit else "-" for k in EXTRA[4:]]
                 if d else ["-"] * len(EXTRA))
        f.write("\t".join([r[k] for k in head] + extra) + "\n")
with open(OUT + "-pages.tsv", "w", encoding="utf-8") as f:
    f.write(f"# layout-compare: one row per combination and page, hybrid-table.py's pages file (see {os.path.basename(OUT)}.tsv).\n")
    f.write(page_head + "\n")
    for r in page_rows:
        f.write("\t".join(r[k] for k in page_head.split("\t")) + "\n")
with open(OUT + "-fit.tsv", "w", encoding="utf-8") as f:
    f.write("# layout-compare's fit test (layout-fit.sh): each detector alone on 300 dpi renders of the pages, a fresh process a page;\n"
            "# peak_rss_MB by /usr/bin/time -l; ink_covered is layout-regions.py's own measure (it leaves out each model's own\n"
            "# non-text boxes). heron-0.6 is the model card's threshold, tried and not used.\n")
    f.write("detector\tid\twidth\theight\tconf\timgsz\tload_s\tdetect_s\tregions\ttext_regions\tlargest_MP\tink_covered\tpeak_rss_MB\tseconds\n")
    for name in sorted(os.listdir(FIT)) if os.path.isdir(FIT) else []:
        if not name.endswith(".tsv"):
            continue
        for line in open(os.path.join(FIT, name), encoding="utf-8").read().splitlines()[1:]:
            f.write(name[:-4] + "\t" + line + "\n")
print(f"layout-table: {OUT}.tsv {OUT}-pages.tsv {OUT}-fit.tsv")
