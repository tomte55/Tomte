"""Image and font helpers shared by tools/theme_art.py and tools/themes/*.py.

Every helper was moved out of one of those scripts; where the scripts differed the difference is a parameter, so the
generated art stays byte-identical. Needs Pillow (and fontTools for the font helpers).
"""

import math
import shutil
from pathlib import Path

from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
FONTS = ROOT / "Media" / "Fonts"


def wrap_blur(img, blur):
    """Blur an L image with wrap-around (tile 3x3, blur, take the middle) so the result tiles."""
    size = img.width
    big = Image.new("L", (size * 3, size * 3))
    for x in range(3):
        for y in range(3):
            big.paste(img, (x * size, y * size))
    big = big.filter(ImageFilter.GaussianBlur(blur))
    return big.crop((size, size, size * 2, size * 2))


def seamless_noise(size, rnd, sigma, blur):
    """Gaussian noise around 128, blurred with wrap-around so it tiles."""
    base = Image.new("L", (size, size))
    base.putdata([max(0, min(255, int(rnd.gauss(128, sigma)))) for _ in range(size * size)])
    return wrap_blur(base, blur)


def signed_rgba_values(diffs, size, k):
    """RGBA image from signed differences around 128: white where positive, black where not, alpha abs(d) * k."""
    out = Image.new("RGBA", (size, size))
    px = []
    for d in diffs:
        a = max(0, min(255, int(abs(d) * k)))
        c = 255 if d > 0 else 0
        px.append((c, c, c, a))
    out.putdata(px)
    return out


def signed_rgba(grey_img, k):
    """Grey around 128 as white/black RGBA with alpha growing with the distance from 128, so it lightens and
    darkens whatever is under it."""
    return signed_rgba_values((v - 128 for v in grey_img.get_flattened_data()), grey_img.width, k)


def white(alpha):
    """White RGBA image with `alpha` (an L image) as its alpha."""
    out = Image.new("RGBA", alpha.size, (255, 255, 255, 0))
    out.putalpha(alpha)
    return out


def finish(img, w, h):
    """Downsample a supersampled L drawing to w x h and use it as the alpha of a white image."""
    return white(img.resize((w, h), Image.LANCZOS))


def glow(size=256, rgb=(255, 255, 255)):
    """Soft spot fading out from the center (WoW has no radial gradients), in the colour `rgb`."""
    img = Image.new("L", (size, size))
    pix = img.load()
    c = (size - 1) / 2
    for y in range(size):
        for x in range(size):
            d = math.hypot(x - c, y - c) / c
            pix[x, y] = int(255 * max(0.0, 1 - d) ** 2)
    out = Image.new("RGBA", (size, size), tuple(rgb) + (0,))
    out.putalpha(img)
    return out


def hairline(img, cx, cy, start, ss, power, row_shift=0.0, include_start=False):
    """Draw the flourish hairline on the supersampled L image `img`: from `start` pixels away from the center
    column it runs out to both edges, fading as (1 - distance fraction) ** power, about `ss` rows thick. Existing
    brighter pixels stay. `row_shift` and `include_start` keep the generators' differing rounding."""
    W, H = img.size
    pix = img.load()
    for x in range(W):
        ax = abs(x - cx)
        if ax < start or (ax == start and not include_start):
            continue
        v = int(255 * max(0.0, 1.0 - (ax - start) / (cx - start)) ** power)
        for y in range(H):
            if abs(y + row_shift - cy) <= 0.5 * ss:
                pix[x, y] = max(pix[x, y], v)


def tint(img, rgb, alpha=1.0):
    """The alpha channel of `img` (scaled by `alpha`) as an RGBA layer in the colour `rgb`."""
    out = Image.new("RGBA", img.size, tuple(rgb[:3]) + (0,))
    out.putalpha(img.getchannel("A").point(lambda a: int(a * alpha)))
    return out


def static_font(src_file, dst_path, wght=None, update_names=False):
    """Save `src_file` as a static font. With `wght` a variable font is pinned to that weight first (a static one
    is saved as it is); without, the file is expected to be static already."""
    from fontTools.ttLib import TTFont

    f = TTFont(src_file)
    if wght is None:
        assert "fvar" not in f, "expected the static file"
    elif "fvar" in f:
        from fontTools.varLib import instancer

        f = instancer.instantiateVariableFont(f, {"wght": wght}, updateFontNames=update_names)
    Path(dst_path).parent.mkdir(parents=True, exist_ok=True)
    f.save(dst_path)


def copy_license(src_dir, dst_name, src_name="OFL.txt"):
    """Copy a font's license text from the sources folder next to the fonts."""
    FONTS.mkdir(parents=True, exist_ok=True)
    shutil.copy(Path(src_dir) / src_name, FONTS / dst_name)
