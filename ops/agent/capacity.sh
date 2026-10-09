#!/usr/bin/env bash
# capacity hook (CONTRACT.md section 2): how many sessions this project can safely run at once. One until the
# concurrent-suites item lands: two sessions would each run the full suite, and its shared tests.plist allows one
# at a time (test-lock.sh serialises them, so a second session would mostly wait).
# Change the number in the same commit that makes two suites safe.
set -u
printf '{"max_slots": 1}\n'
