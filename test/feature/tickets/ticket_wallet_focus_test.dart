// 票夹合并列表与 focusId 定位(b1 报告 P2-1)。真源
// `signup/index.js` rebuildTicketList():两个接口各拉各的,只在渲染层合成
// `topics.concat(activities)` —— 路线票在前、场次票在后,组内保持接口返回序;
// 「路线 / 场次」那层 tab 已由用户 2026-09-09 裁决删除,不许再引入分流控件。
import 'package:chengyin_app/data/models/activity.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/tickets/tickets_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

MyRegistration _ticket({
  required int id,
  required int ownerType,
  required String title,
}) => MyRegistration(
  id: id,
  ownerType: ownerType,
  ownerId: 100 + id,
  title: title,
  registrationStatus: 2,
);

/// 票夹的分页/分段结构是**已登录**用户看到的东西。游客另有登录门
/// (见 tickets_guest_gate_test.dart),这里必须先把登录态摆好。
class _SignedIn extends AuthController {
  @override
  AuthState build() => AuthState(
    initialized: true,
    user: User(id: 7, nickname: '探索者', avatar: '', role: 'player'),
  );
}

void main() {
  final tickets = <MyRegistration>[
    _ticket(id: 11, ownerType: 1, title: '外滩路线'),
    _ticket(id: 22, ownerType: 2, title: '周末场次'),
  ];

  Future<void> pumpWallet(
    WidgetTester tester, {
    List<MyRegistration>? list,
    int? focusId,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(_SignedIn.new),
          myTicketsProvider.overrideWith(
            (ref) async =>
                WalletSnapshot(tickets: list ?? tickets, halfFailure: null),
          ),
          walletMyTeamsProvider.overrideWith(
            (ref) async => const <String, WalletTeam>{},
          ),
        ],
        child: MaterialApp(home: TicketsPage(focusId: focusId)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('票夹没有「路线 / 场次」分流层:两种票同屏,路线在前场次在后', (WidgetTester tester) async {
    await pumpWallet(tester);
    // 用户裁决删掉的 tab 层不许回来(连回退档的 Cupertino 分段也不许有)。
    expect(find.text('路线'), findsNothing);
    expect(find.text('场次'), findsNothing);
    expect(
      find.byKey(const Key('ticket-scope-control')),
      findsNothing,
      reason: '真源 2026-09-09 裁决:「路线 / 场次」这层 tab 删掉,两种票放一起',
    );
    expect(find.byType(CupertinoSlidingSegmentedControl<int>), findsNothing);
    // 两类票都渲染。
    expect(find.text('外滩路线'), findsOneWidget);
    expect(find.text('周末场次'), findsOneWidget);
    // 排序口径 = topics.concat(activities):路线票在上,不各自为政。
    expect(
      tester.getRect(find.text('外滩路线')).top,
      lessThan(tester.getRect(find.text('周末场次')).top),
    );
  });

  testWidgets('focusId 定位到那张票(合并列表里的场次票也一样能落)', (WidgetTester tester) async {
    await pumpWallet(tester, focusId: 22);
    expect(
      find.byKey(const ValueKey<String>('ticket-focus-22')),
      findsOneWidget,
    );
  });
}
