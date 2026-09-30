// 票根 CTA 三态与点卡分流(b1 报告 P2-2)。真源
// `subpackageMember/signup/index.wxml` wxs `cta()`:ready→「进入游玩」、
// pending→「去支付」、其余 '';void 的 label 再分「已取消/已过期」。
// 落点按真源 `index.js` `_openTicket`:待支付→订单(唯一例外),
// 已取消/已过期→只提示不跳,已报名→票。
import 'package:chengyin_app/data/models/activity.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/tickets/tickets_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// 票根 CTA 是**已登录**用户看到的东西;页上的游客登录门(#429 N1)会挡掉
/// 一切渲染,所以测试先把登录态摆好(游客门本身另有 tickets_guest_gate 覆盖)。
class _SignedIn extends AuthController {
  @override
  AuthState build() => AuthState(
    initialized: true,
    user: User(id: 7, nickname: '探索者', avatar: '', role: 'player'),
  );
}

MyRegistration _ticket({required int id, required int? reg, int? verify}) =>
    MyRegistration(
      id: id,
      ownerType: 1,
      ownerId: 900 + id,
      title: '票$reg-$verify',
      registrationStatus: reg,
      verificationStatus: verify,
    );

void main() {
  Future<void> pumpWallet(
    WidgetTester tester, {
    required List<MyRegistration> tickets,
  }) async {
    final router = GoRouter(
      routes: <RouteBase>[
        GoRoute(path: '/', builder: (context, state) => const TicketsPage()),
        GoRoute(
          path: '/orders',
          builder: (context, state) =>
              Text('orders-${state.uri.queryParameters['detailId']}'),
        ),
        GoRoute(
          path: '/ticket/:id',
          builder: (context, state) =>
              Text('ticket-${state.pathParameters['id']}'),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(_SignedIn.new),
          myTicketsProvider.overrideWith(
            (ref) async => WalletSnapshot(tickets: tickets),
          ),
          walletMyTeamsProvider.overrideWith(
            (ref) async => const <String, WalletTeam>{},
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('票根 CTA 三态逐字:ready「进入游玩 ›」/pending「去支付 ›」,已核验不出 CTA', (
    WidgetTester tester,
  ) async {
    await pumpWallet(
      tester,
      tickets: <MyRegistration>[
        _ticket(id: 11, reg: 2), // 待使用
        _ticket(id: 12, reg: 1), // 待支付
        _ticket(id: 13, reg: 2, verify: 1), // 已核验
      ],
    );
    expect(find.text('进入游玩 ›'), findsOneWidget);
    expect(find.text('去支付 ›'), findsOneWidget);
    // 真源:已核验只剩状态词,「查看详情」那条路已关。
    expect(find.text('查看详情 ›'), findsNothing);
    expect(find.text('查看详情'), findsNothing);
    expect(find.text('已核验'), findsOneWidget);
    // 三张票只有 ready/pending 各一颗 CTA ⇒ 「›」结尾恰好 2 个。
    expect(
      find.byWidgetPredicate((w) => w is Text && (w.data ?? '').endsWith('›')),
      findsNWidgets(2),
    );
  });

  testWidgets('void 态票根:「已取消/已过期」状态词逐字,不出 CTA', (WidgetTester tester) async {
    await pumpWallet(
      tester,
      tickets: <MyRegistration>[
        _ticket(id: 14, reg: 3), // 已取消
        _ticket(id: 15, reg: 4), // 已过期
      ],
    );
    expect(find.text('已取消'), findsOneWidget);
    expect(find.text('已过期'), findsOneWidget);
    expect(find.text('查看详情 ›'), findsNothing);
    expect(find.text('去支付 ›'), findsNothing);
  });

  testWidgets('点待支付票 → 订单落点 /orders?detailId(真源 _openTicket 唯一例外)', (
    WidgetTester tester,
  ) async {
    await pumpWallet(
      tester,
      tickets: <MyRegistration>[_ticket(id: 12, reg: 1)],
    );
    await tester.tap(find.text('去支付 ›'));
    await tester.pumpAndSettle();
    expect(find.text('orders-12'), findsOneWidget);
  });

  testWidgets('点已报名票 → 票根详情 /ticket/:id', (WidgetTester tester) async {
    await pumpWallet(
      tester,
      tickets: <MyRegistration>[_ticket(id: 11, reg: 2)],
    );
    await tester.tap(find.text('进入游玩 ›'));
    await tester.pumpAndSettle();
    expect(find.text('ticket-11'), findsOneWidget);
  });

  testWidgets('点已取消/已过期票 → 只提示不跳(真源 toast 逐字)', (WidgetTester tester) async {
    await pumpWallet(
      tester,
      tickets: <MyRegistration>[
        _ticket(id: 14, reg: 3),
        _ticket(id: 15, reg: 4),
      ],
    );
    await tester.tap(find.text('已取消'));
    await tester.pump();
    expect(find.text('票已取消'), findsOneWidget);
    expect(find.textContaining('ticket-'), findsNothing);

    await tester.tap(find.text('已过期'));
    await tester.pump();
    expect(find.text('票已过期'), findsOneWidget);
    expect(find.textContaining('ticket-'), findsNothing);
  });
}
