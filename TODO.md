# Work queue

Known work that is worth doing, ordered by what it protects. Defects live in
[BUGS.md](BUGS.md); speculative ideas live in [FEATURES.md](FEATURES.md). This
file is for work that is *decided* but not done.

Move an item to done by deleting it and recording the evidence in the commit and,
if it was a defect, in `BUGS.md`. An item that has sat here through two sessions
without being started should be re-examined: either it matters and should be
promoted, or it does not and should be deleted.

---

**This file is empty of code work.** The 1.0 punchlist is closed (BUGS.md C16,
R21, R22, T3, H1, U13–U16), and the three interface questions that could only be
answered by a running app have been answered — in a headless VM, off-screen. They
passed, and the run found U17, which was worse than any of them.

## Still not verified

- [ ] **The VoiceOver announcements have never been heard.** U16 posts
      `.announcementRequested` at batch start, at each file landing and at the
      summary. The suite cannot assert any of it — the test binary has no `NSApp`
      — and the VM pass deliberately skipped it. What needs a real session: that
      the summary is not swallowed mid-sentence, and that a 78-file batch is
      informative rather than a wall of speech. If it is the latter, announce
      only failures per file and keep the summary.

## Smaller, and genuinely optional

- [ ] **The tab-order walk is still by hand.** `Tools/vm-gui-check.sh` covers
      U13, U15 and U17 — nine checks, one command. The tab order is not in it:
      it needs `AppleKeyboardUIMode` set in the guest and reads focus rings out
      of pixel diffs between captures, which is a lot of machinery for a property
      that changes only when the view hierarchy does. Worth adding the next time
      the layout moves.
