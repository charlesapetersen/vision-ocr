"""chandra_blocks.py — Chandra OCR 2's layout HTML as the app's `replace` blocks.

    python -I chandra_blocks.py <answer.html> <out.tsv>

Chandra answers its layout prompt (chandra-layout-prompt.txt) with one top-level
`<div data-bbox="x0 y0 x1 y1" data-label="L">…</div>` a block, the box on a 0-1000 grid
of the image. Each becomes one line of out.tsv, `x0 y0 x1 y1 label text`, tab-separated,
the four as fractions of the image (`Recogniser.modelBlocks`); the text keeps its inline
markup, which the app strips, with tabs and newlines made spaces, and without its `<img>`
tags, whose `alt` holds Chandra's description of a picture, not the page's words. An
answer with no block at all is a blank page, written as no lines; the app fails a page
Vision read lines on that the model gave none. Exit 1 when a block opened and never
closed: a reading cut short, and when a block holding words has no box this can read
(`[x0, y0, x1, y1]` and bare numbers are read), rather than leave its words out unsaid.
"""
import re, sys

answer = open(sys.argv[1], encoding="utf-8").read()
tag = re.compile(r"<(/?)div\b([^>]*)>", re.I)
n = r"(-?[\d.]+)"
box = re.compile(r'data-bbox="\s*\[?\s*' + n + r"[\s,]+" + n + r"[\s,]+" + n + r"[\s,]+" + n + r'\s*\]?\s*"')
label = re.compile(r'data-label="([^"]*)"')
img = re.compile(r"""<img\b(?:[^>"']|"[^"]*"|'[^']*')*>""", re.I)
rows, depth, opened = [], 0, None
for m in tag.finditer(answer):
    if not m.group(1):
        depth += 1
        if depth == 1:
            opened = m
        continue
    depth -= 1
    if depth < 0:
        depth = 0
        continue
    if depth == 0 and opened is not None:
        b = box.search(opened.group(2))
        inner = " ".join(img.sub(" ", answer[opened.end():m.start()]).split())
        if not b and re.sub(r"<[^>]*>", "", inner).strip():
            sys.exit(f"chandra_blocks.py: a block with words has no box the app can read: {opened.group(0)}")
        if b:
            l = label.search(opened.group(2))
            x0, y0, x1, y1 = (float(v) / 1000 for v in b.groups())
            rows.append(f"{x0:.4f}\t{y0:.4f}\t{x1:.4f}\t{y1:.4f}\t{l.group(1) if l else ''}\t{inner}")
        opened = None
if depth != 0:
    sys.exit(1)
open(sys.argv[2], "w", encoding="utf-8").write("".join(r + "\n" for r in rows))
