{
  description = "Edge Agent ESP32 family Zig/ESP-IDF development shell";

  inputs = {
    # Host side: same channel as nixos-config, locked to the same revision
    # there, so the source and the host tools come from the system store.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    # Firmware side: keeps esp-dev's own nixpkgs lock (nixos-25.11), the
    # combination upstream pins. Its overlay does not evaluate on 26.05
    # (tools.nix requires python310). Not aligned to 26.05 on purpose.
    esp-idf.url = "github:mirrexagon/nixpkgs-esp-dev";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { nixpkgs, flake-utils, esp-idf, ... }:
    flake-utils.lib.eachSystem [ "x86_64-linux" "aarch64-linux" ] (system:
      let
        permittedInsecurePackages = [
          # ESP-IDF v5.5 toolchain still pulls python ecdsa via esptool.
          # This is a dev-shell dependency, not firmware code. The
          # vulnerability (CVE-2024-23342) is not fixed; the exception is
          # scoped to the firmware package set only.
          "python3.13-ecdsa-0.19.1"
        ];

        # Firmware package set: esp-dev's own nixpkgs (25.11) + its overlay.
        # Every firmware-shell package, Python included, comes from here so
        # PYTHONPATH never mixes two nixpkgs.
        pkgs = import esp-idf.inputs.nixpkgs {
          inherit system;
          overlays = [ esp-idf.overlays.default ];
          config = { inherit permittedInsecurePackages; };
        };
        # Host package set: root nixpkgs (26.05), no overlay, no insecure
        # exception. nixpkgs#esptool 5.x does not depend on ecdsa.
        hostPkgs = import nixpkgs { inherit system; };

        # Family-aware defaults. The dev shell stays single — chip and
        # board variations are absorbed by IDF_TARGET and the host port,
        # not by per-chip shells. See NOTES-EXTERNAL.md (2026-05-06)
        # and ./run.sh for the matching host-side mapping.
        defaultTarget      = "esp32";
        defaultPortBridged = "/dev/ttyUSB0";  # external CP2102/CH340 (esp32, esp32s2)
        defaultPortNative  = "/dev/ttyACM0";  # native USB Serial/JTAG (esp32s3, c3, c6, ...)
        defaultBaud        = "460800";

        zigXtensaSrc =
          if system == "x86_64-linux" then {
            url = "https://github.com/kassane/zig-espressif-bootstrap/releases/download/0.16.0-xtensa/zig-relsafe-x86_64-linux-musl-baseline.tar.xz";
            sha256 = "sha256-QR8YWKlhCAOvKM0nGs9FSIc1RczIZvS5BgkD/w1Lbo4=";
          } else {
            url = "https://github.com/kassane/zig-espressif-bootstrap/releases/download/0.16.0-xtensa/zig-relsafe-aarch64-linux-musl-baseline.tar.xz";
            sha256 = "sha256-0+STC7rAU7QIYCkM3sKtHgUkGBcqpFLlkLJCwIGgH5Q=";
          };

        zigXtensa = pkgs.stdenv.mkDerivation {
          pname = "zig-espressif-bootstrap";
          version = "0.16.0-xtensa-dev";
          src = pkgs.fetchurl zigXtensaSrc;
          dontConfigure = true;
          dontBuild = true;
          dontFixup = true;
          installPhase = ''
            mkdir -p $out/{doc,bin,lib}
            cp -r doc/* $out/doc
            cp -r lib/* $out/lib
            cp zig $out/bin/zig
          '';
        };
      in
      {
        formatter = hostPkgs.nixpkgs-fmt;

        # Host-only shell: serial tools + the Phase 4.5 host-master toy.
        # No ESP-IDF, no Zig. `./run.sh hello-edge` uses it so the toy
        # follows this lock instead of the user's nixpkgs channel.
        devShells.host = hostPkgs.mkShell {
          packages = [
            hostPkgs.esptool
            hostPkgs.tio
            hostPkgs.picocom
            hostPkgs.python3
            hostPkgs.python3Packages.pyserial
            hostPkgs.python3Packages.cbor2
          ] ++ hostPkgs.lib.optionals hostPkgs.stdenv.isLinux [
            hostPkgs.usbutils
          ];
        };

        # Firmware shell. Ships Xtensa toolchains only (esp32, esp32s2,
        # esp32s3) — every bench board is Xtensa, and zigXtensa above is
        # Xtensa-only too. A RISC-V board needs an explicit extension here
        # (esp-idf-riscv or esp-idf-full, plus a RISC-V Zig).
        devShells.default = pkgs.mkShell {
          # Do not pre-bind ESPPORT here — the shellHook picks it from
          # IDF_TARGET so a single shell can serve every verified board.
          IDF_TARGET = defaultTarget;
          ESPBAUD = defaultBaud;

          packages = [
            pkgs.bashInteractive
            zigXtensa
            pkgs.zls
            pkgs.esp-idf-xtensa

            # Standalone board/serial tools.
            # ESP-IDF also exposes esptool.py; nixpkgs#esptool may expose esptool v5.
            pkgs.esptool
            pkgs.tio
            pkgs.picocom
            pkgs.git
            pkgs.cmake
            pkgs.ninja
            pkgs.pkg-config
            pkgs.python3
            pkgs.python3Packages.pyserial
            # Host-master toy (Phase 4.5) — see tools/host-master/.
            # CBOR is the canonical envelope encoding (spec/ENVELOPE.md §2);
            # cbor2 is host-only and never crosses into firmware code.
            pkgs.python3Packages.cbor2
          ] ++ pkgs.lib.optionals pkgs.stdenv.isLinux [
            pkgs.usbutils
          ];

          shellHook = ''
            export IDF_TARGET="''${IDF_TARGET:-${defaultTarget}}"
            export ESPBAUD="''${ESPBAUD:-${defaultBaud}}"

            # Family-aware default port. Override per-call with ESPPORT=...
            # SSOT note: this case mirrors NATIVE_USB_TARGETS in ./run.sh.
            # Keep them in sync by hand (the map is small on purpose).
            if [ -z "''${ESPPORT:-}" ]; then
              case "$IDF_TARGET" in
                esp32s3|esp32s2|esp32c3|esp32c5|esp32c6|esp32c61|esp32h2|esp32p4)
                  export ESPPORT="${defaultPortNative}"
                  ;;
                *)
                  export ESPPORT="${defaultPortBridged}"
                  ;;
              esac
            fi

            case "$IDF_TARGET" in
              esp32|esp32s2|esp32s3) ;;
              *)
                echo "  warn: IDF_TARGET=$IDF_TARGET is not Xtensa. This shell ships"
                echo "        Xtensa toolchains only; extend flake.nix for RISC-V first."
                ;;
            esac

            alias edge-target='idf.py set-target "$IDF_TARGET"'
            alias edge-build='idf.py build'
            alias edge-flash='idf.py -p "$ESPPORT" -b "$ESPBAUD" flash'
            alias edge-monitor='idf.py -p "$ESPPORT" monitor'
            alias edge-run='idf.py -p "$ESPPORT" -b "$ESPBAUD" flash monitor'
            alias edge-chip='esptool.py --chip "$IDF_TARGET" --port "$ESPPORT" chip_id'
            alias edge-flash-id='esptool.py --chip "$IDF_TARGET" --port "$ESPPORT" flash_id'
            alias edge-mac='esptool.py --chip "$IDF_TARGET" --port "$ESPPORT" read_mac'

            echo "Edge Agent — ESP-line basecamp"
            echo "  target: $IDF_TARGET"
            echo "  port:   $ESPPORT"
            echo "  baud:   $ESPBAUD   (flash; monitor uses firmware UART rate)"
            echo "  toggle: IDF_TARGET=esp32s3 nix develop   (Xtensa: esp32, esp32s2, esp32s3)"
            echo
            echo "  verified boards:"
            echo "    - ESP32-WROOM    (LX6, external CP2102 bridge,  /dev/ttyUSB0)"
            echo "    - ESP32-CAM      (LX6, external CH340 via MB,   /dev/ttyUSB0)"
            echo "    - ESP32-S3 Audio (LX7, native USB Serial/JTAG,  /dev/ttyACM0)"
            echo
            echo "  inside shell:  edge-target && edge-build && edge-run"
            echo "  outside shell: ./run.sh boards | targets | port | shell | probe"

            if [ -e "$ESPPORT" ] && [ ! -w "$ESPPORT" ]; then
              echo "  warn: $ESPPORT exists but is not writable by $USER."
              echo "        Add the user to the dialout group or temporarily run: sudo chmod a+rw $ESPPORT"
            fi
          '';
        };
      });
}
