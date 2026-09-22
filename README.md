# Chrome HW Accel

An [Omarchy](https://omarchy.org) Quattro bar plugin that toggles Chrome/Chromium
hardware acceleration from the top bar.

## Why

Chrome's GPU/hardware-accelerated compositing can freeze or jitter on some
Linux GPU/driver combinations, most visibly the moment a `<video>` element is
on screen. The workaround is the "Use hardware acceleration when available"
checkbox in `chrome://settings/system` -- but flipping it back and forth to
compare, or to turn it back on once a driver update fixes things, means
digging through Settings and manually relaunching every time. This plugin
puts that flip in the bar.

## How it actually works (and why it has to restart the browser)

Chrome/Chromium expose **no extension API** for this. `chrome.settingsPrivate`
-- the API the Settings page itself uses -- is restricted to Chrome's own
first-party WebUI and isn't available to regular extensions. There is no
`chrome.system` call, no CLI flag that live-patches a running process.

The setting itself lives outside any profile, in the browser-wide
`Local State` file (not `Preferences`):

```
~/.config/chromium/Local State        → .hardware_acceleration_mode.enabled
~/.config/google-chrome/Local State   → .hardware_acceleration_mode.enabled
```

Chromium only reads that value when its GPU process spins up at browser
start. So there's no way to flip it live -- every implementation of this
setting, including Chrome's own Settings page, works by editing that value
and then restarting the browser.

This plugin's restart is ordered deliberately:

1. **Quit first.** Chromium's pref service holds `Local State` in memory and
   flushes it to disk on shutdown using whatever value it still has in
   memory. Editing the file while Chromium is still running risks that
   shutdown flush silently reverting the edit a moment later. So the browser
   is asked to quit (`SIGTERM` to the main process, not the renderer/GPU
   children) and we wait for it to fully exit.
2. **Then edit** `Local State` with `jq`, atomically (write to a temp file,
   `mv` into place).
3. **Relaunch with `--restore-last-session`.** This forces Chromium to
   restore the tabs that were just open, regardless of the browser's normal
   "on startup" setting (which defaults to the New Tab page, not session
   restore, on most profiles).

If the browser isn't running when you toggle, the file is just edited
directly -- no restart needed, the new value takes effect next launch.

## Install

```sh
omarchy plugin add https://github.com/whitcodes/oma-chrome-hardware-acceleration-toggle --enable
```

Or locally, for development:

```sh
omarchy plugin add /path/to/oma-chrome-hardware-acceleration-toggle --enable
```

`omarchy plugin validate <folder>` checks the manifest before installing.

## Uninstall

```sh
omarchy plugin remove whitcodes.chromehwaccel
```

This only removes the plugin itself -- it never touches Chrome/Chromium's
own settings beyond whatever `hardware_acceleration_mode.enabled` value you
last toggled to, which stays exactly as Chrome's own Settings page left it.

## Using it

- Click the **GPU** bar icon to open the panel. It shows whether Chrome or
  Chromium was found, whether it's currently running, and whether hardware
  acceleration is on or off.
- Click **Turn off & restart** / **Turn on & restart** to actually flip it.
  This is a separate, explicit click from opening the panel -- restarting
  the browser is disruptive enough that it shouldn't happen from a single
  bar-icon tap.
- Middle-click the bar icon to force a status refresh.

## Requirements

- `jq` (already a hard dependency of the Omarchy shell tooling).
- Either `chromium`, `google-chrome-stable`, or `google-chrome` on `PATH`.
  Chromium is the primary target (what this was built and tested against);
  Google Chrome support follows the same Local State mechanism but is
  best-effort.

## Files

- `manifest.json` -- Omarchy plugin manifest.
- `Panel.qml` -- the bar widget and dropdown panel.
- `bin/oma-hwaccel-status` -- read-only JSON status for the widget to poll.
- `bin/oma-hwaccel-toggle` -- does the quit → edit → relaunch dance.
- `bin/oma-hwaccel-lib.sh` -- shared browser-detection helpers.
