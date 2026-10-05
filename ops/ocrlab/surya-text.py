"""surya-text.py <results.json> <out.txt> [names…] — plain text from surya_ocr's results.json.

surya_ocr (the surya-ocr package, run from $OCRLAB/venv-surya) writes one entry per input image, each a
list of pages of blocks in reading order, the text as HTML. This joins the blocks' text, tags stripped,
taking the images in the order given (a crops.tsv's names) or else as the file lists them.
"""
import html, json, re, sys

d = json.load(open(sys.argv[1]))
names = sys.argv[3:] or list(d)
out = []
for name in names:
    for page in d.get(name, []):
        for b in sorted(page.get("blocks", []), key=lambda b: b.get("reading_order", 0)):
            t = html.unescape(re.sub(r"<[^>]+>", " ", b.get("html") or ""))
            if t.strip(): out.append(re.sub(r"[ \t]+", " ", t).strip())
open(sys.argv[2], "w").write("\n".join(out) + "\n")
