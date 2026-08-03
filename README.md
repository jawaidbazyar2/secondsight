# Second Sight

Source, tools, and documentation for the **Sequential Systems Second Sight** VGA card for the Apple IIGS.

Second Sight is a Z180-based VGA/RGB video card that sits in an Apple IIGS slot and provides high-resolution VGA (and AppleColor RGB) display modes, Apple II video emulation, and a host API for uploading pixel data and running code on the card.

## Repository layout

### Host VGA library (repo root + `SECOND/LIB`)

ORCA/C / ORCA/M library used by IIGS software to talk to the card:

| File | Role |
|------|------|
| `VGALOW.ASM` / `VGALOW.MAC` | Low-level slot I/O and handshake (`_SetMode`, `_UploadData`, `_GetVGAReg`, etc.) |
| `VGALIB.C` / `VGALIB.H` / `VGA.H` | Higher-level C API (`vgaStartup`, `vgaSetMode`, `vgaCopyPixelMap`, …) |
| `MODES.H` / `SS.MODES` | Mode numbers and supported-mode notes |
| `LVGA` | Built library binary |
| `MAKEFILE` / `NOTES` | Build rules and library change log |

The same library sources also live under `SECOND/LIB` (the historical project tree). See `SECOND/INSTALL` for ORCA install paths (`2/ORCADEFS`, `2/` libraries folder).

### Firmware

| Path | Role |
|------|------|
| `ROM_BEEF.asm` | Disassembled Z180 firmware (revision **BEEF**) — command interpreter, DMA, video modes, Apple II emulation |
| `SECOND/FIRM/` | Firmware-related helpers: font tables, HIRES/DHIRES conversion notes/algorithms, `RC.TXT` (run-code / MMU call parameter layout), font tooling (`CFONT`, `MKTAB`, …) |
| `Second Sight - Firmware.pdf` | Scanned firmware notes / documentation |

### Documentation

| Path | Role |
|------|------|
| `Second-Sight-Card-API.md` | Modern reference for the byte-level host↔card protocol (registers, handshake, commands), derived from `VGALOW.ASM` and `ROM_BEEF.asm` |
| `secondsight_manual.pdf` | Scanned product manual |
| `SS.MODES` | List of video modes exposed through VGALib |

### `SECOND/SVIEW` — SecondView

IIGS image viewer for Second Sight. Loads GIF, TARGA, TIFF, PICT (limited), and 3200-color images; uses octree quantization and the VGA library. Includes `SSVIEW` binary, sample `PINCUSHION.GIF`, and release notes.

### `SECOND/MISC` — utilities and mode tables

Small ORCA tools and prebuilt mode parameter blobs:

- Register helpers: `SETREG`, `PRINTREG`, `SREG`, upload (`UP`), scroll demo (`TSCROLL`), etc.
- Mode tables under `RGB/`, `VGA/`, and `FUNKY.MODES/` for custom timings

### `SECOND/ZMAC` — Z80/Z180 toolchain

Cross-assembler and helpers used for card-side code:

- `ZMAC` — Z80 macro assembler (`.z` → `.hex`)
- `ZDIS` — disassembler
- `BIN2HEX` / `HEX2BIN` — format converters
- Sample sources (`SAMPLE1.Z`, `SERIAL.Z`) and man pages

## Historical note

Much of this tree dates from the mid-1990s Sequential Systems development era (ORCA/C on the IIGS). `ROM_BEEF.asm` and `Second-Sight-Card-API.md` are later reverse-engineering / documentation work on the shipped firmware and host interface.

Finder metadata files named `finder.data` are gitignored.
