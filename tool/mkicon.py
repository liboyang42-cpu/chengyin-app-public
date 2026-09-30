"""从 128px 的品牌 mark **重建**(不是放大)1024×1024 App 图标。

用法:  python3 tool/mkicon.py && bash tool/make_app_icons.sh /tmp/app_icon_1024.png


★ 不是把 128 放大 —— 那会糊。这里按几何关系**重画**:
  外框是一个切角矩形(左上/右下切),里面一个开口圆环 + 一道斜杠。
  颜色取自原图主色 #7C5CFF。

★ App Store 要求:1024×1024、**无 alpha**、无圆角(系统自己切)。
  所以底色铺满,不留透明。
"""
import math, struct, zlib

S = 1024
PURPLE = (0x7C, 0x5C, 0xFF)
WHITE = (0xFF, 0xFF, 0xFF)

# ★ 画布铺满**紫色**,不留白边。
#   App Store 图标是整块方图(系统自己切圆角),四周留白会让图标
#   在桌面上比别人小一圈,看起来像没做好。
px = [[PURPLE for _ in range(S)] for _ in range(S)]

def inside_chamfer(x, y):
    """切角矩形:原 mark 的外形。铺满版里它用来**放大 mark 本身**。"""
    m = S * 0.10
    if not (m <= x <= S - m and m <= y <= S - m):
        return False
    cut = S * 0.30
    # 左上切角
    if (x - m) + (y - m) < cut:
        return False
    # 右下切角
    if (S - m - x) + (S - m - y) < cut:
        return False
    return True

cx = cy = S / 2
R_OUT = S * 0.315
R_IN = S * 0.195

def in_ring(x, y):
    d = math.hypot(x - cx, y - cy)
    if not (R_IN <= d <= R_OUT):
        return False
    # 开口:右下方向约 55° 的缺口
    ang = math.degrees(math.atan2(y - cy, x - cx))  # -180..180
    if -20 <= ang <= 35:
        return False
    return True

def in_slash(x, y):
    """左下→右上的一道斜杠,穿过圆环开口。"""
    # 直线 y = -x + b,取带宽
    b = cx + cy
    dist = abs(x + y - b) / math.sqrt(2)
    if dist > S * 0.062:
        return False
    d = math.hypot(x - cx, y - cy)
    return d <= R_OUT * 0.98

# ★ 反过来画:整块紫底,把**环与斜杠**挖成白色。
#   切角矩形只用来限定 mark 的作用范围(超出它的地方保持纯紫底)。
for y in range(S):
    for x in range(S):
        xf, yf = x + 0.5, y + 0.5
        if in_ring(xf, yf) or in_slash(xf, yf):
            px[y][x] = WHITE

# 写 PNG(色彩类型 2 = truecolor,无 alpha)
raw = bytearray()
for y in range(S):
    raw.append(0)
    for x in range(S):
        raw.extend(px[y][x])

def chunk(t, d):
    c = struct.pack('>I', len(d)) + t + d
    return c + struct.pack('>I', zlib.crc32(t + d) & 0xFFFFFFFF)

png = b'\x89PNG\r\n\x1a\n'
png += chunk(b'IHDR', struct.pack('>IIBBBBB', S, S, 8, 2, 0, 0, 0))
png += chunk(b'IDAT', zlib.compress(bytes(raw), 9))
png += chunk(b'IEND', b'')
open('/tmp/app_icon_1024.png', 'wb').write(png)
print('written', len(png), 'bytes')
