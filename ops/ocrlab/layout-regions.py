#!/usr/bin/env python3
"""ops/ocrlab/layout-regions.py — run ONE layout detector on a page image and write its regions.

    layout-regions.py --model pp|yolo --image page.png --out regions.tsv
                      [--weights PATH] [--imgsz N] [--conf C] [--crops DIR] [--overlay out.png]

  pp    PP-DocLayoutV3 in MLX (mlx-vlm's `pp_doclayout_v3`), weights converted with
        `python -m mlx_vlm.models.pp_doclayout_v3.convert`. Gives labels AND a reading order.
  yolo  DocLayout-YOLO DocStructBench as ONNX (`wybxc/DocLayout-YOLO-DocStructBench-onnx`) on onnxruntime's
        CPU provider. Gives labels only; `order` is then top-to-bottom within left-to-right columns of boxes
        by x-centre, a stand-in, not the model's.

Writes `order label score x0 y0 x1 y1 megapixels` in page pixels. On stdout, one `key=value` line:
seconds to load and to detect, regions, text regions, the largest text region in megapixels (PaddleOCR-VL's
cap is about 1 MP), and `ink_covered`, the share of the page's dark pixels (< 128) inside a text region,
less the ink inside its non-text regions (photographs), which is what a region step must not drop. `--crops` writes each text region as cNN.png in reading order
with a `name x y w h overlap` TSV beside them, the form `$OCRLAB/pages/newspaper.crops.tsv` has.
Run it under run-guarded.sh like any other model process.
"""
import argparse
import sys
import time

import numpy as np
from PIL import Image, ImageDraw

Image.MAX_IMAGE_PIXELS = None
# Labels that hold no running text, per model; everything else counts as a text region. YOLO's `abandon`
# (running heads, page furniture) is text a reader selects, so it counts as text.
NON_TEXT = {"image", "chart", "table", "seal", "figure", "isolate_formula", "formula", "formula_number"}


def run_pp(img, weights, conf, imgsz):
    import mlx.core as mx  # noqa: F401  (load before the model module, as mlx-vlm does)
    from pathlib import Path
    from mlx_vlm.utils import load_model
    t = time.time()
    model = load_model(Path(weights))
    model.eval()
    load_s = time.time() - t
    t = time.time()
    recs = model.detect(img, conf=conf, img_size=imgsz)
    det_s = time.time() - t
    w, h = img.size
    out = []
    for r in recs:
        y0, x0, y1, x1 = r["bbox"]
        out.append((r["reading_order"], r["label"], r["score"],
                    x0 / 1000 * w, y0 / 1000 * h, x1 / 1000 * w, y1 / 1000 * h))
    return out, load_s, det_s


def run_yolo(img, weights, conf, imgsz):
    import ast
    import cv2
    import onnx
    import onnxruntime as ort
    t = time.time()
    m = onnx.load(weights)
    meta = {p.key: p.value for p in m.metadata_props}
    names = ast.literal_eval(meta["names"])
    sess = ort.InferenceSession(m.SerializeToString(), providers=["CPUExecutionProvider"])
    load_s = time.time() - t
    t = time.time()
    a = cv2.cvtColor(np.array(img.convert("RGB")), cv2.COLOR_RGB2BGR)
    h, w = a.shape[:2]
    r = min(imgsz / h, imgsz / w)
    rh, rw = int(round(h * r)), int(round(w * r))
    a = cv2.resize(a, (rw, rh), interpolation=cv2.INTER_AREA)
    ph, pw = (imgsz - rh) % 32, (imgsz - rw) % 32
    a = cv2.copyMakeBorder(a, ph // 2, ph - ph // 2, pw // 2, pw - pw // 2, cv2.BORDER_CONSTANT, value=(114, 114, 114))
    x = (np.transpose(a, (2, 0, 1))[None].astype(np.float32)) / 255.0
    preds = sess.run(None, {"images": x})[0][0]
    det_s = time.time() - t
    preds = preds[preds[:, 4] > conf]
    out = []
    for p in preds:
        x0, y0, x1, y1 = ((p[0] - pw // 2) / r, (p[1] - ph // 2) / r, (p[2] - pw // 2) / r, (p[3] - ph // 2) / r)
        out.append([0, names[int(p[5])], round(float(p[4]), 3), x0, y0, x1, y1])
    # Stand-in order: columns by x-centre (a new column where the centre jumps past the previous box's right edge).
    out.sort(key=lambda o: (o[3] + o[5]) / 2)
    cols, right = [], -1.0
    for o in out:
        if not cols or (o[3] + o[5]) / 2 > right:
            cols.append([])
            right = o[5]
        cols[-1].append(o)
        right = max(right, o[5]) if len(cols[-1]) > 1 else o[5]
    k = 1
    for c in cols:
        for o in sorted(c, key=lambda o: o[4]):
            o[0] = k
            k += 1
    return [tuple(o) for o in out], load_s, det_s


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", choices=["pp", "yolo"], required=True)
    ap.add_argument("--image", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--weights", required=True)
    ap.add_argument("--imgsz", type=int, default=1024)
    ap.add_argument("--conf", type=float, default=None, help="pp default 0.5, yolo 0.25")
    ap.add_argument("--crops")
    ap.add_argument("--overlay")
    a = ap.parse_args()
    img = Image.open(a.image)
    img.load()
    w, h = img.size
    conf = a.conf if a.conf is not None else (0.5 if a.model == "pp" else 0.25)
    regs, load_s, det_s = (run_pp if a.model == "pp" else run_yolo)(img, a.weights, conf, a.imgsz)
    clip = lambda v, hi: int(max(0, min(hi, round(v))))
    regs = sorted(((o, l, s, clip(x0, w), clip(y0, h), clip(x1, w), clip(y1, h)) for o, l, s, x0, y0, x1, y1 in regs))
    text = [r for r in regs if r[1] not in NON_TEXT and r[5] > r[3] and r[6] > r[4]]
    with open(a.out, "w") as f:
        f.write("order\tlabel\tscore\tx0\ty0\tx1\ty1\tmegapixels\n")
        for o, l, s, x0, y0, x1, y1 in regs:
            f.write(f"{o}\t{l}\t{s}\t{x0}\t{y0}\t{x1}\t{y1}\t{(x1 - x0) * (y1 - y0) / 1e6:.2f}\n")
    ink = np.array(img.convert("L")) < 128
    mask = np.zeros_like(ink)
    for _, _, _, x0, y0, x1, y1 in text:
        mask[y0:y1, x0:x1] = True
    # Photographs are mostly dark pixels: leave ink inside a non-text region out of the denominator.
    pic = np.zeros_like(ink)
    for _, l, _, x0, y0, x1, y1 in regs:
        if l in NON_TEXT:
            pic[y0:y1, x0:x1] = True
    ink &= ~pic | mask
    covered = (ink & mask).sum() / max(1, ink.sum())
    biggest = max(((r[5] - r[3]) * (r[6] - r[4]) / 1e6 for r in text), default=0.0)
    if a.crops:
        import os
        os.makedirs(a.crops, exist_ok=True)
        with open(os.path.join(a.crops, "crops.tsv"), "w") as f:
            f.write("name\tx\ty\tw\th\toverlap\n")
            for i, (_, _, _, x0, y0, x1, y1) in enumerate(text, 1):
                n = f"c{i:02d}.png"
                img.crop((x0, y0, x1, y1)).save(os.path.join(a.crops, n))
                # YOLO's boxes get no class-agnostic suppression, so a crop can repeat another's text.
                ov = any(j != i and min(x1, b[5]) > max(x0, b[3]) and min(y1, b[6]) > max(y0, b[4])
                         for j, b in enumerate(text, 1))
                f.write(f"{n}\t{x0}\t{y0}\t{x1 - x0}\t{y1 - y0}\t{'yes' if ov else 'no'}\n")
    if a.overlay:
        ov = img.convert("RGB")
        d = ImageDraw.Draw(ov)
        for o, l, _, x0, y0, x1, y1 in regs:
            col = (220, 0, 0) if l not in NON_TEXT else (0, 0, 220)
            d.rectangle((x0, y0, x1, y1), outline=col, width=6)
            d.text((x0 + 8, y0 + 8), f"{o} {l}", fill=col)
        ov.thumbnail((1600, 1600))
        ov.save(a.overlay)
    print(f"model={a.model} imgsz={a.imgsz} conf={conf} load_s={load_s:.1f} detect_s={det_s:.2f} "
          f"regions={len(regs)} text_regions={len(text)} largest_text_MP={biggest:.2f} ink_covered={covered:.3f}")


if __name__ == "__main__":
    sys.exit(main())
