// 店铺资料页。
//
// ★★ /update 是写接口,`边界` 明确要求"表单没做完整之前别接"——
//   这里锁死两条:①保存时**六个字段一次性全发**(不是只发改过的那个),
//   免得半截提交把后端已有字段覆盖成空;②内容被审核拒时弹窗引导改文字,
//   不是普通报错。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/merchant_api.dart';
import 'package:chengyin_app/feature/merchant/merchant_edit_page.dart';

class _FakeMerchantApi implements MerchantApi {
  _FakeMerchantApi({required this.info});
  final Map<String, dynamic> info;
  Map<String, dynamic>? lastUpdateBody;
  Object? updateError;

  @override
  Future<Map<String, dynamic>> merchantInfo() async => info;

  @override
  Future<String> updateMerchant({
    String? logo,
    String? name,
    String? description,
    String? derivatives,
    String? website,
    String? preference,
  }) async {
    lastUpdateBody = <String, dynamic>{
      'logo': logo,
      'name': name,
      'description': description,
      'derivatives': derivatives,
      'website': website,
      'preference': preference,
    };
    if (updateError != null) throw updateError!;
    return '已保存';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<_FakeMerchantApi> _pump(
  WidgetTester tester, {
  Map<String, dynamic>? info,
}) async {
  final api = _FakeMerchantApi(
    info:
        info ??
        <String, dynamic>{
          'id': 42,
          'memberId': 100096,
          'name': '静安咖啡',
          'description': '一杯咖啡的城市',
          'derivatives': '',
          'website': '',
          'preference': '',
          'logo': '',
        },
  );
  await tester.binding.setSurfaceSize(const Size(390, 900));
  await tester.pumpWidget(
    ProviderScope(
      overrides: <dynamic>[merchantApiProvider.overrideWithValue(api)].cast(),
      child: MaterialApp.router(
        routerConfig: GoRouter(
          routes: <RouteBase>[
            GoRoute(path: '/', builder: (_, _) => const MerchantEditPage()),
            GoRoute(
              path: '/merchant/public-home/member/:id',
              builder: (_, GoRouterState s) =>
                  Scaffold(body: Text('公开主页 ${s.pathParameters['id']}')),
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return api;
}

void main() {
  testWidgets('★★ 保存时六个字段一次性全发,不是只发改过的那个', (WidgetTester tester) async {
    final api = await _pump(tester);
    await tester.enterText(
      find.byKey(const Key('merchant-edit-name')),
      '静安咖啡·新',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('merchant-edit-save')));
    await tester.pumpAndSettle();

    expect(api.lastUpdateBody, isNotNull);
    // 只改了 name,其余字段也要跟着一起发(哪怕是空串)——
    // 半截提交会把后端已有字段覆盖成空,这里锁住"全量提交"这个前提。
    expect(api.lastUpdateBody!.keys.toSet(), <String>{
      'logo',
      'name',
      'description',
      'derivatives',
      'website',
      'preference',
    });
    expect(api.lastUpdateBody!['name'], '静安咖啡·新');
    expect(api.lastUpdateBody!['description'], '一杯咖啡的城市');
  });

  testWidgets('★ 表单用 /api/merchant/info 预填,不是空白表单', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      info: <String, dynamic>{
        'id': 1,
        'name': '徐汇书店',
        'description': '',
        'derivatives': '',
        'website': '',
        'preference': '',
        'logo': '',
      },
    );
    expect(find.text('徐汇书店'), findsOneWidget);
  });

  testWidgets('★★ 内容被审核拒 → 弹窗引导改文字,不是普通报错 SnackBar', (
    WidgetTester tester,
  ) async {
    final api = await _pump(tester);
    api.updateError = MerchantApiException('文案包含违规内容');
    await tester.tap(find.byKey(const Key('merchant-edit-save')));
    // ★ 不能用 pumpAndSettle:保存中按钮的 CircularProgressIndicator
    //   是无限动画,settle 永远等不到——手动 pump 几帧,弹窗出来就够。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('内容没能通过审核'), findsOneWidget);
    expect(find.textContaining('文案包含违规内容'), findsOneWidget);
    expect(find.text('去修改'), findsOneWidget);
  });

  testWidgets('预览公开主页传 memberId，不传商家档案 id', (WidgetTester tester) async {
    await _pump(tester);
    await tester.tap(find.byKey(const Key('merchant-edit-preview')));
    await tester.pumpAndSettle();
    expect(find.text('公开主页 100096'), findsOneWidget);
    expect(find.text('公开主页 42'), findsNothing);
  });
}
