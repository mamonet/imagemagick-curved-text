"""Generate the generic product mockups, their shading maps, and before/after samples.

Run:  python gen_assets.py <repo_root>

Produces mockups/{mug,bottle,tin}.png, mockups/*-shading.png, samples/*-before.png,
samples/*-after.png. Everything is drawn procedurally: no photographs, no client assets.
"""
import os
import sys
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter

W = H = 1024
BG = (238, 236, 232)

FONT_CANDIDATES = [
    r"C:\Windows\Fonts\seguisb.ttf",
    r"C:\Windows\Fonts\arialbd.ttf",
    r"C:\Windows\Fonts\calibrib.ttf",
    r"C:\Windows\Fonts\georgia.ttf",
]


def font(size):
    for p in FONT_CANDIDATES:
        if os.path.exists(p):
            return ImageFont.truetype(p, size)
    return ImageFont.load_default()


def cyl_profile(x0, x1, width):
    """Normalised cylinder shading across a horizontal span.

    Returns an array over the full canvas width: 1.0 at the lit band, falling off
    toward both silhouette edges the way a cylinder does.
    """
    xs = np.arange(width, dtype=np.float64)
    t = np.clip((xs - x0) / max(x1 - x0, 1), 0.0, 1.0)
    # angle across the visible half of the cylinder
    theta = (t - 0.5) * np.pi
    lam = np.cos(theta) ** 0.85
    # broad specular band left of centre, as if the key light is up and to the left
    spec = np.exp(-(((t - 0.34) / 0.24) ** 2)) * 0.26
    return np.clip(lam + spec, 0.0, 1.25)


def vgrad(y0, y1, height, top=1.0, bottom=0.86):
    ys = np.arange(height, dtype=np.float64)
    t = np.clip((ys - y0) / max(y1 - y0, 1), 0.0, 1.0)
    return top + (bottom - top) * t


def shade_region(img_arr, mask, x0, x1, y0, y1, base_rgb, ambient=0.30):
    """Apply cylindrical shading to the masked region."""
    prof = cyl_profile(x0, x1, W)[None, :]
    vert = vgrad(y0, y1, H)[:, None]
    lit = (ambient + (1.0 - ambient) * prof) * vert
    base = np.array(base_rgb, dtype=np.float64)[None, None, :]
    shaded = np.clip(base * lit[:, :, None], 0, 255)
    m = mask[:, :, None]
    img_arr[:, :, :3] = np.where(m, shaded, img_arr[:, :, :3])
    img_arr[:, :, 3] = np.where(mask, 255, img_arr[:, :, 3])


def mask_from_draw(fn):
    m = Image.new("L", (W, H), 0)
    fn(ImageDraw.Draw(m))
    return m


def soft_shadow(base, mask_img, dy=26, blur=22, strength=0.42):
    """Darken the ground behind the object only, never the object itself."""
    sh = mask_img.filter(ImageFilter.GaussianBlur(blur))
    sh = sh.transform(sh.size, Image.AFFINE, (1, 0, 0, 0, 1, -dy), resample=Image.BILINEAR)
    a = np.asarray(sh, dtype=np.float64) / 255.0 * strength
    # the object occludes its own shadow
    a *= (np.asarray(mask_img, dtype=np.float64) / 255.0 < 0.5)
    arr = np.asarray(base, dtype=np.float64).copy()
    arr[:, :, :3] *= (1.0 - a[:, :, None])
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")


# ---------------------------------------------------------------- mockups

def make_mug():
    bx0, bx1, by0, by1 = 296, 742, 322, 772
    body = mask_from_draw(lambda d: (
        d.rounded_rectangle([bx0, by0 + 30, bx1, by1 - 34], radius=26, fill=255),
        d.ellipse([bx0, by1 - 96, bx1, by1], fill=255),
        d.ellipse([bx0, by0, bx1, by0 + 74], fill=255),
    ))
    handle = mask_from_draw(lambda d: (
        d.ellipse([700, 402, 892, 618], fill=255),
        d.ellipse([742, 446, 850, 574], fill=0),
        d.rectangle([640, 380, 760, 640], fill=0),
    ))
    full = Image.fromarray(
        np.maximum(np.asarray(body), np.asarray(handle)).astype(np.uint8), "L")

    arr = np.zeros((H, W, 4), dtype=np.float64)
    arr[:, :, :3] = np.array(BG, dtype=np.float64)[None, None, :]
    arr[:, :, 3] = 255

    hm = np.asarray(handle) > 127
    shade_region(arr, hm, 700, 892, 402, 618, (232, 228, 220), ambient=0.42)
    bm = np.asarray(body) > 127
    shade_region(arr, bm, bx0, bx1, by0, by1, (243, 240, 234), ambient=0.26)

    # inner rim: darker ellipse at the top so the mug reads as open
    rim = mask_from_draw(lambda d: d.ellipse([bx0 + 20, by0 + 12, bx1 - 20, by0 + 62], fill=255))
    rm = np.asarray(rim) > 127
    arr[:, :, :3] = np.where(rm[:, :, None], arr[:, :, :3] * 0.58, arr[:, :, :3])

    img = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")
    return soft_shadow(img, full), (bx0, bx1, by0 + 90, by1 - 70)


def make_bottle():
    bx0, bx1 = 380, 650
    body = mask_from_draw(lambda d: (
        d.rounded_rectangle([bx0, 400, bx1, 900], radius=34, fill=255),
        d.polygon([(bx0, 420), (bx1, 420), (bx1 - 78, 250), (bx0 + 78, 250)], fill=255),
        d.rounded_rectangle([bx0 + 92, 150, bx1 - 92, 268], radius=14, fill=255),
        d.rounded_rectangle([bx0 + 84, 128, bx1 - 84, 176], radius=10, fill=255),
    ))
    arr = np.zeros((H, W, 4), dtype=np.float64)
    arr[:, :, :3] = np.array(BG, dtype=np.float64)[None, None, :]
    arr[:, :, 3] = 255

    m = np.asarray(body) > 127
    shade_region(arr, m, bx0, bx1, 150, 900, (46, 74, 58), ambient=0.22)

    # cap
    cap = mask_from_draw(lambda d: d.rounded_rectangle([bx0 + 80, 122, bx1 - 80, 180], radius=10, fill=255))
    cm = np.asarray(cap) > 127
    shade_region(arr, cm, bx0 + 80, bx1 - 80, 122, 180, (58, 52, 46), ambient=0.35)

    img = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")
    return soft_shadow(img, body, dy=20), (bx0, bx1, 470, 800)


def make_tin():
    bx0, bx1, by0, by1 = 286, 754, 356, 726
    body = mask_from_draw(lambda d: (
        d.rectangle([bx0, by0 + 34, bx1, by1 - 30], fill=255),
        d.ellipse([bx0, by1 - 74, bx1, by1], fill=255),
        d.ellipse([bx0, by0, bx1, by0 + 72], fill=255),
    ))
    lid = mask_from_draw(lambda d: (
        d.rectangle([bx0 - 10, by0 + 16, bx1 + 10, by0 + 74], fill=255),
        d.ellipse([bx0 - 10, by0 - 12, bx1 + 10, by0 + 62], fill=255),
        d.ellipse([bx0 - 10, by0 + 44, bx1 + 10, by0 + 104], fill=255),
    ))
    full = Image.fromarray(np.maximum(np.asarray(body), np.asarray(lid)).astype(np.uint8), "L")

    arr = np.zeros((H, W, 4), dtype=np.float64)
    arr[:, :, :3] = np.array(BG, dtype=np.float64)[None, None, :]
    arr[:, :, 3] = 255

    m = np.asarray(body) > 127
    shade_region(arr, m, bx0, bx1, by0, by1, (198, 170, 122), ambient=0.24)
    lm = np.asarray(lid) > 127
    shade_region(arr, lm, bx0 - 10, bx1 + 10, by0 - 12, by0 + 104, (176, 148, 104), ambient=0.30)

    img = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")
    return soft_shadow(img, full, dy=18), (bx0, bx1, by0 + 120, by1 - 60)


# ------------------------------------------------------------ shading maps

def shading_map(box, curve=1.0):
    """Greyscale displacement map for a cylinder spanning box=(x0,x1,y0,y1).

    Mid-grey (128) is zero displacement. The horizontal ramp encodes how far a
    pixel must move to sit on the curved surface: strongest near the silhouette
    edges, zero at the centre line.
    """
    x0, x1, y0, y1 = box
    xs = np.arange(W, dtype=np.float64)
    t = np.clip((xs - x0) / max(x1 - x0, 1), 0.0, 1.0)
    theta = (t - 0.5) * np.pi
    # sin(theta) is the lateral component: negative left of centre, positive right
    ramp = np.sin(theta) * curve
    row = 128.0 + ramp * 127.0
    m = np.tile(row[None, :], (H, 1))
    # outside the product the map is neutral
    m[:y0, :] = 128.0
    m[y1:, :] = 128.0
    m[:, :x0] = 128.0
    m[:, x1:] = 128.0
    img = Image.fromarray(np.clip(m, 0, 255).astype(np.uint8), "L")
    return img.filter(ImageFilter.GaussianBlur(3))


# ------------------------------------------------------------- text label

def render_label(text, size, fill, width):
    f = font(size)
    tmp = Image.new("RGBA", (10, 10))
    bbox = ImageDraw.Draw(tmp).textbbox((0, 0), text, font=f)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    pad = size // 2
    img = Image.new("RGBA", (max(width, tw + 2 * pad), th + 2 * pad), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.text(((img.width - tw) / 2 - bbox[0], pad - bbox[1]), text, font=f, fill=fill)
    return img


def distort_arc(label, degrees, bow_down=False):
    """Bend a label around a cylinder, the way -distort Arc does.

    bow_down flips the arch: text on the front of a mug at eye level dips at the
    ends, because the surface is curving away from the camera there.
    """
    if bow_down:
        return distort_arc(label.rotate(180), degrees).rotate(180)
    lw, lh = label.size
    rad = np.deg2rad(degrees)
    R = lw / rad
    out_w = int(2 * (R + lh) * np.sin(rad / 2)) + 8
    out_h = int((R + lh) - (R * np.cos(rad / 2))) + 8
    out = np.zeros((out_h, out_w, 4), dtype=np.uint8)
    src = np.asarray(label)

    yy, xx = np.mgrid[0:out_h, 0:out_w]
    cx = out_w / 2.0
    # centre of the arc sits below the output: the top of the label is the
    # farthest point from it, at radius R + lh
    cy = R + lh
    dx = xx - cx
    dy = cy - yy
    r = np.sqrt(dx * dx + dy * dy)
    ang = np.arctan2(dx, dy)

    sx = (ang / rad + 0.5) * lw
    sy = (R + lh) - r
    valid = (sx >= 0) & (sx < lw - 1) & (sy >= 0) & (sy < lh - 1)
    sxi = np.clip(sx.astype(int), 0, lw - 1)
    syi = np.clip(sy.astype(int), 0, lh - 1)
    out[valid] = src[syi[valid], sxi[valid]]
    return Image.fromarray(out, "RGBA")


def distort_displace(label, dmap, amount_x, amount_y):
    """Offset each pixel by the map value, the way -compose displace does."""
    lw, lh = label.size
    m = dmap.resize((lw, lh), Image.LANCZOS)
    mv = (np.asarray(m, dtype=np.float64) - 128.0) / 128.0
    src = np.asarray(label)
    yy, xx = np.mgrid[0:lh, 0:lw]
    sx = np.clip((xx + mv * amount_x).astype(int), 0, lw - 1)
    sy = np.clip((yy + mv * amount_y).astype(int), 0, lh - 1)
    return Image.fromarray(src[sy, sx], "RGBA")


def composite_blend(base, layer, pos, opacity, level_floor, blend="multiply"):
    """Composite so the text picks up the product's existing lighting.

    multiply keeps dark ink sitting under the product's own shadows; screen is the
    one to use for light ink on a dark surface, where multiply would erase it.
    """
    b = np.asarray(base, dtype=np.float64)
    over = Image.new("RGBA", base.size, (0, 0, 0, 0))
    over.paste(layer, pos, layer)
    o = np.asarray(over, dtype=np.float64)
    a = (o[:, :, 3:4] / 255.0) * opacity
    if blend == "screen":
        mixed = 255.0 - (255.0 - b[:, :, :3]) * (255.0 - o[:, :, :3]) / 255.0
    else:
        mixed = b[:, :, :3] * (o[:, :, :3] / 255.0)
        # keep dark ink from disappearing entirely into a dark area
        mixed = np.maximum(mixed, level_floor)
    out = b.copy()
    out[:, :, :3] = b[:, :, :3] * (1 - a) + mixed * a
    return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), "RGBA")


def main(root):
    mock = os.path.join(root, "mockups")
    samp = os.path.join(root, "samples")
    os.makedirs(mock, exist_ok=True)
    os.makedirs(samp, exist_ok=True)

    built = []

    # ---- mug: arc
    mug, mbox = make_mug()
    mug.save(os.path.join(mock, "mug.png"))
    shading_map(mbox, 0.9).save(os.path.join(mock, "mug-shading.png"))
    mug.save(os.path.join(samp, "mug-before.png"))
    lab = render_label("Fresh Roast Daily", 46, (43, 43, 43, 255), 330)
    wrapped = distort_arc(lab, 22, bow_down=True)
    pos = (int((mbox[0] + mbox[1]) / 2 - wrapped.width / 2), 486)
    composite_blend(mug, wrapped, pos, 0.92, 18, "multiply").save(
        os.path.join(samp, "mug-after.png"))
    built += ["mug.png", "mug-shading.png", "mug-before.png", "mug-after.png"]

    # ---- bottle: displacement map
    bot, bbox_ = make_bottle()
    bot.save(os.path.join(mock, "bottle.png"))
    bmap = shading_map(bbox_, 1.0)
    bmap.save(os.path.join(mock, "bottle-shading.png"))
    bot.save(os.path.join(samp, "bottle-before.png"))
    lab = render_label("Cold Pressed", 38, (244, 241, 234, 255), 150)
    crop = bmap.crop((bbox_[0], 590, bbox_[1], 590 + lab.height))
    wrapped = distort_displace(lab, crop, 14, 3)
    pos = (int((bbox_[0] + bbox_[1]) / 2 - wrapped.width / 2), 590)
    composite_blend(bot, wrapped, pos, 0.95, 90, "screen").save(
        os.path.join(samp, "bottle-after.png"))
    built += ["bottle.png", "bottle-shading.png", "bottle-before.png", "bottle-after.png"]

    # ---- tin: full wrap
    tin, tbox = make_tin()
    tin.save(os.path.join(mock, "tin.png"))
    tmap = shading_map(tbox, 1.15)
    tmap.save(os.path.join(mock, "tin-shading.png"))
    tin.save(os.path.join(samp, "tin-before.png"))
    lab = render_label("Loose Leaf No. 3", 48, (31, 26, 23, 255), 340)
    crop = tmap.crop((tbox[0], 520, tbox[1], 520 + lab.height))
    wrapped = distort_displace(lab, crop, 22, 0)
    pos = (int((tbox[0] + tbox[1]) / 2 - wrapped.width / 2), 520)
    composite_blend(tin, wrapped, pos, 0.94, 22, "multiply").save(
        os.path.join(samp, "tin-after.png"))
    built += ["tin.png", "tin-shading.png", "tin-before.png", "tin-after.png"]

    for b in built:
        print("wrote", b)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else ".")
