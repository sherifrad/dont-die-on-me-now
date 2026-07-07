# Don't Die On Me Now

A small macOS menu bar app for keeping Codex and Claude Code running while your MacBook lid is closed.

macOS normally sleeps when you close the lid. That can pause long-running Codex or Claude Code work. Don't Die On Me Now gives you a simple menu bar switch to keep the Mac awake for a chosen amount of time, then restore normal sleep automatically.

## What It Does

- Keeps the Mac awake for 30 minutes, 2 hours, 6 hours, or a custom number of minutes.
- Defaults to 6 hours.
- Also supports an infinite manual session that runs until you click Stop.
- Shows a countdown while a timed session is running.
- Restores normal sleep when the timer ends or when you click Stop.

Under the hood, the app uses macOS's built-in `pmset` command. macOS will ask for your administrator password when the app changes the sleep setting. The app does not store your password.

Timed sessions can usually be stopped without a second password prompt. The app writes a local stop token, and the temporary restore job turns normal sleep back on.

## Safety

Do not use this with a MacBook in a bag or sleeve. Keeping a closed Mac awake can make it warm. Use it on a hard, ventilated surface, ideally on power.

Timed sessions are designed to clean up after themselves. When you start one, the app also creates a temporary macOS restore job so sleep is turned back on when the timer ends.

## Install And Run

From a local clone:

```sh
./install.sh
```

That command:

- Builds the app.
- Installs it to `~/Applications/Don't Die On Me Now.app`.
- Registers it with Launch Services and asks Spotlight to index it.
- Launches it as a menu bar app.
- Sets it to open when you log in.

This only opens the app at login. It does not automatically start keeping the Mac awake.

Because this is an unsigned dev utility, macOS may block the first launch. If that happens, Control-click the app in Finder, choose Open, then confirm.

The app appears in the menu bar, not the Dock. After install, you should also be able to find it in Spotlight by searching for "Don't Die On Me Now".

Install without startup:

```sh
./install.sh --no-at-login
```

Install into `/Applications`:

```sh
./install.sh --system
```

Install the optional helper too:

```sh
./install.sh --helper
```

The helper is optional. It needs `sudo` once, then lets the app start and stop awake mode without asking for your password each time.

## Use It

1. Click the menu bar icon.
2. Click 30m, 2h, 6h, or ∞ to start.
3. For a custom duration, type minutes into the Custom field. A Start button appears.
4. Click Stop when you want normal sleep back.

The menu bar usually shows only an icon. During a timed session it also shows an hour-level countdown, and the menu shows the live countdown to the second.

## Run At Login

The normal installer enables this. To reinstall just the login launcher:

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

Run a lid-closed smoke test:

```sh
./script/lid_closed_smoke_test.sh --minutes 15 --expect-sleep-after-minutes 10
```

To test timer expiry, type `10` into the app's Custom field, click Start, run the smoke test, then close the lid for about 13 minutes. When you reopen the Mac, the log should show minute-by-minute `AWAKE HEARTBEAT` entries until the timer expires, then a large gap. In this mode, that gap is the pass condition because it means normal sleep came back.

Restore normal sleep from the terminal:

```sh
./script/restore_sleep_now.sh
```

Optional one-time helper install:

```sh
./script/install_privileged_helper.sh
```

This installs a small root LaunchDaemon for your user account. After that, the menu bar app can start and stop awake mode without asking for your password each time. Remove it with:

```sh
./script/uninstall_privileged_helper.sh
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
- No privileged helper installed by default. The helper is opt-in and installed only with `./install.sh --helper` or `./script/install_privileged_helper.sh`.

## License

MIT. See [LICENSE](LICENSE).
