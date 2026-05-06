# Boards — Verified Inventory

## What this file is

This file is the per-board card. It records what each verified board on
this basecamp **actually is**, measured rather than asserted.

- **Schema lives in [PROFILE.md](PROFILE.md)** (`StaticProfile`,
  `RuntimeCapability`) and [ENVELOPE.md](ENVELOPE.md). This file is the
  instance side: it fills that schema for boards that have been on a desk.
- **All loops collapse to one state machine.** Boards do not branch the
  state machine; chip and PCB differences enter the system only through
  `StaticProfile` (boot-stable) and `RuntimeCapability` (post-init). See
  [INVARIANTS.md §3](INVARIANTS.md) and [AGENTS.md §3](AGENTS.md).
- **Capabilities are an axis, not a board enumeration.** "Microphone" or
  "speaker" is not an ESP32-S3 trait — it is a capability that a board
  may wire on any chip with the necessary peripherals. Two boards on
  different chips can advertise the same capability under the same
  contract.
- **A board enters this file only after a hands-on bring-up cycle has
  passed.** Until then the board is a plan, not a verified inventory item.
- **Identify by measurement, not by assertion.** Chip-side facts come
  from `./run.sh inspect`. PCB model names go in only when an external
  source (eFuse user data, firmware banner, vendor sticker) confirms
  them. When the chip side cannot identify the PCB, that fact is
  recorded as the answer.

## Capability axes

Every board card uses these names. New axes are added only when a
verified board genuinely needs one.

| axis          | meaning                                                       |
|---------------|---------------------------------------------------------------|
| wifi          | 2.4 GHz WiFi radio                                            |
| ble           | Bluetooth LE radio                                            |
| psram         | external or chip-integrated PSRAM accessible to firmware       |
| audio_in      | microphone input path (PDM, I2S codec, analog ADC, ...)        |
| audio_out     | speaker / DAC output path (I2S codec, internal DAC, ...)       |
| camera        | parallel/serial camera interface (DVP, MIPI-CSI)              |
| sd_card       | SD/MMC card slot wired to the chip                            |
| button_user   | a user-pressable button wired to a GPIO                       |
| button_boot   | the BOOT/IO0 button used to enter download mode               |
| led_status    | a status LED wired to a GPIO                                  |
| deep_sleep    | deep sleep + at least one wake source available               |
| touch         | capacitive touch sensor pads exposed                          |
| usb_device    | native USB Serial/JTAG (chip-side USB)                        |

A capability listed on a board means the **board has wired it**, not
just that the chip could in principle do it. Wiring details (codec
chip, GPIO numbers, amplifier model, …) belong to firmware-side
`StaticProfile` once the board is brought up; until then they are
recorded as `unknown`.

## Boards

### ESP32-WROOM (devkit)

- **chip:** ESP32 (Xtensa LX6 dual), D0WDQ6-V3
- **memory:** 4 MB flash · no PSRAM · 520 KB on-chip SRAM
- **host path:** external CP2102 USB-UART → `/dev/ttyUSB0`
- **MAC (this unit):** `78:21:84:9d:d1:28`
- **capabilities (wired on this board):**
  `wifi`, `ble`, `button_boot`, `button_user`, `led_status`,
  `deep_sleep`, `touch`
- **capabilities the chip can do but this board does not wire:**
  `audio_in`, `audio_out`, `camera`, `sd_card` — chip native, board
  needs external circuitry
- **bring-up notes:** download mode is automatic via RTS/DTR.
- **verified:** chip_id, flash_id, MAC, hello_world (Phase 0, 2026-04-30)

### ESP32-CAM (AI Thinker)

- **chip:** ESP32 (Xtensa LX6 dual), D0WDQ6 v1.0
- **memory:** 4 MB flash · 4 MB external PSRAM · 520 KB on-chip SRAM
- **host path:** external CH340 (ESP32-CAM-MB baseboard) → `/dev/ttyUSB0`
- **MAC (this unit):** `08:3a:f2:6d:5f:90`
- **capabilities (wired on this board):**
  `wifi`, `ble`, `psram`, `camera` (OV2640), `sd_card`, `led_status`,
  `button_boot`, `deep_sleep`
- **capabilities the chip can do but this board does not wire:**
  `audio_in`, `audio_out` — pins are not broken out on the module
- **not present:** `button_user`
- **bring-up notes:** the camera module itself has no BOOT button; the
  ESP32-CAM-MB baseboard provides reset and a usable IO0 path. Without
  the MB, jumper IO0 to GND, press reset, then run `esptool`.
- **verified:** chip_id, flash_id, MAC, hello_world (Phase 0, 2026-04-30)

### ESP32-S3 audio board  (PCB model: not identified from chip-side measurement)

- **chip:** ESP32-S3 (Xtensa LX7 dual), QFN56, revision v0.2
- **memory:** 16 MB quad-SPI flash (XMC, mfr 0x20 / dev 0x4018, 3.3 V)
  · 8 MB chip-integrated PSRAM (AP_3v3, 85 °C grade) · 512 KB SRAM
- **host path:** native USB Serial/JTAG (chip-side USB CDC) → `/dev/ttyACM0`
- **MAC (this unit):** `44:1b:f6:84:c5:48`
- **capabilities the chip can do (always available on ESP32-S3):**
  `wifi`, `ble`, `psram`, `usb_device`, `deep_sleep`, `touch`
- **capabilities the board declares (per user; wiring not yet
  introspected from firmware):** `audio_in`, `audio_out`,
  `button_user`, `button_boot`, `led_status`
- **identification status:** the PCB model is **not identified from
  chip-side measurement.** All available host-side identification
  surfaces were tried via `./run.sh inspect esp32s3`:
  - eFuse `BLOCK_USR_DATA` (BLOCK3): empty — vendor did not burn user data.
  - eFuse `CUSTOM_MAC` (BLOCK3): empty — factory MAC only.
  - USB descriptor (`303a:1001`): generic Espressif "USB JTAG/serial
    debug unit"; vendor/product strings carry no PCB model.
  - Preloaded firmware boot log: only one identifiable line
    (`App version: 1.8.9` on ESP-IDF v5.4.1) emerged within a 20 s
    capture; no vendor banner appeared. Native USB CDC re-enumerates
    on reset, so longer interactive capture via `idf.py monitor`
    inside the dev shell is the next surface to try.

  Until a vendor source confirms the PCB model, this board is
  identified by its measured capability profile and MAC. This is the
  honest record per "Identify by measurement, not by assertion" above.
- **bring-up notes:** native USB-JTAG handles reset automatically; no
  external BOOT button manipulation required for download mode. Note
  that native USB CDC will disconnect on reset — host tools must
  reconnect.
- **verified (2026-05-06):** chip_id, flash_id, MAC, eFuse summary,
  USB descriptor. Firmware bring-up: not yet performed.

## Adding a new board

1. Connect the board.
2. `./run.sh inspect <target>` and capture the output.
3. Decide the chip-side facts from `inspect`'s probe and eFuse blocks
   only. Do not assert what the chip cannot confirm.
4. Decide capabilities from what is **wired** on the PCB, not from
   what the chip could in principle do.
5. Bring up `hello_world` (or equivalent) at least once. Until then,
   record `verified: chip_id only`.
6. Add the board card to this file. Update [README.md](README.md)'s
   board count if needed.
