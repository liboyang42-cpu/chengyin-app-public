// 基准图里不许烤进「会随日子变」的相对时间。
//
// ★★★ 2026-08-20 实证:聊天基准图的 fixture 用了 2026-08-18(拍图那天是 08-19),
//   `fmtMessageTime` 把它渲成「昨天 20:10」。到了 08-20 同一份 fixture 变成
//   「8月18日 20:10」—— **基准图每天红一次,而红的原因和代码无关**。
//   会自己腐烂的证据比没有更坏:它训练人忽略红色。
//
// 判据不靠人眼:拿**真的格式化函数**,用两个相隔很远的「今天」各算一遍,
// 结果不一样就说明这个 fixture 落在了会漂的档位。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/feature/im/im_time.dart';
import 'package:chengyin_app/data/models/activity.dart';
import 'package:chengyin_app/data/models/merchant_customer.dart';
import 'package:chengyin_app/feature/orders/order_list_state.dart';

/// 从测试源码里抠出所有 `yyyy-MM-dd ...` 形式的日期字面量。
List<String> _dateLiterals(String code) => RegExp(
      r"'(\d{4}-\d{2}-\d{2}(?:[ T]\d{2}:\d{2}(?::\d{2})?)?)'",
    ).allMatches(code).map((RegExpMatch m) => m.group(1)!).toList();

void main() {
  test('★★★ 渲染相对时间的基准图,fixture 日期必须落在「稳定档」', () {
    // ⚠️ 判据必须**把格式化函数绑到真正用它的文件上**。
    //   第一版把三个函数都套在每个日期上,于是聊天页的 fixture 因为
    //   `relativeTime`(那页根本不渲染它)而误报 —— 门禁一过度触发就会
    //   被当成噪音关掉,那还不如没有。
    //
    //   ⚠️ 另一个发现:`relativeTime`(「N 天前 / N 个月前」)对**任何**日期都会漂,
    //   所以只要页面渲染它、且 now 取自系统时钟,基准图就必然是时钟依赖的。
    //   实测它**当前零调用方**(死函数),所以这里不纳入;
    //   将来谁接了它,必须让页面把 now 注入进来,否则这条门禁会立刻红。
    final Map<String, String Function(String, DateTime)> uses =
        <String, String Function(String, DateTime)>{
      // 聊天页渲的是气泡上方的时间分隔。
      'test/golden/pages_last_three_golden_test.dart':
          (String s, DateTime n) => fmtMessageTime(s, now: n),
    };

    // 两个相隔一年的「今天」。落在稳定档的日期,两次算出来必须一样。
    final DateTime a = DateTime(2026, 8, 20);
    final DateTime b = DateTime(2027, 8, 20);

    final List<String> bad = <String>[];
    int checked = 0;

    uses.forEach((String path, String Function(String, DateTime) fmt) {
      final File f = File(path);
      if (!f.existsSync()) return;
      for (final String lit in _dateLiterals(f.readAsStringSync())) {
        checked++;
        if (fmt(lit, a) != fmt(lit, b)) {
          bad.add('$path  「$lit」:${fmt(lit, a)} → ${fmt(lit, b)}');
        }
      }
    });

    expect(checked, greaterThan(3),
        reason: '只扫到 $checked 个日期字面量 —— 断言写法失效了');
    expect(bad, isEmpty,
        reason: '这些 fixture 的日期会随日子变,基准图会自己烂掉。\n'
            '改成一个远早于今天的固定日期(落进「M月d日」那一档):\n'
            '${bad.join('\n')}');
  });

  // ────────────────────────────────────────────────────────────────────────
  // 上面那条只管「渲染相对时间字符串」的基准图。2026-08-26 实证:还有第二种
  // 机制同样会让基准图自己烂掉 —— **用时钟推导状态**。订单页不渲染相对时间,
  // 它拿 startDate/endDate 跟 now 比,算出「未开始/进行中/已完成」,再据此渲染
  // 不同的状态标签和按钮组。fixture 用了 2026-08-25,到 08-26 那单从
  // 「未开始 + 申请退款/查看票夹」变成「已完成 + 查看详情」,3.09% 像素差,
  // 而代码一行没改。上面那条门禁的登记表里没有这个文件,所以没拦住。
  //
  // 判据同源:拿**真的状态函数**,用两个相隔一年的 now 各算一遍,不一样就是漂的。
  // 只扫 startDate/endDate 两个键 —— 它们是唯一流进状态判定的日期。
  // (不扫裸日期字面量:participateDate 是原样渲染的字符串,不参与状态判定,
  //  笼统扫会误伤它,而门禁一旦过度触发就会被当噪音关掉。)
  // ────────────────────────────────────────────────────────────────────────
  // 上面那条只管「渲染相对时间字符串」的基准图。2026-08-26 实证:还有第二种
  // 机制同样会让基准图自己烂掉 —— **用时钟推导状态**。订单页不渲染相对时间,
  // 它拿 startDate/endDate 跟 now 比,算出「未开始/进行中/已完成」,再据此渲染
  // 不同的状态标签和按钮组。fixture 用了 2026-08-25,到 08-26 那单从
  // 「未开始 + 申请退款/查看票夹」变成「已完成 + 查看详情」,3.09% 像素差,
  // 而代码一行没改。上面那条门禁的登记表里没有这个文件,所以没拦住。
  //
  // ⚠️ 沿用上面那条的登记表设计,不做全目录扫描。第一版就是扫了整个 test/golden,
  //   结果把 pages_buy / pages_club 的 startDate 也判成漂 —— 那两个页面渲染的是
  //   ActivityListPage 和俱乐部页,`lib/feature/activity` 里 DateTime.now() 零处,
  //   club 的基准图也没渲染那个唯一用 now 的 sheet。**它们的日期压根不流进状态判定**。
  //   过度触发的门禁会被当噪音关掉,那还不如没有。
  test('★★★ 用时钟推导状态的基准图,startDate/endDate 必须落在稳定档', () {
    // 文件 → 真正作用在它 fixture 上的状态函数。
    final Map<String, OrderListState Function(String, DateTime)> uses =
        <String, OrderListState Function(String, DateTime)>{
      // 订单页:summarizeOrderListState 拿 startDate/endDate 跟 now 比。
      'test/golden/pages_golden_test.dart': _orderStateAt,
    };

    final DateTime a = DateTime(2026, 8, 20);
    final DateTime b = DateTime(2027, 8, 20);

    final List<String> bad = <String>[];
    int checked = 0;

    uses.forEach((String path, OrderListState Function(String, DateTime) f) {
      final File file = File(path);
      if (!file.existsSync()) return;
      // 只扫 startDate/endDate:它们是唯一流进状态判定的日期。
      // participateDate 是原样渲染的字符串,不参与判定,扫它会误伤。
      for (final RegExpMatch m in RegExp(r"(?:startDate|endDate): '([^']+)'")
          .allMatches(file.readAsStringSync())) {
        final String lit = m.group(1)!;
        checked++;
        if (f(lit, a) != f(lit, b)) {
          bad.add('$path  「$lit」:${f(lit, a).name} → ${f(lit, b).name}');
        }
      }
    });

    expect(checked, greaterThan(4),
        reason: '只扫到 $checked 个 startDate/endDate —— 断言写法失效了');
    expect(bad, isEmpty,
        reason: '这些 fixture 的日期会随日子变,基准图会自己烂掉。\n'
            '页面只渲染 MM.dd HH:mm(不带年份),所以把年份改成 2099 '
            '像素不变、基线不用重拍:\n${bad.join('\n')}');
  });

  test('★★ 负控:这个门禁真能红', () {
    final DateTime a = DateTime(2026, 8, 20);
    final DateTime b = DateTime(2027, 8, 20);
    // 「昨天」那一档必然会漂 —— 门禁认不出它就是坏的。
    const String drifting = '2026-08-19 20:10:00';
    expect(fmtMessageTime(drifting, now: a) == fmtMessageTime(drifting, now: b),
        isFalse, reason: '相对日期不会漂?那这个门禁测的是空气');
    // 远期日期必须稳定。
    const String stable = '2026-01-15 20:10:00';
    expect(fmtMessageTime(stable, now: a), fmtMessageTime(stable, now: b));
    // relativeTime 是「N 天前」式的:**任何**日期都会漂。
    // 它当前零调用方,将来谁接了它,页面必须自己注入固定的 now。
    expect(relativeTime(stable, a), isNot(relativeTime(stable, b)));

    // 状态那条门禁的负控:近期日期必然漂,远期日期必然稳。
    expect(_orderStateAt('2026-08-25 19:00:00', a),
        isNot(_orderStateAt('2026-08-25 19:00:00', b)),
        reason: '近期日期不漂?那状态门禁测的是空气');
    expect(_orderStateAt('2099-08-25 19:00:00', a),
        _orderStateAt('2099-08-25 19:00:00', b));
  });
}

/// 把一个日期字面量放进「会走到日期比较那条分支」的订单里,算出它的状态。
/// registrationStatus:2(已支付)+ verificationStatus:0(未核销)是唯一
/// 会落到 `current.isAfter(end)` / `current.isBefore(start)` 的组合。
OrderListState _orderStateAt(String literal, DateTime now) =>
    summarizeOrderListState(
      MyRegistration.fromJson(<String, dynamic>{
        'id': 1,
        'ownerType': 2,
        'ownerId': 101,
        'registrationNo': 'R0',
        'registrationStatus': 2,
        'verificationStatus': 0,
        'cmsActivity': <String, dynamic>{
          'name': 'x',
          'productType': 2,
          'startDate': literal,
          'endDate': literal,
        },
      }),
      now: now,
    );
