#!/usr/bin/env python3
"""Tinder/Bumble-style App Store screenshot generator for Icebreaker.

Pattern derived from analyzing the live Tinder + Bumble App Store listings:
  - Solid brand-color background (full bleed, no gradient noise)
  - App UI shown as a *floating rounded card*, slightly tilted, with a
    drop shadow — no fake iPhone frame around it
  - Big bold white headline at the top
  - A small brand badge accent floating on the card edge

Outputs three size variants:
  • App Store 6.9"   — 1320×2868
  • App Store 6.5"   — 1284×2778
  • Google Play phone — 1080×1920
"""
import math
import os
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path("/Users/dylandreiling/icebreaker/tool/veo")
REPO_ROOT = Path("/Users/dylandreiling/icebreaker")
SCREENS = ROOT / "assets/screens"
SCENES = ROOT / "assets/scenes"
LOGO_PATH = ROOT / "assets/logo_heart_bolt.png"

APPSTORE_69_OUT = REPO_ROOT / "media/marketing/appstore_screenshots"
APPSTORE_65_OUT = REPO_ROOT / "media/marketing/appstore_screenshots_6_5"
PLAYSTORE_OUT  = REPO_ROOT / "media/marketing/playstore_screenshots"

BRAND_PINK = (255, 31, 110, 255)
BRAND_PURPLE = (168, 85, 247, 255)
WHITE = (255, 255, 255, 255)


def pick_font(size, weight="bold"):
    bold_paths = [
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
        "/System/Library/Fonts/HelveticaNeue.ttc",
        "/System/Library/Fonts/SFNS.ttf",
    ]
    regular_paths = [
        "/System/Library/Fonts/Supplemental/Arial.ttf",
        "/System/Library/Fonts/HelveticaNeue.ttc",
        "/System/Library/Fonts/SFNS.ttf",
    ]
    paths = bold_paths if weight == "bold" else regular_paths
    for p in paths:
        if os.path.exists(p):
            try:
                return ImageFont.truetype(p, size)
            except Exception:
                continue
    return ImageFont.load_default()


def brand_bg(w, h):
    """Vertical pink→deep-pink gradient — solid, punchy, no glow noise.

    Used as the fallback when a per-slide bg_NN.png isn't present yet.
    Once all 9 ChatGPT scenes land in `assets/scenes/`, this function is
    never invoked at render time.
    """
    bg = Image.new("RGBA", (w, h), BRAND_PINK)
    px = bg.load()
    top = (255, 56, 130)
    bot = (220, 18, 90)
    for y in range(h):
        t = y / max(1, h - 1)
        r = int(top[0] + (bot[0] - top[0]) * t)
        g = int(top[1] + (bot[1] - top[1]) * t)
        b = int(top[2] + (bot[2] - top[2]) * t)
        for x in range(w):
            px[x, y] = (r, g, b, 255)
    return bg


def load_background(slide_idx, w, h):
    """Load `assets/scenes/bg_{NN}.png` cover-resized to the canvas.

    Falls back to the pink `brand_bg()` gradient when the file is missing,
    so we can iterate the composition layer (vignette / scrim / card /
    headline) before all 9 ChatGPT scenes have been generated.  The
    missing slides are logged with a `[bg missing]` line so the operator
    can see at a glance which slides still need a real bg before final
    upload.
    """
    bg_path = SCENES / f"bg_{slide_idx:02d}.png"
    if not bg_path.exists():
        print(f"  [bg missing] slide {slide_idx} using fallback gradient "
              f"(expected {bg_path.name})")
        return brand_bg(w, h)
    img = Image.open(bg_path).convert("RGBA")
    return cover_resize(img, w, h)


def apply_vignette(bg, edge_strength=0.18):
    """Multiply a radial darkening mask over `bg` to push the card forward.

    The mask is 1.0 at the canvas center and falls to `1 - edge_strength`
    at the corners (default 0.18 → corners at ~82% brightness, ~8% darker
    in linear space).  Applied as a `multiply` against the RGB channels
    so it preserves all of the bg's color character — just makes the
    corners recede.
    """
    w, h = bg.size
    # Build an ellipse-shaped luminance mask (white center → grey corners).
    mask = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(mask)
    cx, cy = w / 2, h / 2
    rx, ry = w * 0.78, h * 0.78  # ellipse axes
    # Approximate a smooth radial gradient with a soft-edged ellipse: draw
    # white into the ellipse, blur the whole mask so the edge falls off,
    # then renormalise to (1.0, 1 - edge_strength) range.
    d.ellipse((cx - rx, cy - ry, cx + rx, cy + ry), fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(max(w, h) * 0.18))
    floor = int(round((1.0 - edge_strength) * 255))
    # Renormalise: 0 (corner) → floor, 255 (center) → 255.
    lut = [floor + (v * (255 - floor) // 255) for v in range(256)]
    mask = mask.point(lut)

    # Multiply each RGB channel by the mask (alpha untouched).
    rgb = Image.merge("RGB", bg.split()[:3])
    rgb = Image.composite(rgb, Image.new("RGB", (w, h), (0, 0, 0)), mask)
    return Image.merge("RGBA", (*rgb.split(), bg.split()[3]))


def apply_top_scrim(bg, height_pct=0.18, max_alpha=140):
    """Paint a top-down dark gradient over the top `height_pct` of the canvas.

    Guarantees the white headline reads cleanly regardless of what the
    underlying ChatGPT scene puts at the top.  Pure additive overlay (no
    color shift on the rest of the bg).
    """
    w, h = bg.size
    band_h = int(h * height_pct)
    overlay = Image.new("RGBA", (w, band_h), (0, 0, 0, 0))
    px = overlay.load()
    for y in range(band_h):
        # Strongest at the very top, fading to 0 at band_h.  Linear easing
        # was too abrupt; ease-out via a (1 - t)**2 curve keeps the lower
        # boundary invisible against the scene.
        t = y / max(1, band_h - 1)
        a = int(max_alpha * (1 - t) ** 2)
        for x in range(w):
            px[x, y] = (0, 0, 0, a)
    bg.alpha_composite(overlay, (0, 0))
    return bg


def wrap_lines(text, font, max_w, draw):
    """Greedy word-wrap to fit within max_w. Returns list of lines."""
    words = text.split()
    lines, cur = [], ""
    for word in words:
        candidate = (cur + " " + word).strip()
        if draw.textlength(candidate, font=font) <= max_w:
            cur = candidate
        else:
            if cur:
                lines.append(cur)
            cur = word
    if cur:
        lines.append(cur)
    return lines


def render_headline_block(canvas, text, top_y, size, color=WHITE, margin=80, line_gap=8):
    """Big bold sans-serif headline, white, multi-line wrapped, top-aligned."""
    w = canvas.size[0]
    draw_probe = ImageDraw.Draw(canvas)
    font = pick_font(size, "bold")
    max_w = w - 2 * margin
    lines = wrap_lines(text, font, max_w, draw_probe)
    # Shrink-to-fit if a single word overruns even one line.
    while any(draw_probe.textlength(ln, font=font) > max_w for ln in lines) and size > 40:
        size = int(size * 0.92)
        font = pick_font(size, "bold")
        lines = wrap_lines(text, font, max_w, draw_probe)

    y = top_y
    for line in lines:
        bb = draw_probe.textbbox((0, 0), line, font=font)
        th = bb[3] - bb[1]
        tw = draw_probe.textlength(line, font=font)
        x0 = (w - int(tw)) // 2
        # Soft drop shadow for legibility over slight color variance.
        shadow_layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
        sd = ImageDraw.Draw(shadow_layer)
        sd.text((x0 + 3, y - bb[1] + 5), line, font=font, fill=(0, 0, 0, 70))
        shadow_layer = shadow_layer.filter(ImageFilter.GaussianBlur(4))
        canvas.alpha_composite(shadow_layer)
        draw = ImageDraw.Draw(canvas)
        draw.text((x0, y - bb[1]), line, font=font, fill=color)
        y += th + line_gap


def cover_resize(img, target_w, target_h):
    sw, sh = img.size
    target_aspect = target_w / target_h
    src_aspect = sw / sh
    if src_aspect < target_aspect:
        new_w = target_w
        new_h = int(sh * target_w / sw)
        img = img.resize((new_w, new_h), Image.LANCZOS)
        y0 = (new_h - target_h) // 2
        img = img.crop((0, y0, target_w, y0 + target_h))
    else:
        new_h = target_h
        new_w = int(sw * target_h / sh)
        img = img.resize((new_w, new_h), Image.LANCZOS)
        x0 = (new_w - target_w) // 2
        img = img.crop((x0, 0, x0 + target_w, target_h))
    return img


def round_corners(img, radius):
    mask = Image.new("L", img.size, 0)
    d = ImageDraw.Draw(mask)
    d.rounded_rectangle((0, 0, img.size[0] - 1, img.size[1] - 1), radius=radius, fill=255)
    out = Image.new("RGBA", img.size, (0, 0, 0, 0))
    out.paste(img, (0, 0), mask)
    return out


def card_with_shadow(card_img, tilt_deg=0, shadow_offset=(0, 24), shadow_blur=40, shadow_alpha=140):
    """Wrap a card image with a soft drop shadow. If tilt_deg != 0, the card
    (and its shadow) are rotated together with expand=True."""
    cw, ch = card_img.size
    pad = shadow_blur * 2 + abs(shadow_offset[0]) + abs(shadow_offset[1])
    canvas = Image.new("RGBA", (cw + pad * 2, ch + pad * 2), (0, 0, 0, 0))

    shadow_mask = Image.new("L", (cw, ch), 0)
    sd = ImageDraw.Draw(shadow_mask)
    sd.rounded_rectangle((0, 0, cw - 1, ch - 1), radius=64, fill=shadow_alpha)
    shadow_layer = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
    shadow_layer.putalpha(shadow_mask)
    canvas.paste(
        shadow_layer,
        (pad + shadow_offset[0], pad + shadow_offset[1]),
        shadow_layer,
    )
    canvas = canvas.filter(ImageFilter.GaussianBlur(shadow_blur))

    canvas.alpha_composite(card_img, (pad, pad))

    if tilt_deg != 0:
        canvas = canvas.rotate(tilt_deg, resample=Image.BICUBIC, expand=True)
    return canvas


def build_screenshot(slide_idx, screen_name, headline, out_name, out_dir, cw, ch, tilt=0):
    # 1) Scene background (ChatGPT-generated, with gradient fallback)
    bg = load_background(slide_idx, cw, ch)
    # 2) Subtle vignette so the card pops out from the scene corners
    bg = apply_vignette(bg)
    # 3) Top scrim so the white headline reads against any bg
    bg = apply_top_scrim(bg)

    # Card sizing — the UI card fills ~70% of canvas height, sits below headline.
    card_h = int(ch * 0.66)
    card_w = int(card_h * 9 / 19.5)        # iPhone aspect 9:19.5
    if card_w > int(cw * 0.75):
        card_w = int(cw * 0.75)
        card_h = int(card_w * 19.5 / 9)

    src = Image.open(SCREENS / screen_name).convert("RGB")
    card = cover_resize(src, card_w, card_h).convert("RGBA")
    card = round_corners(card, radius=int(card_w * 0.07))

    card_with_sh = card_with_shadow(card, tilt_deg=tilt)
    # Headline area sized roughly 30% of canvas height, card centered in lower 70%.
    head_size = max(74, int(cw * 0.092))
    head_top = int(ch * 0.060)
    head_margin = int(cw * 0.075)
    render_headline_block(bg, headline, top_y=head_top, size=head_size,
                          color=WHITE, margin=head_margin, line_gap=int(head_size * 0.10))

    # Card placement — centered horizontally, anchored ~58% down.
    card_x = (cw - card_with_sh.size[0]) // 2
    card_y = int(ch * 0.30)
    bg.alpha_composite(card_with_sh, (card_x, card_y))

    # Brand badge — heart-bolt logo top-right of the card.
    if LOGO_PATH.exists():
        badge_size = int(card_w * 0.22)
        logo = Image.open(LOGO_PATH).convert("RGBA").resize((badge_size, badge_size), Image.LANCZOS)
        # White circle behind the logo for contrast.
        circle = Image.new("RGBA", (badge_size + 32, badge_size + 32), (0, 0, 0, 0))
        cd = ImageDraw.Draw(circle)
        cd.ellipse((0, 0, badge_size + 31, badge_size + 31), fill=(255, 255, 255, 255))
        circle.alpha_composite(logo, (16, 16))
        # Position: just inside the top-right of the card.
        # (For tilted cards we use the card's pre-rotation top-right approximated.)
        bx = card_x + card_with_sh.size[0] - badge_size - 60
        by = card_y + 40
        # Shadow for the badge.
        sh_layer = Image.new("RGBA", bg.size, (0, 0, 0, 0))
        sh_draw = ImageDraw.Draw(sh_layer)
        sh_draw.ellipse((bx + 4, by + 10, bx + badge_size + 32 + 4, by + badge_size + 32 + 10),
                        fill=(0, 0, 0, 90))
        sh_layer = sh_layer.filter(ImageFilter.GaussianBlur(12))
        bg.alpha_composite(sh_layer)
        bg.alpha_composite(circle, (bx, by))

    bg.convert("RGB").save(out_dir / out_name, "PNG", optimize=True)
    print(f"  wrote {out_dir.name}/{out_name}  ({cw}x{ch})")


# Arc-ordered slide list — mirrors the 9-beat production bible.
# Each tuple: (source_screen, headline, output_filename, tilt_degrees).
# The slide index is the 1-based position in this list and drives the
# `bg_NN.png` lookup in `load_background`.
#
# Output filenames use the slide-number prefix so App Store Connect and
# Play Console sort the upload sequence correctly when dragged in.
SHOTS = [
    ("00_splash.png",   "Stop swiping.\nStart meeting.",                "01_stop_swiping.png",       -4),
    ("01_home.png",     "Go live where you are.",                       "02_go_live.png",             3),
    ("02_verify.png",   "Verified live.\nVerified you.",                "03_verified.png",           -3),
    ("04_nearby.png",   "See who's open\nright now.",                   "04_see_nearby.png",         -3),
    ("05_send_ice.png", "Make the first move,\nthe respectful way.",    "05_first_move.png",          4),
    ("07_find.png",     "Find each other\nin the room.",                "06_find_each_other.png",    -3),
    ("08_talking.png",  "Ten minutes that matter.",                     "07_ten_minutes.png",         3),
    ("09_stay.png",     "Chat unlocks\nafter chemistry.",               "08_chat_unlocks.png",       -3),
    ("11_profile.png",  "Real people.\nReal places.",                   "09_real_people.png",         3),
]


TARGETS = [
    ("App Store 6.9\"", APPSTORE_69_OUT, 1320, 2868),
    ("App Store 6.5\"", APPSTORE_65_OUT, 1284, 2778),
    ("Google Play phone", PLAYSTORE_OUT, 1080, 1920),
]


def main():
    SCENES.mkdir(parents=True, exist_ok=True)
    for _, out_dir, _, _ in TARGETS:
        out_dir.mkdir(parents=True, exist_ok=True)
    for label, out_dir, cw, ch in TARGETS:
        print(f"Rendering {label} ({cw}x{ch}) → {out_dir}")
        for idx, (src, head, dst, tilt) in enumerate(SHOTS, start=1):
            build_screenshot(idx, src, head, dst, out_dir, cw, ch, tilt=tilt)
    print("Done.")


if __name__ == "__main__":
    main()
