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

Timed sessions install a temporary root launchd restore job at the same time sleep is disabled, so normal sleep can be restored even if the menu bar app is not frontmost.

Restoring sleep is always permanent until you start a new awake session. The timer only applies while sleep is disabled.

When you click the menu bar action, macOS shows the standard administrator prompt. The app does not store your password or use the network. Timed sessions create a temporary root launchd job so sleep can be re-enabled later without a second prompt. The job removes itself after it restores sleep. If the optional failsafe daemon is installed, a separate root launchd job also checks timed-session deadlines and restores normal sleep if the temporary job is missing.

## Why This Exists

Local agents are only useful while the machine stays awake. Closing a MacBook lid normally puts macOS to sleep, which stops local Codex and Claude Code sessions mid-task. This app gives you a visible, reversible switch for the sleep setting that matters.

## Safety

Disabling sleep can keep the machine warm and active. Do not use this while the MacBook is inside a bag, sleeve, or anywhere heat cannot escape. Use it on a hard, ventilated surface, ideally on power.

## Compatibility

The app targets macOS 13 or newer because it uses SwiftUI's menu bar APIs. The sleep switch itself relies on Apple's `pmset` command; Apple documents `sudo pmset -a disablesleep 1` as disabling all sleep functions, and separately documents `pmset` as the Terminal utility for Mac sleep, wake, restart, and shutdown scheduling:

- https://support.apple.com/101114
- https://support.apple.com/guide/mac-help/mchl40376151/mac

Because `disablesleep` is not documented in every local `pmset` man page, the app reads `pmset -g` after every change and reports an error if the setting did not actually change.

## Install And Run

For normal use, build or download the app, then put it in `/Applications`.

From a local clone:

```sh
./script/build_and_run.sh --build-only
cp -R "dist/Don't Die On Me Now.app" /Applications/
open "/Applications/Don't Die On Me Now.app"
```

From a release zip:

1. Unzip `DontDieOnMeNow.zip`.
2. Move `Don't Die On Me Now.app` to `/Applications`.
3. Open it from Finder or Terminal.

Because this is an unsigned dev utility, macOS may block the first launch. If that happens, Control-click the app in Finder, choose Open, then confirm. After the first accepted launch, it should open normally.

The app appears in the macOS menu bar, not the Dock. Click the menu bar item, choose a duration, then click Keep Awake. When it is running, click Stop to restore normal sleep.

## Run At Login

Yes, it can be set up to run when you log in.

Recommended manual setup:

1. Move `Don't Die On Me Now.app` to `/Applications`.
2. Open System Settings.
3. Go to General, then Login Items & Extensions.
4. Under Open at Login, click the add button.
5. Select `/Applications/Don't Die On Me Now.app`.

Apple documents this flow here: https://support.apple.com/guide/mac-help/open-items-automatically-when-you-log-in-mh15189/mac

This only launches the menu bar app at login. It does not automatically disable sleep. You still choose when to start an awake session, and macOS still shows the administrator prompt when the app changes `pmset`.

If you move or delete the app later, remove and re-add the Login Item so macOS points at the new app location.

Dev setup script:

```sh
./script/install_login_launcher.sh
```

Remove it:

```sh
./script/uninstall_login_launcher.sh
```

The script installs a user LaunchAgent at `~/Library/LaunchAgents/com.josh.DontDieOnMeNow.login.plist`. It launches the app at login with `/usr/bin/open`.

## Safety Net

For timed sessions, the app uses two protections:

1. It bootstraps a temporary launchd restore job before it disables sleep. If the app crashes after the admin command succeeds, launchd owns the restore work.
2. It atomically writes a root-owned deadline file at `/Library/Application Support/DontDieOnMeNow/deadline`.

The temporary restore job lives at `/Library/LaunchDaemons/com.josh.DontDieOnMeNow.restore.plist` while a timed session is active. It runs `/Library/Application Support/DontDieOnMeNow/restore_once.sh`, sleeps until the saved deadline, runs `pmset -a disablesleep 0`, then removes itself. Clicking Stop removes it too.

For extra protection, install the optional root failsafe daemon:

```sh
./script/install_failsafe_daemon.sh
```

That installs `/Library/LaunchDaemons/com.josh.DontDieOnMeNow.failsafe.plist`. It runs once per minute as root. If a timed-session deadline has passed, it runs:

```sh
pmset -a disablesleep 0
```

Remove it:

```sh
./script/uninstall_failsafe_daemon.sh
```

Check the current safety state:

```sh
./script/safety_status.sh
```

Manual emergency restore:

```sh
./script/restore_sleep_now.sh
```

There is still no honest "no way, ever" guarantee. macOS, root launchd, `pmset`, power loss, and manual root-level file edits can fail or interfere. The practical guarantee is: for timed sessions, normal app crashes do not strand the Mac in no-sleep mode, and the temporary launchd restore job can self-recover after reboot by reading the saved deadline. The optional failsafe daemon is a second line of defense if the temporary restore job is missing. The "Until I restore it" mode is intentionally manual and can stay awake until you click Stop or run the restore script.

## Build And Run From Source

Requirements:

- macOS 13 or newer
- Xcode Command Line Tools
- Swift 6-capable toolchain

Run the tests:

```sh
swift test
```

Build and launch the app bundle from the repository:

```sh
./script/build_and_run.sh
```

The menu bar icon changes by mode:

- moon: normal sleep
- timer: timed awake session
- infinity: awake until manually restored
- warning: timer expired, or the timed restore was lost after a restart
- moon outline: checking current state

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

The default app is intentionally small:

- no privileged helper installed by default
- no telemetry
- no network access
- no password storage
- no persistent background service unless you install the optional failsafe daemon
- timed sessions use a temporary launchd restore job that removes itself

The default app still has no persistent background service. Timed sessions create a temporary launchd restore job only for the lifetime of that session. The optional failsafe daemon is a dev-targeted safety net you can install if you want an always-on second check. The tradeoff is that each toggle uses the normal macOS administrator prompt.

If you do not install the failsafe daemon and the temporary restore job is manually removed, the app cannot automatically fix sleep settings before it is running. Launch the app and choose Stop or start a new Keep Awake session.

`disablesleep` is visible in `pmset -g` on supported systems, but it is not documented in every local `pmset` man page. Apple documents `sudo pmset -a disablesleep 1` in an OS X Server support article, and this app verifies the setting after each change. If your Mac does not accept the setting, the app should show the underlying `pmset` or administrator-prompt error and leave the current state unchanged.

## License

No license has been selected yet. Add one before making the repository public.
