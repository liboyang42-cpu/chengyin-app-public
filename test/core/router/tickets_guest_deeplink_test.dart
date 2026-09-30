// 票夹域游客深链的门(B1 模拟器报告 #231 P1)。
//
// ★ 症状:`/tickets` `/ticket/:id` `/ticket/:id/pass` 三条深链被
//   `_loginRequiredPrefixes` 静默弹回首页 —— 游客点别人发来的票卡链接,
//   看到的是「链接坏了」,而同一份链接登录后本来就能看。
// ★ 口径同先例:club(`club_login_gate.dart` / `027cf346`)、roam(#208)。
//   路由不拦,页面落地并用页内登录门解释(「登录后查看」+「去登录」),
//   登完就地重拉本页数据(那一段在 test/feature/tickets/tickets_guest_gate_test.dart)。
// ★ 另一条必须守住的:游客态**不发注定 401 的请求**(票在账号里,无 token 必被拒),
//   否则错误态与登录门同屏打架。

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/core/router/app_router.dart';
import 'package:chengyin_app/data/api/activity_api.dart';
import 'package:chengyin_app/data/models/activity.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/main.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// 游客(auth 已完成恢复但未登录)。
class _GuestAuth extends AuthController {
  @override
  AuthState build() => const AuthState(initialized: true);
}

/// 假 API:只记「有没有人调」,不真打网络。票夹域三页各走一条接口。
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('游客深链票夹三页:落地 + 页内登录门,不被静默弹回首页', (WidgetTester tester) async {
    final _FakeActivityApi api = _FakeActivityApi();
    final container = ProviderContainer(
      retry: (int _, Object _) => null,
      overrides: <dynamic>[
        authControllerProvider.overrideWith(_GuestAuth.new),
        activityApiProvider.overrideWithValue(api),
      ].cast(),
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const ChengyinApp(),
      ),
    );
    await tester.pump();
    final router = container.read(appRouterProvider);

    for (final (String path, String gateKey) in <(String, String)>[
      ('/tickets', 'tickets-login-gate'),
      ('/ticket/11', 'ticket-detail-login-gate'),
      ('/ticket/11/pass', 'ticket-pass-login-gate'),
    ]) {
      router.go(path);
      await tester.pump();
      // 400ms:让上一页的 Cupertino 转场跑完,免得用「两个页面都在树上」误判。
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        router.routeInformationProvider.value.uri.path,
        path,
        reason: '$path 仍被弹回首页(用户以为链接坏了)',
      );
      final Finder gate = find.byKey(Key(gateKey));
      expect(gate, findsOneWidget, reason: '$path 缺少登录门');
      expect(
        find.descendant(of: gate, matching: find.text('去登录')),
        findsOneWidget,
        reason: '$path 的登录门没给出下一步',
      );
    }

    expect(api.ticketListCalls, 0, reason: '游客态不该发注定 401 的票夹请求');
    expect(api.ticketInfoCalls, 0, reason: '游客态不该发注定 401 的票卡详情请求');
    expect(api.issueCalls, 0, reason: '游客态不该发注定 401 的出码请求');
  });
}
