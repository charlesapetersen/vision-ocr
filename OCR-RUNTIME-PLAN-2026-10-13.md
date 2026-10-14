# The model runtime for the accurate mode: plan, 2026-10-13

This is the first sub-box of `ocr-integrate-engine` (`BUGS.md` C57). It says how the two approved models get into
the app, what that costs on disk, and how it loads in an app that is not notarized. What was measured by running
code and what was only reasoned is marked on each line.

## What is to be built

The owner approved on 2026-10-13 the recommendations of `OCR-COMPARE-DECISION-2026-10-13.md` ("Let's move forward
with the recommendations in OCR-COMPARE-DECISION-2026-10-13"). The readers to offer:

- Books, articles and other print: Vision whole page (the default), PaddleOCR-VL 1.6 4-bit on regions, Falcon-OCR
  bf16 on align.
- Newspapers: Vision whole page (the default), Vision on regions (needs no model download), PaddleOCR-VL on regions,
  Falcon-OCR on regions.
- No fill, with either model, on either kind.

So the app needs three things it does not have: a runtime for the two models, the models' weights, and
DocLayout-YOLO in a form that works without that runtime, because Vision on regions must work with no download.

## The runtime: a standalone Python with MLX, downloaded on first use

Both models ran in the lab through `mlx-vlm` 0.7.4 on MLX 0.32.3 (`ops/ocrlab/read-mlx.py`). The runtime is that
same code, cut down to what a page read imports, in one directory that runs from wherever it is unpacked.
`ops/ocrlab/make-runtime.sh` builds it from pinned versions.

Measured on this Mac, 2026-10-13:

| | Size |
|---|---|
| Runtime on disk (CPython 3.12.13, MLX, mlx-vlm, transformers, tokenizers, NumPy, Pillow) | 439-445 MB |
| Runtime as a `.tgz` download | 134 MB |
| The lab's venv, for comparison (it also holds onnxruntime, OpenCV, SciPy, matplotlib) | 829 MB |
| Falcon-OCR bf16 weights and code | 1.08 GB |
| PaddleOCR-VL 1.6 4-bit weights and code | 0.70 GB |
| DocLayout-YOLO DocStructBench, ONNX | 75 MB |

Sizes are in decimal units (1 MB = 10^6 B). The two models' figures are their snapshot files followed through
the cache's links, as the comparison's download column gives them (1.0 GB and 682 MiB).

MLX alone is 210 MB of that, and 182 MB of it is the Metal kernel library [measured, `du`]. A user who wants one
model downloads the runtime and that model: 134 MB plus 0.70 GB for PaddleOCR-VL, or plus 1.08 GB for Falcon-OCR.
The build's size varies by a few MB with the bytecode the import check leaves; the archive's hash differs on every
build, so the app carries the hash of the one archive published.

**It reads exactly as the lab did** [measured]. On two sample pages, `s01` (a short page) and `s46` (a newspaper
page that DocLayout-YOLO cut into 181 regions), Falcon-OCR's whole-page reading of both, and PaddleOCR-VL's reading of
`s46`'s 181 regions, are byte-identical between the lab's venv and the runtime. That held for the runtime built in place,
for a copy moved to a path with a space in it (`…/App Support/runtime`), and for the one `make-runtime.sh`
built from scratch. Falcon-OCR on regions was not compared; it is the same model call over crops, and its
sub-box checks it. Peak memory under `run-guarded.sh` was the same within the guard's sampling: Falcon 4.0-4.2 GB
footprint, PaddleOCR-VL 2.2-2.3 GB.

Options considered and rejected:

- **Port both models to MLX Swift and run them inside the helper.** No Python, and a smaller download. Rejected:
  it means rewriting two model architectures (`falcon_ocr`, `paddleocr_vl`) and their image processors in Swift,
  and the result would not reproduce `ocr-compare-run`'s figures byte for byte, which is this item's DONE WHEN.
  Whether MLX Swift's model library already has either architecture was not checked. If it later has both, the
  readers can move to it one at a time, measured against this runtime.
- **Ship the runtime inside the app.** Rejected: every user would download 134 MB more for a mode that is off by
  default. `ocr-integrate-settings` already says the runtime downloads on first use.
- **Use the lab's venv as it is.** Rejected: 829 MB, with packages a page read never imports, and it points back at
  uv's interpreter by an absolute path.

## How it loads in an app that is not notarized

- The app and its helper are signed ad hoc and without the hardened runtime (`build.sh`, the `codesign --sign -`
  lines). Without the hardened runtime there is no library validation [reasoned from the signing flags], and the
  runtime is not loaded into the app anyway: the helper starts `runtime/bin/python3` as a child process, the way it
  starts `jbig2`, `qpdf` and today's model reader (`Recogniser.modelReading`).
- Every Mach-O file in the runtime is already signed ad hoc by the linker [measured with `codesign -dv` on
  `python3.12` and `libmlx.dylib`], which Apple silicon requires before it runs any code. Nothing has to be
  re-signed after unpacking.
- Gatekeeper assesses a file only when it carries the quarantine attribute. A file the app downloads and writes
  itself is not quarantined unless the app's `Info.plist` asks for it with `LSFileQuarantineEnabled` [reasoned, not
  tested: a refused launch draws a dialog, and nothing may draw on the owner's display]. The downloads sub-box
  tests this in a VM (`Tools/vm-gui-check.sh`). The plan for that sub-box: check the archive's SHA-256 against
  the hash compiled into the app, remove any quarantine attribute from the archive only after the hash matches and
  before unpacking (`tar` gives every file it extracts the archive's attribute), then unpack to
  `~/Library/Application Support/Vision OCR/Runtime/<sha256>/`.
- So the user's one "Open Anyway" in System Settings, Privacy & Security, is for the app itself, as now. The
  runtime and the models ask for nothing more.
- The reader script is found from the helper's own bundle at run time, never from a stored path: an app run from
  where it was downloaded is translocated by macOS to a random path.
- The weights go under `~/Library/Application Support/Vision OCR/Models/`, and the reader runs with `HF_HOME`
  pointing there and `HF_HUB_OFFLINE=1`, so a page read never touches the network.

## The layout model: Core ML, run by the helper itself

Vision on regions is the newspaper choice for a user who downloads no model, so DocLayout-YOLO cannot depend on the
Python runtime. It is converted to Core ML once, on our side (`ops/ocrlab/convert-layout.py`; 72 MB at 32 bits,
measured; done in ie-layout). Its weights are Apache-2.0 (the DocLayout-YOLO code is AGPL-3.0, and is not shipped); it is downloaded like the models, not put in the app. The helper runs it with
Core ML and does the lab's pre- and post-processing in Swift: the letterbox to 1,024 px on grey 114
(`layout-regions.py`), the box decoding, and `dedupe-regions.py`'s merge. The test is that the Swift path gives the
lab's regions on the sample pages, and that Vision on regions reproduces its `OCR-COMPARE-2026-10-13.tsv` figures.

Rejected: running the ONNX file through onnxruntime in the Python runtime. It adds 80 MB of onnxruntime to the
runtime, and it would make Vision on regions need the runtime download.

## The guard and the fallback

`ops/ocrlab/run-guarded.sh` is a shell script; the app needs the same tripwires in Swift, in the helper: sample the
reader's process tree every 2 s and stop it when its footprint passes the memory slider's value, when memory
pressure reaches critical, or when swap grows by more than 2 GB. A stopped or failed reading falls back to
Vision's own reading for that page, and the page's report says so, naming the reason (invariant 1: a page read by a
fallback must not look like a page read by the model).

## The reader script and the app's call

Today `Prefs.modelReader` names one executable, run as `<reader> <image> <out> [crops]`. The shipped reader is the
runtime's interpreter plus a script in the app's `Resources/` (the part of `read-mlx.py` the two models use, with
the prompts the comparison used: `plain` for Falcon-OCR, `OCR:` for PaddleOCR-VL). So `modelReading` gets a form
that takes an interpreter and the script's arguments. One process per page, as now: loading took 0.4-0.9 s against
reads of 2-200 s [measured on the two pages above], so a long-lived server would save little, and a process per page
gives back all of a model's memory between pages.

## The sub-boxes, in order

1. **The runtime plan** — this document and `make-runtime.sh`. Done.
2. **The runtime in the helper** — the interpreter-plus-script form of `modelReading`, the reader script in
   `Resources/`, and a test that runs the helper on a sample page with each model and compares the result with the
   lab's reading. The runtime and weights come from a directory set by a default until the downloads exist.
3. **The layout model in the app** — the Core ML conversion, the Swift pre- and post-processing and dedupe, and the
   regions arrangement fed from it in place of `reader-regions.sh`.
4. **The guard and fallback** — as above, with a test that a reader made to overrun its cap falls back to Vision
   and says so.
5. **One reader at a time wired in** — Vision on regions, PaddleOCR-VL on regions, Falcon-OCR on align and on
   regions, each reproducing its `OCR-COMPARE-2026-10-13.tsv` row on the sample through the helper.

Unmeasured, and left to the last sub-box's own check: Falcon-OCR on align over the clippings the page classifier
calls print (the approval's own note).
