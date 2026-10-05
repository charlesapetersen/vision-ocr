"""read-mlx.py — read one page image with one MLX vision model, plain text out.

    python read-mlx.py <model-dir-or-repo> <image.png> <out.txt> [--prompt P] [--max-tokens N] [--seconds S]
                       [--crops crops.tsv] [--max-side PX]

Run it under run-guarded.sh. Prints one JSON line of statistics on stdout: load and read seconds,
prompt and generated tokens, MLX's own peak memory, and whether the read was cut off by --seconds
or --max-tokens (then the text is incomplete and the row must say so).
"""
import argparse, json, sys, time

ap = argparse.ArgumentParser()
ap.add_argument("model"); ap.add_argument("image"); ap.add_argument("out")
ap.add_argument("--prompt", default="Transcribe all the text on this page, in reading order, as plain text.")
ap.add_argument("--max-tokens", type=int, default=12000)
ap.add_argument("--seconds", type=float, default=600)
ap.add_argument("--crops", help="a truth set crops.tsv: read each crop of the image in turn, joined")
ap.add_argument("--no-template", action="store_true", help="pass the prompt raw, without the chat template")
ap.add_argument("--no-remote-code", action="store_true",
                help="load without the repo's own Python (DeepSeek-OCR-2's needs an older transformers)")
ap.add_argument("--max-side", type=int, help="shrink each image (or crop) so its longer side is at most this")
a = ap.parse_args()

import mlx.core as mx
from mlx_vlm import load, stream_generate
from mlx_vlm.prompt_utils import apply_chat_template

# Freed buffers otherwise stay in MLX's cache and count in the process's footprint, which the guard
# reads; a small cache keeps the footprint near what the model actually holds.
mx.set_cache_limit(256 * 2**20)
t0 = time.time()
model, processor = load(a.model, trust_remote_code=not a.no_remote_code)
t1 = time.time()
prompt = a.prompt if a.no_template else apply_chat_template(processor, model.config, a.prompt, num_images=1)
images = [a.image]
if a.crops:
    import os, tempfile
    from PIL import Image
    page, tmp, images = Image.open(a.image), tempfile.mkdtemp(prefix="ocrlab-crops-"), []
    for line in open(a.crops).read().splitlines()[1:]:
        name, x, y, w, h = line.split("\t")[:5]
        x, y, w, h = int(x), int(y), int(w), int(h)
        images.append(os.path.join(tmp, name)); page.crop((x, y, x + w, y + h)).save(images[-1])
if a.max_side:
    # A model trained at a fixed resolution can spend its memory on vision tokens for a 300 dpi page.
    import os, tempfile
    from PIL import Image
    tmp, shrunk = tempfile.mkdtemp(prefix="ocrlab-shrunk-"), []
    for i, path in enumerate(images):
        im = Image.open(path); im.thumbnail((a.max_side, a.max_side), Image.LANCZOS)
        shrunk.append(os.path.join(tmp, f"{i}.png")); im.save(shrunk[-1])
    images = shrunk
text, last, cut, gen = [], None, "-", 0
first = None
for img in images:
    last = None   # a crop that yields nothing must not count the previous crop's tokens again
    for r in stream_generate(model, processor, prompt, image=[img], max_tokens=a.max_tokens, temperature=0.0):
        if first is None: first = time.time()
        text.append(r.text); last = r
        if time.time() - t1 > a.seconds:
            cut = "seconds"; break
    gen += getattr(last, "generation_tokens", 0)
    if cut == "seconds": break
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
