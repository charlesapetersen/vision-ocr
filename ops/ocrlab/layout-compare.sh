#!/bin/bash
# ops/ocrlab/layout-compare.sh — layout-compare (QUEUE.md, owner 2026-10-14): three layout detectors, DocLayout-YOLO
# (what the app ships), PP-DocLayoutV3 and docling-layout-heron, each cutting the sample's 11 newspaper pages and C41's
# four other whole-page scans (layout-sample.tsv), each detector's regions read by Vision, PaddleOCR-VL and Falcon-OCR
# through the production pipeline, one page at a time, as ocr-compare-run ran (hybrid-run.sh: score-gate publishes,
# ux-harness --truth scores; layout-combos.tsv). The job lives in $STATE/ocrlab/layout and resumes from what is saved.
#
#   layout-compare.sh start|run|status|stop      as hybrid-run.sh; HYBRID_COMBOS and HYBRID_PAGES narrow a smoke run
#
# Afterwards: hybrid-table.py $STATE/ocrlab/layout LAYOUT-COMPARE-<date>.tsv LAYOUT-COMPARE-<date>-pages.tsv, and
# layout-fit.sh for each detector's own load, detect time and memory.
here="$(cd "$(dirname "$0")" && pwd)"
STATE="${STATE:-$HOME/.local/state/visionocr-autonomous}"
export HYBRID_DIR="${HYBRID_DIR:-$STATE/ocrlab/layout}"
export HYBRID_SAMPLE="${HYBRID_SAMPLE:-$here/layout-sample.tsv}" HYBRID_COMBOS_TSV="${HYBRID_COMBOS_TSV:-$here/layout-combos.tsv}"
# The heavy lock once for each reader's three detectors (hybrid-run.sh's header, HYBRID_HOLD): Archive Suite's sessions
# queue half-hour VM runs behind every release, so a page or a combination at a time would take a day.
export HYBRID_HOLD="${HYBRID_HOLD:-group}"
exec "$here/hybrid-run.sh" "$@"
