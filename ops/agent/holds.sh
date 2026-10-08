#!/usr/bin/env bash
# holds hook: pending owner items as JSON lines (QUEUE.md holds, RUN.md NEEDS OWNER bullets). See hooks.py.
exec /usr/bin/python3 "$(dirname "${BASH_SOURCE[0]}")/hooks.py" holds
