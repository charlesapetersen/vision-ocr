# Vision OCR

**Turn scanned PDFs into documents you can actually search.**

A scan is a picture of a page. Your Mac can see it, but it can't read it — you
can't select a sentence, you can't copy a quote, and ⌘F finds nothing. Vision OCR
fixes that. Drop a scan in, and you get back a PDF that looks exactly the same but
whose words you can select, copy and search like any other document.

It can also just hand you the plain text, if that's what you're after.

### [⬇︎ Download Vision OCR](https://github.com/charlesapetersen/vision-ocr/releases/latest)

Free, open source, and it runs entirely on your Mac — **nothing you scan is ever
uploaded anywhere.** Requires macOS 13 (Ventura) or later, on an Apple Silicon
or Intel Mac. No setup beyond dragging it to Applications.

---

## Installing it

1. Download the disk image from the [latest
   release](https://github.com/charlesapetersen/vision-ocr/releases/latest).
2. Open it and drag **Vision OCR** onto the **Applications** folder shortcut.
3. The first time you open it, macOS will refuse and say it *"could not verify"*
   the app. That's expected, and [getting past
   it](#macos-says-it-cant-verify-the-app) takes about fifteen seconds.

That's all. **There is no Terminal step, and nothing to install alongside it.**
Everything the app needs — reading the page, and compressing the result — ships
inside it.

> Earlier versions asked you to install Homebrew, then Node, then an npm package
> before the app would do anything. If you did that, you can leave it alone —
> the app now uses its own copy either way, and you can point **Settings ▸
> Behaviour ▸ mac-ocr path** at yours if you'd rather.

Searchable PDFs are compressed automatically, which makes them roughly a third
the size — the tools for that are inside the app too.

## Using it

1. **Drag your scans onto the window.** PDFs, or images (`jpg`, `png`, `heic`,
   `tiff`). Drop a whole folder and it takes everything inside. Or click
   **Choose Files…**.
2. **Say where the results go** — a folder you pick, or right beside each
   original.
3. **Choose what you want:**
   - **Searchable PDF** — the same document, now selectable and searchable. This
     is what most people want.
   - **Extract text** — a plain `.txt` file of the words on the page.
4. **Click Start OCR.**

You'll see progress for each file as it goes. A page or two takes seconds; a
long book takes a few minutes. If one file fails, the rest carry on, and the log
tells you exactly which one and why.

**Your originals are never modified.** Results are written as new files
(`scan.ocr.pdf`, `scan.txt`) alongside or wherever you chose.

## Questions people actually ask

#### Is my document sent anywhere?

**No.** Recognition happens on your Mac using Apple's built-in text recognition.
Your documents, their text, their names and their contents never leave your
machine, and OCR works perfectly with the Wi-Fi off.

The app makes exactly one kind of network request, and it is not about your
documents: **once a day it asks GitHub whether a newer version exists.** That
request sends nothing about you — no identifiers, no usage data, no file names —
and it never installs anything by itself; it just shows a banner with a link.
Turn it off in **Settings ▸ Behaviour ▸ Check for new versions** and the app
makes no network requests at all.

*(Earlier versions of this page said the app had "no network code in it at all".
That stopped being true when update checking was added in 1.6.0, so the sentence
was rewritten rather than left to quietly mislead. And "sends nothing about you"
was itself not quite true in 1.6.0: the system's networking layer had filled in
two headers nobody wrote, carrying the exact macOS point release and the Mac's
language list. Neither was intended, both were removed in 1.6.1, and the claim
above holds from that version on.)*

#### macOS says it can't verify the app

You'll see a dialog headed *"Vision OCR" Not Opened*, offering only **Move to
Trash** and **Done**. Nothing is wrong with the download. The app isn't
registered with Apple's paid notarization service, so macOS refuses it the first
time on principle.

1. Click **Done**.
2. Open **System Settings ▸ Privacy & Security** and scroll down to **Security**.
3. There'll be a line saying *"VisionOCR" was blocked to protect your Mac*. Click
   **Open Anyway** beside it, and authenticate.
4. Open the app again. It will ask once more; click **Open**.

That's it, permanently — macOS remembers.

**Don't look for a Control-click → Open shortcut.** Older instructions all over
the internet say to right-click the app and choose Open. macOS 15 removed that
bypass; on macOS 15 and later it does nothing for an app in this position. System
Settings is the route.

If the **Open Anyway** line isn't there, it's because it only appears just after
a blocked attempt and lapses after about an hour. Try opening the app again,
then go straight back to Settings.

#### It says it can't find mac-ocr

It shouldn't — the engine is inside the app. If you see this, the copy in the
app bundle is missing or has been quarantined; re-downloading usually fixes it.
Failing that, `npm install -g mac-ocr` and point **Settings ▸ Behaviour ▸
mac-ocr path** at the result.

#### How accurate is it?

On a test set of 232 real scanned documents — books, newspapers, journals and
typescripts from the 1900s to today — every one processed successfully, and in
the typical document **100% of the words** came back selectable and in the right
place. The hardest material is dense 1920s–40s newsprint and carbon-copy
typescript, where the worst document still reached 91%.

Those numbers are measured, not estimated, and the method is written down in
[TECHNICAL.md](TECHNICAL.md#measured-on-real-scans) — including the part where an
earlier version of the test set turned out to be mostly the wrong kind of
document and the flattering results it gave had to be thrown out.

#### The text looks like it's in the wrong place when I select it

Selection highlights sit on an invisible text layer laid over the picture of the
page. On tightly-set material the fit isn't perfect. If it's badly off, that's a
bug worth reporting — please
[open an issue](https://github.com/charlesapetersen/vision-ocr/issues) and say
what kind of document it was.

#### Can it read handwriting?

Only sometimes, and not well. Apple's recognition is built for printed text.
Clear printing may come through; cursive generally won't.

#### What about a page that already has text?

If the app finds a document that already has real, working text in it, it asks
before replacing it — because sometimes the existing text is the broken part and
re-doing it is the whole point, and sometimes it's perfectly good and you'd be
throwing it away.

#### Does it cost anything, or collect anything?

No, and no. No payment, no account, no analytics, no telemetry.

## Settings, briefly

Press ⌘, or click the gear. The defaults are sensible; you can ignore this
entirely. The things most likely to be worth changing:

| | |
|---|---|
| **Languages** | Tell it what language the document is in — it helps a lot |
| **Fast mode** | About 2.5× quicker, slightly less accurate. Good for a rough pass |
| **Files at once** | Lower this if OCR is making the rest of your Mac sluggish |
| **Uncertain text** | Leave it on "keep everything" unless you know why you want less. Raising it deletes words without saying where |
| **Rebuild as** | Automatic handles a mixed book on its own — plain pages come back small, photographs stay photographs, and colour stays colour. The other two are for forcing one treatment on everything |

## Something's wrong / I have an idea

[Open an issue](https://github.com/charlesapetersen/vision-ocr/issues). Saying
what kind of document it was, and attaching one if you can share it, makes a
real difference — most of the bugs worth fixing in this app were found in
specific awkward material rather than in general.

## For developers

Building from source, how the searchable text layer is constructed and why it
isn't done the obvious way, the measurements, and the test suite:
**[TECHNICAL.md](TECHNICAL.md)**.

The rest of the documentation is deliberately thorough:
[ARCHITECTURE.md](ARCHITECTURE.md) (call path and where the risk sits),
[CONTRIBUTING.md](CONTRIBUTING.md) (the process, and the regressions that caused
it), [HANDOFF.md](HANDOFF.md) (design decisions and lessons already paid for),
[CLAUDE.md](CLAUDE.md) (invariants and environment traps),
[BUGS.md](BUGS.md) (every defect with its evidence),
[TODO.md](TODO.md), [FEATURES.md](FEATURES.md) and
[CHANGELOG.md](CHANGELOG.md).

#### Are the files it makes big?

Not usually. A searchable PDF is normally about the same size as what you put
in, because the pages are compressed as it works. On an Intel Mac the
compression step isn't included and files come out roughly three times larger —
they work identically, just take more disk. Installing it separately fixes that:
`brew install jbig2enc qpdf`.

## Credits

Recognition is Apple's Vision framework, reached through
[mac-ocr](https://github.com/privatenumber/mac-ocr) by Hiroki Osame. Compression
is [jbig2enc](https://github.com/agl/jbig2enc) and
[qpdf](https://github.com/qpdf/qpdf), with leptonica and the usual image codecs
behind them. All ship inside the app under their own licences, which travel with
it in `Contents/Resources/third-party-licences` — permissive throughout: MIT,
Apache-2.0, BSD and 0BSD.

JBIG2 is a published ISO standard whose encoder carries a notice that its
methods may be patented in some countries; jbig2enc's own `PATENTS` file is
shipped verbatim rather than summarised here.

*(The app was called Vision Reader GUI before 1.1.0. Your settings carry over
automatically.)*
