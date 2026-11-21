from io import BytesIO
from pathlib import Path
import fitz
from PIL import Image, ImageDraw

root = Path(__file__).resolve().parents[2] / 'build' / 'branding'
root.mkdir(parents=True, exist_ok=True)
ink = '#3726CF'
paper = '#FFFAEF'
lime = '#DDF34D'
upper = ('M55.8 52.9 Q56.7 46.5 63 45.9 L210.8 32.4 '
         'Q219 31.7 218 39.7 L208.3 117.4 L44.4 130.5 Z')
burst = ('M153 46 L163 69 L193 56 L178 78 L196 93 L167 93 L150 114 '
         'L144 96 L111 105 L126 86 L100 73 L134 72 Z')
left = 'M42.7 144.3 L98.8 139.8 L89.7 213.1 L39.9 217.3 Q32 218 33 210.4 Z'
slashes = ('M51 176 L72 152 L82 151 L60 176 Z '
           'M48 200 L78 166 L88 165 L58 200 Z')
right = 'M113.8 138.6 L206.6 131.1 L200.3 181.2 L174.8 205.8 L104.9 211.8 Z'
turn = 'M174.8 205.8 L178.1 184.9 Q178.4 182 181.8 181.7 L200.3 181.2 Z'


def svg(contents):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" '
            f'viewBox="0 0 256 256">{contents}</svg>')


def path(data, fill):
    return f'<path d="{data}" fill="{fill}" fill-rule="evenodd"/>'


def draw_art(mode, turned):
    background = ''
    primary = ink
    lower = ink
    fold = '#A7A0FE'
    star = ''
    if mode == 'ink':
        background = f'<rect width="256" height="256" rx="57" fill="{ink}"/>'
        primary, lower, fold = paper, lime, '#B3CA22'
    if mode == 'paper':
        background = f'<rect width="256" height="256" rx="57" fill="{paper}"/>'
        star = path(burst, lime)
    return svg(background + path(upper + ' ' + burst, primary) + star
               + path(left + ' ' + slashes, primary) + path(right, lower)
               + (path(turn, fold) if turned else ''))


def render(source, size):
    with fitz.open(stream=source.encode(), filetype='svg') as doc:
        page = doc[0]
        zoom = size / page.rect.width
        pixels = page.get_pixmap(matrix=fitz.Matrix(zoom, zoom), alpha=True)
        return Image.open(BytesIO(pixels.tobytes('png'))).convert('RGBA')


image = Image.new('RGB', (1060, 752), '#F2F1F8')
canvas = ImageDraw.Draw(image)
for column, mode in enumerate(('transparent', 'ink', 'paper')):
    for row, folded in enumerate((False, True)):
        x = 29 + column * 348
        y = 18 + 374 * row
        art = render(draw_art(mode, folded), 258)
        image.paste(art, (x + 22, y), art)
        for index, size in enumerate((16, 20, 24, 32, 48, 64)):
            sample = art.resize((size, size), Image.Resampling.LANCZOS)
            image.paste(sample, (x + index * 50, y + 277), sample)
        canvas.text((x, y + 348), f'{mode} {"fold" if folded else ""}', fill=ink)
image.save(root / 'draft.png')
