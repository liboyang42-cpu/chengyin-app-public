import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:chengyin_app/data/api/merchant_api.dart';
import 'package:chengyin_app/feature/merchant/merchant_error_view.dart';

/// 商家域四种态的分流。
///
/// ★ 为什么要有页面级测试而不只测判据:**判据之间有重叠**。
///   「仅启用且审核通过的商家可查看客户名册」里同时含「商家」二字,
///   分支顺序写反就会把「审核中」归成「还不是商家」,给他一个
///   「去申请入驻」按钮 —— 而他早就申请过了。
Future<void> pumpError(WidgetTester tester, Object error) async {
  final router = GoRouter(
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (BuildContext c, GoRouterState s) => Scaffold(
          body: merchantErrorView(c, error, onRetry: () {}),
        ),
      ),
      GoRoute(
        path: '/merchant/apply',
        builder: (_, __) => const Scaffold(body: Text('申请页')),
      ),
    ],
  );
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('账户互斥 → 说清原因,什么按钮都不给', (WidgetTester tester) async {
    await pumpError(tester,
        MerchantApiException('您已是俱乐部主理人,一个账户不能同时是商户与俱乐部主理人'));
    expect(find.text('这个账户不能成为商家'), findsOneWidget);
    expect(find.text('重试'), findsNothing, reason: '这条规则重试一万次也不会变');
    expect(find.text('去申请入驻'), findsNothing, reason: '他永远申请不了');
  });

  testWidgets('★ 审核中 → 不给申请入口(他已经申请过了)', (WidgetTester tester) async {
    await pumpError(
        tester, MerchantApiException('仅启用且审核通过的商家可查看客户名册'));
    expect(find.text('商家资质审核中'), findsOneWidget);
    expect(find.text('去申请入驻'), findsNothing,
        reason: '判据重叠:这句里也含「商家」,顺序写反就会引导他重复申请');
    expect(find.text('你还不是商家'), findsNothing);
  });

  testWidgets('还不是商家 → 给「去申请入驻」', (WidgetTester tester) async {
    await pumpError(tester, MerchantApiException('商家信息不存在'));
    expect(find.text('你还不是商家'), findsOneWidget);
    expect(find.text('去申请入驻'), findsOneWidget);
  });

  testWidgets('真故障 → 给「重试」,并把原话说出来', (WidgetTester tester) async {
    await pumpError(tester, MerchantApiException('网络连接超时'));
    expect(find.text('内容没能加载出来'), findsOneWidget,
        reason: '不传 what 时退回「内容」—— 仍比只说「加载失败」强');
    expect(find.text('网络连接超时'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(find.text('去申请入驻'), findsNothing);
  });

  testWidgets('非 MerchantApiException 的异常也当故障处理', (WidgetTester tester) async {
    await pumpError(tester, Exception('什么东西炸了'));
    expect(find.text('内容没能加载出来'), findsOneWidget,
        reason: '不传 what 时退回「内容」—— 仍比只说「加载失败」强');
    expect(find.text('重试'), findsOneWidget);
  });
}
