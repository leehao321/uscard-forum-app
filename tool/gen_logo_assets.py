"""由 docs/uscard/logo-source.webp 生成 logo 矢量资源与各平台图标。

输出:
- assets/logo.svg         完整 logo(气泡 + 圆环 + 指针)
- assets/logo_base.svg    不含指针(指针单独旋转用)
- assets/logo_needle.svg  只含指针,viewBox 以指针中心为原点,可绕中心旋转
- 各平台应用图标 PNG / ICO,Android 自适应图标的前景 / 单色矢量

图标按 assets/logo.svg 的矢量几何在目标尺寸上直接渲染(超采样抗锯齿),
不缩放位图。图标去掉气泡外框:绿色铺满,奶油色圆环和指针居中放大,
圆角交给系统(iOS / Android 自带遮罩)或在这里裁(macOS / Windows)。

依赖: numpy、opencv-python、Pillow。
用法: python tool/gen_logo_assets.py         重新描摹 SVG 并生成图标
      python tool/gen_logo_assets.py icons   只按现有 assets/logo.svg 生成图标
"""
import os
import re
import sys

import cv2
import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, 'docs', 'uscard', 'logo-source.webp')
GREEN, CREAM, GOLD = (23, 62, 49), (246, 239, 226), (195, 158, 91)
# 裁成正方形 viewBox,四周留白
VB = (187, 192, 880, 880)


def load():
    im = Image.open(SRC).convert('RGBA')
    a = np.array(im).astype(np.float32)
    return im, a


def soft_mask(m):
    """模糊后阈值,让轮廓亚像素平滑。"""
    m = cv2.GaussianBlur(m.astype(np.float32), (0, 0), 2.0)
    return (m > 0.5).astype(np.uint8)


def contours_path(mask, eps=0.45, holes=True):
    mode = cv2.RETR_CCOMP if holes else cv2.RETR_EXTERNAL
    cs, _ = cv2.findContours(mask, mode, cv2.CHAIN_APPROX_NONE)
    parts = []
    for c in cs:
        if cv2.contourArea(c) < 30:
            continue
        c = cv2.approxPolyDP(c, eps, True).reshape(-1, 2)
        parts.append('M' + 'L'.join(f'{x} {y}' for x, y in c) + 'Z')
    return ''.join(parts)


def trace():
    im, a = load()
    alpha = a[..., 3] > 128
    rgb = a[..., :3]

    def dist(col):
        return np.linalg.norm(rgb - np.array(col, np.float32), axis=2)

    d_green, d_cream, d_gold = dist(GREEN), dist(CREAM), dist(GOLD)
    nearest = np.argmin(np.stack([d_green, d_cream, d_gold]), axis=0)
    cream = alpha & (nearest == 1)
    gold = alpha & (nearest == 2)

    # 指针的奶油色部分:包含点 (500,700) 的连通域
    n, lab = cv2.connectedComponents(cream.astype(np.uint8))
    needle_label = lab[700, 500]
    assert needle_label != 0, '没找到指针奶油色部分'
    needle_cream = lab == needle_label
    ring_cream = cream & ~needle_cream

    # 指针金色部分:包含点 (730,520) 的连通域
    n2, lab2 = cv2.connectedComponents(gold.astype(np.uint8))
    needle_gold = lab2 == lab2[520, 730]

    # 指针中心孔: 以指针 bbox 内的绿色孤立连通域重心为旋转中心
    needle_all = needle_cream | needle_gold
    ys, xs = np.nonzero(needle_all)
    hole = np.zeros_like(needle_all)
    hole[ys.min():ys.max(), xs.min():xs.max()] = True
    hole &= alpha & (nearest == 0)
    n3, lab3 = cv2.connectedComponents(hole.astype(np.uint8))
    hl = lab3[610, 627]
    assert hl != 0, '没找到中心孔'
    hy, hx = np.nonzero(lab3 == hl)
    cx, cy = float(hx.mean()), float(hy.mean())
    hole_r = float(np.sqrt(len(hx) / np.pi))
    print(f'指针中心 ({cx:.1f},{cy:.1f}) 孔半径 {hole_r:.1f}')

    # 气泡轮廓 = 所有不透明像素(填满内部孔洞)
    bubble = alpha.astype(np.uint8)
    p_bubble = contours_path(soft_mask(bubble), holes=False)
    p_ring = contours_path(soft_mask(ring_cream))
    # 指针(含孔洞一起填成实心,孔洞用 circle 单独画)
    nc = (needle_cream | (lab3 == hl))
    p_ncream = contours_path(soft_mask(nc), holes=False)
    p_ngold = contours_path(soft_mask(needle_gold), holes=False)

    g = '#%02X%02X%02X' % GREEN
    c = '#%02X%02X%02X' % CREAM
    o = '#%02X%02X%02X' % GOLD
    vb = ' '.join(map(str, VB))
    head = f'<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="{vb}">'
    base = (f'<path fill="{g}" d="{p_bubble}"/>'
            f'<path fill="{c}" fill-rule="evenodd" d="{p_ring}"/>')
    needle = (f'<path fill="{c}" d="{p_ncream}"/>'
              f'<path fill="{o}" d="{p_ngold}"/>'
              f'<circle cx="{cx:.1f}" cy="{cy:.1f}" r="{hole_r:.1f}" fill="{g}"/>')
    w = lambda name, s: open(os.path.join(ROOT, 'assets', name), 'w', encoding='utf-8').write(s)
    w('logo_base.svg', head + base + '</svg>')
    w('logo.svg', head + base + needle + '</svg>')
    R = 250
    nvb = f'{cx - R:.1f} {cy - R:.1f} {2 * R} {2 * R}'
    w('logo_needle.svg',
      f'<svg xmlns="http://www.w3.org/2000/svg" width="500" height="500" viewBox="{nvb}">{needle}</svg>')
    print('needle center / viewbox', cx, cy, VB)


# ---------------- 图标 ----------------

SS = 8            # 超采样倍数(每像素 64 个采样点),边缘抗锯齿
ICON_FILL = 0.80  # 圆环(含尾巴)外接框长边占图标边长的比例
SHAPE_NAMES = ('bubble', 'ring', 'needle_cream', 'needle_gold', 'hole')
FOREGROUND = ('ring', 'needle_cream', 'needle_gold', 'hole')
MAC_INSET = 100 / 1024  # macOS 图标模板:1024 画布里 824 的圆角方块


def load_shapes(path=None):
    """读 assets/logo.svg:trace() 只输出 M/L/Z 折线 path 和一个 circle。"""
    path = path or os.path.join(ROOT, 'assets', 'logo.svg')
    s = open(path, encoding='utf-8').read()
    elems = re.findall(r'<(path|circle)([^>]*)/>', s)
    assert len(elems) == len(SHAPE_NAMES), f'logo.svg 结构变了: {len(elems)} 个图形'
    shapes = {}
    for name, (tag, attrs) in zip(SHAPE_NAMES, elems):
        a = dict(re.findall(r'([\w-]+)="([^"]*)"', attrs))
        if tag == 'circle':
            cx, cy, r = float(a['cx']), float(a['cy']), float(a['r'])
            t = np.linspace(0, 2 * np.pi, 720, endpoint=False)
            polys = [np.stack([cx + r * np.cos(t), cy + r * np.sin(t)], 1)]
            d = (f'M{cx - r:g} {cy:g}A{r:g} {r:g} 0 1 0 {cx + r:g} {cy:g}'
                 f'A{r:g} {r:g} 0 1 0 {cx - r:g} {cy:g}Z')
        else:
            d = a['d']
            polys = [np.array(re.findall(r'-?\d+(?:\.\d+)?', sp), float).reshape(-1, 2)
                     for sp in d.split('Z') if sp.strip()]
        shapes[name] = {'fill': a['fill'], 'evenodd': a.get('fill-rule') == 'evenodd',
                        'polys': polys, 'd': d}
    return shapes


def bbox(shapes, names):
    pts = np.concatenate([p for n in names for p in shapes[n]['polys']])
    return pts.min(0), pts.max(0)


def fit(shapes, names, size, fill):
    """把 names 的外接框长边缩放到 size*fill 并居中,返回 (scale, offset)。"""
    lo, hi = bbox(shapes, names)
    scale = size * fill / (hi - lo).max()
    return scale, size / 2 - (lo + hi) / 2 * scale


def coverage(shape, size, scale=1.0, offset=(0.0, 0.0)):
    """图形在 size×size 画布上的覆盖率(0~1),坐标 p' = p*scale + offset。"""
    big = size * SS
    m = np.zeros((big, big), bool)
    for p in shape['polys']:
        q = (p * scale + np.asarray(offset)) * SS
        layer = Image.new('1', (big, big))
        ImageDraw.Draw(layer).polygon([tuple(v) for v in q], fill=1)
        m = (m ^ np.array(layer)) if shape['evenodd'] else (m | np.array(layer))
    img = Image.fromarray(m.astype(np.uint8) * 255)
    return np.asarray(img.reduce(SS), np.float32) / 255


def hex_rgb(h):
    return np.array([int(h[i:i + 2], 16) for i in (1, 3, 5)], np.float32)


def render(shapes, names, size, scale, offset, bg):
    """按顺序把 names 里的图形叠到不透明底色 bg 上,返回 RGBA 图。"""
    rgb = np.empty((size, size, 3), np.float32)
    rgb[:] = bg
    for n in names:
        cov = coverage(shapes[n], size, scale, offset)[..., None]
        rgb = hex_rgb(shapes[n]['fill']) * cov + rgb * (1 - cov)
    alpha = np.full((size, size, 1), 255, np.float32)
    return Image.fromarray(np.dstack([rgb, alpha]).round().clip(0, 255).astype(np.uint8), 'RGBA')


def squircle(size, inset=0.0, n=5.0):
    """连续曲率圆角方块(超椭圆,近似 iOS / macOS 图标外形)。"""
    t = np.linspace(0, 2 * np.pi, 4096, endpoint=False)
    c, s = np.cos(t), np.sin(t)
    r = size / 2 - inset
    x = np.sign(c) * np.abs(c) ** (2 / n)
    y = np.sign(s) * np.abs(s) ** (2 / n)
    return {'polys': [np.stack([size / 2 + r * x, size / 2 + r * y], 1)], 'evenodd': False}


def icon_full(shapes, size):
    """铺满的方形图标:绿底 + 奶油色圆环和指针,不透明(iOS 要求),圆角由系统裁。"""
    return render(shapes, FOREGROUND, size, *fit(shapes, FOREGROUND, size, ICON_FILL), GREEN)


def icon_rounded(shapes, size, inset_ratio=0.0):
    """自己裁好圆角的图标(macOS / Windows / 旧版 Android 不会替应用裁)。"""
    inset = size * inset_ratio
    scale, offset = fit(shapes, FOREGROUND, size, ICON_FILL * (size - 2 * inset) / size)
    im = render(shapes, FOREGROUND, size, scale, offset, GREEN)
    mask = coverage(squircle(size, inset), size)
    im.putalpha(Image.fromarray((mask * 255).round().astype(np.uint8)))
    return im


def adaptive_xml(shapes, mono=False):
    """Android 自适应图标前景 / 单色层(108dp),内容落在直径 66dp 的安全圆内。"""
    lo, hi = bbox(shapes, FOREGROUND)
    c = (lo + hi) / 2
    pts = np.concatenate([p for n in FOREGROUND for p in shapes[n]['polys']])
    s = 33 / np.linalg.norm(pts - c, axis=1).max()
    tx, ty = 54 - c * s
    if mono:
        # 单色层只看透明度:指针两色合成一条 evenOdd 路径,中心孔镂空
        needle = ''.join(shapes[n]['d'] for n in ('needle_cream', 'needle_gold', 'hole'))
        paths = [('#FFFFFFFF', 'evenOdd', shapes['ring']['d']), ('#FFFFFFFF', 'evenOdd', needle)]
    else:
        paths = [(shapes[n]['fill'], 'evenOdd' if shapes[n]['evenodd'] else 'nonZero',
                  shapes[n]['d']) for n in FOREGROUND]
    body = ''.join(f'\n        <path\n            android:fillColor="{f}"\n'
                   f'            android:fillType="{t}"\n            android:pathData="{d}" />'
                   for f, t, d in paths)
    return ('<?xml version="1.0" encoding="utf-8"?>\n'
            '<!-- 由 tool/gen_logo_assets.py 生成,不要手改 -->\n'
            '<vector xmlns:android="http://schemas.android.com/apk/res/android"\n'
            '    android:width="108dp"\n    android:height="108dp"\n'
            '    android:viewportWidth="108"\n    android:viewportHeight="108">\n'
            f'    <group\n        android:scaleX="{s:.6f}"\n        android:scaleY="{s:.6f}"\n'
            f'        android:translateX="{tx:.4f}"\n        android:translateY="{ty:.4f}">{body}\n'
            '    </group>\n</vector>\n')


def make_icons():
    shapes = load_shapes()
    res = os.path.join(ROOT, 'android', 'app', 'src', 'main', 'res')
    jobs = []  # (路径, 生成函数, 输出模式)
    for dp, _, fs in os.walk(res):
        jobs += [(os.path.join(dp, f), icon_rounded, 'RGBA') for f in fs
                 if f in ('ic_launcher.png', 'ic_launcher_modern.png')]
    jobs += [(os.path.join(ROOT, 'assets', 'images', f), icon_full, 'RGBA') for f in (
        'icon_default_dark_preview.png', 'icon_default_preview.png',
        'icon_modern_light_preview.png', 'icon_modern_preview.png')]
    for dp, _, fs in os.walk(os.path.join(ROOT, 'ios', 'Runner', 'Assets.xcassets')):
        jobs += [(os.path.join(dp, f), icon_full, 'RGB') for f in fs if f.endswith('1024x1024.png')]
    mac = lambda sh, size: icon_rounded(sh, size, MAC_INSET)
    for dp, _, fs in os.walk(os.path.join(ROOT, 'macos', 'Runner', 'Assets.xcassets')):
        jobs += [(os.path.join(dp, f), mac, 'RGBA') for f in fs
                 if f.startswith('app_icon_') and f.endswith('.png')]
    cache = {}
    for path, fn, mode in jobs:
        size = Image.open(path).size[0]
        if (fn, size) not in cache:
            cache[fn, size] = fn(shapes, size)
        cache[fn, size].convert(mode).save(path)

    # 每个尺寸单独按矢量渲染,不让 Pillow 从 256 缩小
    sizes = [16, 24, 32, 48, 64, 128, 256]
    frames = [icon_rounded(shapes, s) for s in sizes]
    ico = os.path.join(ROOT, 'windows', 'runner', 'resources', 'app_icon.ico')
    frames[-1].save(ico, sizes=[(s, s) for s in sizes], append_images=frames[:-1])

    drawable = os.path.join(res, 'drawable')
    xml = lambda path, text: open(path, 'w', encoding='utf-8', newline='\n').write(text)
    for f in ('ic_launcher_foreground.xml', 'ic_launcher_modern_foreground.xml',
              'ic_launcher_modern_light_foreground.xml'):
        xml(os.path.join(drawable, f), adaptive_xml(shapes))
    for path in (os.path.join(drawable, 'ic_launcher_monochrome.xml'),
                 os.path.join(drawable, 'ic_launcher_modern_monochrome.xml'),
                 os.path.join(res, 'drawable-night', 'ic_launcher_monochrome.xml')):
        xml(path, adaptive_xml(shapes, mono=True))
    print(f'已更新 {len(jobs)} 个 PNG、ico({len(sizes)} 个尺寸)、6 个 Android 矢量')


def main(argv):
    if argv[1:2] != ['icons']:
        trace()
    make_icons()


if __name__ == '__main__':
    sys.exit(main(sys.argv))
