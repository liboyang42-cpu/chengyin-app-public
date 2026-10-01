// 票夹三页的游客登录门:门本身 + 「登完就地重拉」那一段(B1 报告 #231 P1)。
//
// ★ 路由层只保证「深链不再被弹回首页」(见
//   test/core/router/tickets_guest_deeplink_test.dart);这里补的是
//   ① 门上说的是不是人话(「登录后查看」+ 去哪登录),
//   ② 游客态不发注定 401 的请求,
//   ③ 登完**回到本页**并把数据重拉出来 —— 只落地不重拉等于把人停在一个空壳上。

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/activity_api.dart';
import 'package:chengyin_app/data/models/activity.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/tickets/pass_page.dart';
import 'package:chengyin_app/feature/tickets/ticket_detail_page.dart';
import 'package:chengyin_app/feature/tickets/tickets_page.dart';
import 'package:flutter/material.dart';
import 'package:chengyin_app/l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class _MutableAuth extends AuthController {
  @override
  AuthState build() => const AuthState(initialized: true);

  void signIn() {
    state = AuthState(
      initialized: true,
      user: User(id: 7, nickname: '探索者', avatar: '', role: 'player'),
    );
  }
}

class _FakeActivityApi extends ActivityApi {
  _FakeActivityApi()
    : super(DioClient(TokenStore(const FlutterSecureStorage())));

  int ticketListCalls = 0;
  int ticketInfoCalls = 0;
  int issueCalls = 0;

  @override
  Future<List<MyRegistration>> ticketList({
    int? isOnline,
    String fallbackMsg = '活动票加载失败',
  }) async {
    ticketListCalls += 1;
    return <MyRegistration>[
      MyRegistration(
        id: 11,
        ownerType: 1,
        ownerId: 101,
        title: '外滩路线',
        registrationStatus: 2,
      ),
    ];
  }

  @override
  Future<List<MyRegistration>> topicTicketList({
    String fallbackMsg = '没能取得已报名主题',
  }) async {
    return const <MyRegistration>[];
  }

  @override
  Future<RegistrationDetail> ticketInfo(int id) async {
    ticketInfoCalls += 1;
    return RegistrationDetail.fromJson(<String, dynamic>{
      'id': id,
      'ownerType': 1,
      'ownerId': 101,
      'registrationNo': 'R20260918011',
      'registrationStatus': 2,
      'verificationStatus': 0,
      'cmsActivity': <String, dynamic>{'name': '外滩路线'},
    });
  }

  @override
  Future<DynCode> issueDynamicCode(int registrationId) async {
    issueCalls += 1;
    return DynCode(
      code: 'CY.11.activity.aB3xQ7',
      expiresAt: DateTime.now().millisecondsSinceEpoch + 300000,
    );
  }
}

class _Harness {
  _Harness(this.container, this.api);

  final ProviderContainer container;
  final _FakeActivityApi api;

  AuthController get auth => container.read(authControllerProvider.notifier);

  void signIn() => (auth as _MutableAuth).signIn();
}

Future<_Harness> _pump(WidgetTester tester, Widget page, {bool english = false}) async {
  final _FakeActivityApi api = _FakeActivityApi();
  final _MutableAuth auth = _MutableAuth();
  final container = ProviderContainer(
    retry: (int _, Object _) => null,
    overrides: <dynamic>[
      authControllerProvider.overrideWith(() => auth),
      activityApiProvider.overrideWithValue(api),
    ].cast(),
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: english ? const Locale('en') : const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(english ? 2 : 1)),
          child: child!,
        ),
        home: page,
      ),
    ),
  );
  await tester.pump();
  return _Harness(container, api);
}

/// 走一遍真实的「门 → 登录 → 回本页」:在登录弹窗还开着时登入,再关掉弹窗 ——
/// 与真机上 `_run` 成功后自弹自关的顺序一致,`requireLogin` 的 await 才会带着
/// isLoggedIn=true 收敛。
Future<void> _signInFromGate(WidgetTester tester, _Harness h) async {
  await tester.tap(find.text('去登录'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  expect(find.text('登录城瘾'), findsOneWidget, reason: '「去登录」没有弹登录弹窗');

  h.signIn();
  await tester.pump();
  Navigator.of(tester.element(find.text('登录城瘾'))).pop();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  // NOT_RUN locally: Flutter SDK unavailable.
  testWidgets('English pass guest gate makes no issuance request at large text', (tester) async {
    final h = await _pump(tester, const PassPage(registrationId: 11), english: true);
    expect(find.text('Sign in to show your redemption code'), findsOneWidget);
    expect(h.api.issueCalls, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('票夹:游客见登录门,登完就地重拉', (WidgetTester tester) async {
    final _Harness h = await _pump(tester, const TicketsPage());

    expect(find.byKey(const Key('tickets-login-gate')), findsOneWidget);
    expect(find.text('登录后查看票夹'), findsOneWidget);
    expect(h.api.ticketListCalls, 0, reason: '游客态不该发注定 401 的票夹请求');

    await _signInFromGate(tester, h);

    expect(find.byKey(const Key('tickets-login-gate')), findsNothing);
    expect(find.text('外滩路线'), findsOneWidget, reason: '登录后没有就地重拉票夹');
    expect(h.api.ticketListCalls, 1);
  });

  testWidgets('票卡详情:游客见登录门,登完就地重拉', (WidgetTester tester) async {
    final _Harness h = await _pump(
      tester,
      const TicketDetailPage(registrationId: 11),
    );

    expect(find.byKey(const Key('ticket-detail-login-gate')), findsOneWidget);
    expect(find.text('登录后查看票券详情'), findsOneWidget);
    expect(h.api.ticketInfoCalls, 0, reason: '游客态不该发注定 401 的详情请求');

    await _signInFromGate(tester, h);

    expect(find.byKey(const Key('ticket-detail-login-gate')), findsNothing);
    expect(find.text('R20260918011'), findsOneWidget, reason: '登录后没有就地重拉详情');
    expect(h.api.ticketInfoCalls, 1);
  });

  testWidgets('出示核销码:游客见登录门,登完就地出码', (WidgetTester tester) async {
    final _Harness h = await _pump(tester, const PassPage(registrationId: 11));

    expect(find.byKey(const Key('ticket-pass-login-gate')), findsOneWidget);
    expect(find.text('登录后出示核销码'), findsOneWidget);
    expect(h.api.issueCalls, 0, reason: '游客态不该发注定 401 的出码请求');

    await _signInFromGate(tester, h);

    expect(find.byKey(const Key('ticket-pass-login-gate')), findsNothing);
    expect(find.text('请把此码交给商家核销'), findsOneWidget, reason: '登录后没有就地出码');
    expect(h.api.issueCalls, 1);

    // 收尾:PassPage 有每秒倒计时的 periodic timer,拆树把它停掉。
    await tester.pumpWidget(const SizedBox());
  });
}
