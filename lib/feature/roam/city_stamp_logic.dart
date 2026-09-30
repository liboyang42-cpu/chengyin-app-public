/// 城市贴纸 / 今日城市签的纯函数(与小程序 `subpackageRoam/citystamp/index.js` 对齐)。
library;

/// 配文上限:§6.4 定的是 30 字带计数。
const int kCityStampCaptionMax = 30;

/// 条码:同一个签号画出来的条形永远一样 —— 它是签号的样子,不是随机装饰。
///
/// ★ 逐位对齐小程序那条 LCG(种子 = 77 + 签号 × 31),
///   两端对同一个签号必须画出同一张条形码。
///
/// ⚠️ 这里**照着 JS 的精度丢失**复刻,不是「等价改写」:JS 的
///   `s * 1103515245` 一旦越过 2^53 就被双精度舍入,再用 `&` 取 31 位;
///   而 Dart 的 int 是精确 64 位,直译会算出**另一串**条形 ——
///   同一个签号在小程序和 App 里长成两张,而条码正是签号的样子。
///   跨端逐位对拍钉在 test/feature/roam/city_stamp_logic_test.dart。
List<({int width, int gap})> cityStampBarcode(Object? serial) {
  int s = 77 + (_serialOf(serial) * 31);
  double rnd() {
    s = _jsToInt32(s.toDouble() * 1103515245 + 12345) & 0x7fffffff;
    return s / 0x7fffffff;
  }

  const List<int> widths = <int>[1, 1, 1, 2, 2, 3];
  return <({int width, int gap})>[
    for (int i = 0; i < 46; i++)
      (
        width: widths[(rnd() * 6).floor() % 6],
        gap: 1 + (rnd() * 2).floor() % 2,
      ),
  ];
}

/// 签号显示:`NO. 0001`(取签号后四位)。
String cityStampSerialLabel(Object? serial) {
  final int n = _serialOf(serial);
  return 'NO. ${(n % 10000).toString().padLeft(4, '0')}';
}

int _serialOf(Object? serial) =>
    serial is num ? serial.toInt() : int.tryParse('$serial') ?? 0;

/// JS `x & 0x7fffffff` 的完整语义:先 ToInt32(截断 → 对 2^32 取模 →
/// 解释为有符号),再按位与。中间那步必须经过 double —— 见上方注释。
int _jsToInt32(double value) {
  final int truncated = value.truncate();
  final int mod = truncated % 4294967296;
  return mod >= 2147483648 ? mod - 4294967296 : mod;
}

/// 后端 createTime(可能是 `2026-09-15T07:09:17`)→ `2026-09-15 07:09`。
String cityStampAtLabel(Object? createTime) {
  final String raw = (createTime ?? '').toString();
  if (raw.length < 16) return raw;
  return raw.substring(0, 16).replaceFirst('T', ' ');
}
