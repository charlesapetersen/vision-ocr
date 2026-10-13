#!/bin/bash
# make-runtime.sh — build the model runtime ocr-integrate-engine ships: a standalone CPython with only what
# mlx-vlm needs to run Falcon-OCR bf16 and PaddleOCR-VL 1.6 4-bit, in one directory that runs from any path.
#
#   make-runtime.sh <out dir>    writes <out dir>/runtime/ and <out dir>/runtime.tgz, prints sizes and the sha256
#
# Plan and measurements: OCR-RUNTIME-PLAN-2026-10-13.md (BUGS.md C57). The lab's venv carries 829 MB of tools
# (onnxruntime, OpenCV, SciPy, matplotlib) the two readers do not import; this one is the readers' closure and
# nothing else. mlx-vlm is installed without its dependencies: its required list pulls in a web server, audio
# and OpenCV, none of which a page read touches. The pins are the lab venv's, the versions ocr-compare-run's
# figures were measured on; change one and the readings must be compared again. Only the top level is pinned.
set -eu
[ $# -eq 1 ] || { echo "usage: make-runtime.sh <out dir>" >&2; exit 2; }
PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
command -v uv >/dev/null || { echo "make-runtime.sh: needs uv" >&2; exit 1; }
out="$1"
[ -e "$out/runtime" ] || [ -e "$out/runtime.tgz" ] && { echo "make-runtime.sh: $out already holds a runtime" >&2; exit 1; }
mkdir -p "$out"
work="$(mktemp -d -t visionocr-runtime)"
# A build that fails leaves no runtime behind, so the next one can start.
ok=0
trap 'rm -rf "$work"; [ $ok = 1 ] || rm -rf "$out/runtime" "$out/runtime.tgz"' EXIT
trap 'exit 1' INT TERM
uv python install -q 3.12.13
# --managed-python: uv's own install, never a venv that happens to be active or nearby, whose python is a
# symlink back to this Mac's uv.
base="$(dirname "$(dirname "$(VIRTUAL_ENV= uv python find --managed-python 3.12.13)")")"
[ -e "$base/pyvenv.cfg" ] && { echo "make-runtime.sh: $base is a venv, not an install" >&2; exit 1; }
uv venv -q --python 3.12.13 "$work/env"
uv pip install -q --python "$work/env/bin/python" \
    mlx==0.32.3 mlx-metal==0.32.3 transformers==5.18.0 tokenizers==0.23.2 safetensors==0.8.0 \
    huggingface-hub==1.33.0 numpy==2.5.3 pillow==12.3.0 jinja2==3.1.6 sentencepiece==0.2.2 tqdm==4.70.1 \
    requests==2.34.2
uv pip install -q --python "$work/env/bin/python" --no-deps mlx-vlm==0.7.4
# The interpreter, then the readers' packages in its own site-packages, so nothing points back at uv.
rsync -a --exclude __pycache__ --exclude 'lib/python3.12/site-packages/' "$base/" "$out/runtime/"
rsync -a --exclude __pycache__ "$work/env/lib/python3.12/site-packages/" "$out/runtime/lib/python3.12/site-packages/"
[ -z "$(find "$out/runtime" -type l -lname '/*' | head -1)" ] \
    || { echo "make-runtime.sh: the runtime holds a symlink to an absolute path" >&2; exit 1; }
# The two readers' own modules too: mlx-vlm imports a model's module only when the model is opened.
"$out/runtime/bin/python3" -I -c 'import mlx.core, mlx_vlm, transformers, PIL, mlx_vlm.models.falcon_ocr, mlx_vlm.models.paddleocr_vl' \
    || { echo "make-runtime.sh: the built runtime cannot import the readers" >&2; exit 1; }
( cd "$out" && tar -czf runtime.tgz runtime )
du -sh "$out/runtime" | awk '{print "on disk  " $1}'
ls -l "$out/runtime.tgz" | awk '{print "archive  " $5 " B"}'
# tar keeps mtimes, so the hash differs on every build: the app must carry the hash of the archive published.
shasum -a 256 "$out/runtime.tgz" | awk '{print "sha256   " $1}'
ok=1
