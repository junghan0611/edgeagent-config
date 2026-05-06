#!/usr/bin/env bash
# Edge Agent — ESP-line basecamp interface
#
# Single host-side entry point. No nix shell required for any of the
# commands here. Once inside `nix develop`, prefer the `edge-*` aliases
# defined by flake.nix for build / flash / monitor.
#
# SSOT note: target → port mapping below (NATIVE_USB_TARGETS) is mirrored
# in flake.nix shellHook. The map is small enough that one-file SSOT is
# heavier than the duplication; keep the two in sync by hand.

set -euo pipefail

# ---------------------------------------------------------------------------
# Family knowledge — one axis, kept in sync with NOTES-EXTERNAL.md
# ---------------------------------------------------------------------------

XTENSA_TARGETS="esp32 esp32s2 esp32s3"
RISCV_TARGETS="esp32c2 esp32c3 esp32c5 esp32c6 esp32c61 esp32h2 esp32h21 esp32h4 esp32p4"

# Targets whose default host path is native USB Serial/JTAG (/dev/ttyACM0).
# Targets not listed default to /dev/ttyUSB0 (external CP210x/CH340 bridge).
# Override per-call with `ESPPORT=/dev/...`.
NATIVE_USB_TARGETS="esp32s3 esp32s2 esp32c3 esp32c5 esp32c6 esp32c61 esp32h2 esp32p4"

PORT_NATIVE="/dev/ttyACM0"
PORT_BRIDGED="/dev/ttyUSB0"

# Verified boards — extend only after a board has actually been on a desk.
verified_boards() {
  cat <<'EOF'
  ESP32-WROOM     LX6   external CP2102 bridge   /dev/ttyUSB0
  ESP32-CAM       LX6   external CH340 via MB    /dev/ttyUSB0
  ESP32-S3 Audio  LX7   native USB Serial/JTAG   /dev/ttyACM0
EOF
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

contains() {
  # contains <needle> <space-separated-list>
  local n="$1"; shift
  local list="$*"
  case " $list " in *" $n "*) return 0 ;; *) return 1 ;; esac
}

resolve_target() {
  # arg > env > "esp32"
  echo "${1:-${IDF_TARGET:-esp32}}"
}

resolve_port() {
  local t; t="$(resolve_target "${1:-}")"
  if contains "$t" $NATIVE_USB_TARGETS; then
    echo "$PORT_NATIVE"
  else
    echo "$PORT_BRIDGED"
  fi
}

esptool_bin() {
  if command -v esptool.py >/dev/null 2>&1; then
    echo "esptool.py"
  elif command -v esptool >/dev/null 2>&1; then
    echo "esptool"
  else
    return 1
  fi
}

# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

cmd_boards() {
  echo "Verified boards (all share the same single-shell entry point):"
  verified_boards
  echo
  echo "Add a board only after a hands-on bring-up cycle has passed."
}

cmd_targets() {
  echo "Supported chip families (one toggle, no per-chip branches):"
  echo "  Xtensa (LX6/LX7):  $XTENSA_TARGETS"
  echo "  RISC-V:            $RISCV_TARGETS"
  echo
  echo "Switch with: ./run.sh shell <target>   (or  IDF_TARGET=<target> nix develop)"
}

cmd_port() {
  local t; t="$(resolve_target "${1:-}")"
  resolve_port "$t"
}

cmd_shell() {
  local t; t="$(resolve_target "${1:-}")"
  echo "Entering nix dev shell with IDF_TARGET=$t (clearing stale ESPPORT)" >&2
  # Drop ESPPORT so flake.nix shellHook re-derives it from IDF_TARGET.
  exec env -u ESPPORT IDF_TARGET="$t" nix develop
}

cmd_probe() {
  local t p
  if [ $# -gt 0 ] && [ -n "$1" ]; then
    # Explicit target argument: trust the family map, ignore stale ESPPORT.
    t="$1"
    p="$(resolve_port "$t")"
  else
    t="$(resolve_target "")"
    p="${ESPPORT:-$(resolve_port "$t")}"
  fi
  local et
  if ! et="$(esptool_bin)"; then
    echo "esptool not on PATH. Either:" >&2
    echo "  1) ./run.sh shell $t        # then: edge-chip / edge-flash-id / edge-mac" >&2
    echo "  2) nix shell nixpkgs#esptool -c esptool --port $p --chip $t chip_id" >&2
    return 1
  fi
  echo "# target: $t   port: $p   tool: $et"
  echo
  echo "--- chip_id ---"
  "$et" --port "$p" --chip "$t" chip_id 2>&1 | tail -15
  echo
  echo "--- flash_id (selected lines) ---"
  "$et" --port "$p" --chip "$t" flash_id 2>&1 \
    | grep -E 'Manufacturer|Device|Detected flash|Flash type|voltage' || true
  echo
  echo "--- read_mac ---"
  "$et" --port "$p" --chip "$t" read_mac 2>&1 | grep -E '^MAC:' | tail -1
}

cmd_inspect() {
  # Deeper read of a connected board: probe + USB descriptor + eFuse +
  # short serial capture of any existing firmware boot log. Each step is
  # best-effort; missing tools or permissions degrade gracefully.
  local t p
  if [ $# -gt 0 ] && [ -n "$1" ]; then
    t="$1"
    p="$(resolve_port "$t")"
  else
    t="$(resolve_target "")"
    p="${ESPPORT:-$(resolve_port "$t")}"
  fi

  echo "# inspect: target=$t  port=$p"
  echo
  echo "============================================================"
  echo "  1. probe (chip / flash / MAC)"
  echo "============================================================"
  cmd_probe "$@" || true
  echo

  echo "============================================================"
  echo "  2. host-side USB descriptor (sysfs)"
  echo "============================================================"
  local found=0
  for d in /sys/bus/usb/devices/*/; do
    [ -f "$d/idVendor" ] || continue
    local v; v="$(cat "$d/idVendor" 2>/dev/null)"
    # Espressif: 303a. CP210x: 10c4. CH34x: 1a86. FTDI: 0403.
    case "$v" in 303a|10c4|1a86|0403) ;; *) continue ;; esac
    found=1
    echo "  ${d}"
    printf "    %-12s %s  %s\n" "vendor:"  "$v"             "$(cat "$d/manufacturer" 2>/dev/null || echo -)"
    printf "    %-12s %s  %s\n" "product:" "$(cat "$d/idProduct" 2>/dev/null)" "$(cat "$d/product"      2>/dev/null || echo -)"
    printf "    %-12s %s\n"     "serial:"  "$(cat "$d/serial"   2>/dev/null || echo -)"
    printf "    %-12s %s\n"     "bcdDev:"  "$(cat "$d/bcdDevice" 2>/dev/null || echo -)"
  done
  [ "$found" = 0 ] && echo "  (no Espressif/CP210x/CH34x/FTDI USB device on this host)"
  echo

  echo "============================================================"
  echo "  3. eFuse summary (selected lines — board id may live here)"
  echo "============================================================"
  if command -v espefuse.py >/dev/null 2>&1; then
    espefuse.py --port "$p" summary 2>&1 \
      | grep -E 'CUSTOM_MAC|USER_DATA|BLOCK_USR|BLOCK3|MAC_VER|WAFER_VERSION|PKG_VERSION|FLASH_TYPE|PSRAM|VENDOR' \
      | head -40 \
      || echo "  (no matching eFuse fields)"
  else
    echo "  espefuse.py not on PATH."
    echo "  Run from inside the dev shell:  ./run.sh shell $t  → espefuse.py --port $p summary"
  fi
  echo

  echo "============================================================"
  echo "  4. existing firmware boot log (5s capture after reset)"
  echo "============================================================"
  local et
  if et="$(esptool_bin)"; then
    # Hard-reset the chip via RTS, then read the serial port for ~5s.
    "$et" --port "$p" --chip "$t" --after hard_reset run 2>/dev/null >/dev/null \
      || "$et" --port "$p" --chip "$t" --no-stub flash_id 2>/dev/null >/dev/null \
      || true
    if [ -r "$p" ]; then
      timeout 5 cat "$p" 2>/dev/null \
        | tr -d '\r' \
        | grep -aE '.' \
        | head -40 \
        || echo "  (no readable serial output within 5s — port may be held, or no firmware running)"
    else
      echo "  (cannot read $p — permission or device missing)"
    fi
  else
    echo "  (esptool not available — skipped)"
  fi
  echo

  echo "============================================================"
  echo "  identifiability note"
  echo "============================================================"
  echo "  Chip-level facts (chip family, revision, flash size, PSRAM,"
  echo "  USB mode, MAC) come from esptool and are authoritative."
  echo "  PCB-level model name is NOT carried in the chip itself; it can"
  echo "  only be inferred from eFuse user data (if the board vendor"
  echo "  burned one) or from any existing firmware boot log. If neither"
  echo "  reveals it, record the board as identified by its measured"
  echo "  capability profile, not by an asserted model name."
}

cmd_help() {
  cat <<'EOF'
Edge Agent — ESP-line basecamp

Usage: ./run.sh <command> [target]

Commands (host-side, no nix shell required):
  boards          List verified boards on this basecamp.
  targets         List supported chip families (single-axis toggle).
  port [target]   Print the default serial port for a target.
  shell [target]  Enter nix dev shell with IDF_TARGET=<target>.
  probe [target]  Read chip_id + flash_id + MAC from the connected board.
  inspect [target] Probe + USB descriptor + eFuse + 5s serial capture.
                   Use this to identify a board, not just its chip.
  help            This message.

Inside `nix develop`, prefer the `edge-*` aliases:
  edge-target  edge-build  edge-flash  edge-monitor  edge-run
  edge-chip    edge-flash-id  edge-mac

target defaults to $IDF_TARGET (env), then 'esp32'.
EOF
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------

case "${1:-help}" in
  boards)         shift; cmd_boards   "$@" ;;
  targets)        shift; cmd_targets  "$@" ;;
  port)           shift; cmd_port     "$@" ;;
  shell)          shift; cmd_shell    "$@" ;;
  probe)          shift; cmd_probe    "$@" ;;
  inspect)        shift; cmd_inspect  "$@" ;;
  help|-h|--help) cmd_help ;;
  *) echo "unknown command: $1" >&2; cmd_help; exit 64 ;;
esac
