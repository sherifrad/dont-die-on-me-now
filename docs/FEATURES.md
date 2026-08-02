# Features And Requirements

Don't Die On Me Now is a local macOS menu bar utility for keeping a Mac awake while developer tools continue running, and for powering the Mac off after a selected delay.

## Feature Overview

### Awake Sessions

- Presets: 30 minutes, 2 hours, and 6 hours.
- Custom duration from 1 minute through 24 hours.
- Indefinite mode that remains active until the user chooses Stop or restores normal sleep manually.
- Timed sessions restore normal sleep through a separate root-owned launchd job, so the app does not need to remain open.
- The menu bar shows a quiet coffee cup when ready, a steaming cup while awake, and a compact countdown for timed sessions.
- Selected durations and custom values are saved locally for the next launch.

### Scheduled Shutdown

- Presets and custom shutdown delays from 1 minute through 24 hours.
- Optional quiet shutdown mode to suppress the normal macOS shutdown warning.
- A live countdown is shown in the menu bar window.
- Scheduled shutdown deadlines are saved locally and restored when the app is reopened.
- A Cancel control removes the pending shutdown before it runs.
- The app uses the installed privileged helper when available and falls back to the standard macOS administrator prompt when the helper is unavailable or unhealthy.

### OpenCode Completion Trigger

The Shutdown Mac section can defer the shutdown countdown until OpenCode work finishes. The installer places a small local plugin in the user's OpenCode plugin directory.

The user can choose one of two monitoring modes:

#### First task only

The plugin watches the first session that becomes busy after monitoring is armed. The shutdown countdown starts when that session becomes idle or reports an error.

#### All active tasks

The plugin watches every session that becomes busy after monitoring is armed. The shutdown countdown starts only after all observed sessions become idle or terminal. If any observed session reports an error, the aggregate completion is reported as an error. Explicitly canceled sessions do not trigger shutdown by themselves.

OpenCode session IDs are included in the local completion callback. The app validates the one-shot marker token before accepting the callback, then disarms the marker before scheduling shutdown.

The monitoring marker is intentionally one-shot. Canceling the pending OpenCode shutdown removes it without scheduling a power-off deadline.

## Requirements

### macOS

- macOS 13 or newer.
- A Mac that supports `pmset -a disablesleep`.
- Xcode command-line tools to build from source.
- Administrator approval during helper installation, or administrator approval whenever a sleep or shutdown change is requested when the helper is skipped.

The release build attempts to produce arm64 and x86_64 binaries when the system has the required universal-build tooling. On a host without that tooling, the build script uses the host architecture instead of failing before creating the app bundle.

### OpenCode Integration

The OpenCode-dependent shutdown features additionally require:

- OpenCode with its plugin system enabled.
- The installed `dont-die-on-me-now.js` plugin.
- A restart of OpenCode after installing or updating the plugin so it reloads the plugin.
- The installed app bundle to be registered with macOS for the `dont-die-on-me-now` callback URL scheme.
- OpenCode session events including `session.status`, `session.idle`, and `session.error`.

The plugin runs inside OpenCode's plugin runtime and is not a standalone background daemon. If OpenCode integration is not wanted, install with `--no-opencode`; ordinary awake and scheduled-shutdown controls remain available.

## Installation

The default installer builds, installs, registers, and launches the app:

```sh
./install.sh
```

Useful options:

```sh
./install.sh --at-login       # Launch the menu bar utility at login
./install.sh --no-at-login   # Do not launch it at login
./install.sh --no-helper     # Use an administrator prompt for each change
./install.sh --no-opencode   # Skip the OpenCode plugin
./install.sh --system        # Install in /Applications
```

The app itself does not start an awake session during installation or login launch. The user must choose an awake duration or schedule a shutdown from the menu bar.

## Permissions And Safety

- The privileged helper accepts only fixed actions: start, stop, schedule shutdown, and cancel shutdown.
- Helper requests validate action names, identifiers, paths, and durations before execution.
- Awake sessions and shutdowns are limited to 24 hours.
- The helper does not receive or store the user's password.
- Preventing sleep can make a MacBook run hot. Use a hard, ventilated surface and do not use the feature inside a bag or sleeve.
- The timed restore job is designed to restore normal sleep after a deadline or explicit Stop request.

## Privacy

The project is local-only:

- No telemetry.
- No network access.
- No prompt, source-code, or task-output collection.
- No password storage.
- OpenCode integration reads only the local arm marker and receives session lifecycle events from OpenCode.
- Session IDs are used only to correlate local completion events and are sent through the local app callback URL.
- Preferences, deadlines, one-shot tokens, and helper request files remain on the Mac and are used to resume or validate local state.

The repository documentation uses generic `$HOME` and system paths. It does not require publishing usernames, machine names, task contents, or personal configuration values.

## Verification

From a source checkout:

```sh
swift test
./script/build_and_run.sh --build-only
./script/safety_status.sh
```

For a lid-closed timer smoke test:

```sh
./script/lid_closed_smoke_test.sh --minutes 15 --expect-sleep-after-minutes 10
```

The smoke test logs a heartbeat only. It does not keep the Mac awake by itself.

## Troubleshooting

### OpenCode options are missing

Open the coffee cup menu, then look under `Shutdown Mac`. The visible `OpenCode monitoring` control offers `First task only` and `All active tasks`. Enable `Start countdown after OpenCode finishes`, choose a delay, and click a preset or schedule the custom delay.

### OpenCode completion is not detected

Re-run the installer without `--no-opencode`, restart OpenCode, and confirm the app is running in the menu bar. The OpenCode option is a one-shot arm for the next matching session or group of sessions.

### A password prompt appears for every change

The app is operating without the privileged helper. Re-run the installer without `--no-helper` if a root-owned helper is appropriate for the Mac.

### The Mac remains awake after a timed session

Open the app and choose Stop. If the app cannot be opened, run:

```sh
./script/restore_sleep_now.sh
```
