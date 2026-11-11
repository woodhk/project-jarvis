# Project Jarvis

A voice switcher for your Mac. Hold the **fn (Globe) key**, say what you want, and release. About one second later
it is in front of you.

This is the tool from my "Project Jarvis" Reel. It is not the Jarvis from Iron Man. It opens things: the Claude
Code session you mean, a folder deep on a drive, an app, a website.

## Build your own

I built this for my own Mac (macOS 14 or later, Apple silicon). To get one made for **your** computer and the apps
you use, open Claude Code in a new, empty folder and paste this:

```
Clone https://github.com/woodhk/project-jarvis into a folder called jarvis-reference, read jarvis-reference/PROMPT.md, and follow it to build this for my computer.
```

[`PROMPT.md`](PROMPT.md) tells the agent to look at your machine, ask you a few questions (which system, which
terminal and browser, which key, what you want to open), show you a plan, and then build it with this repo as the
reference. I have only built and tested it on macOS; on Windows or Linux the agent has to port it.

If your Mac is like mine, you can also just follow "Set up (once)" below.

## What it does

Jarvis can bring forward:

- an open Claude Code session, down to its exact tab, in Terminal or in a VS Code terminal;
- an artifact that one of those sessions published or opened (in Google Chrome);
- an app, by name ("open ChatGPT");
- a website ("open Instagram", "open YouTube on Chrome"): about thirty well-known ones are built in, and you can
  add your own.
- a folder in Finder ("open downloads in Finder", "open my documents folder"): Downloads, Documents, Desktop,
  Pictures, Movies, Music, Applications and your home folder are built in, and you can add your own.

When it is not sure, it shows two choices and opens neither. Tap fn for the first, hold fn briefly for the second,
or type 1 or 2. Keep fn held and the hold becomes a new request. When nothing matches, it says so and does nothing.
Say **"back"** to return to where you were.

Say **"close Spotify"** to take an app off the screen: it is hidden and keeps running, so nothing in it is closed
or lost. Say **"quit Spotify"** to quit it. The app is asked to quit in the normal way and is never forced, so it
can still ask about unsaved work. Jarvis asks first ("Quit Terminal?") when quitting would end Claude Code sessions
that run inside the app, or when the name was not heard exactly: tap fn, type 1 or say "yes" to go ahead; say "no"
or press any other key to cancel. **"Close it"** hides the app in front; **"quit it"** names that app and asks
first. Only apps can be closed or quit; never a session, a page or a website. Finder can be hidden but is never
quit.

Say **"show all sessions"** to see every open session as a numbered list, the one used most recently first. Type
the number, or hold fn and say it. Any other key closes the list. While a list is on show it has the keyboard; the
window you were in stays in front and gets the keyboard back when the list goes.

Two short phrases use what is in front of you: "open the artifact" (with a session in front) and "open the terminal
for this" (with an artifact in front).

The microphone is on only while fn is held. Speech is recognised on this Mac. Audio is never saved.

## What leaves this Mac

Without a TypeSafe key, nothing: apps, websites, folders and the list of sessions need no request at all, and a
session or artifact that you describe is found by a plain word match on this Mac and offered as two choices.

With a key (optional, step 3 of the setup), Jarvis picks sessions and artifacts better and opens them directly.
To choose between sessions and artifacts, Jarvis then sends one request to TypeSafe's Jev service
(https://docs.typesafe.ai). It contains what you
said, and for each open session: its title, its folder name, a few distinctive words you typed there, and a few
distinctive words from what Claude wrote there (its replies, the documents and text files it wrote, and the titles
and descriptions of its artifacts). Code, shell commands and files Claude only read are not used. For artifacts of
open sessions it contains their titles and descriptions. Links, file paths, email addresses, long tokens and your
name are removed first, and your home folder is sent as "home". Other people's names are not removed. Apps and
websites that you name outright are opened without any request, and so is the list of all sessions.

The words are gathered by Jarvis itself from each open session, again every 30 seconds and each time fn goes down.
Nothing is written by hand, and a session that closes is forgotten.

## Set up (once)

Run these in order, from this folder. Each one says what it did.

| Step | Command | What it does |
|---|---|---|
| 1 | `scripts/make-cert.sh` | Makes a signing certificate that stays on this Mac, so macOS keeps Jarvis's permissions after a rebuild. macOS asks for your password once. |
| 2 | `scripts/fetch-model.sh` | Downloads the speech model (about 480 MB). |
| 3 | `scripts/store-key.sh` | **Optional.** Copies your `TYPESAFE_API_KEY` from the shell into the login Keychain. The key is never printed. Skip it if you have no key: the Setup window then shows that one line as not done, and described sessions are offered as two choices. |
| 4 | `scripts/install-addon.sh` | Installs the small VS Code add-on that selects one terminal. |
| 5 | `scripts/install.sh` | Builds Jarvis, puts it in `~/Applications`, and starts it at every login. |

Then change two keyboard settings:

1. System Settings → Keyboard → **Press Globe key to** → **Do Nothing**.
2. System Settings → Keyboard → Dictation → **Shortcut**: choose anything other than "Press Globe twice", or turn
   Dictation off.

The first time, macOS asks you to allow the microphone, Input Monitoring (so Jarvis can see the fn key; reopen
Jarvis after you allow it), and control of Terminal and Google Chrome. The menu-bar item has **Setup…**, which
shows a tick for each thing that is ready and says what to do for each thing that is not.

Requirements: macOS 14 or later on Apple silicon, the Swift toolchain (Command Line Tools are enough), Node, and
Homebrew's `whisper-cpp`.

## Day to day

- **Websites:** well-known sites (Instagram, Gmail, GitHub, LinkedIn, Reddit and so on) are known already. For any
  other, menu-bar item → **Edit websites…** opens
  `~/Library/Application Support/Jarvis/config.json`. Add a name, other spoken names ("aliases") and an address.
  An entry of yours replaces a built-in site of the same name. When an app with that name is installed, the name
  means the app ("open Spotify"). Websites open in Google Chrome: an open tab on that site comes forward, otherwise
  a new tab opens.
- **Folders on a drive or in a projects folder:** add the top folder under `"folders"` in the same file, for example
  `{"path": "/Volumes/vault", "depth": 5, "skip": ["App data"]}`. Every folder below it, down to that many levels,
  can then be opened in Finder by name: "open the Claude Code Series folder", "open episode 9 in the Claude Code
  Series folder", "open the vault". A folder in `skip` is listed but not entered. Hidden folders, apps and other
  packages, and `node_modules` are left out.
  - Say **"folder"**, **"in Finder"** or the drive's name. Folder names are often also the names of pieces of work,
    and without those words sessions come first; a folder is then offered only when nothing else fits.
  - When two folders fit, both are shown with where they are, and your choice is remembered for that phrase.
  - Jarvis reads folder names only, never a file, and the names stay on this Mac. The first time, macOS asks whether
    Jarvis may access files on a removable volume: allow it, or the drive's folders stay unknown (System Settings,
    Privacy & Security, Files and Folders, Jarvis).
  - The list is refreshed every five minutes and when a drive is plugged in or taken out. An unplugged drive's
    folders are still known by name, and Jarvis says that the folder is not there now.
- **A single folder** can also be an entry in the websites list with an address that starts with `file:///`.
  The same file holds extra spoken names for apps and the thresholds. Changes to websites and app names apply at
  the next request; changes to thresholds apply the next time Jarvis starts.
- **Remembered choices:** `~/Library/Application Support/Jarvis/remembered.json`. Delete a line to forget it.
- **Log:** menu-bar item → **Open log** (`~/Library/Logs/Jarvis/events.jsonl`). One line per request: what was
  heard, what happened, and how long each step took. `python3 scripts/tally.py` summarises it.
- **What Jarvis sees:** `build/Jarvis.app/Contents/MacOS/Jarvis --list-sessions` prints the open sessions and the
  words it knows them by. `--check-setup` prints the setup checks.
- **Why did it pick that?** `build/Jarvis.app/Contents/MacOS/Jarvis --pick "open the pattern artifact"` shows what
  Jarvis would do with a phrase right now and what Jev answered to each question. It opens nothing. Each log line
  of a request that went to Jev holds the same answers under `jev`.

## After an upgrade

- After `brew upgrade` changes `whisper-cpp` or `ggml`, run `scripts/install.sh` again so Jarvis is rebuilt
  against the new library.
- After a Claude Code upgrade, if sessions or artifacts stop being found: Claude Code's own files are internal and
  can change. Everything that reads them is in `Sources/JarvisCore/Claude/`, with tests and sample files.

## Build and test

```
swift test                 # all tests; the speech tests are skipped when the model is not downloaded
JARVIS_LIVE=1 swift test --filter JevLive    # three real requests to Jev with the sample cards
cd vscode-addon && npm test
scripts/make-app.sh        # build/Jarvis.app
```

## Remove

```
launchctl bootout gui/$(id -u)/local.jarvis.switcher
rm ~/Library/LaunchAgents/local.jarvis.switcher.plist
rm -r ~/Applications/Jarvis.app ~/Library/Application\ Support/Jarvis ~/Library/Logs/Jarvis
code --uninstall-extension local.jarvis-bridge
security delete-generic-password -s Jarvis -a typesafe-api-key
security delete-identity -c "Jarvis Local Signing"     # the local signing certificate and its key
```

A note on that certificate: its key sits in your login Keychain, where the `codesign` tool may use it. Any program
running as you could therefore sign something as Jarvis and be given the permissions you granted Jarvis
(microphone, seeing keys, controlling Terminal and Chrome). That is the price of permissions that survive a
rebuild without a paid Apple developer identity.

## How it is put together

`Sources/JarvisCore` is the logic with no Mac plumbing in it: the cards (every destination), the picker, reading
Claude Code's files, and the privacy scrub. `Sources/JarvisKit` is the Mac side: the key, the microphone, speech
with whisper.cpp, the pill, and bringing windows forward. `vscode-addon` selects one terminal inside VS Code.
[`PROMPT.md`](PROMPT.md) lists the rules the tool keeps and where to read first.

## Licence

MIT. See [`LICENSE`](LICENSE).
