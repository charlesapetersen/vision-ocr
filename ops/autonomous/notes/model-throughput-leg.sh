#!/bin/bash
# leg.sh <reader> <concurrency> <slots> : one batch of /private/tmp/mt/in through the gate.
PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
r=$1 c=$2 s=$3; L=/private/tmp/mt/legs/$r-c$c-s$s; D=vo-mt-gate
rm -rf "$L"; mkdir -p "$L/out" "$L/stats"
defaults delete $D >/dev/null 2>&1
defaults write $D accurateMode -bool true
defaults write $D accurateEnabledReaders "paddleocr-vl,falcon-ocr"
for k in accurateReader accurateNewspaperReader accuratePhotoReader; do defaults write $D $k "$r"; done
defaults write $D concurrency -int "$c"
( while :; do echo "$(date +%s) $(vm_stat | awk '/Pages free/{f=$3} /Pages speculative/{s=$3} END{print (f+s)*16384/1048576}') $(sysctl -n vm.swapusage | awk '{print $6}')"; sleep 2; done ) > "$L/mem.txt" &
smp=$!
t0=$(python3 -c 'import time;print(time.time())')
VISIONOCR_MT_SLOTS=$s VISIONOCR_MT_STATS="$L/stats" VISIONOCR_HELPER=/private/tmp/mt/bin/visionocr-recognise \
VISIONOCR_READER_SCRIPT=/private/tmp/vo-20261015-221801-84980/Resources/read-model.py \
  /private/tmp/mt/bin/$D /private/tmp/mt/in "$L/out" > "$L/gate.log" 2>&1
rc=$?
kill $smp
echo "$t0" > "$L/t0"; echo "$rc" > "$L/rc"
echo "leg $r c$c s$s rc=$rc"
