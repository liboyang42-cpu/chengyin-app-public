#!/usr/bin/env python3
"""生成 iOS 启动图:**黑底 + 居中白色品牌 mark**。

★ 底色必须与 App 首屏一致(CyTokens.bgPage = #000000)——
  启动屏原来是纯白,冷启动会先白闪一下再跳黑,那一下很显眼。
  storyboard 的 backgroundColor 也已同步改黑,两处都要对。

★ mark 用**白色**而不是紫色:紫色 mark 压在黑底上对比度不够
  (#7C5CFF on #000 ≈ 4.3:1),而启动图只闪一瞬,要一眼看清。

★ 尺寸按 storyboard 的 contentMode="center" —— 图不缩放,按点尺寸给三档:
  1x=160pt / 2x=320px / 3x=480px。给大了会溢出屏幕边缘。

用法:  python3 tool/mklaunch.py
"""
import math, struct, zlib, pathlib

BLACK = (0, 0, 0)
WHITE = (0xFF, 0xFF, 0xFF)
OUT = pathlib.Path('ios/Runner/Assets.xcassets/LaunchImage.imageset')


def render(size: int) -> bytes:
    cx = cy = size / 2
    r_out = size * 0.42
    r_in = size * 0.26
    px = [[BLACK for _ in range(size)] for _ in range(size)]

    def in_ring(x, y):
        d = math.hypot(x - cx, y - cy)
        if not (r_in <= d <= r_out):
            return False
        ang = math.degrees(math.atan2(y - cy, x - cx))
        return not (-20 <= ang <= 35)          # 右下开口

    def in_slash(x, y):
        b = cx + cy
        if abs(x + y - b) / math.sqrt(2) > size * 0.082:
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

    return (b'\x89PNG\r\n\x1a\n'
            + ck(b'IHDR', struct.pack('>IIBBBBB', size, size, 8, 2, 0, 0, 0))
            + ck(b'IDAT', zlib.compress(bytes(raw), 9))
            + ck(b'IEND', b''))


for name, size in (('LaunchImage.png', 160),
                   ('LaunchImage@2x.png', 320),
                   ('LaunchImage@3x.png', 480)):
    (OUT / name).write_bytes(render(size))
    print(f'  ✓ {name}  {size}×{size}')
print('启动图已生成。⚠️ storyboard 的 backgroundColor 也必须是黑 —— 两处都对才不会闪。')
