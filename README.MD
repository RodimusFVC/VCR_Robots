<p align="center">
  <img src="Useful Information/Robots.jpg" width="800">
</p>

<h1 align="center">Isaac Asimov's Robots FPGA Core</h1>

<p align="center">
  VCR hardware implementation for MiSTer FPGA
</p>

---

## Overview

FPGA implementation of **Isaac Asimov's Robots (1988)**, originally developed and released by Kodak.

This core targets MiSTer FPGA and aims for accurate gameplay behavior, video timing, and sound reproduction.

---

## Core Information

| Field        | Value |
|--------------|--------|
| Core Name    | Robots |
| Year         | 1988 |
| Developer    | Kodak |
| Genre        | VCR |
| Players      | Everyone |

---

## Controls

Default MiSTer gamepad mapping:

| Robots |
| Input | Action |
|-------|--------|
| D-Pad / Joystick | Move Selection |
| A | Select/Activate Item |
| B | Return/Revert Selection |
| X | Not Used |
| Y | Not Used |
| Select | Restart / Reset Game |
| Start | Start / Pause Playback |
| Right Shoulder | Seek to Next Index |
| Left Shoulder | Seek to Prior Index |

---

## Features

- VCR Simulated to provided video/audio stream
- MiSTer-compatible .mra provided

---

## ROM Requirements

This title doesn't require 'ROMS' as other games do - only the Robots.dlv file

ROM files are **not included**.

To use this core, you must provide legally obtained files.  You may create your own
files using your original media and the scripts provided.

To simplify setup:

- `.mra` files are provided in the **Releases** section.
- The `.mra` specifies all required ROM files along with checksums.
- The ROM `.zip` filename corresponds to the naming convention used by the MAME project.

For setup instructions and environment configuration, refer to:

MiSTer Arcade ROM guide:  
https://github.com/MiSTer-devel/Main_MiSTer/wiki/Arcade-Roms

---

## Installation

1. Copy the core `.rbf` file to your MiSTer `/_VCR/cores` folder.
2. Copy the '.mra' file to your MiSTer '/_VCR' folder.
3. Place your `robots.dlv` in the `/games/robots` directory (no ROM `.zip` is used).
4. Launch the core from the MiSTer Arcade menu.

---

## Legal Notice

This project contains **no copyrighted game data**.

Users are responsible for obtaining and using ROM files in accordance with applicable laws.

Do not request ROM files in issues or discussions.

---

## Credits

FPGA core development: RodimusFVC 
Original game © Eastman Kodak Company

---
