"""由 docs/uscard/logo-source.webp 生成 logo 矢量资源与各平台图标。

输出:
- assets/logo.svg         完整 logo(气泡 + 圆环 + 指针)
- assets/logo_base.svg    不含指针(指针单独旋转用)
- assets/logo_needle.svg  只含指针,viewBox 以指针中心为原点,可绕中心旋转
- 各平台应用图标 PNG / ICO

依赖: numpy、opencv-python、Pillow。用法: python tool/gen_logo_assets.py
"""
import os
import sys

import cv2
import numpy as np
from PIL import Image

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


def main():
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

    make_icons(im)


def icon_image(src, size, bg=CREAM, scale=0.74):
    """奶油底 + 居中 logo 的方形图标(不透明,iOS 要求)。"""
    # 裁出气泡所在的正方形区域
    x, y, w, h = VB
    logo = src.crop((x, y, x + w, y + h))
    canvas = Image.new('RGBA', (size, size), bg + (255,))
    s = int(size * scale)
    logo = logo.resize((s, s), Image.LANCZOS)
    canvas.alpha_composite(logo, ((size - s) // 2, (size - s) // 2))
    return canvas


def make_icons(src):
    targets = []
    for dp, _, fs in os.walk(os.path.join(ROOT, 'android', 'app', 'src', 'main', 'res')):
        for f in fs:
            if f in ('ic_launcher.png', 'ic_launcher_modern.png'):
                targets.append(os.path.join(dp, f))
    targets += [os.path.join(ROOT, 'assets', 'images', f) for f in (
        'icon_default_dark_preview.png', 'icon_default_preview.png',
        'icon_modern_light_preview.png', 'icon_modern_preview.png')]
    for dp, _, fs in os.walk(os.path.join(ROOT, 'ios', 'Runner', 'Assets.xcassets')):
        targets += [os.path.join(dp, f) for f in fs if f.endswith('1024x1024.png')]
    for dp, _, fs in os.walk(os.path.join(ROOT, 'macos', 'Runner', 'Assets.xcassets')):
        targets += [os.path.join(dp, f) for f in fs if f.startswith('app_icon_') and f.endswith('.png')]
    for t in targets:
        size = Image.open(t).size[0]
        icon = icon_image(src, size)
        icon.convert('RGB' if 'ios' in t else 'RGBA').save(t)
    ico = os.path.join(ROOT, 'windows', 'runner', 'resources', 'app_icon.ico')
    big = icon_image(src, 256)
    big.save(ico, sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
    print(f'已更新 {len(targets)} 个 PNG + ico')


if __name__ == '__main__':
    sys.exit(main())
