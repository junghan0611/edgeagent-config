{
  description = "Edge Agent ESP32 family Zig/ESP-IDF development shell";

  inputs = {
    esp-idf.url = "github:mirrexagon/nixpkgs-esp-dev";
    nixpkgs.follows = "esp-idf/nixpkgs";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { nixpkgs, flake-utils, esp-idf, ... }:
    flake-utils.lib.eachSystem [ "x86_64-linux" "aarch64-linux" ] (system:
      let
        permittedInsecurePackages = [
          # ESP-IDF v5.5 toolchain still pulls python ecdsa via esptool.
          # This is a dev-shell dependency, not firmware code.
          "python3.13-ecdsa-0.19.1"
        ];

        pkgs = import nixpkgs {
          inherit system;
          overlays = [ esp-idf.overlays.default ];
          config = { inherit permittedInsecurePackages; };
        };
        basePkgs = import nixpkgs {
          inherit system;
          config = { inherit permittedInsecurePackages; };
        };

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
        formatter = pkgs.nixpkgs-fmt;

        devShells.default = pkgs.mkShell {
          # Do not pre-bind ESPPORT here — the shellHook picks it from
          # IDF_TARGET so a single shell can serve every verified board.
          IDF_TARGET = defaultTarget;
          ESPBAUD = defaultBaud;

          packages = [
            pkgs.bashInteractive
            zigXtensa
            pkgs.zls
            pkgs.esp-idf-full

            # Standalone board/serial tools.
            # ESP-IDF also exposes esptool.py; nixpkgs#esptool may expose esptool v5.
            basePkgs.esptool
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
            echo "  toggle: IDF_TARGET=esp32s3 nix develop"
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
