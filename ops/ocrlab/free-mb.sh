#!/bin/bash
# ops/ocrlab/free-mb.sh [path] — MB available for new files on path's volume, counted as Finder counts it.
#
# macOS's "available capacity for important usage" includes purgeable space (Time Machine's local snapshots,
# caches), which the system frees on demand when a download needs it. `df` leaves purgeable space out: on
# 2026-10-05 Finder showed 70 GB available and `df` 17 GB, because the hourly snapshots still held every
# deleted model download, and the lab's 20 GB rule refused downloads all day (owner: count it as Finder does).
# Falls back to `df` if Swift cannot answer, so a failure errs toward refusing a download, never toward a full disk.
p="${1:-/}"
mb=$(/usr/bin/swift -e 'import Foundation
let v = try? URL(fileURLWithPath: CommandLine.arguments[1]).resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
if let c = v?.volumeAvailableCapacityForImportantUsage, c > 0 { print(c / 1048576) }' "$p" 2>/dev/null)
case "$mb" in ''|*[!0-9]*) mb=$(df -m "$p" | awk 'NR==2 {print $4}') ;; esac
case "$mb" in ''|*[!0-9]*) mb=0 ;; esac   # no answer at all: report none free, so try-mlx refuses
echo "$mb"
