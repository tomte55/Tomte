"""Writes BLP2 textures compressed as DXT1 with every mipmap, the format the game's own map art comes in, for
tools/mapart.py's merged zone pictures (a 256 x 256 tile is 43 KB this way, 192 KB as a 24-bit TGA).

DXT1: each 4 x 4 block keeps two 5:6:5 colours and a 2-bit index per pixel into those two and two between them. The
two colours are the block's extremes along its main colour axis (the colours' principal direction, by a few rounds of
power iteration), the usual way to pick them. No alpha: the map draws these through its zone masks.

BLP2 header (as the client and Pillow's BlpImagePlugin read it): "BLP2", type 1, encoding 2 (DXT), alpha depth 0,
alpha encoding 0 (DXT1), has mips 1, width, height, 16 mip offsets, 16 mip sizes, a 256-colour palette (unused), then
the mips, largest first.
"""
import struct

import numpy as np
from PIL import Image


def _to565(c):
    """float RGB (..., 3) in 0..255 -> 5:6:5 ints."""
    r = np.clip(np.round(c[..., 0] * 31 / 255), 0, 31).astype(np.uint16)
    g = np.clip(np.round(c[..., 1] * 63 / 255), 0, 63).astype(np.uint16)
    b = np.clip(np.round(c[..., 2] * 31 / 255), 0, 31).astype(np.uint16)
    return (r << 11) | (g << 5) | b


def _from565(v):
    r = ((v >> 11) & 31).astype(np.float32) * 255 / 31
    g = ((v >> 5) & 63).astype(np.float32) * 255 / 63
    b = (v & 31).astype(np.float32) * 255 / 31
    return np.stack([r, g, b], -1)


def dxt1(img):
    """An RGB image whose sides are multiples of 4 -> DXT1 bytes."""
    a = np.asarray(img.convert("RGB"), np.float32)
    h, w, _ = a.shape
    blocks = a.reshape(h // 4, 4, w // 4, 4, 3).transpose(0, 2, 1, 3, 4).reshape(-1, 16, 3)
    mean = blocks.mean(1, keepdims=True)
    d = blocks - mean
    cov = np.einsum("bpi,bpj->bij", d, d)
    axis = np.ones((len(blocks), 3), np.float32)
    for _ in range(8):
        axis = np.einsum("bij,bj->bi", cov, axis)
        axis /= np.maximum(np.linalg.norm(axis, axis=1, keepdims=True), 1e-6)
    t = np.einsum("bpi,bi->bp", d, axis)
    lo = mean[:, 0] + axis * t.min(1, keepdims=True)
    hi = mean[:, 0] + axis * t.max(1, keepdims=True)
    c0, c1 = _to565(hi), _to565(lo)
    # Four-colour mode needs c0 > c1; equal colours fall back to that one colour (all indices 0).
    swap = c0 < c1
    c0, c1 = np.where(swap, c1, c0), np.where(swap, c0, c1)
    p0, p1 = _from565(c0), _from565(c1)
    palette = np.stack([p0, p1, (2 * p0 + p1) / 3, (p0 + 2 * p1) / 3], 1)  # (blocks, 4, 3)
    dist = ((blocks[:, :, None, :] - palette[:, None, :, :]) ** 2).sum(-1)  # (blocks, 16, 4)
    idx = dist.argmin(-1).astype(np.uint32)
    idx = np.where((c0 == c1)[:, None], 0, idx)
    bits = (idx << (2 * np.arange(16, dtype=np.uint32))).sum(1).astype(np.uint32)
    out = np.zeros((len(blocks), 2), np.uint32)
    out[:, 0] = c0.astype(np.uint32) | (c1.astype(np.uint32) << 16)
    out[:, 1] = bits
    return out.astype("<u4").tobytes()


def write(img, path):
    """img: RGB, square power-of-two sides (256). Writes a DXT1 BLP2 with mips down to 1 x 1."""
    img = img.convert("RGB")
    w, h = img.size
    mips = []
    size = img
    while True:
        mw, mh = size.size
        padded = size
        if mw < 4 or mh < 4:  # DXT keeps whole 4 x 4 blocks; the smallest mips use one
            padded = Image.new("RGB", (max(mw, 4), max(mh, 4)))
            padded.paste(size, (0, 0))
        mips.append(dxt1(padded))
        if mw == 1 and mh == 1:
            break
        size = size.resize((max(mw // 2, 1), max(mh // 2, 1)), Image.BOX)
        if len(mips) == 16:
            break
    header = b"BLP2" + struct.pack("<I", 1) + struct.pack("<BBBB", 2, 0, 0, 1) + struct.pack("<II", w, h)
    offsets, sizes = [], []
    at = len(header) + 16 * 4 * 2 + 256 * 4
    for m in mips:
        offsets.append(at)
        sizes.append(len(m))
        at += len(m)
    offsets += [0] * (16 - len(offsets))
    sizes += [0] * (16 - len(sizes))
    with open(path, "wb") as f:
        f.write(header)
        f.write(struct.pack("<16I", *offsets))
        f.write(struct.pack("<16I", *sizes))
        f.write(b"\0" * 1024)
        for m in mips:
            f.write(m)
