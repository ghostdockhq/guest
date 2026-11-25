"""Draws the Ghostdock wallpapers: a quiet harbor, a long pier, and at its
end, small, the ghost from the mark (docs/brand.md, "Ghost on the Pier").

  python3 wallpaper.py OUT     writes OUT/ghostdock-light.jpg (dawn) and
                               OUT/ghostdock-dark.jpg (night), 3840x2160

The ghost is a detail to find, not a logo to look at: about 2% of the
width, flat, no glow or shadow (the brand's rule for the mark). Large soft
shapes and few edges, so the picture stays cheap for the stream. The
xfdesktop style is "zoom", which crops the sides on narrow screens: the
ghost stands right of centre, inside a 4:3 crop.
"""
import random
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter

W, H = 3840, 2160
HORIZON = 1180          # where the sea meets the sky
WATERLINE = 1420        # the pier's posts stand in the water here
SS = 4                  # supersampling for the pier and the ghost

DAWN = {
    "sky": [(0.00, (206, 222, 240)), (0.55, (226, 232, 243)), (1.00, (246, 236, 232))],
    "sea": [(0.00, (214, 226, 236)), (0.35, (188, 207, 222)), (1.00, (160, 184, 204))],
    "sun": ((255, 226, 200), 0.55),
    "shore": (196, 210, 226),
    "pier": (32, 188, 140),        # phosphor 550, the deck as in the mark
    "ghost": (13, 27, 42),         # night: the mark on light
    "eyes": (232, 238, 243),       # fog
    "glint": (255, 255, 255),
    "reflection": 0.22,
    "stars": 0,
}
NIGHT = {
    "sky": [(0.00, (9, 19, 31)), (0.60, (13, 27, 42)), (1.00, (26, 44, 64))],
    "sea": [(0.00, (22, 38, 58)), (0.40, (14, 28, 44)), (1.00, (8, 18, 30))],
    "sun": ((232, 238, 243), 0.30),  # the moon
    "shore": (20, 36, 54),
    "pier": (32, 188, 140),
    "ghost": (232, 238, 243),      # fog: the mark on dark
    "eyes": (13, 27, 42),
    "glint": (232, 238, 243),
    "reflection": 0.28,
    "stars": 90,
}


def gradient(w, h, stops):
    """A vertical gradient through (position, colour) stops."""
    col = Image.new("RGB", (1, h))
    px = col.load()
    for y in range(h):
        t = y / max(1, h - 1)
        for (t0, c0), (t1, c1) in zip(stops, stops[1:]):
            if t0 <= t <= t1:
                k = (t - t0) / (t1 - t0) if t1 > t0 else 0
                k = k * k * (3 - 2 * k)            # smoothstep: no visible seams
                px[0, y] = tuple(round(a + (b - a) * k) for a, b in zip(c0, c1))
                break
    return col.resize((w, h))


def glow(size, center, radius, color, alpha, blur):
    """A soft disc: the low sun at dawn, the moon at night."""
    layer = Image.new("RGBA", size, color + (0,))
    mask = Image.new("L", size, 0)
    x, y = center
    ImageDraw.Draw(mask).ellipse([x - radius, y - radius, x + radius, y + radius], fill=round(255 * alpha))
    layer.putalpha(mask.filter(ImageFilter.GaussianBlur(blur)))
    return layer


def pier_and_ghost(p, scale):
    """The pier (deck on posts, from the right edge) and the ghost at its end,
    in the mark's geometry: 160 units per mark, deck 18 high, posts 18 wide.
    Drawn SS times larger; returns the layer and its top-left on the canvas."""
    u = scale * SS                      # pixels per mark unit, supersampled
    end_x = 2560                        # where the deck ends (canvas px)
    deck_top = WATERLINE - 58 * scale   # deck height above the water
    left = end_x - 40 * scale
    top = deck_top - 120 * scale
    w, h = W - left + 20, WATERLINE - top + 40 * scale
    im = Image.new("RGBA", (int(w * SS), int(h * SS)), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)

    def X(x):
        return (x - left) * SS

    def Y(y):
        return (y - top) * SS

    # ghost: body (a dome over a straight side), drawn before the deck so
    # the deck covers its bottom, as in the mark
    gx = end_x + 8 * scale              # the body's left edge (mark x=34)
    gy = deck_top - 48 * scale          # the dome's centre (mark y=60)
    r = 46 * u
    cx, cy = X(gx) + r, Y(gy)
    d.pieslice([cx - r, cy - r, cx + r, cy + r], 180, 360, fill=p["ghost"])
    d.rectangle([cx - r, cy, cx + r, Y(deck_top) + 4 * u], fill=p["ghost"])
    for ex in (62.52 - 34, 97.48 - 34):
        ecx, ecy, er = X(gx) + ex * u, cy + 2 * u, 11 * u
        d.ellipse([ecx - er, ecy - er, ecx + er, ecy + er], fill=p["eyes"])

    # deck: one long rounded bar from past the right edge to end_x
    dh = 18 * u
    d.rounded_rectangle([X(end_x), Y(deck_top), X(W + 40), Y(deck_top) + dh], radius=dh / 2, fill=p["pier"])
    # posts: from under the deck into the water, evenly spaced
    pw = 18 * u
    x = end_x + 19 * scale
    while x < W + 40:
        d.rounded_rectangle([X(x), Y(deck_top) + dh - pw / 2, X(x) + pw, Y(WATERLINE) + 6 * u], radius=pw / 2,
                            fill=p["pier"])
        x += 470 * scale
    im = im.resize((int(w), int(h)), Image.LANCZOS)
    return im, (int(left), int(top))


def draw(p, out, seed):
    random.seed(seed)
    sky = gradient(W, HORIZON, p["sky"])
    sea = gradient(W, H - HORIZON, p["sea"])
    img = Image.new("RGB", (W, H))
    img.paste(sky, (0, 0))
    img.paste(sea, (0, HORIZON))
    img = img.convert("RGBA")

    # stars at night: sparse, small, faint
    if p["stars"]:
        stars = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        sd = ImageDraw.Draw(stars)
        for _ in range(p["stars"]):
            x, y = random.uniform(0, W), random.uniform(0, HORIZON * 0.8)
            rr = random.choice((1.4, 1.8, 2.2))
            a = random.randint(60, 150)
            sd.ellipse([x - rr, y - rr, x + rr, y + rr], fill=(232, 238, 243, a))
        img = Image.alpha_composite(img, stars)

    # the low sun (or moon), left of centre, and its path on the water
    sun_c, sun_a = p["sun"]
    sx, sy = 1180, HORIZON - 150
    img = Image.alpha_composite(img, glow((W, H), (sx, sy), 520, sun_c, sun_a * 0.55, 220))
    img = Image.alpha_composite(img, glow((W, H), (sx, sy), 92, sun_c, min(1, sun_a * 1.6), 6))
    # glints on the water below it: short soft dashes, wider and sparser
    # toward the viewer
    path = Image.new("L", (W, H), 0)
    pd = ImageDraw.Draw(path)
    for _ in range(46):
        depth = random.random() ** 1.6                 # more of them near the horizon
        y = HORIZON + 14 + depth * (H - HORIZON - 120)
        x = sx + random.gauss(0, 30 + depth * 170)
        half = random.uniform(14, 40) * (0.6 + depth * 2.2)
        a = round(255 * sun_a * random.uniform(0.45, 0.9) * (1 - depth * 0.6))
        pd.rounded_rectangle([x - half, y, x + half, y + 2 + depth * 4], radius=3, fill=a)
    path = path.filter(ImageFilter.GaussianBlur(3))
    glints = Image.new("RGBA", (W, H), sun_c + (0,))
    glints.putalpha(path)
    img = Image.alpha_composite(img, glints)

    # a far, low shore on the left: depth, nothing to look at
    shore = Image.new("L", (W, H), 0)
    ImageDraw.Draw(shore).polygon(
        [(0, HORIZON - 44), (380, HORIZON - 58), (760, HORIZON - 30), (1020, HORIZON - 12),
         (1180, HORIZON), (0, HORIZON)], fill=255)
    shore_l = Image.new("RGBA", (W, H), p["shore"] + (0,))
    shore_l.putalpha(shore.filter(ImageFilter.GaussianBlur(3)))
    img = Image.alpha_composite(img, shore_l)

    # the pier and the ghost, and their reflection in the water
    scale = 1.0
    layer, (lx, ly) = pier_and_ghost(p, scale)
    full = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    full.paste(layer, (lx, ly), layer)
    refl = full.crop((0, 0, W, WATERLINE)).transpose(Image.FLIP_TOP_BOTTOM)
    refl = refl.resize((W, int(WATERLINE * 0.62)))
    a = refl.getchannel("A").point(lambda v: round(v * p["reflection"]))
    refl.putalpha(a)
    refl = refl.filter(ImageFilter.GaussianBlur(4))
    # ripple: cut the reflection into thin bands, nudged sideways
    rip = Image.new("RGBA", refl.size, (0, 0, 0, 0))
    band = 7
    for y in range(0, refl.size[1], band):
        dx = round(6 * ((y // band) % 3 - 1))
        rip.paste(refl.crop((0, y, W, y + band)), (dx, y))
    fade = Image.linear_gradient("L").resize(rip.size)       # stronger near the pier
    fade = ImageChops.invert(fade)
    rip.putalpha(ImageChops.multiply(rip.getchannel("A"), fade))
    under = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    under.paste(rip, (0, WATERLINE), rip)
    img = Image.alpha_composite(img, under)
    img = Image.alpha_composite(img, full)

    # a whisper of noise against banding in the soft gradients
    noise = Image.effect_noise((W, H), 3).point(lambda v: v - 128 + 128)
    img = ImageChops.add(img.convert("RGB"), Image.merge("RGB", [noise] * 3), scale=1.0, offset=-128)
    img.save(out, quality=93, subsampling=0)


if __name__ == "__main__":
    draw(DAWN, f"{sys.argv[1]}/ghostdock-light.jpg", seed=7)
    draw(NIGHT, f"{sys.argv[1]}/ghostdock-dark.jpg", seed=7)
