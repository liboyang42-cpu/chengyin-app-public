#!/usr/bin/env python3
"""生成 Android 自适应图标的**前景层**(透明底 + 白色品牌 mark)。

★★ 自适应图标的前景**必须留安全边距**:
  系统按各家 launcher 的形状(圆/方/水滴/squircle)裁切,
  **只保证中心 66% 可见**(108dp 画布里的中心 72dp)。
  铺满的前景会被切掉边角 —— 那正是"图标看起来被啃了一口"的原因。
  所以这里把 mark 画在 **0.66 的内切区**里。

★ 前景必须**带 alpha**(与 App Store 的 1024 图标相反)——
  背景层由 <background> 提供,前景要透出它。

★ 五档密度按 108dp 换算:mdpi 108 / hdpi 162 / xhdpi 216 /
  xxhdpi 324 / xxxhdpi 432。

用法:  python3 tool/mkadaptive.py
"""
import math, struct, zlib, pathlib

RES = pathlib.Path('android/app/src/main/res')
WHITE = (0xFF, 0xFF, 0xFF, 255)
CLEAR = (0, 0, 0, 0)

DENSITIES = {
    'mipmap-mdpi': 108,
    'mipmap-hdpi': 162,
    'mipmap-xhdpi': 216,
    'mipmap-xxhdpi': 324,
    'mipmap-xxxhdpi': 432,
}

# ★ mark 只占画布的这么大 —— 留出裁切余量。
SAFE = 0.62


def render(size: int) -> bytes:
    cx = cy = size / 2
    m = size * SAFE            # mark 的直径范围
    r_out = m * 0.42
    r_in = m * 0.26
    px = [[CLEAR for _ in range(size)] for _ in range(size)]

    def in_ring(x, y):
        d = math.hypot(x - cx, y - cy)
        if not (r_in <= d <= r_out):
            return False
        ang = math.degrees(math.atan2(y - cy, x - cx))
        return not (-20 <= ang <= 35)

    def in_slash(x, y):
        b = cx + cy
        if abs(x + y - b) / math.sqrt(2) > m * 0.082:
            return False
        return math.hypot(x - cx, y - cy) <= r_out * 0.98

    for y in range(size):
        for x in range(size):
            xf, yf = x + 0.5, y + 0.5
            if in_ring(xf, yf) or in_slash(xf, yf):
                px[y][x] = WHITE

    raw = bytearray()
    for y in range(size):
        raw.append(0)
        for x in range(size):
            raw.extend(px[y][x])

    def ck(t, d):
        c = struct.pack('>I', len(d)) + t + d
        return c + struct.pack('>I', zlib.crc32(t + d) & 0xFFFFFFFF)

    # colorType 6 = RGBA(前景必须带 alpha)
    return (b'\x89PNG\r\n\x1a\n'
            + ck(b'IHDR', struct.pack('>IIBBBBB', size, size, 8, 6, 0, 0, 0))
            + ck(b'IDAT', zlib.compress(bytes(raw), 9))
            + ck(b'IEND', b''))


for d, size in DENSITIES.items():
    out = RES / d / 'ic_launcher_foreground.png'
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(render(size))
    print(f'  ✓ {d}/ic_launcher_foreground.png  {size}×{size}')
print('前景层已生成(透明底 + 白 mark,中心 62% 安全区内)。')
