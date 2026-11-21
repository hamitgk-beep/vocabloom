"""Draws the Storilex brand pictures in assets/brand from the Cinzel Decorative
font (SIL OFL, tools/brand/fonts). The app ships only the pictures, not the font.

    python3 tools/brand/make_brand.py      (needs Node with Playwright and Pillow)

Writes: wordmark-light.png / wordmark-dark.png (gold "Storilex" for day and
night), icon.png and icon-adaptive-*.png (gold S on leather brown with a thin
gold frame), logo.png (the same icon, small), splash.png / splash-dark.png (the
launch screen's wordmark, no words
in one language: the system shows it before the app knows the language) and splash-android12.png (the S for Android 12+).
"""
import json
import os
import subprocess
import sys
import tempfile

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, '..', '..', 'assets', 'brand')
FONT = os.path.join(HERE, 'fonts', 'CinzelDecorative-Bold.ttf')

GOLD_NIGHT = 'linear-gradient(178deg,#FFF6D2 0%,#F6DA8A 20%,#D7A949 42%,#8E5F1E 52%,#C89640 63%,#F7DE97 82%,#B58130 100%)'
GOLD_DAY = 'linear-gradient(178deg,#E9C46F 0%,#C9973B 30%,#8A5A16 52%,#A87428 66%,#D9AE58 84%,#8E6020 100%)'
LEATHER = 'radial-gradient(ellipse 90% 80% at 50% 35%,#4A3622 0%,#2A1E14 60%,#1B140D 100%)'

CSS = f"""
@font-face{{font-family:CinzelD;src:url(file://{FONT});font-weight:700}}
*{{margin:0;padding:0;box-sizing:border-box}}
body{{background:transparent}}
.g{{font-family:CinzelD;font-weight:700;line-height:1;white-space:nowrap;-webkit-background-clip:text;background-clip:text;color:transparent}}
.n{{background-image:{GOLD_NIGHT}}}
.d{{background-image:{GOLD_DAY}}}
.box{{display:flex;flex-direction:column;align-items:center;justify-content:center;position:relative;overflow:hidden}}
.rule{{height:6px;background:linear-gradient(90deg,transparent,#C99A3E,transparent)}}
"""


def wordmark(cls, size, shadow):
    return f'<span class="g {cls}" style="font-size:{size}px;letter-spacing:.06em;padding:{size*.1:.0f}px {size*.12:.0f}px;filter:{shadow}">Storilex</span>'


def icon(px, bg=True, fg=True, scale=1.0):
    """The launcher icon: S and frame drawn at [scale] of the square (adaptive
    icons keep their picture inside the middle two thirds)."""
    s = px * scale
    off = (px - s) / 2
    frame = f'<div style="position:absolute;left:{off + s*.07:.1f}px;top:{off + s*.07:.1f}px;width:{s*.86:.1f}px;height:{s*.86:.1f}px;border:{max(s/96,1):.1f}px solid rgba(214,177,108,.55);border-radius:{s*.22*.7:.1f}px"></div>'
    letter = f'<span class="g n" style="font-size:{s*.62:.1f}px;margin-top:{s*.04:.1f}px;position:relative">S</span>'
    return f'<div class="box" style="width:{px}px;height:{px}px;background:{LEATHER if bg else "transparent"}">{frame if fg else ""}{letter if fg else ""}</div>'


def splash(cls, rule_op):
    return f'''<div class="box" style="width:1024px;height:1024px">{wordmark(cls, 150, "none")}
<div class="rule" style="width:640px;margin-top:34px;opacity:{rule_op}"></div></div>'''


SHOTS = {
    # name: (html, trim to content)
    'wordmark-light': (wordmark('d', 160, 'drop-shadow(0 2px 0 rgba(255,255,255,.9))'), True),
    'wordmark-dark': (wordmark('n', 160, 'drop-shadow(0 3px 0 #4A300C)'), True),
    'icon': (icon(1024), False),
    'icon-adaptive-bg': (icon(1024, fg=False), False),
    'icon-adaptive-fg': (icon(1024, bg=False, scale=0.62), False),
    'logo': (icon(256), False),
    'splash': (splash('d', 1), False),
    'splash-dark': (splash('n', 1), False),
    'splash-android12': (f'<div class="box" style="width:1024px;height:1024px"><span class="g n" style="font-size:420px;margin-top:40px">S</span></div>', False),
}

JS = r"""
const { chromium } = require('playwright');
const [html, out, names] = process.argv.slice(2);
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1400, height: 1400 }, deviceScaleFactor: 1 });
  await p.goto('file://' + html);
  await p.evaluate(() => document.fonts.ready);
  for (const n of JSON.parse(names)) {
    const el = await p.$('#' + n);
    await el.screenshot({ path: out + '/' + n + '.png', omitBackground: true });
  }
  await b.close();
})();
"""


def main():
    with tempfile.TemporaryDirectory() as tmp:
        page = ''.join(f'<div id="{n}" style="display:inline-block;vertical-align:top;line-height:0">{h}</div>' for n, (h, _) in SHOTS.items())
        html = os.path.join(tmp, 'brand.html')
        open(html, 'w').write(f'<!doctype html><html><head><meta charset="utf-8"><style>{CSS}</style></head><body>{page}</body></html>')
        js = os.path.join(tmp, 'shot.js')
        open(js, 'w').write(JS)
        subprocess.run(['node', js, html, tmp, json.dumps(list(SHOTS))], check=True)
        for n, (_, trim) in SHOTS.items():
            im = Image.open(os.path.join(tmp, n + '.png')).convert('RGBA')
            if trim:
                im = im.crop(im.getbbox())
            if n in ('icon', 'icon-adaptive-bg', 'logo'):
                im = im.convert('RGB')  # no transparency: iOS and the stores refuse it
            im.save(os.path.join(OUT, n + '.png'), optimize=True)
            print(n, im.size, os.path.getsize(os.path.join(OUT, n + '.png')))


if __name__ == '__main__':
    sys.exit(main())
