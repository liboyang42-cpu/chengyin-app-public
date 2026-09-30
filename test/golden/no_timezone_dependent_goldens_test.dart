// 基准图里不许烤进「换个时区就变」的日期。
//
// ★★★ 2026-08-25 实证:把 golden 放上 macOS CI 后,page_roam_history 与
//   page_roam_session 两张红了。基线拍摄机是 UTC-7,runner 是 UTC,而
//   fixture 的 ts = 2025-08-18 06:53 UTC —— 在 UTC-7 掉回前一天,于是
//   基线写着「17日 周日」、CI 渲出「18日 周一」。代码没错,fixture 会漂。
//
// 这跟 no_clock_dependent_goldens_test 是两根轴:那条管「随日子变」,
// 这条管「随时区变」。判据同样不靠人眼:同一个 ts,在开发/CI 现实会遇到的
// 时区区间里各算一次日历日,不一致就是不稳的 fixture。
//
// 稳定写法:把 fixture 的时刻放在**当天正午 UTC**,这样 UTC-8(美西)到
// UTC+9(日韩)全落在同一日历日。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 现实会遇到的时区区间:美西到日韩,含中国 UTC+8。
const List<int> _offsets = <int>[-8, -7, -5, 0, 1, 8, 9];

/// 只抠**真的被当成时刻用**的毫秒时间戳:`ts: 123…` 与
/// `fromMillisecondsSinceEpoch(123…)`。
///
/// ⚠️ 不要退回成「扫所有 12 位数字」:那样会把二维码载荷里的
/// `v1.9001.activity.1786000000000.n7.sig` 这类 token 也算进来。
/// 门禁一过度触发就会被当成噪音关掉,那还不如没有。
List<int> _epochMsLiterals(String code) => <int>{
      for (final RegExpMatch m in RegExp(
        r'(?:\bts:\s*|fromMillisecondsSinceEpoch\(\s*)(1[5-9]\d{11})\b',
      ).allMatches(code))
        int.parse(m.group(1)!),
    }.toList();

/// 带**显式时区标记**的 ISO 字符串字面量('…Z' / '…+08:00' / '…-07:00')。
///
/// ★★ 2026-09-09 补:原来这条门禁只认 epoch 毫秒(`ts:` / `fromMillisecondsSinceEpoch`),
///   **ISO 字符串是它的盲区**。page_free_explore_detail 的 fixture 写的是
///   `validEnd: '2026-12-31T00:00:00Z'`,渲染代码当时用 `toLocal()` ——
///   在这台 PDT 机器上烤出来的基线写着「有效期至 12/30」,门禁一声没吭。
///   带时区标记的字符串同样是「一个绝对时刻」,判据与 epoch 那支完全一样。
///
/// ⚠️ 只收带标记的:裸串(`'2026-08-19T10:20:00'`)语义是**中国墙上时间**、
///   没有绝对时刻可言,拿它算时区漂移是无中生有。
List<int> _isoInstantLiterals(String code) => <int>{
      for (final RegExpMatch m in RegExp(
        r"'(\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}(?::\d{2})?(?:\.\d+)?"
        r"(?:[zZ]|[+-]\d{2}:?\d{2}))'",
      ).allMatches(code))
        if (DateTime.tryParse(m.group(1)!) != null)
          DateTime.parse(m.group(1)!).millisecondsSinceEpoch,
    }.toList();

/// 该时间戳在 [_offsets] 里是否始终落在同一个日历日。
bool _isTimezoneStable(int ms) {
  final DateTime utc = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  final Set<String> days = _offsets
      .map((int off) {
        final DateTime local = utc.add(Duration(hours: off));
        return '${local.year}-${local.month}-${local.day}';
      })
      .toSet();
  return days.length == 1;
}

void main() {
  test('负控:UTC 午夜附近的 ts 必须被判为不稳', () {
    // 2025-08-18 06:53 UTC —— 就是当初漏网的那个值。
    expect(_isTimezoneStable(1755500000000), isFalse);
    // 2025-08-18 12:00 UTC —— 正午,现实时区区间内同一天。
    expect(_isTimezoneStable(1755518400000), isTrue);
  });

  test('负控:带时区标记的 ISO 字符串既要抠得出来,也要判得出稳不稳', () {
    // 抠不出来的话下面那条整条门禁就是空转 —— 先证明提取器真的在工作。
    expect(
      _isoInstantLiterals("validEnd: '2026-12-31T00:00:00Z',"),
      hasLength(1),
    );
    expect(_isoInstantLiterals("'2026-12-31T20:00:00+08:00'"), hasLength(1));
    // 裸串没有绝对时刻,不收。
    expect(_isoInstantLiterals("joinTime: '2026-08-19T10:20:00',"), isEmpty);
    // 就是那个漏网的值:UTC 午夜 ⇒ 美西还在前一天。
    expect(
      _isTimezoneStable(_isoInstantLiterals("'2026-12-31T00:00:00Z'").single),
      isFalse,
    );
    // 挪到当天正午 UTC ⇒ 美西到日韩同一天。
    expect(
      _isTimezoneStable(_isoInstantLiterals("'2026-12-31T12:00:00Z'").single),
      isTrue,
    );
  });

  test('★★ 渲染日期的基准图,fixture 时间戳必须落在时区稳定档', () {
    final List<String> bad = <String>[];
    for (final FileSystemEntity e
        in Directory('test/golden').listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('_test.dart')) continue;
      // 本文件内含负控用的「坏」字面量,跳过自己。
      if (e.path.endsWith('no_timezone_dependent_goldens_test.dart')) continue;
      final String code = e.readAsStringSync();
      for (final int ms in <int>[
        ..._epochMsLiterals(code),
        ..._isoInstantLiterals(code),
      ]) {
        if (!_isTimezoneStable(ms)) {
          final DateTime u =
              DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
          bad.add('${e.path}: $ms (${u.toIso8601String()} UTC)');
        }
      }
    }
    expect(
      bad,
      isEmpty,
      reason:
          '这些 fixture 换个时区就渲染成另一天,基准图会在别的机器上假红。\n'
          '把时刻挪到当天正午 UTC 再重拍基线。\n${bad.join('\n')}',
    );
  });
}
