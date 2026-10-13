# lib-fake-suite.sh — sourced by prove-run-tests.sh and prove-mac-heavy-lock.sh. Builds a scratch tree that
# run_tests.sh can run in, with fake swiftc / xcrun / sw_vers / uname / jbig2 / qpdf first on PATH, so the
# script's real logic (keys, cache, stamp, which lock wraps which phase) runs without compiling or OCRing
# anything. Every call is appended to $FAKE_LOG:
#   compile <output name> heavy=<yes|no> testlock=<yes|no> args=<swiftc args>
#   run <binary name> build=<n> heavy=<yes|no> label=<heavy-lock holder label>
# where build=<n> is the compile count at the moment that binary was written, so a run served from the cache
# shows the build number of the compile that made it. Knobs (environment): FAKE_SWIFT_VERSION, FAKE_SDK,
# FAKE_SDKPATH, FAKE_BUILD, FAKE_ARCH, FAKE_JBIG2, FAKE_QPDF, FAKE_LOGIN_DIR (the login shell's tools, with
# SHELL=$FB/loginsh); FAKE_FAIL=<output name> fails that compile;
# FAKE_EDIT_DURING=<file> is appended to during each compile; FAKE_TESTS_RC is the suite's exit status;
# FAKE_RUN_SLEEP delays the suite and logs `runoverlap <n>`, n being how many other fake suites were running when it
# started; FAKE_RUN_EDIT=<file> is appended to during the suite.
# FAKE_COMPILE_SLEEP holds each compile open that long and logs `overlap <output name> <n>`, n being how many other
# fake compiles were in progress when it started (any tree sharing $FAKE_LOG). FAKE_OK_MV_DELAY=<s> makes the
# FIRST `mv` onto a file named `ok` (once per $FAKE_LOG) sleep that long first: the window in which a second,
# unserialised writer of the same cache key can put its binary under the first one's checksum.
# Needs $T (a scratch directory) and the real run_tests.sh path in $1 of fake_tree.

fake_bin() {   # $1 directory to fill
  local b="$1"; mkdir -p "$b"
  cat > "$b/swiftc" <<'EOF'
#!/bin/bash
[ "${1:-}" = --version ] && { echo "fake swift ${FAKE_SWIFT_VERSION:-1}"; exit 0; }
out=""; prev=""; for a in "$@"; do [ "$prev" = -o ] && out="$a"; prev="$a"; done
heavy=no; [ -d "${MAC_HEAVY_LOCK:-/nonexistent}" ] && heavy=yes
tl=no; [ -n "${VISIONOCR_TEST_LOCK:-}" ] && [ -d "$VISIONOCR_TEST_LOCK" ] && tl=yes
echo "compile ${out##*/} heavy=$heavy testlock=$tl args=$*" >> "$FAKE_LOG"
[ -n "${FAKE_EDIT_DURING:-}" ] && echo "// edited during the compile" >> "$FAKE_EDIT_DURING"
if [ -n "${FAKE_COMPILE_SLEEP:-}" ]; then
  act="$FAKE_LOG.active"; mkdir -p "$act"
  echo "overlap ${out##*/} $(ls "$act" | wc -l | tr -d ' ')" >> "$FAKE_LOG"
  : > "$act/$$"; sleep "$FAKE_COMPILE_SLEEP"; rm -f "$act/$$"
fi
[ -n "${FAKE_FAIL:-}" ] && [ "${out##*/}" = "$FAKE_FAIL" ] && { echo "error: fake compile failure" >&2; exit 1; }
n=$(grep -c '^compile' "$FAKE_LOG")
cat > "$out" <<EOS
#!/bin/bash
# made by fake compile $$ (so two compiles of one key differ, as prove-run-tests [5] needs)
h=no; [ -d "\$MAC_HEAVY_LOCK" ] && h=yes
echo "run \${0##*/} build=$n heavy=\$h label=\$(sed -n 's/^label=//p' "\$MAC_HEAVY_LOCK/owner" 2>/dev/null)" >> "\$FAKE_LOG"
[ -n "\${FAKE_RUN_EDIT:-}" ] && echo "// edited during the run" >> "\$FAKE_RUN_EDIT"
if [ -n "\${FAKE_RUN_SLEEP:-}" ]; then
  ra="\$FAKE_LOG.running"; mkdir -p "\$ra"
  echo "runoverlap \$(ls "\$ra" | wc -l | tr -d ' ')" >> "\$FAKE_LOG"
  : > "\$ra/\$\$"; sleep "\$FAKE_RUN_SLEEP"; rm -f "\$ra/\$\$"
fi
echo "3/3 passed"
exit \${FAKE_TESTS_RC:-0}
EOS
chmod +x "$out"
EOF
  cat > "$b/mv" <<'EOF'
#!/bin/bash
last=""; for a in "$@"; do last="$a"; done
if [ -n "${FAKE_OK_MV_DELAY:-}" ] && [ "${last##*/}" = ok ] && mkdir "$FAKE_LOG.ok-delayed" 2>/dev/null; then
  sleep "$FAKE_OK_MV_DELAY"
fi
exec /bin/mv "$@"
EOF
  cat > "$b/xcrun" <<'EOF'
#!/bin/bash
case "$*" in
  --show-sdk-version) echo "${FAKE_SDK:-27.0}" ;;
  --show-sdk-path) echo "${FAKE_SDKPATH:-/fake/MacOSX.sdk}" ;;
  *) exit 1 ;;
esac
EOF
  printf '#!/bin/bash\n[ "$1" = -buildVersion ] && { echo "${FAKE_BUILD:-25G72}"; exit 0; }\nexit 1\n' > "$b/sw_vers"
  printf '#!/bin/bash\n[ "$*" = -m ] && { echo "${FAKE_ARCH:-arm64}"; exit 0; }\nexec /usr/bin/uname "$@"\n' > "$b/uname"
  printf '#!/bin/bash\necho "jbig2enc ${FAKE_JBIG2:-0.32}"\n' > "$b/jbig2"
  printf '#!/bin/bash\necho "qpdf version ${FAKE_QPDF:-12.3.2}"\n' > "$b/qpdf"
  # A login shell for run_tests.sh's `$SHELL -lc "command -v X"`: a startup line, then $FAKE_LOGIN_DIR/X if it is there.
  printf '#!/bin/bash\necho "Last login: fake"\nn="${2##* }"\n[ -n "${FAKE_LOGIN_DIR:-}" ] && [ -x "$FAKE_LOGIN_DIR/$n" ] && echo "$FAKE_LOGIN_DIR/$n"\nexit 0\n' > "$b/loginsh"
  chmod +x "$b"/*
}

fake_tree() {   # $1 run_tests.sh to install, $2 directory to create
  local rt="$1" d="$2" f
  mkdir -p "$d/Sources" "$d/Tests" "$d/Helper" "$d/Tools" "$d/build"
  for f in App Prefs Runner Recogniser SearchableWriter Flattener JBIG2 Model; do
    echo "// $f" > "$d/Sources/$f.swift"
  done
  echo "// tests" > "$d/Tests/main.swift"
  echo "// helper" > "$d/Helper/main.swift"
  echo "// plates" > "$d/Tools/make-plate-fixtures.swift"
  cp "$rt" "$d/run_tests.sh"; chmod +x "$d/run_tests.sh"
}

# compiles_since N — the output names compiled after line N of $FAKE_LOG, space-separated and sorted.
log_lines() { wc -l < "$FAKE_LOG" 2>/dev/null | tr -d ' '; }
compiles_since() { tail -n +"$(( $1 + 1 ))" "$FAKE_LOG" | sed -n 's/^compile \([^ ]*\) .*/\1/p' | sort | tr '\n' ' ' | sed 's/ $//'; }
runs_since() { tail -n +"$(( $1 + 1 ))" "$FAKE_LOG" | grep -c '^run '; }
