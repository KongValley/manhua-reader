from io import BytesIO
from pathlib import Path
import sys

import fitz
from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont
from PIL import Image


INK = '#3726CF'
PAPER = '#FFFAEF'
LIME = '#DDF34D'
CREASE = '#ABA2FF'
TYPE = '#211840'
INDIGO = '#2C1EB6'

TOP = ('M55.8 52.9 Q56.7 46.5 63 45.9 L210.8 32.4 '
       'Q219 31.7 218 39.7 L208.3 117.4 L44.4 130.5 Z')
BURST = ('M153 46 L163 69 L193 56 L178 78 L196 93 L167 93 '
         'L150 114 L144 96 L111 105 L126 86 L100 73 L134 72 Z')
LEFT = 'M42.7 144.3 L98.8 139.8 L89.7 213.1 L39.9 217.3 Q32 218 33 210.4 Z'
SPEED = 'M51 176 L72 152 L82 151 L60 176 Z M48 200 L78 166 L88 165 L58 200 Z'
RIGHT = 'M113.8 138.6 L206.6 131.1 L200.3 181.2 L174.8 205.8 L104.9 211.8 Z'
FOLD = 'M174.8 205.8 L178.1 184.9 Q178.4 182 181.8 181.7 L200.3 181.2 Z'


def document(title, content, width, height, view_box=None):
    view_box = view_box or f'0 0 {width} {height}'
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}"\n'
            f'     viewBox="{view_box}" role="img" aria-labelledby="title">\n'
            f'  <title id="title">{title}</title>\n{content}\n</svg>\n')


def logo(monochrome=False):
    if monochrome:
        return (f'  <g fill="{TYPE}" fill-rule="evenodd">\n'
                f'    <path d="{TOP} {BURST}"/>\n'
                f'    <path d="{LEFT} {SPEED}"/>\n'
                f'    <path d="{RIGHT}"/>\n  </g>')
    return (f'  <g fill="{INK}">\n'
            f'    <path d="{TOP}"/>\n'
            f'    <path d="{LEFT} {SPEED}" fill-rule="evenodd"/>\n'
            f'    <path d="{RIGHT}"/>\n'
            f'    <path d="{BURST}" fill="{LIME}"/>\n'
            f'    <path d="{FOLD}" fill="{CREASE}"/>\n  </g>')


def tile_content():
    return f'  <rect width="256" height="256" rx="57" fill="{PAPER}"/>\n{logo()}'


def place(content, x, y, scale=1.0):
    return (f'  <g transform="translate({x:.4f} {y:.4f}) scale({scale:.6f})">\n'
            + '\n'.join('  ' + line for line in content.splitlines()) + '\n  </g>')


font_dir = Path('C:/Windows/Fonts')
heavy = TTFont(font_dir / 'SourceHanSansSC-Heavy.otf')
medium = TTFont(font_dir / 'SourceHanSansSC-Medium.otf')
latin = TTFont(font_dir / 'SourceSans3-Regular.ttf')


def lettering(text, font, height, color, tracking=0, slant=0, squeeze=1):
    glyphs = font.getGlyphSet()
    cmap = font.getBestCmap()
    commands = SVGPathPen(glyphs)
    bounds = BoundsPen(glyphs)
    cursor = 0
    for character in text:
        glyph = glyphs[cmap[ord(character)]]
        transform = (1, 0, slant, -1, cursor, 0)
        glyph.draw(TransformPen(commands, transform))
        glyph.draw(TransformPen(bounds, transform))
        cursor += glyph.width + tracking
    x_min, y_min, x_max, y_max = bounds.bounds
    sy = height / (y_max - y_min)
    sx = sy * squeeze
    width = (x_max - x_min) * sx
    element = (f'  <path fill="{color}" transform="scale({sx:.8f} {sy:.8f}) '
               f'translate({-x_min:.4f} {-y_min:.4f})"\n'
               f'        d="{commands.getCommands()}"/>')
    return element, width


def lockup():
    chinese, width = lettering('漫阅', heavy, 109, TYPE, tracking=-6, slant=0.060, squeeze=0.95)
    english, english_width = lettering('MANHUA READER', latin, 17.6, INK, tracking=110)
    advance = max(width, english_width + 4)
    content = '\n'.join((place(logo(), -8, -2),
                         place(chinese, 246, 49),
                         place(english, 248, 180)))
    return content, round(246 + advance + 22), 248


def render(svg, size, supersample=2, mode='RGBA'):
    with fitz.open(stream=svg.encode('utf-8'), filetype='svg') as doc:
        page = doc[0]
        scale = size[0] * supersample / page.rect.width
        pixmap = page.get_pixmap(matrix=fitz.Matrix(scale, scale), alpha=mode == 'RGBA')
        pixels = Image.open(BytesIO(pixmap.tobytes('png'))).convert(mode)
    expected = (size[0] * supersample, size[1] * supersample)
    if pixels.size != expected:
        raise ValueError(f'Render has size {pixels.size}, expected {expected}')
    return pixels.resize(size, Image.Resampling.LANCZOS)


def showcase(lockup_content, lockup_width):
    items = [
        '  <rect width="1440" height="810" fill="#FFFFFF"/>',
        f'  <rect x="904" width="536" height="810" fill="{INDIGO}"/>',
        place(lockup_content, (904 - 1.37 * lockup_width) / 2, 229, 1.37),
    ]
    name, name_width = lettering('应用图标', medium, 21, PAPER, tracking=95)
    items.append(place(name, 1172 - name_width / 2, 100))
    items.append(place(tile_content(), 1003, 165, 338 / 256))
    items.append('  <path d="M970 556 H1374" stroke="#FFFFFF" stroke-opacity="0.22"/>')
    for center, size in zip((1019, 1121, 1223, 1325), (24, 32, 48, 64)):
        items.append(place(tile_content(), center - size / 2, 630 - size / 2, size / 256))
        label, width = lettering(f'{size} px', latin, 14, '#E5DFFF', tracking=16)
        items.append(place(label, center - width / 2, 694))
    return document('漫阅标志与应用图标', '\n'.join(items), 1440, 810)


def export(folder):
    contents, width, height = lockup()
    art = {
        'logo': document('漫阅标志', logo(), 1024, 1024, '17 17 217 217'),
        'logo-monochrome': document('漫阅单色标志', logo(monochrome=True), 1024, 1024,
                                    '17 17 217 217'),
        'app-icon': document('漫阅应用图标', tile_content(), 1024, 1024, '0 0 256 256'),
        'logo-lockup': document('漫阅 · Manhua Reader', contents, width, height),
    }
    folder.mkdir(parents=True, exist_ok=True)
    for name, vector in art.items():
        (folder / f'{name}.svg').write_text(vector, encoding='utf-8', newline='\n')
    for name in ('logo', 'app-icon'):
        render(art[name], (1024, 1024)).save(folder / f'{name}.png', optimize=True)
    render(art['logo-lockup'], (width * 2, height * 2)).save(folder / 'logo-lockup.png', optimize=True)
    render(showcase(contents, width), (1440, 810), mode='RGB').save(folder / 'preview.png', optimize=True)


if __name__ == '__main__':
    export(Path(sys.argv[1]))
