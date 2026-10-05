"""make-table.py <results.tsv> <out.tsv> [label…] — one row per candidate for OCR-MODELS-<date>.tsv.

With labels, only those candidates' rows, and none of NOT_RUN (a later round's table).

Takes each candidate's LAST row per page from try-mlx.sh's results.tsv, adds what is known about the
model from its card (CARDS below: parameters, what boxes it can give, notes), and decides `fits`:
peak memory under 12 GB on the ordinary page and the newspaper crops, both run to exit 0, and rough recall
of at least 0.5 on each. Speed does not decide fit (the owner dropped the 90 s rule on 2026-10-04), and a
crop cut off at max_tokens or the time limit still counts as read: it looped or ran long, it did not crash.
`why` gives the reasons a candidate does not fit, then notes (cut-offs, NOTES below).
Candidates that could not be run here are listed in NOT_RUN with the reason.
"""
import csv, sys

# From the model cards, not measured here. boxes: what the model itself can emit, by its card.
CARDS = {
    "paddleocr-vl-1.6-4bit": ("0.9B", "none from the VLM; blocks from its PP-DocLayout pipeline"),
    "paddleocr-vl-1.5-4bit": ("0.9B", "none from the VLM; blocks from its PP-DocLayout pipeline"),
    "glm-ocr-4bit": ("0.9B", "none from the VLM; blocks from its layout pipeline"),
    "lightonocr-2-1b-4bit": ("1B", "image boxes only (bbox variants)"),
    "lightonocr-2-1b-4bit-1540": ("1B", "image boxes only (bbox variants)"),
    "deepseek-ocr-2-4bit": ("3B", "block boxes in grounding mode"),
    "mineru2.5-2509-bf16": ("1.2B", "block boxes (two-stage layout)"),
    "hunyuanocr-4bit": ("1B", "line boxes in its spotting mode"),
    "qwen3.5-2b-4bit": ("2B", "boxes by prompting (grounding), unmeasured"),
    "qwen3.5-4b-4bit": ("4B", "boxes by prompting (grounding), unmeasured"),
    "qwen3.5-9b-4bit": ("9B", "boxes by prompting (grounding), unmeasured"),
    "mineru2.5-pro-2604-4bit": ("1.2B", "block boxes (two-stage layout)"),
    "surya-ocr-2-gguf": ("0.65B", "line/block boxes (layout stage)"),
    "dots.mocr-4bit": ("3B", "block boxes (layout JSON)"),
    "qianfan-ocr-4bit": ("4B", "block boxes (layout mode)"),
    "chandra-ocr-2-oQ8": ("5B", "block boxes with text (HTML layout)"),
    "chandra-ocr-2-q4km": ("5B", "block boxes with text (HTML layout)"),
    "surya-ocr-2-pkg": ("0.65B", "block polygons with layout labels and reading order (seen in its output)"),
    "lightonocr-2-1b-ocr-soup-8bit-1540": ("1B", "image boxes only (bbox variants)"),
    "lightonocr-2-1b-base-8bit-1540": ("1B", "image boxes only (bbox variants)"),
    "lightonocr-2-1b-8bit-1540": ("1B", "image boxes only (bbox variants)"),
}
NOTES = {
    "lightonocr-2-1b-4bit": "superseded by its retry, lightonocr-2-1b-4bit-1540",
    "qwen3.5-9b-4bit": "tripped once with 5.9 GB reclaimable (a 6.9 GB footprint); one try left, on a machine "
                       "with more memory free",
    "lightonocr-2-1b-4bit-1540": "retry of lightonocr-2-1b-4bit with each image shrunk to 1540 px (--max-side); "
                                 "crops peak 11.0 GB and swap +1.6 GB, both close to the guard's limits",
    "deepseek-ocr-2-4bit": "loads only with --no-remote-code (the guard killed its first try, swap_grew_2095MB); "
                           "newspaper crops precision 0.63, lowest of those that fit",
    "chandra-ocr-2-q4km": "GGUF Q4_K_M; newspaper crops stopped at read-gguf.py's 600 s limit after an "
                          "unrecorded number of the 13 crops, so its crops recall is of a partial read; "
                          "GGUF seconds include a model load per crop",
    "chandra-ocr-2-oQ8": "newspaper crops stopped at read-mlx.py's 600 s limit (24 tokens/s), so its crops "
                         "recall is of a partial read",
    "surya-ocr-2-gguf": "the GGUF under a plain prompt; superseded by surya-ocr-2-pkg",
    "surya-ocr-2-pkg": "surya-ocr 0.22.1 in $OCRLAB/venv-surya: `surya_ocr <image or dir> --output_dir D`, "
                       "text by surya-text.py; it serves the same GGUF through brew's llama-server; its seconds "
                       "are from its log, server ready to results written",
    "lightonocr-2-1b-ocr-soup-8bit-1540": "converted here at 8-bit by convert-mlx.py (mlx-vlm reports 11.6 bits "
                                          "per weight); empty prompt, 1540 px, 4096 tokens; crops grew swap "
                                          "1.7 GB against the guard's 2 GB",
    "lightonocr-2-1b-base-8bit-1540": "converted here like ocr-soup; its ordinary read is byte-identical to "
                                      "ocr-soup's; the guard killed its first crops read (swap_grew_2687MB; "
                                      "8.4 GB of swap in use just after); read on its one retry, needing 8 GB "
                                      "reclaimable",
    "lightonocr-2-1b-8bit-1540": "control for the tested 4-bit build; one guarded retry owed, on a machine with "
                                 "10 GB reclaimable (it waited 20 min for that on 2026-10-05 and did not get it); "
                                 "ocr-bakeoff-bits compares 4-bit with 8-bit anyway",
}
NOT_RUN = [
    ("teleocr", "XingChen-AGI/TeleOCR", "1.2B", "-", "-",
     "not run: its only GGUF is for teleocr-rs (Rust/Candle), not llama.cpp, and mlx-vlm has no loader "
     "for its Qwen3-style decoder; needs teleocr-rs built with Metal"),
    ("navidc-ocr", "nandraj/NaviDC-OCR-GGUF", "1.2B", "-", "-",
     "not run: the GGUF needs a patched llama.cpp (stock build fails check_tensor_dims, per its card)"),
    ("dots.ocr-1.5", "kristaller486/dots.ocr-1.5", "3B", "-", "-",
     "not run: full weights only; dots.mocr-4bit, its successor, stands in"),
]

only = set(sys.argv[3:])
rows = {}
for r in csv.reader(open(sys.argv[1]), delimiter="\t"):
    if len(r) < 14 or (only and r[0] not in only): continue
    label, repo, page = r[0], r[1], r[2]
    rows.setdefault(label, {"repo": repo})[page] = r

def size_mb(repo):
    """Download size of the build (only the named files for a repo:file:file GGUF build), from the Hub;
    for a build converted here (local/<name>), its size on disk."""
    import os
    from huggingface_hub import HfApi
    if repo.startswith("local/"):
        d = os.path.join(os.environ.get("OCRLAB", os.path.expanduser("~/.local/share/visionocr-ocrlab")),
                         "mlx", repo[len("local/"):])
        return str(sum(os.path.getsize(os.path.join(d, f)) for f in os.listdir(d)) // 2**20) if os.path.isdir(d) else "-"
    name, _, files = repo.partition(":")
    want = files.split(":") if files else None
    try:
        info = HfApi().model_info(name, files_metadata=True)
    except Exception:
        return "-"
    return str(sum((f.size or 0) for f in info.siblings if not want or f.rfilename in want) // 2**20)

head = ["candidate", "build", "params", "runtime", "quant", "download_MB", "boxes",
        "ordinary_peak_MB", "ordinary_s", "ordinary_recall", "ordinary_precision",
        "newspaper_page_peak_MB", "newspaper_page_s", "newspaper_page_outcome",
        "newspaper_crops_peak_MB", "newspaper_crops_s", "newspaper_crops_recall", "newspaper_crops_precision",
        "fits", "why"]
out = csv.writer(open(sys.argv[2], "w"), delimiter="\t", lineterminator="\n")
out.writerow(head)

def outcome(r):
    if r is None: return "-"
    if r[3] == "137": return "guard:" + r[13]
    if r[3] != "0": return f"exit {r[3]}"
    return "cut:" + r[8] if r[8] != "-" else "read"

for label, d in rows.items():
    o, n, c = d.get("ordinary"), d.get("newspaper"), d.get("newspaper-crops")
    params, boxes = CARDS.get(label, ("?", "?"))
    runtime = "llama.cpp (GGUF)" if ".gguf" in d["repo"] else "MLX (mlx-vlm 0.7.4)"
    quant = next((q for q in ("4bit", "8bit", "oQ8", "bf16", "q4km", "gguf") if q in label),
                 "gguf" if ".gguf" in d["repo"] else "?")
    why, notes, peaks = [], [], []
    for name, r in (("ordinary", o), ("newspaper crops", c)):
        if r is None: why.append(f"{name} not read"); continue
        peaks.append(int(r[9]) if r[9].isdigit() else 0)
        if r[3] == "137": why.append(f"guard killed it on the {name} ({r[13]})"); continue
        if r[3] != "0": why.append(f"{name}: exit {r[3]}"); continue
        if r[11] in ("-", ""): why.append(f"{name} gave no text"); continue
        if float(r[11]) < 0.5: why.append(f"{name} not read (recall {r[11]})")
        if r[8] != "-": notes.append(f"{name} cut off ({r[8]})")
    if peaks and max(peaks) > 12 * 1024: why.append("peak over 12 GB")
    if label in NOTES: notes.append(NOTES[label])
    g = lambda r, i: r[i] if r is not None else "-"
    out.writerow([label, d["repo"], params, runtime, quant, size_mb(d["repo"]), boxes,
                  g(o, 9), g(o, 6), g(o, 11), g(o, 12),
                  g(n, 9), g(n, 6), outcome(n),
                  g(c, 9), g(c, 6), g(c, 11), g(c, 12),
                  "no" if why else "yes", "; ".join(why + notes) or "-"])
for label, repo, params, runtime, quant, why in ([] if only else NOT_RUN):
    out.writerow([label, repo, params, runtime, quant, size_mb(repo), "-"] + ["-"] * 11 + ["unknown", why])
