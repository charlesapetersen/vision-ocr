# ops/agent/lib.sh — sourced by every Agent Manager hook in this directory (CONTRACT.md in the Agent Manager repo).
#
# The hooks are thin adapters over the project's own scripts in ops/autonomous/. The scripts are found beside
# the hook (this checkout); the data comes from $AGENT_REPO (the checkout the manager's registry names) and
# $AGENT_STATE (RUN.md, attempts.tsv, last-gate*). A launchd or engine shell has almost no PATH (CLAUDE.md's
# environment trap), so it is set here.
AGENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$(cd "$AGENT_DIR/../autonomous" && pwd)"
REPO="${AGENT_REPO:-$(cd "$AGENT_DIR/../.." && pwd)}"
STATE="${AGENT_STATE:-$HOME/.local/state/visionocr-autonomous}"
RUN="$STATE/RUN.md"
QUEUE="$REPO/ops/autonomous/QUEUE.md"
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"
