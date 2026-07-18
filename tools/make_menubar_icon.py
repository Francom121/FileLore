#!/usr/bin/env python3
"""Regenerate the FileLore menu bar (status item) icon from logo.png.

The logo is RGB (no alpha), so the quill is segmented out of the amber badge:
  1. find the amber badge disc (largest amber connected component, bottom-right)
  2. erode the disc past its glossy rim highlight
  3. inside it, the quill is the largest whitish connected component
  4. soft alpha from pixel "whiteness" (min of RGB), boosted and slightly
     dilated so the strokes read bold at menu bar size
  5. crop to content bounds and scale so the quill fills the canvas height
     edge-to-edge (no transparent padding)

Output: FileLore/Assets.xcassets/FileLore.imageset/FileLore-{18,36}.png
(black RGB + alpha; the imageset keeps template-rendering-intent = template).
Never touches logo.png. Requires: Pillow, numpy.
"""

from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
LOGO = ROOT / "logo.png"
IMAGESET = ROOT / "FileLore" / "Assets.xcassets" / "FileLore.imageset"

# Stroke-boldening: alpha gamma (<1 lifts midtones) + max-filter dilation
# applied at native resolution before the final downscale.
ALPHA_GAMMA = 0.6
DILATE_KERNEL = 5  # MaxFilter kernel at native res (~2 px grow per side)


def largest_component(mask: np.ndarray) -> list[tuple[int, int]]:
    """4-connected components via BFS; returns the largest one's pixels."""
    seen = np.zeros(mask.shape, bool)
    best: list[tuple[int, int]] = []
    ys, xs = np.nonzero(mask)
    for sy, sx in zip(ys.tolist(), xs.tolist()):
        if seen[sy, sx]:
            continue
        comp: list[tuple[int, int]] = []
        q = deque([(sy, sx)])
        seen[sy, sx] = True
        while q:
            y, x = q.popleft()
            comp.append((y, x))
            for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                ny, nx = y + dy, x + dx
                if (
                    0 <= ny < mask.shape[0]
                    and 0 <= nx < mask.shape[1]
                    and mask[ny, nx]
                    and not seen[ny, nx]
                ):
                    seen[ny, nx] = True
                    q.append((ny, nx))
        if len(comp) > len(best):
            best = comp
    return best


def extract_quill_alpha() -> np.ndarray:
    """Segment the quill out of the logo; returns a cropped HxW float alpha."""
    a = np.asarray(Image.open(LOGO).convert("RGB")).astype(np.float32)
    r_ch, g_ch, b_ch = a[:, :, 0], a[:, :, 1], a[:, :, 2]
    height, width = r_ch.shape

    # Amber badge disc, restricted to the bottom-right quadrant so highlight
    # specks elsewhere can't pollute the measurement.
    amber = (r_ch > 170) & (g_ch > 70) & (g_ch < 210) & (b_ch < 120)
    amber[:600, :] = False
    amber[:, :600] = False
    disc_px = largest_component(amber)
    dys = np.array([p[0] for p in disc_px])
    dxs = np.array([p[1] for p in disc_px])
    cx, cy = (dxs.min() + dxs.max()) / 2, (dys.min() + dys.max()) / 2
    radius = ((dxs.max() - dxs.min()) + (dys.max() - dys.min())) / 4

    # Filled disc, eroded past the bright glossy rim (~16 px at logo scale).
    yy, xx = np.mgrid[0:height, 0:width]
    inner = ((xx - cx) ** 2 + (yy - cy) ** 2) <= (radius - 16) ** 2

    # Quill = largest whitish component inside the eroded disc. Whiteness is
    # min(R,G,B): amber reads ~15-60, the quill's warm white ~195-235.
    minc = np.minimum(np.minimum(r_ch, g_ch), b_ch)
    quill_px = largest_component((minc > 110) & inner)
    quill_mask = np.zeros_like(inner)
    for y, x in quill_px:
        quill_mask[y, x] = True

    alpha = np.clip((minc - 120) / (210 - 120), 0, 1)
    alpha[~quill_mask] = 0

    qys = np.array([p[0] for p in quill_px])
    qxs = np.array([p[1] for p in quill_px])
    return alpha[qys.min() : qys.max() + 1, qxs.min() : qxs.max() + 1]


def render(alpha: np.ndarray, canvas: int) -> Image.Image:
    """Bolden + dilate, then scale the quill to fill `canvas` height."""
    boosted = np.power(np.clip(alpha, 0, 1), ALPHA_GAMMA)
    mask = Image.fromarray((boosted * 255).astype(np.uint8), "L")
    mask = mask.filter(ImageFilter.MaxFilter(DILATE_KERNEL))

    w, h = mask.size
    new_h = canvas
    new_w = max(1, round(w * canvas / h))
    mask = mask.resize((new_w, new_h), Image.LANCZOS)

    out = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    out.paste(Image.new("RGB", (new_w, new_h), (0, 0, 0)), ((canvas - new_w) // 2, 0), mask)
    return out


def main() -> None:
    alpha = extract_quill_alpha()
    for canvas, name in ((18, "FileLore-18.png"), (36, "FileLore-36.png")):
        render(alpha, canvas).save(IMAGESET / name)
        print(f"wrote {IMAGESET / name}")

    # Verification previews (not part of the imageset).
    scratch = ROOT / ".scratch"
    scratch.mkdir(exist_ok=True)
    render(alpha, 36).save(scratch / "menubar_icon_new_36.png")
    render(alpha, 36).resize((22, 22), Image.LANCZOS).save(scratch / "menubar_icon_new_22.png")
    print("previews in .scratch/menubar_icon_new_{22,36}.png")


if __name__ == "__main__":
    main()
