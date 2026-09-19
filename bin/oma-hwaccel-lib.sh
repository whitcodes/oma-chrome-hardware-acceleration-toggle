# Shared helpers for detecting an installed Chrome/Chromium install and its
# profile paths. Sourced by oma-hwaccel-status and oma-hwaccel-toggle --
# not meant to be run directly.

# Populates BROWSER_BIN, BROWSER_LABEL, BROWSER_CONFIG_DIR,
# BROWSER_LOCAL_STATE, BROWSER_PROC_NAME. Returns 1 if neither is installed.
detect_browser() {
  if command -v chromium >/dev/null 2>&1; then
    BROWSER_BIN="chromium"
    BROWSER_LABEL="Chromium"
    BROWSER_CONFIG_DIR="$HOME/.config/chromium"
    BROWSER_PROC_NAME="chromium"
  elif command -v google-chrome-stable >/dev/null 2>&1; then
    BROWSER_BIN="google-chrome-stable"
    BROWSER_LABEL="Google Chrome"
    BROWSER_CONFIG_DIR="$HOME/.config/google-chrome"
    BROWSER_PROC_NAME="chrome"
  elif command -v google-chrome >/dev/null 2>&1; then
    BROWSER_BIN="google-chrome"
    BROWSER_LABEL="Google Chrome"
    BROWSER_CONFIG_DIR="$HOME/.config/google-chrome"
    BROWSER_PROC_NAME="chrome"
  else
    return 1
  fi
  BROWSER_LOCAL_STATE="$BROWSER_CONFIG_DIR/Local State"
  return 0
}

# True (exit 0) if any process of the detected browser is running.
browser_running() {
  pgrep -x "$BROWSER_PROC_NAME" >/dev/null 2>&1
}

# Prints the pid of the main browser process (the one with no --type= flag,
# i.e. not a renderer/gpu/zygote child), or nothing if none is found.
browser_main_pid() {
  local pid cmdline
  for pid in $(pgrep -x "$BROWSER_PROC_NAME" 2>/dev/null || true); do
    cmdline="$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null || true)"
    if [ -n "$cmdline" ] && ! printf '%s' "$cmdline" | grep -q -- '--type='; then
      echo "$pid"
      return 0
    fi
  done
  return 1
}

# Reads the current hardware_acceleration_mode.enabled value from Local
# State. Chromium defaults to enabled when the key is absent (e.g. a
# profile that's never had the setting touched), so mirror that default
# here rather than reporting a false "off".
#
# Deliberately NOT `.hardware_acceleration_mode.enabled // true` -- jq's
# `//` treats `false` as falsy too, so an explicit `false` (acceleration
# actually off) silently falls through to the `true` default and inverts
# the real state. Check for null explicitly instead.
hwaccel_enabled() {
  if [ ! -f "$BROWSER_LOCAL_STATE" ]; then
    echo "true"
    return
  fi
  jq -r 'if .hardware_acceleration_mode.enabled == null then true else .hardware_acceleration_mode.enabled end' "$BROWSER_LOCAL_STATE"
}
