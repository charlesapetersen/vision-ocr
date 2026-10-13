"""read-model.py — the app's shipped model reader (BUGS.md C57): one page image read by one MLX model.

    python3 -I read-model.py <hub repo> <image> <out.txt> --prompt P [--crops crops.tsv --one-line-each]
                             [--max-tokens N] [--seconds S] [--max-side PX]

Run by the helper (`ModelRuntime.command`) in the runtime `ops/ocrlab/make-runtime.sh` builds. It is the part
of the lab's `ops/ocrlab/read-mlx.py` that Falcon-OCR and PaddleOCR-VL use, line for line, so it writes the
same text ocr-compare-run measured; change one and compare the two again. Prints one JSON line of statistics,
and exits 1 when --seconds stopped the reading, so the app fails the page rather than publish part of it.
"""
import argparse, json, os, sys, time

ap = argparse.ArgumentParser()
ap.add_argument("model"); ap.add_argument("image"); ap.add_argument("out")
ap.add_argument("--prompt", required=True)
ap.add_argument("--max-tokens", type=int, default=12000)
ap.add_argument("--seconds", type=float, default=600)
ap.add_argument("--crops", help="a header line, then `name x y width height` a line: read each crop in turn")
ap.add_argument("--one-line-each", action="store_true", help="with --crops, each crop's reading on one line")
ap.add_argument("--max-side", type=int, help="shrink each image (or crop) so its longer side is at most this")
a = ap.parse_args()

import mlx.core as mx
from mlx_vlm import load, stream_generate
from mlx_vlm.prompt_utils import apply_chat_template

# Freed buffers otherwise stay in MLX's cache and count in the process's footprint, which the guard
# reads; a small cache keeps the footprint near what the model actually holds.
mx.set_cache_limit(256 * 2**20)
t0 = time.time()
model, processor = load(a.model, trust_remote_code=True)
t1 = time.time()
prompt = apply_chat_template(processor, model.config, a.prompt, num_images=1)
images = [a.image]
if a.crops:
    import tempfile
    from PIL import Image
    page, tmp, images = Image.open(a.image), tempfile.mkdtemp(prefix="visionocr-crops-"), []
    for line in open(a.crops).read().splitlines()[1:]:
        name, x, y, w, h = line.split("\t")[:5]
        x, y, w, h = int(x), int(y), int(w), int(h)
        images.append(os.path.join(tmp, name)); page.crop((x, y, x + w, y + h)).save(images[-1])
    import atexit, shutil
    atexit.register(shutil.rmtree, tmp, True)
if a.max_side:
    # A model trained at a fixed resolution can spend its memory on vision tokens for a 300 dpi page.
    import tempfile
    from PIL import Image
    tmp, shrunk = tempfile.mkdtemp(prefix="visionocr-shrunk-"), []
    for i, path in enumerate(images):
        im = Image.open(path); im.thumbnail((a.max_side, a.max_side), Image.LANCZOS)
        shrunk.append(os.path.join(tmp, f"{i}.png")); im.save(shrunk[-1])
    images = shrunk
    import atexit, shutil
    atexit.register(shutil.rmtree, tmp, True)
text, last, cut, gen = [], None, "-", 0
first = None
for img in images:
    last = None   # a crop that yields nothing must not count the previous crop's tokens again
    piece = []
    for r in stream_generate(model, processor, prompt, image=[img], max_tokens=a.max_tokens, temperature=0.0):
        if first is None: first = time.time()
        piece.append(r.text); last = r
        if time.time() - t1 > a.seconds:
            cut = "seconds"; break
    piece = "".join(piece)
    text.append(piece)
    if a.one_line_each: text[-1] = " ".join(text[-1].split())
    gen += getattr(last, "generation_tokens", 0)
    if cut == "seconds": text.append("\n"); break
    # One crop that runs to max_tokens (usually a loop) marks the read cut but does not stop the next crops.
    if last is not None and last.generation_tokens >= a.max_tokens: cut = "max_tokens"
    text.append("\n")
t2 = time.time()
out = "".join(text)
open(a.out, "w").write(out)
print(json.dumps({
    "load_s": round(t1 - t0, 1), "read_s": round(t2 - t1, 1),
    "first_token_s": round((first or t2) - t1, 1),
    "prompt_tokens": getattr(last, "prompt_tokens", 0), "gen_tokens": gen, "images": len(images),
    "gen_tps": round(getattr(last, "generation_tps", 0.0), 1),
    "mlx_peak_gb": round(mx.get_peak_memory() / 2**30, 2), "cut": cut, "chars": len(out),
}))
sys.exit(1 if cut == "seconds" else 0)
