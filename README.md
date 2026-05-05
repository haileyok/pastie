# Pastie

A small macOS menu-bar app that uploads the image on your clipboard to a remote host over SSH and copies the resulting remote path back to your clipboard.

## Requirements

- macOS 14 or newer
- Swift 5.9+ toolchain (`xcode-select --install` if `swift` isn't on your PATH)
- Working SSH access to the target host with key-based auth (no password prompts) — Pastie shells out to `/usr/bin/scp` non-interactively

## Build

```sh
./build-app.sh
```

This produces `Pastie.app` in the repo root, ad-hoc codesigned.

## Install

```sh
mv Pastie.app /Applications/
open /Applications/Pastie.app
```

If macOS Gatekeeper blocks the app on first launch, right-click it in Finder and choose **Open**, or strip the quarantine attribute:

```sh
xattr -dr com.apple.quarantine /Applications/Pastie.app
```

Pastie runs as a menu-bar item only — there is no Dock icon.

## Configure

Click the menu-bar icon and choose **Settings…**.

- **Host Mappings** — pairs of `Window name → SSH host`. The window name is the title of a Ghostty window; the SSH host is any alias from `~/.ssh/config`, or `user@hostname`. Add as many mappings as you like.
- **Remote Directory** — where uploaded files are written. Defaults to `~/uploads`. Pastie does not create the directory; make sure it already exists on every remote (`ssh <host> mkdir -p ~/uploads`).

When you trigger an upload, Pastie reads the frontmost Ghostty window's name (via AppleScript) and looks it up in the mapping table:

- **Match** — uploads to the matching SSH host.
- **No match** — falls back to uploading to *every* host listed in the mapping table in parallel.

The first time you trigger an upload, macOS will ask you to allow Pastie to control Ghostty (Apple Events) — accept the prompt.

The menu-bar dropdown shows the current routing decision (e.g. `gamma → gamma` or `obi → fallback (2 hosts)`) so you can sanity-check before triggering.

## Use

1. Copy an image to the clipboard (screenshot, web image, file copy, etc.).
2. Press **⌃⌥⌘V** (Control-Option-Command-V), or click the menu-bar icon and choose **Upload Clipboard Image**.
3. Pastie writes a timestamped PNG (`pastie-YYYY-MM-DD-HHmmss.png`) to the configured remote directory on the resolved host(s) and copies the resulting remote path to your clipboard. The path is the same on every host, so the clipboard string is unambiguous.

A notification confirms success, partial success (some hosts failed in the fallback case), or failure.
