// 承接档案页。
//
// ★★ `coopOpen` 此前 App 侧**完全没有** —— 商家无法让自己出现在合作发现里
//   (/api/club/merchants 与 /merchant/relation-home 都强制 coopOpen=1 才捞)。
//   也就是说:商家在 App 里做完所有事,仍然一个合作邀约都收不到,
//   而且看不出为什么。
//
// ★★ 还没读回来时**不预设 true/false**:
//   预设成关 → 商家以为自己没开;
//   预设成开 → 更糟:界面说着"已开放"而实际没有,他会一直等不来邀约。
//
// ★ 后端只 set 六个字段,页面也只放这六项 —— 多放一个 = 改了不生效。

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/merchant_api.dart';
import 'package:chengyin_app/feature/merchant/merchant_coop_profile_page.dart';

import '../../support/source_text.dart';

class _FakeMerchantApi implements MerchantApi {
  _FakeMerchantApi(this.profile);

  final Future<Map<String, dynamic>> profile;
  Map<String, dynamic>? saved;

  @override
  Future<Map<String, dynamic>> coopProfile() => profile;

  @override
  Future<String> saveCoopProfile({
    int? capacity,
    String? availableTime,
    String? suitActivityTypes,
    int? chargeType,
    String? demand,
    int? coopOpen,
  }) async {
    saved = <String, dynamic>{
      'capacity': capacity,
      'availableTime': availableTime,
      'suitActivityTypes': suitActivityTypes,
      'chargeType': chargeType,
      'demand': demand,
      'coopOpen': coopOpen,
    };
    return '已保存';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<_FakeMerchantApi> _pumpPage(
  WidgetTester tester, {
  required Map<String, dynamic> profile,
  Object? profileError,
}) async {
  final _FakeMerchantApi api = _FakeMerchantApi(
    profileError == null
        ? Future<Map<String, dynamic>>.value(profile)
        : Future<Map<String, dynamic>>.delayed(
            Duration.zero,
            () => throw profileError,
          ),
  );
  await tester.binding.setSurfaceSize(const Size(390, 1400));
  await tester.pumpWidget(
    ProviderScope(
      overrides: <dynamic>[merchantApiProvider.overrideWithValue(api)].cast(),
      child: MaterialApp(
        initialRoute: '/coop',
        routes: <String, WidgetBuilder>{
          '/': (_) => const Scaffold(body: Text('店铺资料')),
          '/coop': (_) => const MerchantCoopProfilePage(),
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  return api;
}

void main() {
  final String code = codeOf(
    'lib/feature/merchant/merchant_coop_profile_page.dart',
  );

  test('★ 保存只发后端认的六个字段', () {
    const Set<String> allowed = <String>{
      'capacity',
      'availableTime',
      'suitActivityTypes',
      'chargeType',
      'demand',
      'coopOpen',
    };
    final int at = code.indexOf('saveCoopProfile(');
    expect(at, greaterThan(0));
    final String seg = code.substring(at, code.indexOf(');', at));
    final Set<String> sent = RegExp(
      r'(\w+):\s',
    ).allMatches(seg).map((RegExpMatch m) => m.group(1)!).toSet();
    expect(sent, isNotEmpty);
    expect(
      sent.difference(allowed),
      isEmpty,
      reason: '后端不 set 的字段做成输入框 = 改了不生效,用户以为填了',
    );
  });

  test('★ 保存用后端原话,不自己写「保存成功」', () {
    expect(code.contains('CyNativeNotice.show(context, msg)'), isTrue);
    expect(code.contains("Text('保存成功')"), isFalse);
  });

  testWidgets('按小程序真源只显示四项，顺序、标题与底部 CTA 不变', (WidgetTester tester) async {
    await _pumpPage(
      tester,
      profile: <String, dynamic>{
        'capacity': 30,
        'availableTime': '周末',
        'chargeType': 1,
        'demand': '联合招募',
        'suitActivityTypes': 'citywalk',
        'coopOpen': 1,
      },
    );

    expect(find.text('承接设置'), findsOneWidget);
    expect(find.text('可容纳人数'), findsOneWidget);
    expect(find.text('可承接时段'), findsOneWidget);
    expect(find.text('收费方式'), findsOneWidget);
    expect(find.text('免费承接'), findsOneWidget);
    expect(find.text('收费承接'), findsOneWidget);
    expect(find.text('合作诉求'), findsOneWidget);
    expect(find.text('保存承接设置'), findsOneWidget);
    expect(find.text('开放对接'), findsNothing);
    expect(find.text('适合的活动类型'), findsNothing);
    expect(find.byType(CupertinoSlidingSegmentedControl<int>), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('可容纳人数')).dy,
      lessThan(tester.getTopLeft(find.text('可承接时段')).dy),
    );
    expect(
      tester.getTopLeft(find.text('可承接时段')).dy,
      lessThan(tester.getTopLeft(find.text('收费方式')).dy),
    );
    expect(
      tester.getTopLeft(find.text('收费方式')).dy,
      lessThan(tester.getTopLeft(find.text('合作诉求')).dy),
    );
    expect(
      tester.getTopLeft(find.text('合作诉求')).dy,
      lessThan(tester.getTopLeft(find.text('保存承接设置')).dy),
    );
  });

  testWidgets('收费选择与隐藏字段原样保存，成功后按小程序返回上一页', (WidgetTester tester) async {
    final _FakeMerchantApi api = await _pumpPage(
      tester,
      profile: <String, dynamic>{
        'capacity': 12,
        'availableTime': '工作日晚间',
        'chargeType': 0,
        'demand': '联名活动',
        'suitActivityTypes': '桌游',
        'coopOpen': 1,
      },
    );

    final CupertinoSlidingSegmentedControl<int> charge = tester.widget(
      find.byType(CupertinoSlidingSegmentedControl<int>),
    );
    charge.onValueChanged(1);
    await tester.pump();

    final Finder save = find.byKey(const Key('merchant-coop-save')).first;
    await tester.tap(save);
    await tester.pump();
    expect(api.saved?['capacity'], 12);
    expect(api.saved?['availableTime'], '工作日晚间');
    expect(api.saved?['chargeType'], 1);
    expect(api.saved?['demand'], '联名活动');
    expect(api.saved?['suitActivityTypes'], '桌游');
    expect(api.saved?['coopOpen'], 1);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(find.text('店铺资料'), findsOneWidget);
  });

  testWidgets('非法人数不调用保存，页面保留原值供修改', (WidgetTester tester) async {
    final _FakeMerchantApi api = await _pumpPage(
      tester,
      profile: <String, dynamic>{'capacity': 'abc', 'chargeType': 0},
    );

    await tester.tap(find.byKey(const Key('merchant-coop-save')));
    await tester.pump();
    expect(api.saved, isNull);
    expect(find.text('可容纳人数要填数字'), findsOneWidget);
    expect(find.text('abc'), findsOneWidget);
  });

  testWidgets('空档案呈现入驻空态，不渲染可保存的假表单', (WidgetTester tester) async {
    await _pumpPage(tester, profile: <String, dynamic>{});

    expect(find.text('暂时无法编辑承接设置'), findsOneWidget);
    expect(find.text('去商家入驻'), findsOneWidget);
    expect(find.byKey(const Key('merchant-coop-save')), findsNothing);
  });

  testWidgets('档案读取失败仍保留原错误态，不渲染真假开关', (WidgetTester tester) async {
    await _pumpPage(
      tester,
      profile: <String, dynamic>{},
      profileError: Exception('网络暂时不可用'),
    );

    expect(find.text('承接设置加载失败'), findsOneWidget);
    expect(find.text('网络暂时不可用'), findsOneWidget);
    expect(find.byKey(const Key('merchant-coop-save')), findsNothing);
  });
}
