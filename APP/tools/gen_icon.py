"""Genera el ícono de Doc SILOG (misma identidad que la animación de bienvenida).

Salida en assets/icon/: icon.png (legacy), background.png, foreground.png, monochrome.png
Uso:  python tools/gen_icon.py   (requiere Pillow)  y luego  dart run flutter_launcher_icons
"""
from PIL import Image, ImageDraw, ImageFilter, ImageChops
import os

K = 2                      # supersampling
N = 1024 * K
G1, G2 = (34, 197, 94), (20, 184, 166)
OUT = os.path.join(os.path.dirname(__file__), '..', 'assets', 'icon')


def P(v):
    return int(round(v * K))


def grad(w, h, c1=G1, c2=G2):
    small = Image.new('RGB', (128, 128))
    px = small.load()
    for y in range(128):
        for x in range(128):
            t = (x + y) / 254
            px[x, y] = tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(3))
    return small.resize((w, h), Image.BICUBIC)


def paste_grad(dst, mask, bbox=None):
    dst.paste(grad(N, N), (0, 0), mask)


def blank():
    return Image.new('RGBA', (N, N), (0, 0, 0, 0))


def mask():
    return Image.new('L', (N, N), 0)


# ---------- geometría (unidades de 1024) ----------
CX = CY = 512
SW, SH = 380, 490
X0, X1 = CX - SW // 2, CX + SW // 2
Y0, Y1 = CY - SH // 2, CY + SH // 2
FOLD = 100
BEAM_Y = Y0 + 275


def sheet_mask():
    m = mask()
    d = ImageDraw.Draw(m)
    d.rounded_rectangle([P(X0), P(Y0), P(X1), P(Y1)], radius=P(38), fill=255)
    d.polygon([(P(X1 - FOLD), P(Y0) - 4), (P(X1) + 4, P(Y0) - 4), (P(X1) + 4, P(Y0 + FOLD))], fill=0)
    return m


def fold_mask():
    m = mask()
    ImageDraw.Draw(m).polygon(
        [(P(X1 - FOLD), P(Y0)), (P(X1), P(Y0 + FOLD)), (P(X1 - FOLD), P(Y0 + FOLD))], fill=255)
    return m


def lines_mask():
    m = mask()
    d = ImageDraw.Draw(m)
    widths = [0.50, 1.0, 1.0, 0.86, 1.0, 0.72, 0.46]
    full = SW - 88
    y = Y0 + 150
    for i, w in enumerate(widths):
        th = 26 if i == 0 else 20
        d.rounded_rectangle(
            [P(X0 + 44), P(y), P(X0 + 44 + full * w), P(y + th)], radius=P(th / 2), fill=255)
        y += 46
    return m


def brackets_mask():
    m = mask()
    d = ImageDraw.Draw(m)
    mg, ln, st = 62, 96, 26
    L, R, T, B = X0 - mg, X1 + mg, Y0 - mg, Y1 + mg
    segs = [
        [(L, T + ln), (L, T), (L + ln, T)],
        [(R - ln, T), (R, T), (R, T + ln)],
        [(R, B - ln), (R, B), (R - ln, B)],
        [(L + ln, B), (L, B), (L, B - ln)],
    ]
    for s in segs:
        pts = [(P(x), P(y)) for x, y in s]
        d.line(pts, fill=255, width=P(st), joint='curve')
        for x, y in (pts[0], pts[-1]):
            r = P(st) / 2
            d.ellipse([x - r, y - r, x + r, y + r], fill=255)
    return m


def glyph(mono=False):
    layer = blank()
    sm, fm, lm = sheet_mask(), fold_mask(), lines_mask()

    if mono:
        white = Image.new('RGBA', (N, N), (255, 255, 255, 255))
        body = ImageChops.subtract(sm, lm)
        layer.paste(white, (0, 0), body)
        layer.paste(white, (0, 0), brackets_mask())
        return layer.resize((1024, 1024), Image.LANCZOS)

    # sombra
    sh = mask()
    sh.paste(sm, (0, P(14)))
    shadow = Image.new('RGBA', (N, N), (0, 0, 0, 120))
    sh = sh.filter(ImageFilter.GaussianBlur(P(18)))
    layer.paste(shadow, (0, 0), sh)

    # hoja "cruda" (gris) completa
    layer.paste(Image.new('RGBA', (N, N), (195, 203, 219, 255)), (0, 0), sm)
    layer.paste(Image.new('RGBA', (N, N), (169, 179, 200, 255)), (0, 0), fm)
    layer.paste(Image.new('RGBA', (N, N), (142, 153, 178, 255)), (0, 0), lm)

    # hoja "mejorada" por encima del haz
    clip = mask()
    ImageDraw.Draw(clip).rectangle([0, 0, N, P(BEAM_Y)], fill=255)
    enh = blank()
    enh.paste(Image.new('RGBA', (N, N), (255, 255, 255, 255)), (0, 0), sm)
    enh.paste(Image.new('RGBA', (N, N), (205, 235, 221, 255)), (0, 0), fm)
    enh.paste(grad(N, N).convert('RGBA'), (0, 0), lm)
    em = ImageChops.multiply(clip, ImageChops.lighter(sm, fm))
    layer.paste(enh, (0, 0), em)

    # estela + haz
    trail_h = 150
    tm = mask()
    ramp = Image.linear_gradient('L').resize((P(SW + 150), P(trail_h)))  # 0 (arriba) -> 255 (abajo)
    ramp = ramp.point(lambda v: int(v * 0.30))
    tm.paste(ramp, (P(CX - (SW + 150) / 2), P(BEAM_Y - trail_h)))
    tm = ImageChops.multiply(tm, sm)   # la estela solo ilumina la hoja
    layer.paste(Image.new('RGBA', (N, N), G1 + (255,)), (0, 0), tm)

    glow = blank()
    gm = mask()
    ImageDraw.Draw(gm).rounded_rectangle(
        [P(X0 - 90), P(BEAM_Y - 8), P(X1 + 90), P(BEAM_Y + 8)], radius=P(8), fill=255)
    glow.paste(Image.new('RGBA', (N, N), G1 + (255,)), (0, 0), gm.filter(ImageFilter.GaussianBlur(P(22))))
    layer = Image.alpha_composite(layer, glow)

    bm = mask()
    ImageDraw.Draw(bm).rounded_rectangle(
        [P(X0 - 90), P(BEAM_Y - 7), P(X1 + 90), P(BEAM_Y + 7)], radius=P(7), fill=255)
    fade = Image.linear_gradient('L').rotate(90).resize((N, N))  # horizontal
    fade = fade.point(lambda v: 255 - abs(v - 128) * 2 if abs(v - 128) < 128 else 0)
    bm = ImageChops.multiply(bm, fade.point(lambda v: min(255, int(v * 1.6))))
    layer.paste(Image.new('RGBA', (N, N), (255, 255, 255, 255)), (0, 0), bm)

    # marco de detección
    layer.paste(grad(N, N).convert('RGBA'), (0, 0), brackets_mask())
    return layer.resize((1024, 1024), Image.LANCZOS)


def background():
    bg = Image.new('RGB', (N, N))
    d = ImageDraw.Draw(bg)
    top, bot = (22, 34, 58), (11, 18, 32)
    for y in range(N):
        t = y / N
        d.line([(0, y), (N, y)], fill=tuple(int(top[i] + (bot[i] - top[i]) * t) for i in range(3)))
    bg = bg.convert('RGBA')
    for (cx, cy, r, col, a) in [(850, 130, 420, G1, 85), (130, 930, 460, G2, 70)]:
        g = blank()
        ImageDraw.Draw(g).ellipse([P(cx - r), P(cy - r), P(cx + r), P(cy + r)], fill=col + (a,))
        g = g.filter(ImageFilter.GaussianBlur(P(120)))
        bg = Image.alpha_composite(bg, g)
    return bg.resize((1024, 1024), Image.LANCZOS)


if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    bg, fg, mono = background(), glyph(), glyph(mono=True)
    bg.convert('RGB').save(os.path.join(OUT, 'background.png'))

    def zoom(im, f=1.1):
        # flutter_launcher_icons ya aplica un 16% de margen interno a las capas adaptables
        big = im.resize((int(1024 * f), int(1024 * f)), Image.LANCZOS)
        o = (big.width - 1024) // 2
        return big.crop((o, o, o + 1024, o + 1024))

    zoom(fg).save(os.path.join(OUT, 'foreground.png'))
    zoom(mono).save(os.path.join(OUT, 'monochrome.png'))

    full = Image.alpha_composite(bg, fg)
    rm = Image.new('L', (1024, 1024), 0)
    ImageDraw.Draw(rm).rounded_rectangle([0, 0, 1023, 1023], radius=230, fill=255)
    icon = Image.new('RGBA', (1024, 1024), (0, 0, 0, 0))
    icon.paste(full, (0, 0), rm)
    icon.save(os.path.join(OUT, 'icon.png'))
    print('ok')
