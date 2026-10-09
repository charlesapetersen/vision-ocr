"""falcon-w13.py <build dir> — make a Falcon-OCR build written by convert-mlx.py load as the model it is.

mlx_vlm 0.7.4's falcon_ocr `sanitize` de-interleaves every `.w13.` tensor's rows (w1 and w3 are stored
interleaved in tiiuae/Falcon-OCR) whatever the key's form, so it runs again on a converted build's
already-sanitized weights and scrambles all 22 feed-forward layers: an unquantized conversion reads s01 as
noise, as do 4-bit and 8-bit (ocr-bakeoff-bits, 2026-10-08). This writes those rows back interleaved, so the
load's de-interleave restores them. Rows only: a quantized tensor's groups run along axis 1, so its weight,
scales and biases are permuted alike. A marker file keeps a second run from undoing the first.
"""
import glob, os, sys

import mlx.core as mx

d = sys.argv[1]
mark = os.path.join(d, ".w13-interleaved")
if os.path.exists(mark):
    sys.exit(f"falcon-w13: {d} is already done")
files = sorted(glob.glob(os.path.join(d, "*.safetensors")))
loaded = [(f,) + mx.load(f, return_metadata=True) for f in files]
# The source snapshot's keys hold `.w13.` too; interleaving them again would corrupt the shared HF cache.
for f, w, meta in loaded:
    if meta.get("format") != "mlx" or not all(k.startswith("language_model.") for k in w):
        sys.exit(f"falcon-w13: {f} is not a convert-mlx.py build; nothing written")
n = 0
for f, w, meta in loaded:
    for k, v in w.items():
        if ".w13." in k:
            h = v.shape[0] // 2
            w[k] = mx.stack([v[:h], v[h:]], axis=1).reshape(v.shape)
            n += 1
    mx.eval(w)
    # A temporary file and a rename, so a crash leaves each shard either old or new, never cut short.
    mx.save_safetensors(f + ".tmp.safetensors", w, metadata=meta)
if n == 0:
    sys.exit(f"falcon-w13: no .w13. tensors in {d}")
for f, _, _ in loaded:
    os.replace(f + ".tmp.safetensors", f)
import mlx_vlm
open(mark, "w").write(f"{n} tensors, mlx_vlm {mlx_vlm.__version__}\n")
print(f"falcon-w13: {n} tensors re-interleaved in {d}")
