"""Draws the Ghostdock xfwm4 theme: window frames for the desktop image.

  python3 xfwm4.py OUT     writes OUT/Ghostdock/xfwm4 (dark, the default),
                           OUT/Ghostdock-Light/xfwm4, and each at 2x as
                           OUT/<name>-xhdpi/xfwm4

A unified title bar in the colour of Adwaita's toolbar (dark or light), with
rounded top corners and a hairline border.
The side and bottom borders are mostly transparent: the compositor shows
the window's shadow through them, and they still give the pointer a
resize edge. Buttons are dots that show their symbol on hover. Every
piece is drawn at 4x the target size and scaled down, for clean edges.
"""
import os
import sys

from PIL import Image, ImageDraw

TITLE = 28          # title bar height, logical px
RADIUS = 10         # top corner radius
EDGE = 4            # side and bottom border: transparent, then one hairline
DOT = 12            # button diameter
CELL = 20           # button width: the dot and the gap to the next one

# The colours of one variant; write() makes them the module's for a run.
# ACTIVE is Adwaita's toolbar, so the title bar and toolbar read as one.
DARK = {
    "ACTIVE": (45, 45, 45),
    "INACTIVE": (36, 36, 36),
    "HAIRLINE": (0, 0, 0, 150),
    "HIGHLIGHT": (255, 255, 255, 20),
    "SEPARATOR": (0, 0, 0, 90),
    "TEXT_ACTIVE": "#E6E6E6",
    "TEXT_INACTIVE": "#8A8A8A",
    "DOT_INACTIVE": ((74, 74, 74), (62, 62, 62)),
}
LIGHT = {
    "ACTIVE": (246, 245, 244),
    "INACTIVE": (250, 250, 249),
    "HAIRLINE": (0, 0, 0, 38),
    "HIGHLIGHT": (255, 255, 255, 150),
    "SEPARATOR": (0, 0, 0, 22),
    "TEXT_ACTIVE": "#2B2F36",
    "TEXT_INACTIVE": "#9AA0A8",
    "DOT_INACTIVE": ((214, 217, 222), (196, 200, 206)),
}
ACTIVE = INACTIVE = HAIRLINE = HIGHLIGHT = SEPARATOR = TEXT_ACTIVE = TEXT_INACTIVE = DOT_INACTIVE = None

BUTTONS = {
    # name: (fill, ring, glyph)
    "close": ((242, 85, 90), (214, 62, 68), "x"),
    "hide": ((245, 184, 61), (215, 152, 34), "-"),
    "maximize": ((32, 188, 140), (20, 150, 110), "+"),   # phosphor 550
}
GLYPH = (0, 0, 0, 120)

SS = 4  # supersampling


def over(bg, rgba):
    """rgba composited onto the solid bg: Pillow replaces pixels, it does not blend."""
    a = rgba[3] / 255
    return tuple(round(c * a + b * (1 - a)) for c, b in zip(rgba[:3], bg)) + (255,)


def canvas(w, h, s):
    return Image.new("RGBA", (w * s * SS, h * s * SS), (0, 0, 0, 0))


def done(im, s):
    w, h = im.size
    return im.resize((w // SS, h // SS), Image.LANCZOS)


def title_piece(w, s, bg, separator=True):
    """A tile of the title bar: background and the bottom separator."""
    im = canvas(w, TITLE, s)
    d = ImageDraw.Draw(im)
    u = s * SS
    d.rectangle([0, 0, w * u, TITLE * u], fill=bg)
    d.rectangle([0, 0, w * u, u - 1], fill=HAIRLINE)                       # top hairline
    d.rectangle([0, u, w * u, 2 * u - 1], fill=over(bg, HIGHLIGHT))   # highlight
    if separator:
        d.rectangle([0, (TITLE - 1) * u, w * u, TITLE * u], fill=over(bg, SEPARATOR))
    return done(im, s)


def corner(s, bg, right):
    """Top corner: transparent margin, then the rounded title bar edge."""
    w = EDGE + RADIUS
    im = canvas(w, TITLE, s)
    d = ImageDraw.Draw(im)
    u = s * SS
    x0 = (EDGE - 1) * u
    box = [x0, 0, (w + RADIUS) * u, (TITLE + RADIUS) * u]
    d.rounded_rectangle(box, radius=RADIUS * u, fill=HAIRLINE)
    inner = [x0 + u, u, (w + RADIUS) * u, (TITLE + RADIUS) * u]
    d.rounded_rectangle(inner, radius=(RADIUS - 1) * u, fill=bg + (255,))
    hl = [x0 + u, u, (w + RADIUS) * u, (TITLE + RADIUS) * u]
    d.rounded_rectangle(hl, radius=(RADIUS - 1) * u, outline=over(bg, HIGHLIGHT), width=u)
    # bottom row: the separator, and the hairline continuing down the side
    d.rectangle([x0 + u, (TITLE - 1) * u, w * u, TITLE * u], fill=over(bg, SEPARATOR))
    d.rectangle([x0, (TITLE - RADIUS) * u, x0 + u - 1, TITLE * u], fill=HAIRLINE)
    im = done(im, s)
    return im.transpose(Image.FLIP_LEFT_RIGHT) if right else im


def side(s, right):
    im = canvas(EDGE, 1, s)
    d = ImageDraw.Draw(im)
    u = s * SS
    d.rectangle([(EDGE - 1) * u, 0, EDGE * u, u], fill=HAIRLINE)
    im = done(im, s)
    return im.transpose(Image.FLIP_LEFT_RIGHT) if right else im


def bottom(s):
    im = canvas(1, EDGE, s)
    d = ImageDraw.Draw(im)
    u = s * SS
    d.rectangle([0, 0, u, u - 1], fill=HAIRLINE)
    return done(im, s)


def bottom_corner(s, right):
    im = canvas(EDGE, EDGE, s)
    d = ImageDraw.Draw(im)
    u = s * SS
    d.rectangle([(EDGE - 1) * u, 0, EDGE * u, u - 1], fill=HAIRLINE)
    im = done(im, s)
    return im.transpose(Image.FLIP_LEFT_RIGHT) if right else im


def button(s, bg, name, state):
    """One button cell: title bar background with a dot in it."""
    w = CELL
    im = title_piece(w, s, bg).resize((w * s * SS, TITLE * s * SS), Image.NEAREST)
    d = ImageDraw.Draw(im)
    u = s * SS
    cx = DOT / 2 * u
    cy = TITLE / 2 * u
    r = DOT / 2 * u
    if state == "inactive":
        fill, ring = DOT_INACTIVE
    else:
        fill, ring, _ = BUTTONS[name]
        if state == "pressed":
            fill = tuple(int(c * 0.82) for c in fill)
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=ring)
    d.ellipse([cx - r + u * 0.6, cy - r + u * 0.6, cx + r - u * 0.6, cy + r - u * 0.6], fill=fill)
    if state in ("prelight", "pressed"):
        g = BUTTONS[name][2]
        a = DOT * 0.22 * u
        lw = max(1, int(1.3 * u))
        if g == "x":
            d.line([cx - a, cy - a, cx + a, cy + a], fill=over(fill, GLYPH), width=lw)
            d.line([cx - a, cy + a, cx + a, cy - a], fill=over(fill, GLYPH), width=lw)
        else:
            d.line([cx - a * 1.2, cy, cx + a * 1.2, cy], fill=over(fill, GLYPH), width=lw)
            if g == "+":
                d.line([cx, cy - a * 1.2, cx, cy + a * 1.2], fill=over(fill, GLYPH), width=lw)
    return done(im, s)


THEMERC = """\
# Ghostdock: drawn by theme/xfwm4.py of the module ghostdock/desktop
active_text_color={text_active}
inactive_text_color={text_inactive}
title_alignment=center
full_width_title=true
title_shadow_active=false
title_shadow_inactive=false
title_vertical_offset_active={voff}
title_vertical_offset_inactive={voff}
# buttons start after the top-left corner piece, so they do not paint over it
button_offset={button_offset}
button_spacing=0
maximized_offset={max_off}
shadow_delta_height=2
shadow_delta_width=0
shadow_delta_x=0
shadow_delta_y=-{shadow_y}
shadow_opacity=28
"""


def write(out, s, palette):
    globals().update(palette)
    os.makedirs(out, exist_ok=True)
    states = ("active", "inactive")
    for st in states:
        bg = ACTIVE if st == "active" else INACTIVE
        corner(s, bg, False).save(f"{out}/top-left-{st}.png")
        corner(s, bg, True).save(f"{out}/top-right-{st}.png")
        for i in range(1, 6):
            title_piece(1, s, bg).save(f"{out}/title-{i}-{st}.png")
        side(s, False).save(f"{out}/left-{st}.png")
        side(s, True).save(f"{out}/right-{st}.png")
        bottom(s).save(f"{out}/bottom-{st}.png")
        bottom_corner(s, False).save(f"{out}/bottom-left-{st}.png")
        bottom_corner(s, True).save(f"{out}/bottom-right-{st}.png")
    for name in BUTTONS:
        for st in ("active", "inactive", "prelight", "pressed"):
            bg = INACTIVE if st == "inactive" else ACTIVE
            img = button(s, bg, name, st)
            img.save(f"{out}/{name}-{st}.png")
            if name == "maximize":
                img.save(f"{out}/maximize-toggled-{st}.png")
    # buttons the layout does not show still need images
    blank = title_piece(1, s, ACTIVE)
    for name in ("menu", "shade", "stick"):
        for st in ("active", "inactive", "prelight", "pressed"):
            blank.save(f"{out}/{name}-{st}.png")
            blank.save(f"{out}/{name}-toggled-{st}.png")
    with open(f"{out}/themerc", "w") as f:
        f.write(THEMERC.format(text_active=TEXT_ACTIVE, text_inactive=TEXT_INACTIVE,
                               voff=0, max_off=(EDGE + RADIUS) * s, shadow_y=s,
                               button_offset=(EDGE + RADIUS) * s))


if __name__ == "__main__":
    root = sys.argv[1]
    for name, palette in (("Ghostdock", DARK), ("Ghostdock-Light", LIGHT)):
        write(f"{root}/{name}/xfwm4", 1, palette)
        write(f"{root}/{name}-xhdpi/xfwm4", 2, palette)
