# Vision OCR

**Turn scanned PDFs into documents you can actually search.**

A scan is a picture of a page. Your Mac can see it, but it can't read it — you
can't select a sentence, you can't copy a quote, and ⌘F finds nothing. Vision OCR
fixes that. Drop a scan in, and you get back a PDF that looks exactly the same but
whose words you can select, copy and search like any other document.

It can also just hand you the plain text, if that's what you're after.

### [⬇︎ Download Vision OCR](https://github.com/charlesapetersen/vision-ocr/releases/latest)

Free, open source, and it runs entirely on your Mac — **nothing you scan is ever
uploaded anywhere.** Requires macOS 13 (Ventura) or later. Works on both Apple
Silicon and Intel Macs.

---

## Setting it up

There are two pieces: the app, and the recognition engine it drives. The second
part needs the Terminal once. It's two lines, and you never have to touch it
again.

### 1. Install the app

1. Download the disk image from the [latest
   release](https://github.com/charlesapetersen/vision-ocr/releases/latest).
2. Open it, and drag **Vision OCR** onto the **Applications** folder shortcut.
3. The first time you open it, macOS will say it *"cannot verify the developer"*.
   That's expected — see [the first-launch note](#macos-says-it-cant-verify-the-developer)
   below for the two clicks that get past it.

### 2. Install the recognition engine

Vision OCR reads pages using `mac-ocr`, a free tool that talks to the text
recognition built into macOS. Open **Terminal** (⌘Space, type "Terminal") and
paste these two lines, pressing Return after each:

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" && brew install node
npm install -g mac-ocr
```

The first line installs Homebrew and Node, which `mac-ocr` needs. If you already
have Node, you only need the second line. Then quit and reopen Vision OCR.

> **Why isn't this just built in?** Because `mac-ocr` is someone else's tool and
> bundling it would mean shipping a copy that goes stale. The app looks for it
> automatically in the usual places; if you ever move it, you can point at it
> directly in Settings.

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

No. Recognition happens on your Mac using Apple's built-in text recognition. The
app has no network code in it at all. It works with the Wi-Fi off.

#### macOS says it "can't verify the developer"

This app isn't signed with a paid Apple Developer certificate, so macOS treats it
as coming from an unknown developer. To open it anyway:

**Control-click** (or right-click) the app in your Applications folder and choose
**Open**, then click **Open** in the dialog. You only do this once.

If the dialog doesn't offer an Open button, go to **System Settings ▸ Privacy &
Security**, scroll down, and click **Open Anyway** next to the message about
Vision OCR.

#### It says it can't find mac-ocr

The app looks in the standard places, then asks your shell. If it still comes up
empty, find it by running `which mac-ocr` in Terminal, then paste that path into
**Settings ▸ Behaviour ▸ mac-ocr path**.

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
| **Black & white vs greyscale** | Greyscale for pages with photographs; black and white is far smaller for plain text |

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

*(The app was called Vision Reader GUI before 1.1.0. Your settings carry over
automatically.)*
