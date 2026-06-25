# Don't Die On Me Now

A tiny macOS menu bar utility for keeping local coding agents running while your MacBook lid is closed.

It is designed for workflows where Codex, Claude Code, builds, tests, or other long-running terminal jobs should keep working instead of being paused by system sleep.

## What It Does

Don't Die On Me Now starts an awake session by running Apple's `pmset` power setting:

```sh
pmset -a disablesleep 1
pmset -a disablesleep 0
```

By default, an awake session lasts 6 hours. You can change the duration from the menu bar before starting or restarting a session:

- 1 hour
- 3 hours
- 6 hours
- 12 hours
- Until I restore it

Timed sessions schedule a delayed restore command at the same time sleep is disabled, so normal sleep can be restored even if the menu bar app is not frontmost.

Restoring sleep is always permanent until you start a new awake session. The timer only applies while sleep is disabled.

When you click the menu bar action, macOS shows the standard administrator prompt. The app does not store your password, install a daemon, start a login item, or use the network. Timed sessions create a one-shot delayed restore process so sleep can be re-enabled later without a second prompt.

## Why This Exists

Local agents are only useful while the machine stays awake. Closing a MacBook lid normally puts macOS to sleep, which stops local Codex and Claude Code sessions mid-task. This app gives you a visible, reversible switch for the sleep setting that matters.

## Safety

Disabling sleep can keep the machine warm and active. Do not use this while the MacBook is inside a bag, sleeve, or anywhere heat cannot escape. Use it on a hard, ventilated surface, ideally on power.

## Build And Run

Requirements:

- macOS 13 or newer
- Xcode Command Line Tools
- Swift 6-capable toolchain

Run the tests:

```sh
swift test
```

Build and launch the app bundle:

```sh
./script/build_and_run.sh
```

The app appears in the macOS menu bar, not the Dock. Click the menu bar item to enable or disable sleep.

The menu bar icon changes by mode:

- moon: normal sleep
- timer: timed awake session
- infinity: awake until manually restored
- warning: timer expired but sleep still appears disabled
- question mark: state unknown

Install the staged app for local testing:

```sh
cp -R "dist/Don't Die On Me Now.app" /Applications/
```

Verify the staged app launches:

```sh
./script/build_and_run.sh --verify
```

Build the app bundle without launching it:

```sh
./script/build_and_run.sh --build-only
```

Create a local zip:

```sh
./script/package_release.sh
```

## Manual Verification

Check the current setting:

```sh
pmset -g | grep -i SleepDisabled
```

Expected values:

- `SleepDisabled 1`: sleep is disabled
- `SleepDisabled 0` or no `SleepDisabled` line: normal sleep behavior

## Design Notes

This is intentionally small:

- no privileged helper
- no launch daemon
- no telemetry
- no network access
- no password storage
- no persistent background service

The tradeoff is that each toggle uses the normal macOS administrator prompt.

`disablesleep` is visible in `pmset -g` on supported systems, but it is not documented in every local `pmset` man page. Apple documents `sudo pmset -a disablesleep 1` in an OS X Server support article, and this app verifies the setting after each change. If your Mac does not accept the setting, the app should show the underlying `pmset` or administrator-prompt error and leave the current state unchanged.

## License

No license has been selected yet. Add one before making the repository public.
