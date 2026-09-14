# GestureBind

Bind MacBook trackpad gestures to macOS actions. A menu-bar agent that reads raw
multitouch data from the built-in trackpad, recognises multi-finger taps, and runs
whatever you've bound them to — screenshots to the clipboard, keyboard shortcuts,
arbitrary commands.

Out of the box:

| Gesture | Action |
| --- | --- |
| 3-finger tap | Full screen to clipboard |
| 4-finger tap | Selected region to clipboard |

## Requirements

- macOS 13 or later
- Xcode Command Line Tools (`xcode-select --install`) — the build uses `swiftc` only,
  there is no Xcode project

## Setup

```bash
./build.sh          # produces GestureBind.app in this directory
open GestureBind.app
```

The app has no Dock icon. It appears as a hand icon in the menu bar; that menu is
where you'll find Settings and Quit.

### Grant every permission macOS asks for

**This is the step that makes or breaks it.** The first time you run the app — and the
first time each gesture actually fires — macOS will interrupt with permission prompts.
Accept all of them. If you dismiss one, the gesture will appear to do nothing at all,
with no error anywhere.

You will be asked for some combination of:

- **Screen Recording** — required by `screencapture`, so any screenshot binding needs it.
  macOS will not prompt again if you decline; you have to add it by hand in
  System Settings → Privacy & Security → Screen Recording, then toggle GestureBind on.
- **Accessibility** — required to post synthetic keystrokes (Mission Control, Spotlight,
  and any other key-stroke action). System Settings → Privacy & Security → Accessibility.
- **Input Monitoring** — some macOS versions ask for this to read the trackpad.

After granting anything in System Settings, **quit GestureBind from its menu bar icon and
open it again**. macOS only hands a process its new permissions at launch, so a running
app keeps behaving as if it were still denied.

### If macOS refuses to open the app

The build is signed ad-hoc, not notarised. If Gatekeeper blocks it, right-click
`GestureBind.app` → **Open** → **Open**, once.

### Launch at login

System Settings → General → Login Items → **+** → pick `GestureBind.app`.

## Using it

Click the menu bar icon:

- **Gestures Enabled** — master switch, for when a gesture is fighting you
- **Settings…** — the binding editor
- **Quit GestureBind**

In Settings, the left column lists your bindings with a per-binding on/off switch and
**+** / **−** to add and remove. Selecting one opens its editor:

- **Fingers** — set the finger count directly, or hit **Record gesture** and perform the
  gesture on the trackpad. While recording, gestures don't fire their actions.
- **Preset** — common macOS actions (screenshots, Mission Control, Spotlight, lock screen).
  Editing the fields below switches the picker to *Custom*.
- **Command / Arguments** — runs an executable directly. This is not a shell: no pipes,
  no globbing, no `~`. Use a full path like `/usr/sbin/screencapture`.
- **Key code / modifiers** — posts a key-down/up pair. Key codes are the classic Carbon
  virtual key codes (49 = Space, 125/126 = down/up arrow, 12 = Q).

The bar along the bottom shows the last gesture the recogniser saw, which is the fastest
way to tell "my gesture wasn't recognised" apart from "the action failed".

Changes save immediately to
`~/Library/Application Support/GestureBind/bindings.json`. **Reveal config** opens it in
Finder; it's plain JSON and safe to edit while the app is closed.

## Tuning

Three-finger gestures are contested territory — macOS uses them for 3-finger drag (if
enabled in Accessibility → Pointer Control) and for swiping between spaces. The
recogniser rejects anything that travels more than `tapMaxMovement` or lasts longer than
`tapMaxDuration`, so a genuine swipe won't fire a tap, but a hesitant one that barely
moves might. Both thresholds are at the top of `Sources/Engine.swift`:

```swift
var tapMaxDuration = 0.35     // seconds; lower = stricter
var tapMaxMovement: Float = 0.03   // normalized trackpad units; lower = stricter
var maxContactSize: Float = 1.2    // palm rejection
```

## How it works

```
trackpad ──> MultitouchSupport.swift ──> Recognizer ──> Engine ──> Action
             raw contact frames         taps            routing    shell / keystroke
                                                          │
                                                          └─> Store (bindings.json)
```

- `Sources/MultitouchSupport.swift` — runtime bindings to Apple's private
  `MultitouchSupport.framework`, loaded with `dlopen`/`dlsym` rather than linked, so a
  future macOS that removes the symbols gives a clean error instead of failing to launch.
- `Sources/Engine.swift` — the recogniser (a state machine over contact frames) and the
  dispatcher that hops results from the multitouch thread to the main queue.
- `Sources/Model.swift` — `Gesture`, `Action`, `Binding`, and the action presets. The
  JSON format carries a `kind` discriminator so new gesture and action types can be added
  without invalidating existing configs.
- `Sources/Store.swift` — persistence and lookup.
- `Sources/SettingsView.swift`, `Sources/main.swift` — SwiftUI editor and menu bar agent.

### A note on the private framework

Reading per-finger trackpad data has no public API. `MultitouchSupport.framework` is what
every tool in this space uses, and the struct layout in `MultitouchSupport.swift` is the
community-documented one that has held stable for well over a decade. The consequences:
this app can never ship on the Mac App Store, and a macOS update could in principle
change the layout. The public fallback — a `CGEventTap` on gesture events plus
`NSEvent.allTouches()` — gives less data and needs Accessibility permission just to read,
but it would slot in behind the same `Recognizer` interface.

## Roadmap

- Per-app bindings (watch `NSWorkspace.didActivateApplicationNotification`, key the
  lookup on bundle ID with a global fallback)
- Swipes, pinches, rotations and tip-taps
- Keystroke recording in the UI instead of raw key codes
- Typing suppression: ignore contacts within ~150ms of a key event
- Window management actions via the Accessibility API
