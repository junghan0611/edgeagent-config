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

        # Defaults assume one ESP32-family board on /dev/ttyUSB0.
        # Verified bring-up: ESP32-WROOM (CP2102) and ESP32-CAM via MB (CH340).
        defaultTarget = "esp32";
        defaultPort = "/dev/ttyUSB0";
        defaultBaud = "460800";

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
          ESPPORT = defaultPort;
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
          ] ++ pkgs.lib.optionals pkgs.stdenv.isLinux [
            pkgs.usbutils
          ];

          shellHook = ''
            export ESPPORT="''${ESPPORT:-${defaultPort}}"
            export IDF_TARGET="''${IDF_TARGET:-${defaultTarget}}"
            export ESPBAUD="''${ESPBAUD:-${defaultBaud}}"

            alias edge-target='idf.py set-target "$IDF_TARGET"'
            alias edge-build='idf.py build'
            alias edge-flash='idf.py -p "$ESPPORT" -b "$ESPBAUD" flash'
            alias edge-monitor='idf.py -p "$ESPPORT" monitor'
            alias edge-run='idf.py -p "$ESPPORT" -b "$ESPBAUD" flash monitor'
            alias edge-chip='esptool.py --chip "$IDF_TARGET" --port "$ESPPORT" chip_id'
            alias edge-flash-id='esptool.py --chip "$IDF_TARGET" --port "$ESPPORT" flash_id'
            alias edge-mac='esptool.py --chip "$IDF_TARGET" --port "$ESPPORT" read_mac'

            echo "Edge Agent ESP32 family shell"
            echo "  target: $IDF_TARGET (Xtensa LX6)"
            echo "  port:   $ESPPORT"
            echo "  baud:   $ESPBAUD"
            echo "  boards: ESP32-WROOM (devkit) | ESP32-CAM (AI Thinker, MB)"
            echo "  quick:  edge-target && edge-build && edge-run"

            if [ -e "$ESPPORT" ] && [ ! -w "$ESPPORT" ]; then
              echo "  warn: $ESPPORT exists but is not writable by $USER."
              echo "        Add the user to the dialout group or temporarily run: sudo chmod a+rw $ESPPORT"
            fi
          '';
        };
      });
}
