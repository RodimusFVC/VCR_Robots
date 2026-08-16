#!/usr/bin/env python3
"""
append_assets.py -- add the rendered assets to robots.dlv as frames past the tape.

WHY IT DOESN'T REWRITE 2.6 GB
    Layout is: header | index | video blob | audio blob.  Naively appending video
    frames would push the audio blob along and force a full rewrite.  Two facts
    avoid that:

      * The index entry is {u32 offset_from_video_off, u32 size}, and the whole
        file (2.58 GB) is inside u32 range -- so an asset can live AFTER the
        audio blob and still be addressed normally.
      * index_off is a header field (dlv_streamer.v reads it at [48] and does
        idx_byte = index_off + frame*8), so the index is freely relocatable.

    So we append assets + a fresh full index at EOF and patch only the header.
    ~18 MB written instead of 2.6 GB, and the existing bytes are never touched.
    (The index cannot grow in place: it ends at 649,032 with video starting at
    649,216 -- only 184 bytes of slack.)

SAFETY
    The original 512-byte header is saved beside the .dlv before anything is
    patched, and the header is written LAST.  --undo restores the header and
    truncates back, so this is fully reversible.

Header fields touched:
    [16] u32 frame_count   += number of asset frames
    [24] u64 RESERVED      -> tape_frames (where tape ends / assets begin)
    [48] u64 index_off     -> relocated index

Usage:
    ./append_assets.py robots.dlv assets/ [--dry-run] [--undo]
"""

import argparse, json, os, struct, sys

HDR = 512
OFF_FRAME_COUNT, OFF_RESERVED, OFF_INDEX, OFF_VIDEO = 16, 24, 48, 64


def read_header(f):
    f.seek(0)
    h = f.read(HDR)
    return {
        "frame_count": struct.unpack_from("<I", h, OFF_FRAME_COUNT)[0],
        "reserved":    struct.unpack_from("<Q", h, OFF_RESERVED)[0],
        "index_off":   struct.unpack_from("<Q", h, OFF_INDEX)[0],
        "video_off":   struct.unpack_from("<Q", h, OFF_VIDEO)[0],
        "raw": h,
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dlv")
    ap.add_argument("assets", nargs="?", default=None)
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--undo", action="store_true")
    a = ap.parse_args()

    bak = a.dlv + ".header.bak"

    if a.undo:
        if not os.path.exists(bak):
            print(f"  no backup at {bak}"); return 1
        raw = open(bak, "rb").read()
        size = struct.unpack_from("<Q", raw, 504)[0]      # original size stashed at [504]
        with open(a.dlv, "r+b") as f:
            f.seek(0); f.write(raw[:504] + b"\0" * 8)
            f.truncate(size)
        os.remove(bak)
        print(f"  restored header, truncated to {size} bytes")
        return 0

    man = json.load(open(os.path.join(a.assets, "manifest.json")))
    frames = [fr for asset in man["assets"] for fr in asset["frames"]]
    frames.sort(key=lambda x: x["frame"])
    for i, fr in enumerate(frames):
        if fr["frame"] != i:
            print(f"  manifest frame numbering is not contiguous at {i}"); return 1

    with open(a.dlv, "r+b") as f:
        h = read_header(f)
        f.seek(0, 2)
        eof = f.tell()
        tape = h["frame_count"]
        print(f"  tape frames      {tape}")
        print(f"  index_off        {h['index_off']}  video_off {h['video_off']}")
        print(f"  file size        {eof/1e9:.3f} GB")
        print(f"  assets to append {len(frames)} frames, "
              f"{sum(fr['bytes'] for fr in frames)/1e6:.2f} MB")

        if h["reserved"] != 0:
            print(f"  reserved@24 is {h['reserved']}, not 0 -- assets already appended?")
            return 1

        # read the existing index verbatim so the tape entries are preserved exactly
        f.seek(h["index_off"])
        old_index = f.read(tape * 8)
        if len(old_index) != tape * 8:
            print("  short read on the existing index"); return 1

        # ---- plan the layout ------------------------------------------------
        asset_base = eof                     # assets start at current EOF
        entries, cur = [], asset_base
        for fr in frames:
            off = cur - h["video_off"]       # index offsets are relative to video_off
            if off > 0xFFFFFFFF or fr["bytes"] > 0xFFFFFFFF:
                print(f"  offset {off} exceeds u32 -- cannot address {fr['file']}")
                return 1
            entries.append(struct.pack("<II", off, fr["bytes"]))
            cur += fr["bytes"]
        new_index_off = cur
        total_frames = tape + len(frames)
        print(f"  asset bytes      {asset_base} .. {cur}")
        print(f"  new index_off    {new_index_off}  ({total_frames} entries, "
              f"{total_frames*8/1e6:.2f} MB)")
        print(f"  frame_count      {tape} -> {total_frames}")
        print(f"  reserved@24      0 -> {tape}   (tape_frames)")
        print(f"  bytes written    {(cur-asset_base + total_frames*8 + HDR)/1e6:.2f} MB "
              f"(vs {eof/1e9:.2f} GB for a full repack)")

        if a.dry_run:
            print("\n  dry run -- nothing written")
            return 0

        # ---- stash the original header + size, so --undo works --------------
        with open(bak, "wb") as b:
            b.write(h["raw"][:504] + struct.pack("<Q", eof))

        # ---- append assets --------------------------------------------------
        f.seek(asset_base)
        for fr in frames:
            f.write(open(os.path.join(a.assets, fr["file"]), "rb").read())
        # ---- append the relocated full index --------------------------------
        f.write(old_index)
        f.write(b"".join(entries))
        f.flush(); os.fsync(f.fileno())

        # ---- patch the header LAST, so an interrupted run leaves a valid file
        f.seek(OFF_FRAME_COUNT); f.write(struct.pack("<I", total_frames))
        f.seek(OFF_RESERVED);    f.write(struct.pack("<Q", tape))
        f.seek(OFF_INDEX);       f.write(struct.pack("<Q", new_index_off))
        f.flush(); os.fsync(f.fileno())

    print(f"\n  done. header backup at {bak} (--undo to revert)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
