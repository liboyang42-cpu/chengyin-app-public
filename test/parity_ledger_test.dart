import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// 对齐台账:**哪些小程序页面故意不在 App 造,以及为什么**。
///
/// ★ 为什么要写成测试而不是文档:按「小程序页数 vs App 路由数」统计缺口时,
///   这些页会被反复算成"还没做"。我自己就用页数统计过好几轮 ——
///   把判断固化在这里,下次再统计能直接看到结论,不必重新调查一遍。
///
/// ⚠️ 这条**不是门禁**(它不判红任何代码),是一份可执行的备忘。
///   每条都记了核实日期与依据,过期了就该重新核。
void main() {
  test('故意不造的小程序页 —— 逐条记明原因', () {
    const decisions = <String, String>{
      // 2026-08-19 核实:12 行 wxml,零后端端点,唯一动作是跳 /subpackageMember/tixian。
      'pages/coop/withdraw':
          '「提现方式已调整」告知壳页(唯一动作=弹平台客服微信,不再跳银行卡表单);'
          'App 的 /withdrawal 入口按 R10 同样只弹客服号弹窗',
      // 2026-08-19 核实:4 行 wxml,onLoad 立即转向,本页不渲染任何内容。
      'pages/coop/withdraw/records':
          '历史深链转向壳;App 已有 /withdrawal-records',
      // 2026-08-19 核实:空目录,没有任何文件。
      'pages/topic/merchantapply2': '空目录,小程序侧本就没有这个页面',
      // 2026-08-19 核实:数据同源(relation-home 一次返回 relations + discovery.merchants),
      // 分成两页只是小程序的导航惯例,不是契约。
      'pages/merchant/discover':
          '与 pages/merchant/relation 数据同源,App 合成一页两档(/merchant/relations)',
    };

    // 这条断言只保证台账本身没被清空 —— 真正的价值在上面的注释里。
    expect(decisions.length, greaterThanOrEqualTo(4),
        reason: '台账被清空了?每条决定都该留着,否则下次统计缺口会重新把它们算进去');
    for (final MapEntry<String, String> e in decisions.entries) {
      expect(e.value.trim(), isNotEmpty, reason: '${e.key} 缺少不造的理由');
    }
  });

  test('App 路由数应随对齐推进而增长(下限锚点)', () {
    final src = File('lib/core/router/app_router.dart').readAsStringSync();
    final count = RegExp(r"path: '/").allMatches(src).length;
    // ★ 只设**下限**:防止有人整块删掉路由而没人发现。
    //   不设上限 —— 那会在每次加页时逼人改测试,变成纯粹的噪音。
    expect(count, greaterThanOrEqualTo(60),
        reason: '路由数掉到 60 以下,是不是有整块被误删?当前应在 65 左右');
  });
}
