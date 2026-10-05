"""make-table.py <results.tsv> <out.tsv> — one row per candidate for OCR-MODELS-<date>.tsv.

Takes each candidate's LAST row per page from try-mlx.sh's results.tsv, adds what is known about the
model from its card (CARDS below: parameters, what boxes it can give, notes), and decides `fits`:
peak memory under 12 GB on the ordinary page and the newspaper crops, and the newspaper read in under 90 s; `fits_memory` drops
the time limit (a crop cut off at max_tokens still counts as read to the end: it looped, it did not crash).
Candidates that could not be run here are listed in NOT_RUN with the reason.
"""
import csv, sys

# From the model cards, not measured here. boxes: what the model itself can emit, by its card.
CARDS = {
    "paddleocr-vl-1.6-4bit": ("0.9B", "none from the VLM; blocks from its PP-DocLayout pipeline"),
    "paddleocr-vl-1.5-4bit": ("0.9B", "none from the VLM; blocks from its PP-DocLayout pipeline"),
    "glm-ocr-4bit": ("0.9B", "none from the VLM; blocks from its layout pipeline"),
    "lightonocr-2-1b-4bit": ("1B", "image boxes only (bbox variants)"),
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

rows = {}
for r in csv.reader(open(sys.argv[1]), delimiter="\t"):
    if len(r) < 14: continue
    label, repo, page = r[0], r[1], r[2]
    rows.setdefault(label, {"repo": repo})[page] = r

def size_mb(repo):
    """Download size of the build (only the named files for a repo:file:file GGUF build), from the Hub."""
    from huggingface_hub import HfApi
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
        "fits", "fits_memory", "why"]
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
    quant = next((q for q in ("4bit", "8bit", "oQ8", "bf16", "gguf") if q in label), "?")
    why, peaks = [], []
    for name, r in (("ordinary", o), ("newspaper crops", c)):
        if r is None: why.append(f"{name} not read"); continue
        if r[3] == "137": why.append(f"guard killed it on the {name} ({r[13]})")
        elif r[3] != "0": why.append(f"{name}: exit {r[3]}")
        elif r[8] != "-": why.append(f"{name} cut off ({r[8]})")
        elif r[11] in ("-", ""): why.append(f"{name} gave no text")
        elif float(r[11]) < 0.5: why.append(f"{name} not read (recall {r[11]})")
        peaks.append(int(r[9]) if r[9].isdigit() else 0)
    if c is not None and c[3] == "0" and c[6] not in ("-", "") and float(c[6]) > 90:
        why.append(f"newspaper crops took {float(c[6]):.0f} s (> 90 s)")
    if peaks and max(peaks) > 12 * 1024: why.append("peak over 12 GB")
    fits = "yes" if not why else "no"
    # fits_memory: read both pages to the end under the guard, ignoring the 90 s limit.
    read = all(r[11] not in ("-", "") and float(r[11]) >= 0.5 for r in (o, c) if r is not None)
    fits_memory = "yes" if o is not None and c is not None and o[3] == c[3] == "0" and read and peaks \
        and max(peaks) <= 12 * 1024 else "no"
    g = lambda r, i: r[i] if r is not None else "-"
    out.writerow([label, d["repo"], params, runtime, quant, size_mb(d["repo"]), boxes,
                  g(o, 9), g(o, 6), g(o, 11), g(o, 12),
                  g(n, 9), g(n, 6), outcome(n),
                  g(c, 9), g(c, 6), g(c, 11), g(c, 12),
                  fits, fits_memory, "; ".join(why) or "-"])
for label, repo, params, runtime, quant, why in NOT_RUN:
    out.writerow([label, repo, params, runtime, quant, size_mb(repo), "-"] + ["-"] * 11 + ["unknown", "unknown", why])
