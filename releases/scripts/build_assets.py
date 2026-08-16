#!/usr/bin/env python3
"""
build_assets.py -- render every non-video asset for the Robots core.

WHY THIS EXISTS
    The core has no text renderer (by design: all clue text is part of the
    printed artwork), so every screen with words on it must arrive as a bitmap.
    Those bitmaps ride in the SAME robots.dlv as extra frames past the tape, so
    the core needs exactly one file.

THE CONSTRAINT THAT SHAPES EVERYTHING
    dlv_streamer.v:102  FBUF_AW = 17  ->  128 KB per frame, and OVERFLOW IS
    SILENT (the buffer wraps, frm_size truncates, the decoder gets a corrupt
    JPEG with no error). Raising it is not possible: the 5CSEBA6 has ~707 KB of
    M10K in total. So:

      1. Assets are stored at HALF display size and blitted 2x. Integer pixel
         replication is free and the video already does it (512x480 -> 1024x960).
      2. Anything still over 128 KB is TILED across consecutive frames and
         blitted as horizontal strips. Costs no quality and almost no bytes --
         only frame count. Text takes this route, since halving then upscaling
         would soften the words.

    Measured 2026-08-15: a card at 900x1033 is 405 KB (600 dpi halftone scans
    are high-frequency noise JPEG cannot compress). At 450x516 it is 82 KB.

OUTPUT
    _VCR/assets/*.jpg          one file per tile
    _VCR/assets/manifest.json  ordered asset -> frame list, for the packer

Usage:  ./build_assets.py [--scans DIR] [--out DIR] [--quality N]
"""

import argparse, json, os, re, sys, io
from PIL import Image, ImageOps, ImageDraw, ImageFont
import numpy as np

FBUF_LIMIT = 131072                      # dlv_streamer.v FBUF_AW=17 -- HARD ceiling
# Tile against a margin, not the ceiling. Overflow is silent in fabric, and a
# re-encode (different PIL/libjpeg build, a quality tweak) can move a frame by a
# few KB -- landing at 126 K would then corrupt with no error. 8 KB of headroom.
TILE_TARGET = FBUF_LIMIT - 8192          # 120 KB
LETTERS = [chr(c) for c in range(65, 91)] + ["AA", "BB", "CC", "DD", "EE", "FF"]
PACKETS = [("Beginner", "1 - Beginner"), ("Intermediate", "2 - Intermediate"),
           ("Advanced", "3 - Advanced"), ("Expert", "4 - Expert")]
CARD_LETTERS = list("ABCDEF")
CARD_VALUES = ["01", "02", "04", "08", "16", "32"]

# Sampled from the real card artwork so composed UI matches it exactly.
NAVY, CREAM = (44, 68, 100), (248, 248, 226)
PACKET_RGB = {"Beginner": (40, 154, 56), "Intermediate": (250, 236, 78),
              "Advanced": (191, 32, 52), "Expert": (47, 47, 47)}

SUSPECTS = [
    ("Han Fastolfe", "Spacer"), ("Vasilia Fastolfe", "Spacer"),
    ("Kelden Amadiro", "Spacer"), ("Lije Baley", "Earth"),
    ("Julius Enderby", "Earth"), ("Sophia Quintana", "Earth"),
    ("R. Daneel Olivaw", "Robot"), ("R. Giskard", "Robot"),
    ("R. Borgraf", "Robot"), ("R. Sammy", "Robot"), ("R. Jane", "Robot"),
]
BUTTONS = [("SHOW MAP", "Spacertown / New York"), ("SUSPECTS", "The eleven"),
           ("FULL ANSWER", "from the case file"), ("BALEY'S NOTES", "how he solved it"),
           ("GAME ASSETS", "the original box")]

FB = "/usr/share/fonts/liberation/LiberationSerif-Bold.ttf"
FR = "/usr/share/fonts/liberation/LiberationSerif-Regular.ttf"


def font(path, size):
    try:
        return ImageFont.truetype(path, size)
    except Exception:
        return ImageFont.load_default()


def trim_shadow(im, margin=0.10, dark=215, pad=8):
    """White-paper documents: cut the curled-edge shadow line the scanner leaves.

    Only the outer `margin` of each edge is examined, and only columns/rows whose
    10th percentile is dark count as artifact -- a thin shadow line drags the low
    percentile down while leaving the mean almost untouched, which is why a
    mean-based profile misses these entirely.
    """
    g = np.array(ImageOps.grayscale(im), dtype=np.uint8)
    h, w = g.shape
    colp = np.percentile(g, 10, axis=0)
    rowp = np.percentile(g, 10, axis=1)

    def cut(prof, n):
        c = 0
        for i in range(n):
            if prof[i] < dark:
                c = i + 1
        return c

    mw, mh = int(w * margin), int(h * margin)
    L = cut(colp, mw)
    R = cut(colp[::-1], mw)
    T = cut(rowp, mh)
    B = cut(rowp[::-1], mh)
    return im.crop((min(L + pad, mw), min(T + pad, mh),
                    max(w - R - pad, w - mw), max(h - B - pad, h - mh)))


def trim_content(im, thresh=232, pad=6):
    """Artwork that runs to its own edge (box, tape): crop to the non-white bbox,
    which drops the surrounding scanner bed and the shadow along with it."""
    g = np.array(ImageOps.grayscale(im), dtype=np.uint8)
    mask = g < thresh
    ys, xs = np.where(mask)
    if len(xs) == 0:
        return im
    x0, x1 = max(0, xs.min() - pad), min(im.width, xs.max() + pad)
    y0, y1 = max(0, ys.min() - pad), min(im.height, ys.max() + pad)
    return im.crop((x0, y0, x1, y1))


def fit(im, bw, bh):
    s = min(bw / im.width, bh / im.height)
    return im.resize((max(1, int(im.width * s)), max(1, int(im.height * s))), Image.LANCZOS)


def encode(im, q):
    b = io.BytesIO()
    im.convert("RGB").save(b, "JPEG", quality=q, subsampling=2, optimize=True)
    return b.getvalue()


def tile_to_fit(im, q, limit=TILE_TARGET, max_tiles=8):
    """Split horizontally into the fewest tiles that each fit the frame buffer."""
    for n in range(1, max_tiles + 1):
        h = im.height // n
        tiles, blobs = [], []
        for i in range(n):
            y0, y1 = i * h, (im.height if i == n - 1 else (i + 1) * h)
            t = im.crop((0, y0, im.width, y1))
            tiles.append(t)
            blobs.append(encode(t, q))
        if max(len(b) for b in blobs) <= limit:
            return tiles, blobs
    return tiles, blobs      # caller checks and reports


# ---------------------------------------------------------------- composed UI
def card_button(w, h, label, sub=None, enabled=True):
    b = NAVY if enabled else (92, 92, 96)
    pan = CREAM if enabled else (188, 188, 180)
    ink = (30, 30, 30) if enabled else (120, 120, 116)
    im = Image.new("RGB", (w, h), b)
    d = ImageDraw.Draw(im)
    bw = max(4, h // 14)
    d.rectangle([bw, bw, w - bw - 1, h - bw - 1], fill=pan)
    f1 = font(FB, 40 if not sub else 36)
    f2 = font(FR, 24)
    y = h // 2 - (30 if sub else 22)
    d.text(((w - d.textlength(label, f1)) // 2, y), label, font=f1, fill=ink)
    if sub:
        d.text(((w - d.textlength(sub, f2)) // 2, y + 46), sub, font=f2, fill=(90, 90, 88))
    return im


def suspect_plate(w, h, name, faction):
    im = Image.new("RGB", (w, h), NAVY)
    d = ImageDraw.Draw(im)
    bw = max(3, h // 12)
    d.rectangle([bw, bw, w - bw - 1, h - bw - 1], fill=CREAM)
    f1, f2 = font(FB, int(h * 0.42)), font(FR, int(h * 0.26))
    d.text((bw + 18, h * 0.18), name, font=f1, fill=(30, 30, 30))
    tw = d.textlength(faction, f2)
    d.text((w - bw - 18 - tw, h * 0.30), faction, font=f2, fill=(110, 110, 105))
    return im


def banner(w, h, text, rgb):
    im = Image.new("RGB", (w, h), rgb)
    d = ImageDraw.Draw(im)
    f = font(FB, int(h * 0.46))
    d.text(((w - d.textlength(text, f)) // 2, h * 0.24), text, font=f, fill=(255, 255, 240))
    return im


# ------------------------------------------------------- notebook entry split
def notebook_entries(path):
    """Auto-isolate one entry per boxed letter. Left column top-to-bottom, then right."""
    im = Image.open(path)
    a = np.array(ImageOps.grayscale(im))
    h, w = a.shape
    ink = a < 140
    out = []
    for x0, x1 in [(int(w * .02), int(w * .44)), (int(w * .56), int(w * .99))]:
        rows = ink[:, x0:x1].sum(1)
        thr = max(3, rows.max() * 0.02)
        on = rows > thr
        runs, s = [], None
        for y in range(h):
            if on[y] and s is None:
                s = y
            elif not on[y] and s is not None:
                if y - s > 60:
                    runs.append((s, y))
                s = None
        if s is not None and h - s > 60:
            runs.append((s, h))
        merged = []
        for r in runs:
            if merged and r[0] - merged[-1][1] < 70:
                merged[-1] = (merged[-1][0], r[1])
            else:
                merged.append(r)
        for y0, y1 in [m for m in merged if m[1] - m[0] > 120]:
            pad = 40
            out.append(im.crop((max(0, x0 - pad), max(0, y0 - pad),
                                min(w, x1 + pad), min(h, y1 + pad))))
    return out


# ------------------------------------------------------------------- pipeline
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--scans", default="_VCR/scans")
    ap.add_argument("--out", default="_VCR/assets")
    ap.add_argument("--quality", type=int, default=85)
    a = ap.parse_args()
    S, OUT, Q = a.scans, a.out, a.quality
    os.makedirs(OUT, exist_ok=True)

    manifest, frame, problems = [], 0, []

    def reveal_of(name, kind):
        """When may the player SEE this? Enforced by the core, recorded here.

        NO SPOILERS. Three tiers:
          endgame  the solution itself, or anything that leads straight to it:
                   the 32 answer-book pages, the 32 notebook deduction chains,
                   and all 8 packet sleeves -- each sleeve is a complete
                   seed -> answer-page lookup table, so a browsable sleeve hands
                   over the whole game. The printed product agrees: the notebook
                   cover reads "At Game's End".
          play     revealed by the game itself as the tape reaches each clue
                   segment -- never browsable ahead of time.
          always   packaging and player reference the original expected you to
                   hold while watching: box, tape, leaflet, map, front/back
                   covers, and the core's own UI chrome.
        """
        if kind in ("answer", "notes"):
            return "endgame"
        if name.startswith("sleeve_"):
            return "endgame"
        if kind in ("card_half", "card_thumb"):
            return "play"
        return "always"

    def emit(name, kind, im, q=None):
        nonlocal frame
        tiles, blobs = tile_to_fit(im, q or Q)
        big = max(len(b) for b in blobs)
        if big > FBUF_LIMIT:
            problems.append(f"{name}: {big} B even at {len(blobs)} tiles")
        frames = []
        for i, blob in enumerate(blobs):
            fn = f"{name}.t{i}.jpg" if len(blobs) > 1 else f"{name}.jpg"
            open(os.path.join(OUT, fn), "wb").write(blob)
            frames.append({"frame": frame, "file": fn, "bytes": len(blob),
                           "size": list(tiles[i].size)})
            frame += 1
        manifest.append({"name": name, "kind": kind, "reveal": reveal_of(name, kind),
                         "tiles": len(blobs), "w": im.width, "h": im.height,
                         "frames": frames})

    # 1. clue cards: half display size (blit 2x) + panel thumbnail
    for pk, d in PACKETS:
        for L, v in zip(CARD_LETTERS, CARD_VALUES):
            for side, val in (("0", "00"), ("1", v)):
                p = f"{S}/Cropped Cards/{d}/{pk} - {L} - {val}.jpg"
                if not os.path.exists(p):
                    problems.append(f"missing {p}")
                    continue
                src = Image.open(p)
                emit(f"card_{pk[:3].lower()}_{L}_{side}", "card_half", fit(src, 450, 517))
                emit(f"thumb_{pk[:3].lower()}_{L}_{side}", "card_thumb", fit(src, 280, 321))

    # 2. answer book: each spread is two facing pages, one letter per page.
    #    scan n -> letters (2n-2) and (2n-1), 1-indexed with A=1 (scan 9 = P,Q).
    for n in range(1, 18):
        p = f"{S}/Answer Book/Answer Book - {n:02d}.jpg"
        if not os.path.exists(p):
            problems.append(f"missing {p}")
            continue
        im = Image.open(p)
        for half, idx in ((0, 2 * n - 2), (1, 2 * n - 1)):
            if not (1 <= idx <= 32):
                continue                      # front matter / trailing blank
            pg = im.crop((half * im.width // 2, 0, (half + 1) * im.width // 2, im.height))
            emit(f"answer_{LETTERS[idx-1]}", "answer", fit(pg, 1920, 1080))

    # 3. Baley's notebook: one image per lettered entry
    nb = []
    for n in range(1, 8):
        p = f"{S}/Baley's Notebook/Baley's Notebook - {n:02d}.jpg"
        if os.path.exists(p):
            nb += notebook_entries(p)
        else:
            problems.append(f"missing {p}")
    if len(nb) != 32:
        problems.append(f"notebook: detected {len(nb)} entries, expected 32")
    for i, e in enumerate(nb[:32]):
        emit(f"notes_{LETTERS[i]}", "notes", fit(e, 1024, 1080))

    # 4. leaflet + map (player reference)
    for f_ in ["Leaflet - Map", "Leaflet - Page 1", "Leaflet - Page 2", "Leaflet - Page 3"]:
        p = f"{S}/Leaflet/{f_}.jpg"
        if os.path.exists(p):
            emit(f_.lower().replace(" - ", "_").replace(" ", ""), "leaflet",
                 fit(Image.open(p), 1920, 1080))
        else:
            problems.append(f"missing {p}")

    # 5. gallery / archive: everything the boxed game came with
    gallery = [("box_front", f"{S}/Box Front.jpg"), ("box_back", f"{S}/Box Back.jpg"),
               ("box_flap", f"{S}/Box Flap.jpg"), ("tape", f"{S}/Tape.jpg")]
    for pk, d in PACKETS:
        for side in ("Front", "Back"):
            gallery.append((f"sleeve_{pk[:3].lower()}_{side.lower()}",
                            f"{S}/Cards/{d}/Sleeve - {pk} - {side}.jpg"))
    for nm, fn in [("notes_cover_front", "Baley's Notebook - Front Cover"),
                   ("notes_cover_back", "Baley's Notebook - Back Cover")]:
        gallery.append((nm, f"{S}/Baley's Notebook/{fn}.jpg"))
    for nm, fn in [("answer_cover_front", "Answer Book - Front Cover"),
                   ("answer_cover_back", "Answer Book - Back Cover")]:
        gallery.append((nm, f"{S}/Answer Book/{fn}.jpg"))
    for nm, p in gallery:
        if os.path.exists(p):
            emit(nm, "gallery", fit(Image.open(p), 1920, 1080))
        else:
            problems.append(f"missing {p}")

    # 6. composed UI: buttons, suspect plates, outcome banners
    for i, (lab, sub) in enumerate(BUTTONS):
        emit(f"btn_{i}", "ui", card_button(426, 140, lab, sub, True))
    for i, (nm, fac) in enumerate(SUSPECTS):
        emit(f"suspect_{i:02d}", "ui", suspect_plate(760, 88, nm, fac))
    emit("banner_win", "ui", banner(900, 130, "PERPETRATOR JAILED", (40, 154, 56)))
    emit("banner_lose", "ui", banner(900, 130, "AN INNOCENT CONVICTED", (191, 32, 52)))

    json.dump({"fbuf_limit": FBUF_LIMIT, "quality": Q, "total_frames": frame,
               "assets": manifest}, open(os.path.join(OUT, "manifest.json"), "w"), indent=1)

    # ---- report
    by = {}
    for m in manifest:
        k = by.setdefault(m["kind"], [0, 0, 0])
        k[0] += 1
        k[1] += m["tiles"]
        k[2] += sum(f["bytes"] for f in m["frames"])
    print(f"  {'kind':12s} {'assets':>7s} {'frames':>7s} {'MB':>8s}")
    for k in sorted(by):
        n, t, b = by[k]
        print(f"  {k:12s} {n:7d} {t:7d} {b/1e6:8.2f}")
    tb = sum(v[2] for v in by.values())
    print(f"  {'TOTAL':12s} {sum(v[0] for v in by.values()):7d} {frame:7d} {tb/1e6:8.2f}")
    worst = max((f["bytes"], m["name"]) for m in manifest for f in m["frames"])
    print(f"\n  largest frame: {worst[0]/1024:.0f} K  ({worst[1]})   ceiling {FBUF_LIMIT/1024:.0f} K")
    if problems:
        print("\n  PROBLEMS:")
        for p in problems:
            print("   -", p)
        return 1
    print("  all frames fit the 128 KB frame buffer.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
