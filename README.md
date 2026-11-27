# Shutdown Controller

A lightweight macOS menu bar application for scheduling automatic system shutdowns.

## Features

- Menu bar interface
- Up to five configurable shutdown times
- Automatically sorted time slots
- Prevents duplicate shutdown times
- Locks enabled schedules within two hours of shutdown
- Enable or disable individual schedules
- Two-minute shutdown warning popup
- Optional launch-at-login
- Automatic shutdown through macOS `System Events`
- Universal build support for Apple Silicon and Intel Macs

## Requirements

- macOS 13 or newer
- Xcode Command Line Tools

## Installation

Download the latest `.dmg` release, open it, and drag `ShutdownController.app` into `/Applications`.

Alternatively, build the app from source:

```bash
./package-app.sh
```

The app bundle will be created at:

```text
build/ShutdownController.app
```

To build a DMG:

```bash
./build-dmg.sh
```

The DMG will be created at:

```text
build/ShutdownController-1.1.0.dmg
```

## Usage

1. Open `ShutdownController.app`.
2. Click the power icon in the macOS menu bar.
3. Add a shutdown time using the hour and minute pickers.
4. Duplicate times cannot be added.
5. Enable the schedule with the toggle.
6. Enabled schedules are locked two hours before shutdown and cannot be changed or deleted.
7. The app will automatically sort enabled and disabled schedules chronologically.
8. Two minutes before a scheduled shutdown, an acknowledgment popup is displayed.
9. The system shuts down at the scheduled time.

## Running Schedule Rule Tests

Run the focused scheduling tests with:

```bash
swiftc ScheduleRules.swift Tests/ScheduleRulesTests.swift -o /tmp/shutdown-controller-tests
/tmp/shutdown-controller-tests
```

## Launch at Login

Enable **Start at login** in the app popover to register it with macOS Login Items.

## Installation and Removal

See [INSTALL-UNINSTALL.txt](INSTALL-UNINSTALL.txt) for installation, removal, and troubleshooting instructions.

## Source

- `ShutdownApp.swift` — app and menu bar setup
- `ContentView.swift` — schedule UI and shutdown logic
- `ScheduleRules.swift` — duplicate-time and schedule-lock rules
- `package-app.sh` — builds a universal macOS app bundle
- `build-dmg.sh` — builds the DMG installer

## License

This project is licensed under the MIT License. Copyright © 2026 Liuhongdan.

See [LICENSE](LICENSE) for the full license text.
