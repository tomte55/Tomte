"""Textures for the Gathering module (Media/Gather/*.tga): white shapes on transparent, tinted in game by theme role.

  Ring.tga  a hollow circle for node spots on the minimap: Blizzard's own node blip shows through the middle

Run from the repo root: python tools/gather_art.py. Needs Pillow. New files need a full client restart.
"""

from pathlib import Path

from showcase_art import ring

OUT = Path(__file__).resolve().parent.parent / "Media" / "Gather"


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    # Shown at 16 to 20 pixels: a 7/64 line comes out about 2 pixels wide.
    ring(size=64, width=7).save(OUT / "Ring.tga")
    print("wrote", ", ".join(p.name for p in sorted(OUT.glob("*.tga"))))


if __name__ == "__main__":
    main()
