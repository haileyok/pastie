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

- **SSH Host** — any alias from `~/.ssh/config`, or `user@hostname`.
- **Remote Directory** — where uploaded files are written. Defaults to `~/uploads`. Pastie does not create the directory; make sure it already exists on the remote (`ssh <host> mkdir -p ~/uploads`).

## Use

1. Copy an image to the clipboard (screenshot, web image, file copy, etc.).
2. Press **⌃⌥⌘V** (Control-Option-Command-V), or click the menu-bar icon and choose **Upload Clipboard Image**.
3. Pastie writes a timestamped PNG (`pastie-YYYY-MM-DD-HHmmss.png`) to the configured remote directory and copies the resulting remote path to your clipboard.

A notification confirms success or surfaces the error.
