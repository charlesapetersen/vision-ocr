#!/usr/bin/env bash
# status hook: one JSON object, the counts status-digest.sh shows (done, left, finished, health). See hooks.py.
exec /usr/bin/python3 "$(dirname "${BASH_SOURCE[0]}")/hooks.py" status
