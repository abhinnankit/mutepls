# AGENTS.md

## Project

MutePls is a macOS menu bar utility for AirPods Max 2. It toggles the default input microphone mute state from the AirPods Digital Crown and from a menu bar item.

## Build

```sh
make build
```

Use `make help` to list supported workflow targets.

## Package and Install

```sh
make install
make open
```

`make package` creates `dist/MutePls.app`, generates `Assets/MutePls.icns`, and includes it in the app bundle. `make install` always repackages before copying to `/Applications/MutePls.app`. `make reinstall` installs, stops a running app instance, waits briefly, and opens a fresh app instance with `open -n`.

Generated outputs are ignored:

- `.build/`
- `dist/`
- `Assets/AppIcon.iconset/`
- `Assets/MutePls.icns`

The source of truth for the app icon is `scripts/generate-app-icon.swift`.

## App Behavior

- Left-click the menu bar icon to toggle mute.
- Right-click the menu bar icon to open the menu.
- The menu includes mute/unmute, refresh, Accessibility settings when needed, Start at Login, and quit.
- `Start at Login` is managed in-app through `~/Library/LaunchAgents/dev.local.mutepls.plist`.

## Input Paths

MutePls uses several paths because AirPods Max 2 behavior varies by macOS state:

- Darwin notification: `com.apple.audioaccessoryd.MuteState`
- MediaPlayer remote commands: `MPRemoteCommandCenter`
- Global Play/Pause fallback: CGEvent tap for system-defined media key events

The MediaPlayer path is important because some AirPods Max 2 crown presses arrive as Play/Pause and otherwise open Music.

## Permissions

The Play/Pause fallback needs Accessibility permission:

```text
System Settings -> Privacy & Security -> Accessibility
```

After packaging as an app, grant permission to `/Applications/MutePls.app`, then restart the app.

## Notes

- The app is an agent app (`LSUIElement`) with no Dock icon.
- Menu bar icons are drawn in code by `StatusIconFactory`.
- The packaged app icon is generated during packaging and referenced by `CFBundleIconFile` in `scripts/package-app.sh`.
- If Finder shows a stale generic icon after packaging changes, touch `/Applications/MutePls.app` and restart Finder.
- Core Audio mute support depends on the current default input device exposing `kAudioDevicePropertyMute`.
- The Darwin notification path relies on private macOS behavior and may change across macOS or AirPods firmware updates.
