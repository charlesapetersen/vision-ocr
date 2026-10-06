"""read-gguf.py — read-mlx.py's twin for GGUF builds, through llama.cpp's llama-mtmd-cli.

    python read-gguf.py <model.gguf>,<mmproj.gguf> <image.png> <out.txt> [--prompt P] [--max-tokens N]
                        [--seconds S] [--crops crops.tsv] [--max-side PX] [--system S]
                        [--repeat-penalty R] [--xml] [--churro]

One llama-mtmd-cli run per image (each crop reloads the model; the load is counted in read_s, and
load_s is the first run's load as llama.cpp reports it). Same JSON statistics line as read-mlx.py;
mlx_peak_gb is "-" here, so the guard's footprint is the memory figure. --system, --repeat-penalty
and --xml are Churro's (ocr-lab-round2): its system prompt, its sampler, and its XML answer turned into
plain text per image by churro_xml.py (the raw answer is kept as <out>.xml).
"""
import argparse, json, os, re, subprocess, tempfile, time

ap = argparse.ArgumentParser()
ap.add_argument("model"); ap.add_argument("image"); ap.add_argument("out")
ap.add_argument("--prompt", default="Transcribe all the text on this page, in reading order, as plain text.")
ap.add_argument("--max-tokens", type=int, default=12000)
ap.add_argument("--seconds", type=float, default=600)
ap.add_argument("--crops")
ap.add_argument("--max-side", type=int, help="shrink each image (or crop) so its longer side is at most this")
ap.add_argument("--system", help="a system prompt (llama-mtmd-cli -sys)")
ap.add_argument("--repeat-penalty", type=float)
ap.add_argument("--xml", action="store_true", help="the model answers in Churro's XML: keep its text")
ap.add_argument("--churro", action="store_true",
                help="Churro's settings in one word, for bakeoff-models.tsv's unquoted extra column")
a = ap.parse_args()
if a.churro:
    a.system = a.system or "Transcribe the entirety of this historical document to XML format."
    a.repeat_penalty, a.xml = a.repeat_penalty or 1.05, True
gguf, mmproj = a.model.split(",")

images = [a.image]
if a.crops:
    from PIL import Image
    page, tmp, images = Image.open(a.image), tempfile.mkdtemp(prefix="ocrlab-crops-"), []
    for line in open(a.crops).read().splitlines()[1:]:
        name, x, y, w, h = line.split("\t")[:5]
        x, y, w, h = int(x), int(y), int(w), int(h)
        images.append(os.path.join(tmp, name)); page.crop((x, y, x + w, y + h)).save(images[-1])
if a.max_side:
    from PIL import Image
    tmp, shrunk = tempfile.mkdtemp(prefix="ocrlab-shrunk-"), []
    for i, path in enumerate(images):
        im = Image.open(path); im.thumbnail((a.max_side, a.max_side), Image.LANCZOS)
        shrunk.append(os.path.join(tmp, f"{i}.png")); im.save(shrunk[-1])
    images = shrunk
more = []
if a.system is not None: more += ["-sys", a.system]
if a.repeat_penalty is not None: more += ["--repeat-penalty", str(a.repeat_penalty)]
if a.xml:
    import sys; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from churro_xml import xml_text

t1 = time.time()
text, raw, gen, cut, load_s = [], [], 0, "-", None
for img in images:
    left = a.seconds - (time.time() - t1)
    if left <= 0: cut = "seconds"; break
    try:
        p = subprocess.run(["/opt/homebrew/bin/llama-mtmd-cli", "-m", gguf, "--mmproj", mmproj, "--image", img,
                            "-p", a.prompt, "-n", str(a.max_tokens), "--temp", "0", "-c", "16384",
                            "-ngl", "99", "--no-warmup"] + more, capture_output=True, text=True, timeout=left)
    except subprocess.TimeoutExpired:
        cut = "seconds"; break
    raw.append(p.stdout.strip() + "\n")
    text.append((xml_text(p.stdout).strip() if a.xml else p.stdout.strip()) + "\n")
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
if a.xml: open(a.out + ".xml", "w").write("".join(raw))
print(json.dumps({"load_s": load_s if load_s is not None else "-", "read_s": round(t2 - t1, 1),
                  "gen_tokens": gen, "images": len(images), "mlx_peak_gb": "-", "cut": cut, "chars": len(out)}))
