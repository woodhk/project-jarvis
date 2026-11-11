# Build your own Jarvis

This file is a prompt for a coding agent (it was written for Claude Code running Fable 5.2).

**If you are the person who wants a Jarvis:** open Claude Code in a new, empty folder and paste this one line:

```
Clone https://github.com/woodhk/project-jarvis into a folder called jarvis-reference, read jarvis-reference/PROMPT.md, and follow it to build this for my computer.
```

Everything below is for the agent.

---

## What you are building

A hold-to-talk voice switcher. The person holds one key, says what they want ("open the multi-agent session",
"open the Claude Code Series folder", "quit Spotify"), lets go, and about one second later it is in front of them.
It can open apps, websites, folders, and the exact terminal tab of a Claude Code session that is already running.

This repository is the author's working version for his own Mac: a Swift menu-bar app and a small VS Code add-on.
It is your reference, so you can see how every part was solved and get it right. Your job is to give this person
their own version, for their computer and the apps they use:

- On a recent Mac that mostly means building and installing the reference, then changing the parts their answers
  call for.
- On Windows or Linux it means porting it: the same behaviour, built with that system's own tools.

The person may not be technical. Lead them. Use plain English, ask one question at a time, and say in a few words
why you are asking. When something cannot be done on their machine, or is a much bigger job than it sounds, say so
before you start and offer the nearest thing that can.

## Step 1. Look before you ask

Find out what you can by yourself, then tell the person what you found in two or three lines:

- the operating system and its version, and the chip (Apple silicon, Intel, ARM);
- which terminals, code editors and browsers are installed, and which browser is the default;
- which of these exist: a package manager (Homebrew, winget, apt), Swift, Node, Python, whisper.cpp;
- whether Claude Code has been used here (a `.claude` folder in the home folder) and how many sessions are open now.

Do not ask a question you can answer by looking.

## Step 2. Ask these, one at a time

Skip any you already know. Offer the usual answer as the default so they can just say "yes".

1. **"You're on [what you found], right?"** The reference needs macOS 14 or later on Apple silicon. Anything else
   changes the plan, so confirm it first.
2. **"What do you want to open by voice?"** Claude Code sessions, apps, websites, folders, pages Claude made
   (artifacts). Each kind is its own piece of work, so build only what they will use.
3. **"Where do you run Claude Code?"** Terminal, iTerm2, Warp, Ghostty, the terminal inside VS Code or Cursor,
   Windows Terminal, WSL. Finding the exact tab is different in each one. The reference handles Terminal and
   VS Code only; anything else needs a new opener.
4. **"Which browser should websites open in?"** The reference uses Google Chrome.
5. **"Which key do you want to hold while you speak?"** The reference uses fn (the Globe key). It has to be a key
   they can hold comfortably and that nothing else uses. Check for clashes (dictation, the emoji picker, a keyboard
   with no fn key) and suggest two that are free.
6. **"Which two or three folders or drives do you dig through most?"** These become the places whose folders can be
   opened by name.
7. **"Any websites you open every day?"** About thirty well-known ones are built in; theirs get added to the list.
8. **"Which language will you speak to it in?"** The reference uses an English-only speech model. Another language
   needs the multilingual model, which is larger and a little slower.
9. **"When you describe a session loosely ('the one about invoices'), how should it work out which one you mean?"**
   Explain the two choices plainly:
   - *On this computer only.* A plain word match. Free, nothing leaves the machine. It shows two choices more often
     and you tap the one you meant.
   - *TypeSafe's Jev,* which the author uses. Quicker, better guesses. It needs their own TypeSafe API key, and it
     sends the session's title, folder name and a few key words (with links, paths, emails and their name removed)
     to that service.
   Use the first unless they have a key and choose the second. Never ask them to paste a key into this chat: have
   them put it in their shell themselves, and read it from there.
10. **"Should it start by itself when you log in?"**
11. **"Is there anything it must never do?"** For example, never quit an app.

## Step 3. Read the reference before you plan

Read these in this order. The comments at the top of each file say why it exists.

| Read | For |
|---|---|
| `README.md` | What it does, day to day, and the one-time setup on a Mac |
| `Sources/JarvisCore/Pick/Picker.swift` | The order of decisions for one spoken phrase: this is the heart of it |
| `Sources/JarvisCore/Cards/` | "Cards": every destination (session, page, app, website, folder) in one model |
| `Sources/JarvisCore/Claude/` | Reading Claude Code's own files to find the sessions that are open now |
| `Sources/JarvisCore/Privacy/Scrubber.swift`, `Jev/` | What may leave the machine, and what is removed first |
| `Sources/JarvisKit/Coordinator.swift`, `Pill/` | The states the person sees: listening, opened, two choices, nothing |
| `Sources/JarvisKit/Open/` | How each kind of destination is brought to the front |
| `Sources/JarvisKit/Audio/`, `KeyMonitor.swift` | Recording while the key is held, and speech to text with whisper.cpp |
| `scripts/`, `Resources/`, `vscode-addon/` | Building, signing, installing, starting at login, the VS Code add-on |
| `Tests/` | What "correct" means, with sample files |

Claude Code's own files are internal and can change between versions. Compare the sample files in
`Tests/JarvisCoreTests/Fixtures/claude/` with what is really on this person's machine before you rely on them, and
keep everything that reads those files in one place with tests, as the reference does.

## Step 4. Show the plan and wait

Write a short plan in plain English and wait for a clear "go":

- what you will build, and what you are leaving out and why;
- what will be installed and where, including the speech model (about 480 MB);
- what they will have to allow or click (microphone, seeing the key, controlling other apps) and why each is needed;
- what, if anything, will leave their computer;
- how to remove all of it again.

## What must stay true on every computer

These rules are the product. Keep them whatever you build it with.

- **Hold to talk.** The microphone is on only while the key is held. Audio is never saved. Speech is turned into
  text on the computer itself.
- **Fast.** The window is in front about one second after the key is released. If it is slow, people go back to
  the mouse. Measure it and tell them the number.
- **Other keys still work.** If another key is pressed during the hold, cancel quietly, so shortcuts that use the
  same key are not broken.
- **Never guess.** Sure: open it, and show what was heard and where it went. Not sure: show two numbered choices
  and open neither. Nothing fits: say so and do nothing. A confident wrong open is worse than a question.
- **Remember choices.** The same phrase should not ask the same question twice. Do not remember phrases that depend
  on what was in front at the time ("open the terminal for this").
- **"Back"** returns to the window that was in front before.
- **Windows come forward as they are.** Never move or resize them.
- **Close hides, quit asks nicely.** "Close" hides an app and loses nothing. "Quit" asks the app to quit in the
  normal way and is never forced, so it can still ask about unsaved work. Ask first when quitting would end running
  Claude Code sessions, or when the name was not heard exactly. Never quit the system's file manager.
- **It only opens, hides and quits.** It never deletes, sends, types into or edits anything.
- **Named things need no internet.** An app, website or folder that is named outright opens with no request to any
  service. Folders are known by name only; no file is read.
- **If a hosted service picks the session,** send only what was said and the cards' text; remove links, file paths,
  email addresses, long tokens and the person's name first; give it a hard time limit (the reference uses 800 ms);
  and when it does not answer, fall back to the word match, which only ever offers choices.
- **A log line per request:** what was heard, what happened, how long each step took. No audio.
- **A setup check** that lists what is ready and, for anything that is not, what to do in one sentence.

## Notes for each system

**Mac, macOS 14 or later, Apple silicon.** Follow the "Set up (once)" table in `README.md`, in order. Then change
what their answers need: a different terminal means a new opener modelled on `TerminalOpener.swift`; a different
browser, one modelled on `ChromeOpener.swift`; a different key, `HoldDetector.swift` and `KeyMonitor.swift`.
`scripts/store-key.sh` is only for people who chose TypeSafe. Without a key the app still works: the setup window
shows that line as not done, and sessions that are described loosely are offered as two choices.

**Intel Mac or older macOS.** Speech will be slower. Measure it first; the smaller `base.en` model may be the right
trade.

**Windows or Linux.** The author has not built or tested this. Tell the person that. Do not try to compile the
Swift app. Port it:

- Keep the logic in `Sources/JarvisCore` (cards, picking, text clean-up, scrubbing) and its tests, translated
  faithfully. That part does not depend on the Mac.
- Replace everything in `Sources/JarvisKit`: the global key, the microphone, the small overlay, and bringing a
  window forward. Use whisper.cpp with the same models for speech.
- Choose the simplest tools that can do all four on that system, and say what you chose and why.
- Be honest about limits. Windows restricts which program may bring a window to the front. On Linux under Wayland,
  an app often may not raise another app's window at all. Find out what is possible on their machine before you
  promise it.
- Sessions that run inside WSL keep their files inside WSL.

## Step 5. Build in this order, and try each step with them

1. Hold the key, record, show the words. Test this with their real voice and microphone before anything else,
   because everything depends on it.
2. Apps, websites and folders named outright.
3. Claude Code sessions: print the ones you can see and compare them with what they have open.
4. Picking, two choices, remembered choices, "back".
5. Close and quit, and the list of all sessions.
6. Start at login and the setup check.

After each step, have them say three phrases. Fix what goes wrong before you move on.

## Step 6. Hand over

Leave them a short page: how to use it, where the settings file is, how to add a website or a folder, what leaves
their computer (if anything), and how to remove everything.

## Rules for you

- Ask before you install anything outside this folder or anything that needs their password. Show the command and
  say what it does.
- Never print, log or ask for an API key.
- Change nothing outside the project folder and the install places named in your plan.
- Do not say something works until you have seen it work on their machine. If you could not test it, say that.
