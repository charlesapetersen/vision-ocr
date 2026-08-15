# MRC over the corpus, 2026-08-15

The five runs behind `BUGS.md` T15, `REVIEW-2026-08-14.md` A12.3 and the MRC entry in
`FEATURES.md`. **A record of one afternoon, not a claim about the present** — the same
shape as `CORPUS-2026-08-08.md` and `CORPUS-2026-08-09.md`.

They are committed because `testdocs/` is not. The corpus is 1.2 GB of third-party
copyrighted PDFs, so a reader who wants to check the arithmetic behind "4.37x" or
"14.6x" would otherwise have to rebuild it from a Zotero library first and then spend
about 35 minutes re-running. The review of the commit that produced these figures
recomputed every one of them from these files and found two arithmetic errors in the
prose; the next reader should be able to do the same.

| file | run | what it establishes |
|---|---|---|
| `confined-balanced.tsv` | shipped route, Photo detail Balanced | the headline: 74 picture pages, 88,972 KB today → 20,364 KB, 4.37x |
| `mirrored-instrument.tsv` | the tool as it was before T15 | the comparison: 72 pages, layered total 43% too high, and the two >60 MP pages missing |
| `blind-stencil.tsv` | `MRC_BLIND=1` | the confinement table. **Not like-for-like on page totals** — blind mode also skips R50's shrink and layers colour pages in grey, so only `maskKB` compares everywhere |
| `photo-detail-maximum.tsv` | `MRC_BG=1` | 83,435 KB published, and three layers losing to one image on 31 of 74 pages |
| `photo-detail-smallest.tsv` | `MRC_BG=3` | 13,363 KB, 6.66x — and identical to Balanced on every all-text page, because the shrink is a floor |

`mirrored-instrument.tsv` has the **old** 11-column header and prints integer KB, with a
twelfth unnamed field — that reporting defect is part of what T15 fixed. Its totals are
therefore up to 1 KB per page low, which slightly *understates* the overstatement it is
evidence for. The other four carry the current 19-column header.

## Regenerating

```sh
mkdir -p /tmp/h && cp Tools/score-mrc.swift /tmp/h/main.swift
swiftc -O -o /tmp/score-mrc -target "$(uname -m)-apple-macos13.0" \
  $(ls Sources/*.swift | grep -v App.swift) /tmp/h/main.swift

/tmp/score-mrc            testdocs/*/*.pdf > confined-balanced.tsv
MRC_BLIND=1 /tmp/score-mrc testdocs/*/*.pdf > blind-stencil.tsv
MRC_BG=1    /tmp/score-mrc testdocs/*/*.pdf > photo-detail-maximum.tsv
MRC_BG=3    /tmp/score-mrc testdocs/*/*.pdf > photo-detail-smallest.tsv
```

About 7 minutes each; two can run at once. `mirrored-instrument.tsv` needs the tool as it
stood at `105a24f` — `git show 105a24f:Tools/score-mrc.swift`.

Numbers will move as the corpus does. Quote the date with the figure.
