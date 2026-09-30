// 出示核销码按钮在**不能出码**时说的话,必须对应真实成因。
//
// ★ 起因:`_canIssue` 为假有三种成因(未支付 / 已取消 / 核销完),原先一律显示
//   「该票已核销完」。对前两种既是假话(票压根没用过),又堵死了下一步 ——
//   待支付的人看到「已核销完」只会以为票废了,而他其实只差付款。
//
// 这类「一个文案覆盖多个状态」的错,**看图看不出来**:每张截图里都只有一个状态,
// 单看哪张都合理,只有把成因和文案并排列出来才显形。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/data/models/activity.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/tickets/ticket_detail_page.dart';

/// 本用例考的是**已登录**用户在「不能出码」时看到的文案。游客另有登录门
/// (见 tickets_guest_gate_test.dart),这里必须先把登录态摆好。
class _SignedIn extends AuthController {
  @override
  AuthState build() => AuthState(
    initialized: true,
    user: User(id: 7, nickname: '探索者', avatar: '', role: 'player'),
  );
}

/// registrationStatus:1待支付 / 2已报名 / 3已取消(同小程序票夹 wxs)。
RegistrationDetail _detail({
  required int registrationStatus,
  int? verificationStatus,
}) {
  return RegistrationDetail.fromJson(<String, dynamic>{
    'id': 1,
    'ownerType': 2,
    'ownerId': 9,
    'registrationNo': 'R1',
    'registrationStatus': registrationStatus,
    'verificationStatus': verificationStatus,
    'participateDate': '2026-08-20 10:00',
    'cmsActivity': <String, dynamic>{'name': '老城漫步'},
  });
}

Future<void> _pump(WidgetTester tester, RegistrationDetail d) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <dynamic>[
        authControllerProvider.overrideWith(_SignedIn.new),
        ticketDetailProvider(1).overrideWith((ref) async => d),
      ].cast(),
      child: const MaterialApp(home: TicketDetailPage(registrationId: 1)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('待支付 → 「支付完成后可出示」,不许说已核销', (WidgetTester tester) async {
    await _pump(tester, _detail(registrationStatus: 1));
    expect(find.text('支付完成后可出示'), findsOneWidget);
    expect(find.textContaining('核销'), findsNothing);
  });

  testWidgets('已取消 → 「该票已取消」', (WidgetTester tester) async {
    await _pump(tester, _detail(registrationStatus: 3));
    expect(find.text('该票已取消'), findsOneWidget);
    expect(find.textContaining('核销'), findsNothing);
  });

  testWidgets('已核销(普通票)→ 「该票已全部核销」', (WidgetTester tester) async {
    await _pump(
      tester,
      _detail(registrationStatus: 2, verificationStatus: 1),
    );
    expect(find.text('该票已全部核销'), findsOneWidget);
  });

  testWidgets('可用 → 「出示核销码」', (WidgetTester tester) async {
    await _pump(
      tester,
      _detail(registrationStatus: 2, verificationStatus: 0),
    );
    expect(find.text('出示核销码'), findsOneWidget);
  });
}
