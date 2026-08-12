# Work queue

Known work that is worth doing, ordered by what it protects. Defects live in
[BUGS.md](BUGS.md); speculative ideas live in [FEATURES.md](FEATURES.md). This
file is for work that is *decided* but not done.

Move an item to done by deleting it and recording the evidence in the commit and,
if it was a defect, in `BUGS.md`. An item that has sat here through two sessions
without being started should be re-examined: either it matters and should be
promoted, or it does not and should be deleted.

---

**The VoiceOver announcements have now been heard** (2026-08-09) and they work —
the last item that could only be settled by a person at a real session. U16 is
closed in full, and `BUGS.md` U8 no longer has a remainder.

**Worth doing before the next release that touches `Flattener`** (added
2026-08-10, not started): re-run the 255-document library end to end and diff the
outcome against 1.7.0's — 255/255, 12.6M characters, 15 colour documents, peak
3.35 GB. The harness pattern is in `HANDOFF.md`; it takes 23 minutes and is the
only check that covers what the suite cannot. Nothing else here is code work.

**This file is otherwise empty of code work.** The 1.0 punchlist is closed (BUGS.md C16,
R21, R22, T3, H1, U13–U16), and the three interface questions that could only be
answered by a running app have been answered — in a headless VM, off-screen. They
passed, and the run found U17, which was worse than any of them.

## Smaller, and genuinely optional

- [x] **The tab order was walked on 2026-08-12** and it is sound: 22 stops
      through the settings sheet in visual order — Recognition, Searchable PDF,
      Behaviour — no trap, no unreachable control, and the four new preset
      buttons land where they read. Done locally by pressing Tab and reading
      `AXFocusedUIElement`, which needs no VM and no pixel diffing.

- [ ] **What that walk could not settle: whether the controls are named for
      VoiceOver.** Three different attribute reads gave three different answers —
      AppleScript's `description` returns the *role* description, `AXDescription`
      is absent on the toggles, and `AXAttributedDescription` came back while the
      probe was visibly failing to advance focus. So the question is open, not
      answered in either direction, and it should not be recorded as either.
      This is what the VM harness exists for, or a person with VoiceOver actually
      running for two minutes. Do not trust a scripted read of it: this file
      already records three instruments that lied about the interface, and this
      would have been a fourth.

- [ ] **The tab-order walk is still by hand.** `Tools/vm-gui-check.sh` covers
      U13, U15 and U17 — nine checks, one command. The tab order is not in it:
      it needs `AppleKeyboardUIMode` set in the guest and reads focus rings out
      of pixel diffs between captures, which is a lot of machinery for a property
      that changes only when the view hierarchy does. Worth adding the next time
      the layout moves.
