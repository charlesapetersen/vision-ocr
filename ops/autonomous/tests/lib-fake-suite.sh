# lib-fake-suite.sh — sourced by prove-run-tests.sh and prove-mac-heavy-lock.sh. Builds a scratch tree that
# run_tests.sh can run in, with fake swiftc / xcrun / sw_vers / uname / jbig2 / qpdf first on PATH, so the
# script's real logic (keys, cache, stamp, which lock wraps which phase) runs without compiling or OCRing
# anything. Every call is appended to $FAKE_LOG:
#   compile <output name> heavy=<yes|no> testlock=<yes|no> args=<swiftc args>
#   run <binary name> build=<n> heavy=<yes|no> label=<heavy-lock holder label>
# where build=<n> is the compile count at the moment that binary was written, so a run served from the cache
# shows the build number of the compile that made it. Knobs (environment): FAKE_SWIFT_VERSION, FAKE_SDK,
# FAKE_SDKPATH, FAKE_BUILD, FAKE_ARCH, FAKE_JBIG2, FAKE_QPDF; FAKE_FAIL=<output name> fails that compile;
# FAKE_EDIT_DURING=<file> is appended to during each compile; FAKE_TESTS_RC is the suite's exit status;
# FAKE_RUN_SLEEP delays the suite; FAKE_RUN_EDIT=<file> is appended to during the suite.
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
[ -n "${FAKE_FAIL:-}" ] && [ "${out##*/}" = "$FAKE_FAIL" ] && { echo "error: fake compile failure" >&2; exit 1; }
n=$(grep -c '^compile' "$FAKE_LOG")
cat > "$out" <<EOS
#!/bin/bash
h=no; [ -d "\$MAC_HEAVY_LOCK" ] && h=yes
echo "run \${0##*/} build=$n heavy=\$h label=\$(sed -n 's/^label=//p' "\$MAC_HEAVY_LOCK/owner" 2>/dev/null)" >> "\$FAKE_LOG"
[ -n "\${FAKE_RUN_EDIT:-}" ] && echo "// edited during the run" >> "\$FAKE_RUN_EDIT"
[ -n "\${FAKE_RUN_SLEEP:-}" ] && sleep "\$FAKE_RUN_SLEEP"
echo "3/3 passed"
exit \${FAKE_TESTS_RC:-0}
EOS
chmod +x "$out"
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
