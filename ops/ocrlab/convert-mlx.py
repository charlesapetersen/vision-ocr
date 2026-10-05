# ops/ocrlab/convert-mlx.py <mlx_vlm.convert args…>, run with the lab venv's python and HF_HOME=$OCRLAB/hf.
# mlx_vlm 0.7.4's convert copies the HF cache's files keeping their read-only mode, then fails overwriting
# tokenizer.json in processor.save_pretrained, before it writes the quantized config.json: the weights are
# quantized, the copied source config does not say so, and the build will not load. This copies them writable.
# (Subdirectories go through copytree's copy2 and stay read-only; LightOnOCR has none.)
# Builds go to $OCRLAB/mlx/<name>, which try-mlx.sh and bakeoff.sh read as `local/<name>`.
import os, shutil, sys

_copy = shutil.copy


def copy(src, dst, **kw):
    r = _copy(src, dst, **kw)
    os.chmod(r, 0o644)
    return r


shutil.copy = copy
from mlx_vlm.convert import main  # noqa: E402

sys.argv = ["convert"] + sys.argv[1:]
main()
