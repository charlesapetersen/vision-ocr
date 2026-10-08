#!/usr/bin/env bash
# queue hook: one JSON line per open QUEUE.md item, in order (CONTRACT.md section 2). See hooks.py.
exec /usr/bin/python3 "$(dirname "${BASH_SOURCE[0]}")/hooks.py" queue
