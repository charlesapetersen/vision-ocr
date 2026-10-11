#!/usr/bin/env python3
"""hybrid-table.py — ocr-hybrid-run's table, from what hybrid-run.sh saved.

    hybrid-table.py <H> <out.tsv> [<pages.tsv>]     H is $STATE/ocrlab/hybrid (or a smoke run's directory)

One row per combination and page group (all, newspaper, other), each against Vision alone (vision-off) on the
same pages, and the combinations hybrid-run.sh does not run, with the reason. With a third argument, one row per
combination and page as well, for ocr-hybrid-pick to regroup (old print, a route).

Columns, over the group's pages the combination published and the truth set scores (`truth.tsv`):
  pages ok failed skipped   runs: published and scored by the harness / refused by the app / not run
  unscored     published pages with no truth row (no transcript, too few words, or the harness failed)
  scored right wrong missing added   ux-harness --truth's word counts, summed
  wm_share     (wrong + missing) / scored: the words a reader copies wrong or cannot copy
  vision_wm    the same for vision-off on the same pages; wm_cut  1 - wm_share / vision_wm (the pick rule's
               "cut by at least a third" is wm_cut >= 0.33)
  copyErr      (wrong + missing + added) / scored        find  mean of the pages' find
  order        adjacent columns in order, summed "a/b"   tflags  pages with any truth flag (tcopy tfind tink tcolour)
  ink_red colour_red   pages the harness's page row flags `faint`/`legibility` or `colour`
  elInk elCol  the least over the pages (the truth set's elements: ink and colour kept)
  secs vision_secs ratio   mean seconds the app took over a published page (the gate's timings.tsv: the
               model's calls inside it, not the gate's start or its pixel check), Vision's on the same pages, and
               their ratio (the rule: at most 3)
  model_secs   mean seconds of the model's own calls a page (the guard's rows)
  peak_mb      the largest guard peak (larger of RSS and footprint) of any model call, failed pages included
  bytes vision_bytes   total size of the published pages, and Vision's on the same pages
  note         `-`, or why a combination was not run
A page failed or skipped counts in no measure; `failed` says how many, and the pages file says why.
"""
import os
import sys
from collections import defaultdict

H, OUT = sys.argv[1], sys.argv[2]
PAGES_OUT = sys.argv[3] if len(sys.argv) > 3 else None


def rows(path):
    try:
        lines = open(path, encoding="utf-8").read().splitlines()
    except OSError:
        return []
    lines = [l for l in lines if l and not l.startswith("#")]
    if not lines:
        return []
    head = lines[0].split("\t")
    return [dict(zip(head, l.split("\t"))) for l in lines[1:]]


def num(s):
    try:
        return float(s)
    except (TypeError, ValueError):
        return None


sample = {}
for line in open(os.path.join(H, "sample.rows"), encoding="utf-8"):
    f = line.rstrip("\n").split("\t")
    if len(f) >= 6:
        sample[f[0]] = {"doc": f[1], "page": f[2], "route": f[3], "why": f[4], "class": f[5]}

combos = [l.split("\t")[0] for l in open(os.path.join(H, "combos.tsv"), encoding="utf-8").read().splitlines() if l]
not_run = [l.split("\t", 1) for l in open(os.path.join(H, "not-run.tsv"), encoding="utf-8").read().splitlines() if l]


def page(combo, pid):
    d = os.path.join(H, "runs", combo, pid)
    try:
        status = open(os.path.join(d, "status"), encoding="utf-8").read().strip()
    except OSError:
        return None
    r = {"combo": combo, "id": pid, "status": status.split(" ", 1)[0], "reason": "-"}
    parts = status.split(" ")
    # ok <app s> <wall s> harness-exit <n> · failed <app s> <wall s> <reason> · skipped <reason>
    if r["status"] in ("ok", "failed"):
        r["secs"], r["wall"] = num(parts[1]), num(parts[2])
    if r["status"] == "ok":
        r["harness"] = parts[4] if len(parts) > 4 else "-"
    else:
        r["reason"] = " ".join(parts[3:] if r["status"] == "failed" else parts[1:])
    guards = []
    for line in open(os.path.join(d, "guard.tsv"), encoding="utf-8") if os.path.exists(os.path.join(d, "guard.tsv")) else []:
        f = line.rstrip("\n").split("\t")
        if f[0] == "GUARD" and len(f) >= 10:
            guards.append(f)
    r["model_secs"] = sum(num(g[4]) or 0 for g in guards) if guards else 0.0
    r["peak_mb"] = max((max(num(g[5]) or 0, num(g[6]) or 0) for g in guards), default=0)
    r["calls"] = len(guards)
    r["killed"] = sum(1 for g in guards if g[9] != "-")
    if r["status"] == "ok":
        t = rows(os.path.join(d, "score", "truth.tsv"))
        p = rows(os.path.join(d, "score", "pages.tsv"))
        doc = rows(os.path.join(d, "score", "document.tsv"))
        r["truth"] = t[0] if t else None
        r["pagerow"] = p[0] if p else None
        # `source>output`, e.g. 260123>84088
        r["bytes"] = num(doc[0].get("bytes", "").partition(">")[2]) if doc else None
    return r


data = {c: {pid: page(c, pid) for pid in sample} for c in combos}
data = {c: {k: v for k, v in pages.items() if v} for c, pages in data.items()}


def group_of(pid):
    return "newspaper" if sample[pid]["route"] == "newspaper" else "other"


COLS = ("combo group pages ok failed skipped unscored scored right wrong missing added wm_share vision_wm wm_cut copyErr find "
        "order tflags ink_red colour_red elInk elCol secs vision_secs ratio model_secs peak_mb bytes vision_bytes note").split()


def fmt(v, digits=4):
    if v is None:
        return "-"
    if isinstance(v, float):
        return f"{v:.{digits}f}" if abs(v) < 100 else f"{v:.0f}"
    return str(v)


def summarise(combo, group):
    pages = {k: v for k, v in data[combo].items() if group == "all" or group_of(k) == group}
    if not pages:
        return None
    ok = {k: v for k, v in pages.items() if v["status"] == "ok"}
    vis = data.get("vision-off", {})
    s = defaultdict(float)
    vs = defaultdict(float)
    finds, elink, elcol, order_a, order_b, tflags = [], [], [], 0, 0, 0
    ink_red = colour_red = 0
    secs, vsecs, msecs, bytes_, vbytes = [], [], [], 0.0, 0.0
    unscored = 0
    for k, v in ok.items():
        t = v.get("truth")
        if not (t and num(t.get("scored"))):
            unscored += 1
        w = vis.get(k)
        wt = w.get("truth") if w and w["status"] == "ok" else None
        if t and num(t.get("scored")) and wt:   # only pages both scored, so the two shares are of the same words
            for c in ("scored", "right", "wrong", "missing", "added"):
                s[c] += num(t[c]) or 0
                vs[c] += num(wt[c]) or 0
            if num(t.get("find")) is not None:
                finds.append(num(t["find"]))
            a, _, b = t.get("order", "").partition("/")
            if a.isdigit() and b.isdigit():
                order_a += int(a); order_b += int(b)
            if t.get("tflags", "-") not in ("-", ""):
                tflags += 1
            for c, lst in (("elInk", elink), ("elCol", elcol)):
                if num(t.get(c)) is not None:
                    lst.append(num(t[c]))
        pr = v.get("pagerow")
        if pr:
            fl = pr.get("flags", "-")
            ink_red += any(x in fl for x in ("faint", "legibility"))
            colour_red += "colour" in fl
        if v.get("secs") is not None and w and w["status"] == "ok" and w.get("secs") is not None:
            secs.append(v["secs"]); vsecs.append(w["secs"]); msecs.append(v["model_secs"])
        if v.get("bytes") and w and w.get("bytes"):
            bytes_ += v["bytes"]; vbytes += w["bytes"]
    wm = (s["wrong"] + s["missing"]) / s["scored"] if s["scored"] else None
    vwm = (vs["wrong"] + vs["missing"]) / vs["scored"] if vs["scored"] else None
    mean = lambda x: sum(x) / len(x) if x else None
    return {
        "combo": combo, "group": group, "pages": len(pages), "ok": len(ok),
        "failed": sum(v["status"] == "failed" for v in pages.values()),
        "skipped": sum(v["status"] == "skipped" for v in pages.values()),
        "unscored": unscored,
        "scored": int(s["scored"]), "right": int(s["right"]), "wrong": int(s["wrong"]),
        "missing": int(s["missing"]), "added": int(s["added"]),
        "wm_share": wm, "vision_wm": vwm,
        "wm_cut": (1 - wm / vwm) if wm is not None and vwm else None,
        "copyErr": (s["wrong"] + s["missing"] + s["added"]) / s["scored"] if s["scored"] else None,
        "find": mean(finds), "order": f"{order_a}/{order_b}" if order_b else "-", "tflags": tflags,
        "ink_red": ink_red, "colour_red": colour_red,
        "elInk": min(elink) if elink else None, "elCol": min(elcol) if elcol else None,
        "secs": mean(secs), "vision_secs": mean(vsecs),
        "ratio": (mean(secs) / mean(vsecs)) if secs and mean(vsecs) else None,
        "model_secs": mean(msecs), "peak_mb": int(max((v["peak_mb"] for v in pages.values()), default=0)) or None,
        "bytes": int(bytes_) or None, "vision_bytes": int(vbytes) or None, "note": "-",
    }


with open(OUT, "w", encoding="utf-8") as f:
    f.write("\t".join(COLS) + "\n")
    for c in combos:
        for g in ("all", "newspaper", "other"):
            r = summarise(c, g)
            if r:
                f.write("\t".join(fmt(r[k]) for k in COLS) + "\n")
    for label, why in not_run:
        f.write("\t".join([label, "all"] + ["-"] * (len(COLS) - 3) + [f"not run: {why}"]) + "\n")
print(f"hybrid-table: {OUT}")

if PAGES_OUT:
    PC = ("combo id document page route class status secs wall model_secs peak_mb calls killed scored right wrong missing "
          "added copyErr find order layerMiss elInk elCol tflags flags bytes reason").split()
    with open(PAGES_OUT, "w", encoding="utf-8") as f:
        f.write("\t".join(PC) + "\n")
        for c in combos:
            for pid in sorted(data[c]):
                v, sm = data[c][pid], sample[pid]
                t = v.get("truth") or {}
                pr = v.get("pagerow") or {}
                vals = [c, pid, sm["doc"], sm["page"], sm["route"], sm["class"], v["status"], fmt(v.get("secs"), 1), fmt(v.get("wall"), 0),
                        fmt(v.get("model_secs"), 0), fmt(int(v["peak_mb"]) or None), str(v["calls"]), str(v["killed"])]
                vals += [t.get(k, "-") for k in ("scored", "right", "wrong", "missing", "added", "copyErr", "find",
                                                  "order", "layerMiss", "elInk", "elCol", "tflags")]
                reason = v["reason"] if v["status"] != "ok" else f"harness exit {v.get('harness', '-')}"
                vals += [pr.get("flags", "-"), fmt(v.get("bytes")), reason.replace("\t", " ")]
                f.write("\t".join(vals) + "\n")
    print(f"hybrid-table: {PAGES_OUT}")
