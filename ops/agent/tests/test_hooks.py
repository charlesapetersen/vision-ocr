#!/usr/bin/python3
"""Tests for the Agent Manager hooks in ops/agent/ (CONTRACT.md section 2 in the manager's repo).

Each test builds a small fixture: a scratch git repo with QUEUE.md and BUGS.md, a state folder with RUN.md and
attempts.tsv, and a copy of ops/agent/ beside an ops/autonomous/ that holds the real next-item.sh from this
checkout plus fakes for the heavy scripts (health-gate.sh, compact-runlog.sh). Nothing outside the scratch
folder is read or written, and the real gate never runs.

Run: /usr/bin/python3 -m unittest discover -s ops/agent/tests   (from the repo root)
"""
import hashlib
import json
import os
import shlex
import shutil
import subprocess
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
AGENT = os.path.dirname(HERE)
AUTONOMOUS = os.path.join(os.path.dirname(AGENT), "autonomous")
DAEMON = os.path.join(AUTONOMOUS, "vision-ocr-autonomous.sh")
EM = "—"

QUEUE = """# Autonomous work queue

## The queue

- [x] **done-one** — finished. (uses: light)
- [ ] **first** — the first item. (uses: build,model:12) (effort: high) (attempts: 1)
      ESTIMATE: 1-2 sessions.
- [ ] **second** — waits on the owner. (blocked-on: approve)
- [ ] **third** — waits on two. (blocked-on: approve-two, first)
- [ ] **later** — not yet. (not-before: 2099-01-01)

## HOLD — owner-only, never auto-executed

- [ ] **approve** — the owner approves. [hold] needs: owner
- [ ] **approve-two** — a second approval. [hold] needs: owner
- [ ] **release** — cutting a release. [hold] needs: owner
"""

BUGS = """# Register

### C1 · a defect — FIXED
### C2 · another — OPEN
### C3 · a third — **WONTFIX**
"""

RUN = """RUN STATUS: IN_PROGRESS — fixture

## FOCUS

Work the queue in order.

## HOLD (owner-only)

Nothing.

## NEEDS OWNER

<!-- sessions append here
- not an item -->
- **2026-10-08** a dead session's worktree holds work: /tmp/vo-x
- an undated note
  continued on an indented line

## SESSION LOG

- 2026-10-08 a session
"""


def run(cmd, cwd=None, env=None, check=True):
    p = subprocess.run(cmd, cwd=cwd, env=env, capture_output=True, text=True, timeout=120)
    if check and p.returncode != 0:
        raise AssertionError("%s failed (%d): %s%s" % (cmd, p.returncode, p.stdout, p.stderr))
    return p


class Fixture(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="agent-hooks-")
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.repo = os.path.join(self.tmp, "repo")
        self.state = os.path.join(self.tmp, "state")
        os.makedirs(self.state)
        shutil.copytree(AGENT, os.path.join(self.repo, "ops", "agent"),
                        ignore=shutil.ignore_patterns("tests", "__pycache__"))
        os.makedirs(os.path.join(self.repo, "ops", "autonomous"))
        shutil.copy2(os.path.join(AUTONOMOUS, "next-item.sh"), os.path.join(self.repo, "ops", "autonomous"))
        self.write("ops/autonomous/QUEUE.md", QUEUE)
        self.write("ops/autonomous/resume-prompt.txt", "work __REPO__\n")
        self.write("BUGS.md", BUGS)
        self.put("RUN.md", RUN)
        self.put("attempts.tsv", "first\t2026-10-07\nfirst\t2026-10-08\nsecond\t2026-10-08\n")
        g = ["git", "-C", self.repo]
        run(g + ["init", "-q", "-b", "main"])
        run(g + ["-c", "user.email=t@example.invalid", "-c", "user.name=t", "add", "-A"])
        run(g + ["-c", "user.email=t@example.invalid", "-c", "user.name=t", "commit", "-q", "-m", "fixture"])
        self.env = dict(os.environ, AGENT_REPO=self.repo, AGENT_STATE=self.state, AGENT_PROJECT="fixture",
                        HOME=self.tmp, VISIONOCR_TODAY="2026-10-08")
        for k in ("VISIONOCR_QUEUE", "VISIONOCR_BUGS"):
            self.env.pop(k, None)

    def write(self, rel, text, mode=None):
        p = os.path.join(self.repo, rel)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "w") as f:
            f.write(text)
        if mode:
            os.chmod(p, mode)

    def put(self, name, text):
        with open(os.path.join(self.state, name), "w") as f:
            f.write(text)

    def hook(self, name, **env):
        e = dict(self.env, AGENT_HOOK=name, **env)
        return run(["/bin/bash", "-c", "ops/agent/%s.sh" % name], cwd=self.repo, env=e, check=False)

    def daemon_function(self, name):
        with open(DAEMON) as f:
            lines = f.read().splitlines()
        start = next(i for i, ln in enumerate(lines) if ln.startswith(name + "() {"))
        end = next(i for i in range(start, len(lines)) if lines[i] == "}")
        return "\n".join(lines[start:end + 1])

    def jsonl(self, out):
        return [json.loads(ln) for ln in out.splitlines() if ln.strip()]


class Queue(Fixture):
    def test_items_statuses_and_fields(self):
        r = self.hook("queue")
        self.assertEqual(r.returncode, 0, r.stderr)
        items = {d["tag"]: d for d in self.jsonl(r.stdout)}
        self.assertEqual(list(items), ["first", "second", "third", "later", "approve", "approve-two", "release"])
        f = items["first"]
        self.assertEqual((f["status"], f["lanes"], f["uses"], f["effort"], f["estimate"], f["attempts"]),
                         ("ok", ["main"], ["build", "model:12"], "high", "1-2 sessions", 3))   # marker 1 + 2 rows
        self.assertEqual((items["second"]["status"], items["second"]["blocked_on"], items["second"]["attempts"]),
                         ("blocked", ["approve"], 1))
        self.assertEqual(items["third"]["blocked_on"], ["approve-two", "first"])
        self.assertNotIn("blocked_on", items["later"])
        self.assertIn("the date 2099-01-01", items["later"]["reason"])
        self.assertEqual(items["release"]["status"], "hold")

    def test_all_blocked_exits_3_and_empty_exits_2(self):
        self.write("ops/autonomous/QUEUE.md", QUEUE.replace("- [ ] **first**", "- [ ] **first** (blocked-on: approve)"))
        r = self.hook("queue")
        self.assertEqual(r.returncode, 3, r.stdout + r.stderr)
        self.write("ops/autonomous/QUEUE.md", "## The queue\n\n- [x] **done-one** — finished.\n")
        r = self.hook("queue")
        self.assertEqual((r.returncode, r.stdout), (2, ""))

    def test_a_missing_queue_is_a_fault(self):
        os.remove(os.path.join(self.repo, "ops", "autonomous", "QUEUE.md"))
        r = self.hook("queue")
        self.assertEqual(r.returncode, 1)


class Holds(Fixture):
    def test_permanence_and_needs_owner(self):
        r = self.hook("holds")
        self.assertEqual(r.returncode, 0, r.stderr)
        items = self.jsonl(r.stdout)
        by = {d["key"]: d for d in items}
        self.assertFalse(by["approve"]["permanent"])     # second waits on it alone
        self.assertTrue(by["approve-two"]["permanent"])  # third also waits on first
        self.assertTrue(by["release"]["permanent"])
        needs = [d for d in items if d["source"] == "RUN.md NEEDS OWNER"]
        self.assertEqual(len(needs), 2)
        self.assertTrue(needs[0]["key"].startswith("needs-2026-10-08-"))
        self.assertEqual(needs[0]["since"], "2026-10-08")
        self.assertTrue(needs[1]["key"].startswith("needs-undated-"))
        self.assertTrue(all(d["permanent"] is False for d in needs))
        self.assertFalse(any("not an item" in d["text"] for d in items))

    def test_keys_are_stable(self):
        a = [d["key"] for d in self.jsonl(self.hook("holds").stdout)]
        self.assertEqual(a, [d["key"] for d in self.jsonl(self.hook("holds").stdout)])
        self.put("RUN.md", RUN.replace("- an undated note", "- 2026-10-09 a newer note\n- an undated note"))
        b = [d["key"] for d in self.jsonl(self.hook("holds").stdout)]
        self.assertEqual(len(b), len(a) + 1)
        self.assertTrue(set(a) <= set(b))

    def test_finishing_the_other_prerequisite_makes_a_hold_pending(self):
        self.write("ops/autonomous/QUEUE.md", QUEUE.replace("- [ ] **first**", "- [x] **first**"))
        by = {d["key"]: d for d in self.jsonl(self.hook("holds").stdout)}
        self.assertFalse(by["approve-two"]["permanent"])


class FingerprintAndCompleted(Fixture):
    def test_the_daemons_four_parts_then_focus(self):
        r = self.hook("fingerprint")
        self.assertEqual(r.returncode, 0)
        head, focus = r.stdout.split("--- FOCUS\n")
        script = 'REPO="$1"; RUN="$2"; QUEUE="$3"\n%s\nwork_fingerprint\n' % self.daemon_function("work_fingerprint")
        theirs = run(["/bin/bash", "-c", script, "x", self.repo, os.path.join(self.state, "RUN.md"),
                      os.path.join(self.repo, "ops", "autonomous", "QUEUE.md")]).stdout.strip()
        self.assertEqual(hashlib.sha256(head.encode()).hexdigest(), theirs)
        self.assertIn("Work the queue in order.", focus)

    def test_a_focus_edit_moves_it_and_the_session_log_does_not(self):
        a = self.hook("fingerprint").stdout
        self.put("RUN.md", RUN.replace("- 2026-10-08 a session", "- 2026-10-09 another"))
        self.assertEqual(a, self.hook("fingerprint").stdout)
        self.put("RUN.md", RUN.replace("Work the queue in order.", "Only C52 this week."))
        self.assertNotEqual(a, self.hook("fingerprint").stdout)

    def test_completed_matches_the_daemon(self):
        r = self.hook("completed")
        self.assertEqual((r.returncode, r.stdout), (0, "3\n"))   # done-one, C1, C3
        script = 'REPO="$1"; QUEUE="$2"\n%s\ncompleted_items\n' % self.daemon_function("completed_items")
        theirs = run(["/bin/bash", "-c", script, "x", self.repo,
                      os.path.join(self.repo, "ops", "autonomous", "QUEUE.md")]).stdout
        self.assertEqual(r.stdout, theirs)


class Gate(Fixture):
    def fake_gate(self, lines, rc):
        body = "".join("echo %s\n" % shlex.quote(ln) for ln in lines)
        self.write("ops/autonomous/health-gate.sh", "#!/bin/bash\n%sexit %d\n" % (body, rc), 0o755)

    def test_green(self):
        self.fake_gate(["HEALTH GATE: GREEN (hooks + suite (locked) + ./build.sh)"], 0)
        r = self.hook("gate")
        self.assertEqual((r.returncode, r.stdout.splitlines()[-1]), (0, "HEALTH GATE: GREEN"))

    def test_red_classes_and_the_stamp_note(self):
        for line, want, klass in (
                ("HEALTH GATE: RED %s suite build" % EM, "suite, build", "code"),
                ("HEALTH GATE: RED %s staleness %s suite skipped: identical inputs passed at 09:00" % (EM, EM),
                 "staleness", "doc"),
                ("HEALTH GATE: RED %s queue-coherence tools-compile" % EM, "queue-coherence, tools-compile",
                 "mixed")):
            with self.subTest(line=line):
                self.fake_gate([line, "--- failing output (tail, per failing step) ---"], 1)
                r = self.hook("gate")
                self.assertEqual(r.returncode, 1)
                self.assertEqual(r.stdout.splitlines()[-2:],
                                 ["HEALTH GATE: RED %s %s" % (EM, want), "HEALTH GATE CLASS: %s" % klass])

    def test_no_verdict_is_inconclusive(self):
        self.fake_gate(["half a log"], 143)
        r = self.hook("gate")
        self.assertEqual(r.returncode, 3)


class Precheck(Fixture):
    def setUp(self):
        super().setUp()
        self.claude = os.path.join(self.tmp, "claude")
        with open(self.claude, "w") as f:
            f.write("#!/bin/sh\n")
        os.chmod(self.claude, 0o755)

    def test_ok_and_each_refusal(self):
        self.assertEqual(self.hook("precheck", AGENT_CLAUDE=self.claude).returncode, 0)
        r = self.hook("precheck", AGENT_CLAUDE=os.path.join(self.tmp, "none"))
        self.assertEqual(r.returncode, 1)
        self.assertIn("claude CLI", r.stdout)
        self.put("RUN.md", RUN.replace("IN_PROGRESS", "COMPLETE"))
        r = self.hook("precheck", AGENT_CLAUDE=self.claude)
        self.assertIn("COMPLETE", r.stdout)
        self.put("RUN.md", RUN)
        self.write("ops/autonomous/QUEUE.md", "## The queue\n\n- [x] **done-one** — finished.\n")
        r = self.hook("precheck", AGENT_CLAUDE=self.claude)
        self.assertIn("drained", r.stdout)
        os.remove(os.path.join(self.state, "RUN.md"))
        r = self.hook("precheck", AGENT_CLAUDE=self.claude)
        self.assertIn("no run-state file", r.stdout)


class Status(Fixture):
    def test_counts_and_health(self):
        r = self.hook("status")
        self.assertEqual(r.returncode, 0, r.stderr)
        d = json.loads(r.stdout)
        self.assertEqual((d["done_24h"], d["left"], d["finished"]), (1, 1, 1))
        self.assertTrue(d["health"].startswith("Not checked yet"))
        head = run(["git", "-C", self.repo, "rev-parse", "HEAD"]).stdout.strip()
        self.put("last-gate", head + "\n")
        self.put("last-gate.log", "HEALTH GATE: GREEN (hooks + suite (skipped: identical inputs passed at 09:00))\n")
        d = json.loads(self.hook("status").stdout)
        self.assertEqual(d["health"], "Build and tool type-check passed (suite skipped: identical inputs passed at "
                                      "09:00), on the current code")
        self.put("last-gate.log", "HEALTH GATE: RED %s suite %s suite skipped: x\n" % (EM, EM))
        d = json.loads(self.hook("status").stdout)
        self.assertEqual(d["health"], "The last full check FAILED: suite; that step is broken now")
        self.put("last-gate", "0" * 40 + "\n")
        self.put("last-gate.log", "")
        d = json.loads(self.hook("status").stdout)
        self.assertIn("a commit this checkout does not have", d["health"])


class Upkeep(Fixture):
    def test_the_compactor_runs_on_run_md_and_an_abort_fails(self):
        marker = os.path.join(self.tmp, "arg")
        self.write("ops/autonomous/compact-runlog.sh", "#!/bin/bash\necho \"$1\" > %s\nexit 0\n" % shlex.quote(marker),
                   0o755)
        self.assertEqual(self.hook("upkeep").returncode, 0)
        with open(marker) as f:
            self.assertEqual(f.read().strip(), os.path.join(self.state, "RUN.md"))
        self.write("ops/autonomous/compact-runlog.sh", "#!/bin/bash\nexit 1\n", 0o755)
        r = self.hook("upkeep")
        self.assertEqual(r.returncode, 1)
        self.assertIn("ABORTED", r.stdout)


class NoOtherProject(unittest.TestCase):
    def test_no_hook_names_another_project(self):
        for f in sorted(os.listdir(AGENT)):
            p = os.path.join(AGENT, f)
            if os.path.isfile(p):
                with open(p) as fh:
                    text = fh.read().lower()
                for name in ("archive" + sep + "suite" for sep in (" ", "-", "")):
                    self.assertNotIn(name, text, f)


if __name__ == "__main__":
    unittest.main()
