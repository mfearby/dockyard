---
name: build-dockyard
description: Build Dockyard from source on this Mac. Checks the macOS version, installs Apple's Command Line Tools if needed, checks Node.js, sets up the "Dockyard Local Dev" code-signing certificate, builds build/Dockyard.app, runs the tests and opens the app. Use when the user asks to build, set up, install or run Dockyard.
---

# Build Dockyard

Build and launch Dockyard on the user's Mac, from a fresh clone. Run every command from the repository root
(the folder containing `Package.swift`). Stop and explain if a step fails; don't skip ahead.

## 1. Check macOS

```bash
sw_vers -productVersion
```

Dockyard needs macOS 14 (Sonoma) or later. If it's older, stop and tell the user.

## 2. Check Apple's Command Line Tools (Swift compiler)

```bash
xcode-select -p && swift --version
```

If either command fails, the Command Line Tools aren't installed. Run:

```bash
xcode-select --install
```

This opens a macOS installer window rather than installing in the terminal. Ask the user to click **Install**
and tell you when it has finished (it can take several minutes), then run the check again. Full Xcode is not
needed.

## 3. Check Node.js

```bash
node --version
```

Node.js 22.18 or later is needed (it runs the TypeScript tests without extra setup). If Node is missing or
older, ask the user before installing anything. If they use Homebrew, suggest `brew install node`; otherwise
point them to https://nodejs.org.

## 4. Set up the local code-signing certificate

```bash
scripts/setup-dev-cert.sh
```

This adds a self-signed "Dockyard Local Dev" certificate to the login keychain so macOS keeps Dockyard's
Accessibility permission across rebuilds. It's safe to run again: it does nothing if the certificate exists.
The certificate only works on this Mac and can't be used to distribute the app. Tell the user what it does
before running it, since it changes their keychain.

## 5. Build the app

```bash
scripts/build-app.sh
```

This installs the web UI's npm dependencies on the first run, builds the TypeScript UI and the Swift app, and
packages `build/Dockyard.app`. Check the output ends with `Signed with "Dockyard Local Dev"` and
`Built build/Dockyard.app`. If it says it signed ad-hoc instead, step 4 didn't work; go back to it.

## 6. Run the tests

```bash
scripts/test.sh
```

Report the Swift and TypeScript test counts. A failure here means the code is broken, not the setup; report it
rather than trying to fix the code unless the user asks.

## 7. Launch Dockyard

If an older copy is running, quit it first, then open the new build:

```bash
pkill -f "Dockyard.app/Contents/MacOS/Dockyard"; open build/Dockyard.app
```

The taskbar appears along the bottom of the main display. Tell the user:

- Several features (separate window buttons, badges, right-click window actions, keeping windows above the
  taskbar) need Accessibility access. They can grant it from the menu button (three lines) → **Options…** →
  **Grant Access…**, or in System Settings → Privacy & Security → Accessibility.
- To quit Dockyard, use the menu button → **Quit Dockyard**.

## Troubleshooting

- **The app won't open or is killed straight away:** check for security software that blocks unknown apps
  (some workplaces use app allow-listing). The user may need to allow `build/Dockyard.app`. Don't try to get
  around it.
- **`security import` asks for a password:** that's the user's login keychain password; let them enter it.
- **Swift Testing errors when running the tests:** run them through `scripts/test.sh`, not plain `swift test`.
  The script adds the flags Swift Testing needs when only the Command Line Tools are installed.
