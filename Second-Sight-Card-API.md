# Second Sight — Low-Level Card API

Copyright 1994, Sequential Systems  
Derived from `VGALOW.ASM` (host interface) and `ROM_BEEF.asm` (Z180 firmware, rev BEEF)

This document describes the byte-level protocol between the Apple IIGS host and the Second Sight VGA card. All multi-byte values are sent **least-significant byte first** unless noted otherwise.

---

## 1. I/O Register Map (IIGS Slot Space)

The host communicates with the card through four byte-wide registers in slot I/O space. In `VGALOW.ASM` these are mapped at bank `$E0`, offset `$C0`:

| Register   | Address  | Direction | Description                                      |
|------------|----------|-----------|--------------------------------------------------|
| `WR_CMD`   | `$E0C0B0` | Write     | Command opcode                                   |
| `WR_DATA`  | `$E0C0B1` | Write     | Command parameter or bulk data byte              |
| `RD_DATA`  | `$E0C0B2` | Read/Write | Data read from the card - but can also write*   |
| `HANDSHAKE`| `$E0C0B8` | Read      | Handshake / ready status                         |

On the Z180, writes to `$C0B0`–`C0B2` arrive through the `$C0Bx` soft-switch decode path and are handled by the firmware command interpreter (`check_for_api_call` in `ROM_BEEF.asm`).

To write a single byte, e.g. : STA C0B1
To write two bytes: REP #$20, STA C0B1
The first cycle will write C0B1, the second C0B2

---

## 2. Handshake Protocol

Most commands follow this pattern:

1. **Write command** — store the opcode in `WR_CMD`.
2. **Wait for ready** — poll `HANDSHAKE` until it reads `$01` (`WaitHSOn`).
3. **Write parameters** — send each parameter byte to `WR_DATA` (or, for bulk phases, stream bytes to `WR_DATA` as described below).
4. **Wait for not-ready** — poll `HANDSHAKE` until it reads `$00` (`WaitHSOff`).
5. **Wait for completion** (optional) — poll `HANDSHAKE` until it reads `$A5` or `$A6` (`WaitHSDone`). Used by `_SetMode`, `_ClearScreen`, `_RunCode`, and `_ScrollScreen`.

| `HANDSHAKE` value | Meaning                                              |
|-------------------|------------------------------------------------------|
| `$00`             | Card not ready for the next host write               |
| `$01`             | Card ready — host may write the next byte            |
| `$A5` / `$A6`     | Long-running command finished                        |

Commands with no parameters (`ScreenOn`, `ScreenOff`, `GetStatus`) omit steps 3–4.

---

## 3. Command Summary

| Code | Name               | Parameter bytes | Bulk data after parameters | Return bytes |
|------|--------------------|-----------------|----------------------------|--------------|
| `$00`| GetStatus          | 0               | —                          | 13           |
| `$01`| SetMode            | 2               | —                          | 0            |
| `$02`| UploadData         | 10              | Yes (see §4.3)             | 0            |
| `$03`| ScrollScreen       | 9               | —                          | 0            |
| `$04`| ScreenOff          | 0               | —                          | 0            |
| `$05`| ScreenOn           | 0               | —                          | 0            |
| `$06`| SetPalette         | 3               | 768 bytes                  | 0            |
| `$07`| SetPaletteEntry    | 4               | —                          | 0            |
| `$08`| SetBorder          | 1               | —                          | 0            |
| `$09`| RunCode            | 5               | —                          | 0            |
| `$0A`| ClearScreen        | 7               | —                          | 0            |
| `$0B`| SetShadow          | 1               | —                          | 0            |
| `$0C`| SetVGAReg          | 6               | —                          | 0            |
| `$0D`| GetVGAReg          | 5               | —                          | 2            |
| `$0E`| SetUserMode        | 0               | 84 bytes                   | 0            |

Parameter byte counts match the firmware dispatch table at `$1B94` in `ROM_BEEF.asm` (total bytes including the command byte, minus one).

Return byte counts are the number of `RD_DATA` reads performed by the host: **13** for GetStatus (1 dummy + 5-byte ID + 1 length byte + 6 record bytes, matching firmware DMA length `stat_size + 7`); **2** for GetVGAReg (1 dummy + 1 register value). All other commands return 0 bytes.

---

## 4. Command Parameter Block Layout

After the command byte is written, the firmware DMAs parameter bytes into a fixed buffer starting at `$1A08` on the Z180. The tables below list **host write order** (each byte goes to `WR_DATA`) and the corresponding firmware field.

### 4.1 `$00` — GetStatus

**Host writes**

| Step | Register | Value        |
|------|----------|--------------|
| 1    | `WR_CMD` | `$00`        |

**Host reads**

The firmware copies a status block from Z180 memory to the host. `VGALOW.ASM` reads from `RD_DATA` after `HANDSHAKE` becomes `$01`:

Copies are done using Z180 DMA, but this is NOT THE SAME as Apple II DMA. 

1. One dummy read.
2. Five bytes into the start of the status record (must begin with ASCII `GSVGA`).
3. One byte *N* = number of additional record bytes.
4. *N* additional bytes.

**Returned record** (from `VGA.H` / firmware `get_status`):

| Offset | Field            | Description                                              |
|--------|------------------|----------------------------------------------------------|
| `$00`–`$04` | `id_str[5]` | `"GSVGA"`                                                |
| `$05`  | `size_rec`       | Bytes following this field (firmware sends `$06`)        |
| `$06`  | `version`        | `$14` = firmware v1.4                                    |
| `$07`  | `shadow_status`  | `$00` = Apple II emulation active, `$01` = disabled      |
| `$08`  | `vga_mode`       | Current mode (see §5)                                    |
| `$09`  | `video_ram`      | `$00` = 512K, `$01` = 1MB (firmware always sends `$01`)  |
| `$0A`  | `monitor_type`   | VGA `$3C2` input status; bit 4 set = VGA monitor         |
| `$0B`+ | `expansion[]`    | Reserved / padding                                       |

---

### 4.2 `$01` — SetMode

**Host writes** (after `WaitHSOn`):

| `$00` | Video mode number (see §5)                          |
| `$01` | Emulation flag: `$00` = emulate Apple II video (`FL_EMULATE`), `$01` = native VGA only (`FL_NOEMULATE`) |

Firmware stores byte `$00` in `vga_mode` and byte `$01` in `emul_flag`, then schedules mode setup on the next vertical blank.

---

### 4.3 `$02` — UploadData

**Phase 1 — command block** (after `WaitHSOn`):

| `$00` | Destination flag: `$00` = Z180/code space (`FL_Z180`), `$01` = VGA video RAM (`FL_VGA`) |
| `$01` | Destination address byte 0 (low)                                                     |
| `$02` | Destination address byte 1                                                           |
| `$03` | Destination address byte 2 (VGA bank; `$08`+ selects high VRAM bank)                  |
| `$04` | Length byte 0 (low)                                                                  |
| `$05` | Length byte 1                                                                        |
| `$06` | Length byte 2 (64K chunk count for transfers ≥ 64K)                                  |
| `$07` | Source address byte 0 (IIGS pointer — host reads data from here)                     |
| `$08` | Source address byte 1                                                              |
| `$09` | Source address byte 2                                                              |

The host source address is sent to the card, but IS NOT USED BY THE CARD. This was based on my misunderstaing the use of DMA by SS. However, if a future card supported actual Apple II slot-bus DMA, then the source addresses here would be necessary.

After the command block, `WaitHSOff` ends phase 1. The host then sends the payload:

**Phase 2 — 64K banks** (while length byte 2 ≠ 0):

For each 64K chunk: `WaitHSOn`, send 256 pages × 256 bytes (see `WritePage` — 256 bytes per page, even-address stride through source), `WaitHSOff`, decrement bank count.

**Phase 3 — remainder**:

`WaitHSOn`, send full 256-byte pages while length byte 1 ≠ 0, then send remaining even-aligned bytes (stride 2 through source), then optionally one final odd byte. `WaitHSOff`.

Destination addresses use the same 24-bit layout as ClearScreen / ScrollScreen. VGA destinations with bank byte ≥ `$08` map to the upper 512K VRAM aperture.

---

### 4.4 `$03` — ScrollScreen

**Host writes**:

| `$00`–`$02` | Source address (24-bit)   |
| `$03`–`$05` | Destination address (24-bit)|
| `$06`–`$08` | Length (24-bit)             |

Firmware copies video memory via Oak Technology DMA mapping (`$3DE`/`$3DF`). If source bank > destination bank, the copy proceeds from high to low addresses to avoid overlap corruption.

This is really more just a "move memory" command. An improvement would be "ScrollRect" to allow much more flexible scrolling of portions of the screen.

---

### 4.5 `$04` — ScreenOff

| Step | Register | Value  |
|------|----------|--------|
| 1    | `WR_CMD` | `$04`  |

No parameters. Firmware sets VGA sequencer clocking mode register bit 5 (screen blanked).

---

### 4.6 `$05` — ScreenOn

| Step | Register | Value  |
|------|----------|--------|
| 1    | `WR_CMD` | `$05`  |

No parameters. Firmware clears sequencer clocking mode register bit 5 (screen enabled).

---

### 4.7 `$06` — SetPalette

**Phase 1 — pointer** (3 bytes after `WaitHSOn`):

| `$00`–`$02` | 24-bit address in **IIGS memory** of a 768-byte palette table |

`WaitHSOff`.

**Phase 2 — palette data**:

`WaitHSOn`, then write **768 bytes** (`256` entries × 3 RGB components) to `WR_DATA` from the IIGS palette buffer. `WaitHSOff`.

Firmware DMAs the 768 bytes into Z180 RAM at `$2000`, then writes them to the VGA DAC (`$3C8`/`$3C9`).

> **Note:** Some `VGALOW.ASM` revisions incorrectly use `WR_CMD` instead of `WR_DATA` for the 3-byte pointer. The firmware expects these bytes on the data port (`$C0B1`).

---

### 4.8 `$07` — SetPaletteEntry

**Host writes**:

| `$00` | Palette index (`0`–`255`) |
| `$01` | Red (`0`–`63`)            |
| `$02` | Green (`0`–`63`)          |
| `$03` | Blue (`0`–`63`)           |

Firmware writes the specified DAC entry via `$3C8` / `$3C9`.

---

### 4.9 `$08` — SetBorder

**Host writes**:

| `$00` | Border / overscan color (`0`–`63`) |

Firmware selects attribute controller overscan register (`$3C0`, index `$11`) and writes the color value.

---

### 4.10 `$09` — RunCode

**Host writes**:

| `$00` | CBR — Z180 common base register value   |
| `$01` | CBAR — common/bank area register value  |
| `$02` | BBR — bank base register value          |
| `$03` | Call address byte 0 (low)               |
| `$04` | Call address byte 1 (high)            |

Firmware saves its MMU state, maps the requested Z180 address space, calls the routine at the specified address, then restores MMU registers. See also `SECOND/FIRM/RC.TXT`.

Example from `RC.TXT`:

```
$00: $09       Command code
$01: $AA       CBR
$02: $BB       CBAR
$03: $CC       BBR
$04: $AABBCC   Address in Z180 memory to CALL (24-bit; only low 16 used for CALL)
```

---

### 4.11 `$0A` — ClearScreen

**Host writes**:

| `$00` | Fill color byte                                           |
| `$01`–`$03` | Start address in video memory (24-bit)               |
| `$04`–`$06` | Byte count (24-bit)                                  |

Firmware fills video memory via DMA using the Oak mapping registers. On completion, `HANDSHAKE` is set to `$A5`.

---

### 4.12 `$0B` — SetShadow

**Host writes**:

| `$00` | Shadow / emulation control bits (see §6) |

Firmware ORs `$08` into the value and writes it to Z180 I/O port `$A1`.

---

### 4.13 `$0C` — SetVGAReg

**Host writes**:

| `$00` | Index register port — low byte  |
| `$01` | Index register port — high byte |
| `$02` | Index value to write first      |
| `$03` | Data register port — low byte   |
| `$04` | Data register port — high byte  |
| `$05` | Value to write to data register |

Typical VGA index/data pairs use ports such as `$3C4`/`$3C5` (sequencer), `$3CE`/`$3CF` (graphics), or `$3D4`/`$3D5` (CRTC).

---

### 4.14 `$0D` — GetVGAReg

**Host writes** (same first five bytes as SetVGAReg):

| `$00`–`$01` | Index register port (16-bit) |
| `$02`       | Index value                  |
| `$03`–`$04` | Data register port (16-bit)  |

**Host reads** (after `WaitHSOff`, then `WaitHSOn`):

| Step | Register  | Notes                    |
|------|-----------|--------------------------|
| 1    | `RD_DATA` | Dummy read               |
| 2    | `RD_DATA` | Register value (low 8 bits) |

Then `WaitHSOff`.

---

### 4.15 `$0E` — SetUserMode

| Step | Register | Value  |
|------|----------|--------|
| 1    | `WR_CMD` | `$0E`  |

After `WaitHSOn`, write **84 bytes** directly to `WR_DATA`. These bytes are the even-indexed bytes (`0, 2, 4, … 82`) of a `vga_mode_rec` structure (`VGA.H`) — a packed VGA register set for user-defined mode `$FF`.

Firmware DMAs 84 bytes (`$54` hex) into mode storage at `$179A` and applies them through the mode-setting path.

---

## 5. Video Mode Numbers

Modes recognized by firmware (`set_mode` / `vga_modes_table`):

| Mode | Resolution / type        | VGA monitor | AppleColor RGB |
|------|--------------------------|-------------|----------------|
| `$01`| 40×25 text               | Yes         | Yes            |
| `$03`| 80×25 text               | Yes         | Yes            |
| `$13`| 320×200×256              | Yes         | —              |
| `$53`| 640×480×256              | Yes         | —              |
| `$61`| 640×400×256              | Yes         | Yes            |
| `$FA`| 560×192×16 (double hires)| Yes         | Yes            |
| `$FB`| 280×192×16 (hires)       | Yes         | Yes            |
| `$FC`| 40×24 text               | Yes         | Yes            |
| `$FD`| 80×24 text               | Yes         | Yes            |
| `$FE`| 640×200 (SHR / lo-res)   | Yes         | Yes            |
| `$FF`| User-defined (`SetUserMode`) | —       | —              |

Additional modes (`$5B`, `$5C`, `$70`, etc.) are supported by `VGALib` on the host side; see `SS.MODES`.

---

## 6. Shadow / Emulation Bits

Used with `SetShadow` (`$0B`) and the second byte of `SetMode` (`$01`):

| Bit   | Name           | Value   | Meaning                          |
|-------|----------------|---------|----------------------------------|
| 0     | `SH_SHR`       | `%00000001` | Super Hires shadowing        |
| 1     | `SH_HIRES`     | `%00000010` | Hires shadowing              |
| 2     | `SH_TEXT`      | `%00000100` | Text shadowing               |
| 3     | `SH_DBL_HIRES` | `%00001000` | Double hires shadowing       |
| 4     | `SH_TEXT_80`   | `%00010000` | 80-column text shadowing     |
| —     | `SH_NONE`      | `%00000000` | No shadowing                 |

Firmware always sets bit 3 of the port `$A1` value internally (`OR $08`).

---

## 7. Typical Host Call Sequence (Template)

```
; Example: SetMode — 640×480×256, Apple II emulation off
sei
lda #CMD_SetMode : sta WR_CMD
jsr WaitHSOn
lda #VM_640x480x256 : sta WR_DATA   ; $53
lda #FL_NOEMULATE   : sta WR_DATA   ; $01
jsr WaitHSOff
jsr WaitHSDone
cli
```

```
; Example: SetPaletteEntry — index 0 = white
sei
lda #CMD_SetPaletteEntry : sta WR_CMD
jsr WaitHSOn
lda #0    : sta WR_DATA   ; index
lda #63   : sta WR_DATA   ; red
lda #63   : sta WR_DATA   ; green
lda #63   : sta WR_DATA   ; blue
jsr WaitHSOff
cli
```

---

## 8. Implementation Notes

1. **Interrupts** — `VGALOW.ASM` wraps most calls in `SEI`/`CLI` because the handshake polling is timing-sensitive.

2. **Upload destination flag** — `FL_VGA` (`$01`) selects Oak linear video memory mapping. `FL_Z180` (`$00`) targets Z180 address space; the BEEF firmware has a known bug in the upload path for code uploads (see comment at `upload_chunk` in `ROM_BEEF.asm`).

3. **24-bit addresses** — Bytes `$00`–`$02` are stored little-endian. On the firmware side they map to `(xxxxCC : xxBBxx : 0Axxxx)` for DMA (offset, page, bank).

4. **Bulk transfer modes** — The Z180 uses three host→card data paths (from comments in `VGALOW.ASM`): INT1-driven command bytes, CTS1-polled bulk bytes, and DMA for large blocks (status, palette, upload).

5. **Reference sources** — Host entry points: `VGA.H`. Firmware dispatch table: `$1C11` (`api_table`). Command buffer: `$1A06` (opcode), `$1A08`+ (parameters).

---

*Sequential Systems / Second Sight — Low-Level Card API reference*
