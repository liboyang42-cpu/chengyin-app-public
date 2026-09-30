// 门禁:金额与方向字段不许 `?? 0`。
//
// 本轮修的 11 个 bug 里,**6 个是同一条规则的不同实例** ——
// 把「没有这个信息」和「零 / 否」合并了:
//   · price ?? 0        → 票价拿不到,页面渲成「**免费**」
//   · price ?? 0(购物车)→ 小计 ¥0.00,合计静默少算
//   · changeType ?? 0   → 一笔进账显示成扣款(两个模型各犯一次)
//   · myIncome ?? 0     → 「待结算」显示成「赚了 0 元」
//   · balance ?? 0      → 「余额没取到」显示成「你没有钱」
//
// 这不是巧合:`?? 0` 在 Dart 里写起来太顺手,而金额字段恰恰是**最不能猜**的 ——
// 猜错的方向永远是「让用户以为不要钱 / 以为被扣了 / 以为没钱」。
// 逐个修修不完,得有一道闸。
//
// 范围**刻意很窄**:只管字段名像钱或像方向的。计数、状态、下标、分页兜 0 都是对的,
// 一刀切会让这道闸变成噪音,然后被人关掉。
//
// 负控:给任意模型加一行 `price: ... ?? 0`,本测试必须红。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 钱味字段名。
/// ⚠️ `mileage`/`distance` 这类**不在**表里:里程不是钱,新用户确实是 0 公里。
/// 判据是「拿不到时显示 0 会不会造成金钱误解」,不是「是不是数值」。
const String _kMoney =
    r'(price|amount|balance|fee|income|payable|refund|settle\w*|deduct\w*'
    r'|subtotal|revenue|payout|cash|money|yuan)';

/// 方向字段名 —— 它们决定「加还是减」,猜错就是符号反了。
const String _kDirection = r'(changeType|isIncome|direction)';

/// 已判定「这里兜 0 是对的」的豁免。每条都必须写清**为什么**。
/// ⚠️ 往里加之前先自问:这个字段拿不到时,显示成 0 会不会让用户产生
///    「不要钱 / 被扣了 / 没有钱」这三种误解之一?会,就不该豁免。
const Map<String, String> _kAllowed = <String, String>{
  'lib/data/models/asset_record.dart:changeBalance':
      '流水的变动额:这条记录存在就说明发生过变动,金额缺席是后端异常,'
      '兜 0 只影响这一行的数值展示,不会让用户误判方向(方向由 isIncome 判,'
      '而 isIncome 已经不吃 changeType 的 0 兜底了)',
  'lib/data/models/asset_record.dart:afterBalance':
      '同上,且它只是辅助展示的「余额快照」,不参与任何计算',
};

void main() {
  test('金额与方向字段不许 ?? 0', () {
    final RegExp pattern = RegExp(
      r'\b\w*' '($_kMoney|$_kDirection)' r'\w*\s*:\s*.*\?\?\s*0',
      caseSensitive: false,
    );

    final List<String> offenders = <String>[];
    final Set<String> usedAllowances = <String>{};
    int scanned = 0;

    for (final FileSystemEntity e
        in Directory('lib/data').listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      scanned++;
      final List<String> lines = e.readAsLinesSync();
      for (int i = 0; i < lines.length; i++) {
        final String code = lines[i].split('//').first;
        final RegExpMatch? m = pattern.firstMatch(code);
        if (m == null) continue;

        // 取字段名做豁免键 —— 用行号会在文件一改动就失效
        final String field =
            RegExp(r'(\w+)\s*:').firstMatch(code.trimLeft())?.group(1) ?? '?';
        final String key = '${e.path}:$field';
        if (_kAllowed.containsKey(key)) {
          usedAllowances.add(key);
          continue;
        }
        offenders.add('${e.path}:${i + 1}  $field  →  ${code.trim()}');
      }
    }

    expect(scanned, greaterThanOrEqualTo(30),
        reason: '只扫到 $scanned 个 lib/data 文件,太少了 —— 目录变了?');

    // ★ 豁免会腐烂:字段改名或删掉后,条目还留着,下次同名字段就被白白放过。
    final Set<String> stale =
        _kAllowed.keys.toSet().difference(usedAllowances);
    expect(stale, isEmpty,
        reason: '这些豁免已经不命中任何代码了,请从 _kAllowed 删掉:\n'
            '${stale.join('\n')}');

    expect(offenders, isEmpty,
        reason: '金额/方向字段拿不到时兜 0,会让用户以为「不要钱 / 被扣了 / 没有钱」。\n'
            '改成可空 + 一个说清三态的 getter(参考 ActivityTicket.priceText、'
            'CartItem.hasPrice、PointsRecord.isIncome):\n'
            '${offenders.join('\n')}');
  });
}
