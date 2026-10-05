"""read-gguf.py — read-mlx.py's twin for GGUF builds, through llama.cpp's llama-mtmd-cli.

    python read-gguf.py <model.gguf>,<mmproj.gguf> <image.png> <out.txt> [--prompt P] [--max-tokens N]
                        [--seconds S] [--crops crops.tsv]

One llama-mtmd-cli run per image (each crop reloads the model; the load is counted in read_s, and
load_s is the first run's load as llama.cpp reports it). Same JSON statistics line as read-mlx.py;
mlx_peak_gb is "-" here, so the guard's footprint is the memory figure.
"""
import argparse, json, os, re, subprocess, tempfile, time

ap = argparse.ArgumentParser()
ap.add_argument("model"); ap.add_argument("image"); ap.add_argument("out")
ap.add_argument("--prompt", default="Transcribe all the text on this page, in reading order, as plain text.")
ap.add_argument("--max-tokens", type=int, default=12000)
ap.add_argument("--seconds", type=float, default=600)
ap.add_argument("--crops")
a = ap.parse_args()
gguf, mmproj = a.model.split(",")

images = [a.image]
if a.crops:
    from PIL import Image
    page, tmp, images = Image.open(a.image), tempfile.mkdtemp(prefix="ocrlab-crops-"), []
    for line in open(a.crops).read().splitlines()[1:]:
        name, x, y, w, h = line.split("\t")[:5]
        x, y, w, h = int(x), int(y), int(w), int(h)
        images.append(os.path.join(tmp, name)); page.crop((x, y, x + w, y + h)).save(images[-1])

t1 = time.time()
text, gen, cut, load_s = [], 0, "-", None
for img in images:
    left = a.seconds - (time.time() - t1)
    if left <= 0: cut = "seconds"; break
    try:
        p = subprocess.run(["/opt/homebrew/bin/llama-mtmd-cli", "-m", gguf, "--mmproj", mmproj, "--image", img,
                            "-p", a.prompt, "-n", str(a.max_tokens), "--temp", "0", "-c", "16384",
                            "-ngl", "99", "--no-warmup"], capture_output=True, text=True, timeout=left)
    except subprocess.TimeoutExpired:
        cut = "seconds"; break
    text.append(p.stdout.strip() + "\n")
    m = re.search(r"load time =\s*([\d.]+) ms", p.stderr)
    if load_s is None and m: load_s = round(float(m.group(1)) / 1000, 1)
    m = re.search(r"eval time =\s*[\d.]+ ms /\s*(\d+) runs", p.stderr.split("prompt eval time")[-1])
    n = int(m.group(1)) if m else 0
    gen += n
    if n >= a.max_tokens: cut = "max_tokens"
    if p.returncode != 0:
        open(a.out + ".stderr", "w").write(p.stderr); cut = f"exit{p.returncode}"; break
t2 = time.time()
out = "".join(text)
open(a.out, "w").write(out)
print(json.dumps({"load_s": load_s if load_s is not None else "-", "read_s": round(t2 - t1, 1),
                  "gen_tokens": gen, "images": len(images), "mlx_peak_gb": "-", "cut": cut, "chars": len(out)}))
