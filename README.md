# Don't Die On Me Now

A tiny macOS menu bar utility for keeping local coding agents running while your MacBook lid is closed.

It is designed for workflows where Codex, Claude Code, builds, tests, or other long-running terminal jobs should keep working instead of being paused by system sleep.

## What It Does

Don't Die On Me Now toggles macOS system sleep by running Apple's `pmset` power setting:

```sh
pmset -a disablesleep 1
pmset -a disablesleep 0
```

When you click the menu bar action, macOS shows the standard administrator prompt. The app does not store your password, install a daemon, start a login item, use the network, or run background services.

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

The tradeoff is that each toggle uses the normal macOS administrator prompt.

`disablesleep` is visible in `pmset -g` on supported systems, but it is not documented in every local `pmset` man page. If your Mac does not accept the setting, the app should show the underlying `pmset` or administrator-prompt error and leave the current state unchanged.

## License

No license has been selected yet. Add one before making the repository public.
