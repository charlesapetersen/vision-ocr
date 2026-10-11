#!/bin/bash
# ops/ocrlab/test-bakeoff-cwd.sh — a job started from a directory that is then removed still reads (bits-cwd).
#
# On 2026-10-08 `bakeoff.sh start` ran from a session worktree; the worktree was removed mid-run and every read
# after that failed in os.path.abspath, because the detached job had inherited it as its working directory.
# This starts a one-page, one-model job from a scratch directory, removes the directory before the first read,
# and checks the read is made. Everything is fake and in a temporary tree: the reader writes a line after the
# same os.path.abspath call that failed, the render tools only write files, the heavy lock is a pass-through.
# BAKEOFF_SRC names the ops/ocrlab to test (default: this script's own). Takes about 10 s.
set -u
unset VISIONOCR_MAC_HEAVY MAC_HEAVY_HELD   # an inherited one would take the real heavy lock, not the stub
PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
src="${BAKEOFF_SRC:-$(cd "$(dirname "$0")" && pwd)}"
t=$(mktemp -d "${TMPDIR:-/tmp}/bakeoff-cwd.XXXXXX")
export STATE="$t/state" OCRLAB="$t/lab"
J="$STATE/ocrlab"; repo="$t/repo"
mkdir -p "$repo/ops/ocrlab" "$repo/ops/autonomous" "$J/bin" "$OCRLAB/venv/bin" "$OCRLAB/mlx/fake" "$t/scratch"
cp "$src"/*.sh "$src"/*.py "$repo/ops/ocrlab/"
printf 't\ttest\tmlx\tlocal/fake\t-\t-\t0\n' > "$repo/ops/ocrlab/bakeoff-models.tsv"
printf 'id\tdoc\tpage\troute\twhy\tclass\ns01\tnone.pdf\t1\tnewspaper\ttest\tx\n' > "$repo/OCR-SAMPLE-test.tsv"
echo '{"quantization": {}}' > "$OCRLAB/mlx/fake/config.json"
cat > "$repo/ops/autonomous/mac-heavy-lock.sh" <<'EOF'
#!/bin/bash
while [ $# -gt 0 ] && [ "$1" != -- ]; do shift; done; shift
MAC_HEAVY_HELD=1 exec "$@"
EOF
# render-page waits, so the scratch directory is gone before the first read.
printf '#!/bin/bash\nsleep 5; : > "$4"; echo 100x100\n' > "$J/bin/render-page"
printf '#!/bin/bash\nmkdir -p "$2"; printf "file\\nc1.png\\n" > "$2/crops.tsv"\n' > "$J/bin/cut-crops"
cat > "$OCRLAB/venv/bin/python" <<'EOF'
#!/bin/bash
case "${1:-}" in
    */read-mlx.py) exec /usr/bin/python3 -c 'import os, sys; os.path.abspath("."); open(sys.argv[1], "w").write("read\n"); print("{}")' "$4" ;;
    *) exec /usr/bin/python3 "$@" ;;
esac
EOF
chmod +x "$repo/ops/autonomous/mac-heavy-lock.sh" "$J/bin/render-page" "$J/bin/cut-crops" "$OCRLAB/venv/bin/python"

fail=0
( cd "$t/scratch" && "$repo/ops/ocrlab/bakeoff.sh" start --build test ) || { echo "FAIL: start"; fail=1; }
rm -rf "$t/scratch"
for i in $(seq 1 60); do
    /usr/bin/grep -q 'job ended' "$J/bakeoff.log" 2>/dev/null && break
    sleep 1
done
if ! /usr/bin/grep -q 'job ended' "$J/bakeoff.log" 2>/dev/null; then
    echo "FAIL: the job did not end in 60 s (a refusing guard waits: is a suite or a VM running?)"
    "$repo/ops/ocrlab/bakeoff.sh" stop; fail=1
fi
if [ -s "$J/readings/t/s01.crops.txt" ]; then echo "ok: read after its starting directory was removed"
else echo "FAIL: no reading; $(cat "$J/readings/t/s01.crops.reason" 2>/dev/null)"; fail=1; fi
[ "$fail" = 0 ] && rm -rf "$t" || echo "left $t"
exit $fail
