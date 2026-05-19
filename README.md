# MutePls

MutePls is a small macOS menu bar utility for AirPods Max 2. It listens for the private macOS audio accessory mute notification emitted by `audioaccessoryd` and toggles the default input device mute state through Core Audio.

It also includes a Play/Pause media-key fallback for AirPods Max 2 setups where pressing the Digital Crown opens Music instead of emitting the audio accessory mute notification.

## Requirements

- macOS 14 or newer
- Xcode command line tools
- AirPods Max 2 connected as the active input device
- Accessibility permission for the Play/Pause fallback

## Build

```sh
make build
```

See all available commands:

```sh
make help
```

## Run

```sh
make run
```

## Package as an app

```sh
make package
```

This creates:

```text
dist/MutePls.app
```

The package step also generates `Assets/MutePls.icns` and includes it in the app bundle.
Generated icon sizes cover the full macOS `.iconset` set: 16, 32, 128, 256, and 512 point icons at both `1x` and `2x`, including a 1024px source.

Install it into `/Applications`:

```sh
make install
make open
```

Install, restart, and open the app in one command:

```sh
make reinstall
```

The install step registers `/Applications/MutePls.app` with LaunchServices so launchers such as Raycast can index it.

If Finder still shows the generic app icon after reinstalling, refresh Finder's icon cache for the bundle:

```sh
touch /Applications/MutePls.app
killall Finder
```

## Start at login

After installing and opening `/Applications/MutePls.app`, right-click the menu bar icon and enable:

```text
Start at Login
```

The item is checked when the LaunchAgent is installed.

The app manages this through:

```text
~/Library/LaunchAgents/dev.local.mutepls.plist
```

The app appears as a compact menu bar microphone icon with a status indicator.

- Left click toggles mute manually.
- Right click opens the menu. The `Mute Microphone` / `Unmute Microphone` item also toggles mute.
- Pressing the AirPods Max 2 Digital Crown should toggle mute if macOS emits `com.apple.audioaccessoryd.MuteState`.
- If the crown press arrives as Play/Pause instead, MutePls intercepts it, prevents Music from opening, and toggles mute. This requires Accessibility permission.

## Debugging AirPods Max 2

Run the app from Terminal and press the Digital Crown. You should see a log line like:

```text
MutePls: received Darwin notification com.apple.audioaccessoryd.MuteState
```

If no line appears, AirPods Max 2 or your current macOS version is not emitting the same notification this app listens for. The manual menu bar toggle will still work as long as the active input device supports Core Audio mute.

If pressing the crown opens Music, grant MutePls Accessibility permission:

```text
System Settings -> Privacy & Security -> Accessibility
```

Then restart MutePls. When the fallback catches the event, Terminal logs:

```text
MutePls: intercepted Play/Pause media key
```

If Music still opens, make sure `/Applications/MutePls.app` is the app that has Accessibility permission, then quit and reopen MutePls.

## Caveat

The Digital Crown notification hook relies on private macOS notification behavior. The Play/Pause fallback catches the system Play/Pause key globally, so it can also intercept keyboard/headset Play/Pause presses while MutePls is running.
