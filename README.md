# Don't Die On Me Now

A small macOS menu bar app for keeping Codex and Claude Code running while your MacBook lid is closed.

macOS normally sleeps when you close the lid. That can pause long-running Codex or Claude Code work. Don't Die On Me Now gives you a simple menu bar switch to keep the Mac awake for a chosen amount of time, then restore normal sleep automatically.

## What It Does

- Keeps the Mac awake for 1 hour, 3 hours, 6 hours, 12 hours, or a custom duration.
- Defaults to 6 hours.
- Also supports "Until I restore it" for a manual session.
- Shows a countdown while a timed session is running.
- Restores normal sleep when the timer ends or when you click Stop.

Under the hood, the app uses macOS's built-in `pmset` command. macOS will ask for your administrator password when the app changes the sleep setting. The app does not store your password.

## Safety

Do not use this with a MacBook in a bag or sleeve. Keeping a closed Mac awake can make it warm. Use it on a hard, ventilated surface, ideally on power.

Timed sessions are designed to clean up after themselves. When you start one, the app also creates a temporary macOS restore job so sleep is turned back on when the timer ends.

## Install And Run

From a local clone:

```sh
./script/build_and_run.sh --build-only
cp -R "dist/Don't Die On Me Now.app" /Applications/
open "/Applications/Don't Die On Me Now.app"
```

Because this is an unsigned dev utility, macOS may block the first launch. If that happens, Control-click the app in Finder, choose Open, then confirm.

The app appears in the menu bar, not the Dock.

## Use It

1. Click the menu bar icon.
2. Pick a duration, or choose Custom and enter minutes.
3. Click Keep Awake.
4. Click Stop when you want normal sleep back.

The menu bar usually shows only an icon. During a timed session it also shows an hour-level countdown, and the menu shows the live countdown to the second.

## Run At Login

Manual setup:

1. Move `Don't Die On Me Now.app` to `/Applications`.
2. Open System Settings.
3. Go to General, then Login Items & Extensions.
4. Add `/Applications/Don't Die On Me Now.app` under Open at Login.

Dev setup script:

```sh
./script/install_login_launcher.sh
```

Remove it:

```sh
./script/uninstall_login_launcher.sh
```

This only opens the app at login. It does not automatically start keeping the Mac awake.

## Developer Commands

Run tests:

```sh
swift test
```

Build and launch:

```sh
./script/build_and_run.sh
```

Create a local zip:

```sh
./script/package_release.sh
```

Check current sleep state:

```sh
./script/safety_status.sh
```

Restore normal sleep from the terminal:

```sh
./script/restore_sleep_now.sh
```

Optional extra watchdog for timed sessions:

```sh
./script/install_failsafe_daemon.sh
./script/uninstall_failsafe_daemon.sh
```

Most people do not need the failsafe daemon. It is there for dev setups that want an extra background check.

## Compatibility

Requires macOS 13 or newer.

The app depends on macOS support for:

```sh
pmset -a disablesleep
```

After every change, the app checks `pmset -g` to confirm the setting actually changed.

## Privacy

- No telemetry.
- No network access.
- No password storage.
- No privileged helper installed by default.

## License

MIT. See [LICENSE](LICENSE).
