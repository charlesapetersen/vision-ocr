#!/usr/bin/python3
"""The Agent Manager's queue, holds and status hooks for this repo (CONTRACT.md section 2, in the manager's repo).

    hooks.py queue | holds | status

Thin adapters: the queue is ops/autonomous/next-item.sh's answer, each row's markers read from the item's whole
span in QUEUE.md the way the daemon reads the head item's (attempts, effort); the holds are the resolver's `hold`
rows and RUN.md's `## NEEDS OWNER` bullets; the status is status-digest.sh's counts. The scripts are found beside
this file (../autonomous); the data comes from $AGENT_REPO and $AGENT_STATE. Read-only, stdlib only, no network.
"""
import hashlib
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPTS = os.path.normpath(os.path.join(HERE, "..", "autonomous"))
REPO = os.environ.get("AGENT_REPO") or os.path.normpath(os.path.join(HERE, "..", ".."))
STATE = os.environ.get("AGENT_STATE") or os.path.expanduser("~/.local/state/visionocr-autonomous")
QUEUE = os.path.join(REPO, "ops", "autonomous", "QUEUE.md")
RUN = os.path.join(STATE, "RUN.md")
PATH = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
LANE = "main"   # one lane: the registry's lanes block for this project

ATTEMPTS = re.compile(r"\(attempts: ([0-9]+)\)")
EFFORT = re.compile(r"\(effort: (low|medium|high|xhigh|max)\)")
USES = re.compile(r"\(uses:\s*([a-z0-9:]+(?:\s*,\s*[a-z0-9:]+)*)\s*\)")
ESTIMATE = re.compile(r"ESTIMATE:\s*(\d+(?:\s*-\s*\d+)?\s+sessions?)\b")
DATE = re.compile(r"\b(20\d\d-\d\d-\d\d)\b")


def read(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return f.read()
    except OSError:
        return None


def resolver_rows():
    """(rc, [(status, tag, text)], message) from next-item.sh."""
    env = dict(os.environ, PATH=PATH + ":" + os.environ.get("PATH", ""))
    p = subprocess.run([os.path.join(SCRIPTS, "next-item.sh"), REPO], env=env, capture_output=True, text=True,
                       timeout=120)
    rows = []
    for line in p.stdout.splitlines():
        f = line.split("\t", 2)
        if len(f) == 3:
            rows.append(tuple(f))
    return p.returncode, rows, (p.stdout + p.stderr).strip()


def span(queue, tag):
    """The item's lines: from its `- [` line naming **tag** to the next `- [` line (the daemon's head_span)."""
    out, inside = [], False
    for line in queue.splitlines():
        if inside and line.startswith("- ["):
            break
        if not inside and line.startswith("- [") and ("**%s**" % tag) in line:
            inside = True
        if inside:
            out.append(line)
    return "\n".join(out)


def attempts(tag, text):
    m = ATTEMPTS.search(text)
    n = int(m.group(1)) if m else 0
    for line in (read(os.path.join(STATE, "attempts.tsv")) or "").splitlines():
        if line.split("\t", 1)[0] == tag:
            n += 1
    return n


def queue():
    rc, rows, msg = resolver_rows()
    if rc == 3:
        return 2
    if rc not in (0, 4):
        print("next-item.sh exited %d: %s" % (rc, msg[:300]), file=sys.stderr)
        return 1
    q = read(QUEUE) or ""
    runnable = 0
    for status, tag, text in rows:
        s = span(q, tag) or text
        d = {"tag": tag, "text": text, "lanes": [LANE], "uses": []}
        m = USES.findall(s)
        if m:
            d["uses"] = [u.strip() for u in m[-1].split(",")]
        if status.startswith("blocked:"):
            d["status"] = "blocked"
            unmet = [t for t in status[len("blocked:"):].split(",") if t]
            tags = [t for t in unmet if not t.startswith("not-before:")]
            if tags:
                d["blocked_on"] = tags
            d["reason"] = "waits for " + ", ".join(t.replace("not-before:", "the date ") for t in unmet)
        elif status == "hold":
            d["status"], d["reason"] = "hold", "owner-only ([hold] or needs: owner)"
        else:
            d["status"] = "ok"
            runnable += 1
        m = EFFORT.search(s)
        if m:
            d["effort"] = m.group(1)
        m = ESTIMATE.search(s)
        if m:
            d["estimate"] = " ".join(m.group(1).split())
        d["attempts"] = attempts(tag, s)
        print(json.dumps(d, ensure_ascii=False, sort_keys=True))
    return 0 if runnable else (3 if rows else 2)


def short_hash(s):
    return hashlib.sha1(s.strip().encode("utf-8")).hexdigest()[:8]


def needs_owner(run):
    """RUN.md's `## NEEDS OWNER` top-level `- ` bullets, HTML comments skipped (status-digest.sh's rule); a bullet's
    indented continuation lines belong to it."""
    out, inside, comment = [], False, False
    for line in run.splitlines():
        if line.startswith("## NEEDS OWNER"):
            inside = True
            continue
        if inside and line.startswith("## "):
            break
        if not inside:
            continue
        if "<!--" in line:
            comment = True
        if comment:
            if "-->" in line:
                comment = False
            continue
        if line.startswith("- "):
            out.append(line[2:].replace("**", "").strip())
    return out


BLOCKED_ON = re.compile(r"\(blocked-on:([^)]*)\)")
NOT_BEFORE = re.compile(r"\(not-before:\s*([^)]*?)\s*\)")
CHECKBOX = re.compile(r"^\s*[-*]\s+\[([ xX])\]\s*")


def tag_done_fn(queue):
    """next-item.sh's rule: a tag is done if QUEUE.md ticks it and opens it nowhere, or its BUGS.md entry closed."""
    done, pend, closed = set(), set(), set()
    for line in queue.splitlines():
        m = CHECKBOX.match(line)
        if m:
            t = re.match(r"[A-Za-z0-9][A-Za-z0-9._-]*", re.sub(r"^`", "", re.sub(r"^\*+", "", line[m.end():])))
            if t:
                (pend if m.group(1) == " " else done).add(t.group(0))
    for line in (read(os.path.join(REPO, "BUGS.md")) or "").splitlines():
        m = re.match(r"^###\s+([A-Za-z0-9][A-Za-z0-9._-]*)", line)
        if m:
            st = line.split("\u2014")[-1].replace("*", "").strip() if "\u2014" in line else ""
            if re.match(r"^(FIXED|WONTFIX|NO DEFECT)", st):
                closed.add(m.group(1))
    return lambda t: t not in pend and (t in done or t in closed)


def own_prerequisites_met(text, tag_done):
    """A hold is ready to decide only when its own (blocked-on:) tags are done and its (not-before:) date has
    come (R1 review finding 4). next-item.sh prints `hold` before it reads these, so they are read here."""
    for clause in BLOCKED_ON.findall(text):
        for t in clause.split(","):
            t = t.replace("`", "").strip()
            if t and not tag_done(t):
                return False
    today = os.environ.get("VISIONOCR_TODAY") or __import__("datetime").date.today().isoformat()
    for d in NOT_BEFORE.findall(text):
        if not re.match(r"^\d{4}-\d\d-\d\d$", d) or today < d:
            return False
    return True


def holds():
    rc, rows, msg = resolver_rows()
    if rc not in (0, 3, 4):
        print("next-item.sh exited %d: %s" % (rc, msg[:300]), file=sys.stderr)
        return 1
    pending = set()
    for status, tag, text in rows:
        if status.startswith("blocked:"):
            unmet = [t for t in status[len("blocked:"):].split(",") if t]
            if len(unmet) == 1:
                pending.add(unmet[0])
    q = read(QUEUE) or ""
    tag_done, seen = tag_done_fn(q), set()
    for status, tag, text in rows:
        if status == "hold" and tag not in seen:
            seen.add(tag)
            ready = tag in pending and own_prerequisites_met(span(q, tag) or text, tag_done)
            print(json.dumps({"key": tag, "text": text, "permanent": not ready, "source": "QUEUE.md"},
                             ensure_ascii=False, sort_keys=True))
    for b in needs_owner(read(RUN) or ""):
        m = DATE.search(b)
        d = {"key": "needs-%s-%s" % (m.group(1) if m else "undated", short_hash(b)),
             "text": b if len(b) <= 200 else b[:197] + "...", "permanent": False, "source": "RUN.md NEEDS OWNER"}
        if m:
            d["since"] = m.group(1)
        print(json.dumps(d, ensure_ascii=False, sort_keys=True))
    return 0


def git(*args):
    p = subprocess.run(["git", "-C", REPO] + list(args), capture_output=True, text=True, timeout=8)
    return p.returncode, p.stdout


def health():
    """status-digest.sh's Health line: the last RED in last-gate.log (unless a gate is running), else how far HEAD
    is past the last green sha."""
    gate_red = ""
    running = subprocess.run(["pgrep", "-f", r"ops/autonomous/health-gate\.sh"], capture_output=True).returncode == 0
    log = read(os.path.join(STATE, "last-gate.log")) or ""
    if not running:
        reds = [ln for ln in log.splitlines() if ln.startswith("HEALTH GATE: RED")]
        if reds:
            s = " ".join(re.sub(r"^HEALTH GATE: RED[^A-Za-z0-9]*", "", reds[-1]).split())
            gate_red = s.split(" — ")[0]
    greens = [ln for ln in log.splitlines() if ln.startswith("HEALTH GATE: GREEN")]
    m = re.search(r"suite \(skipped: identical inputs passed at ([^)]*)\)", greens[-1]) if greens else None
    what = ("Build and tool type-check passed (suite skipped: identical inputs passed at %s)" % m.group(1)
            if m else "Build, suite and tool type-check passed")
    if gate_red:
        return "The last full check FAILED: %s; that step is broken now" % gate_red
    last = (read(os.path.join(STATE, "last-gate")) or "").strip()
    if last and git("cat-file", "-e", last + "^{commit}")[0] == 0:
        rc, n = git("rev-list", "--count", last + "..HEAD")
        if rc == 0 and n.strip().isdigit():
            n = int(n.strip())
            return "%s, on the current code" % what if n == 0 else "%s, %d commit%s ago" % (what, n, "" if n == 1 else "s")
    if last:
        return "Last passed at %s, a commit this checkout does not have, so how stale is unknown" % last[:7]
    return "Not checked yet; the next run will do a full build, suite and tool type-check"


def status():
    rc, out = git("log", "--since=24 hours ago", "--oneline")
    _, rows, _ = resolver_rows()
    done = sum(1 for line in (read(QUEUE) or "").splitlines() if re.match(r"^\s*[-*]\s+\[[xX]\]", line))
    d = {"done_24h": len(out.splitlines()) if rc == 0 else 0,
         "left": sum(1 for r in rows if r[0] == "ok"), "finished": done, "health": health()}
    print(json.dumps(d, ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    cmds = {"queue": queue, "holds": holds, "status": status}
    if len(sys.argv) != 2 or sys.argv[1] not in cmds:
        print("usage: hooks.py queue|holds|status", file=sys.stderr)
        sys.exit(64)
    sys.exit(cmds[sys.argv[1]]())
