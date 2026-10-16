#!/bin/bash
# leg.sh <base|res> <reader> <rep>: the ten-page batch through one build's gate, accurate mode on, concurrency 6.
PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
b=$1 r=$2 n=$3; B=/private/tmp/mrr/$b; L=/private/tmp/mrr/legs/$n-$b-$r; D=vo-mt-gate
SCRIPT=/private/tmp/mrr/base-src/Resources/read-model.py
[ "$b" = final ] && { B=/private/tmp/mrr/final; SCRIPT=/private/tmp/mrr/final-read-model.py; }
[ "$b" = res ] && { B=/private/tmp/mrr/res2; SCRIPT=/private/tmp/mrr/res-read-model.py; }
pkill -f 'read-model.py --serve' ; sleep 1
rm -rf "$L"; mkdir -p "$L/out"
defaults delete $D >/dev/null 2>&1
defaults write $D accurateMode -bool true
defaults write $D accurateEnabledReaders "paddleocr-vl,falcon-ocr"
for k in accurateReader accurateNewspaperReader accuratePhotoReader; do defaults write $D $k "$r"; done
defaults write $D concurrency -int 6
( while :; do pgrep -f 'read-model.py --serve'; sleep 1; done ) > "$L/serve-pids.txt" &
smp=$!
VISIONOCR_HELPER=$B/visionocr-recognise VISIONOCR_READER_SCRIPT=$SCRIPT $B/$D /private/tmp/mt/in "$L/out" > "$L/gate.log" 2>&1
rc=$?
kill $smp
servers=$(pgrep -f 'read-model.py --serve' | wc -l | tr -d ' ')
starts=$(sort -u "$L/serve-pids.txt" | wc -l | tr -d ' ')
pkill -f 'read-model.py --serve'
echo "leg $n $b $r rc=$rc seconds=$(awk '/^ *seconds/{print $2}' "$L/gate.log") pdfs=$(ls "$L/out"/*.pdf 2>/dev/null | wc -l | tr -d ' ') servers_left=$servers server_starts=$starts" | tee -a /private/tmp/mrr/legs.txt
