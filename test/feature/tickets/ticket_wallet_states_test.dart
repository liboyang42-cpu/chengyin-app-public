import 'package:chengyin_app/l10n/app_localizations.dart';
// 票夹三态文案(b1 报告 P2-4/P2-5)。真源 `subpackageMember/signup/index.wxml`:
//   · 载(:54) loading-label「正在加载我的票」—— 走 aria,骨架不渲染可见文字;
//   · 空(:60)「还没有票」+ sub「去首页发现路线或报名场次，票会在这里出现。」;
//   · 错(:57)「票夹没能打开」+ sub=后端 walletErrorMsg 原文,主钮「重试」。
import 'dart:async';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/activity_api.dart';
import 'package:chengyin_app/data/models/activity.dart';
import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/tickets/tickets_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// 三态渲染在登录门之后(#429 N1):游客先见门,这些用例测的是登录后的三态。
class _SignedIn extends AuthController {
  @override
  AuthState build() => AuthState(
    initialized: true,
    user: User(id: 7, nickname: '探索者', avatar: '', role: 'player'),
  );
}

/// 票夹两路接口的假 API:路线票(owner_type=1)/场次票(owner_type=2)
/// 各拉各的,合并口径由 [myTicketsProvider] 负责(真源 rebuildTicketList)。
class _FakeActivityApi extends ActivityApi {
  _FakeActivityApi()
    : super(DioClient(TokenStore(const FlutterSecureStorage())));

  List<MyRegistration> topics = const <MyRegistration>[];
  List<MyRegistration> activities = const <MyRegistration>[];
  Object? topicError;
  Object? activityError;

  @override
  Future<List<MyRegistration>> topicTicketList({
    String fallbackMsg = '没能取得已报名主题',
  }) async {
    if (topicError != null) throw topicError!;
    return topics;
  }

  @override
  Future<List<MyRegistration>> ticketList({
    int? isOnline,
    String fallbackMsg = '活动票加载失败',
  }) async {
    if (activityError != null) throw activityError!;
    return activities;
  }
}

MyRegistration _reg(int id, int ownerType) => MyRegistration(
  id: id,
  ownerType: ownerType,
  ownerId: 100 + id,
  title: '票$id',
  registrationStatus: 2,
);

void main() {
  group('myTicketsProvider 合并口径(真源 rebuildTicketList)', () {
    Future<WalletSnapshot> load(_FakeActivityApi api) async {
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith(_SignedIn.new),
          activityApiProvider.overrideWithValue(api),
        ],
      );
      addTearDown(container.dispose);
      // autoDispose provider:没有监听者会在 loading 期被回收,先钉一个订阅。
      final sub = container.listen(myTicketsProvider, (_, _) {});
      addTearDown(sub.close);
      return container.read(myTicketsProvider.future);
    }

    test('路线票在前、场次票在后(topics.concat(activities)),组内不重排', () async {
      final snap = await load(
        _FakeActivityApi()
          ..topics = <MyRegistration>[_reg(1, 1), _reg(2, 1)]
          ..activities = <MyRegistration>[_reg(3, 2)],
      );
      expect(snap.tickets.map((MyRegistration t) => t.id), <int>[1, 2, 3]);
      expect(snap.halfFailure, isNull);
    });

    test('只挂一路:能拿到的那半照常,失败原文进 halfFailure(真源后端 msg 直读)', () async {
      final snap = await load(
        _FakeActivityApi()
          ..topicError = Exception('路线服务开小差了')
          ..activities = <MyRegistration>[_reg(3, 2)],
      );
      expect(snap.tickets.map((MyRegistration t) => t.id), <int>[3]);
      expect(snap.halfFailure, '路线服务开小差了');
    });

    test('两路都挂:整页 error,walletErrorMsg = 路线 err 优先', () async {
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith(_SignedIn.new),
          activityApiProvider.overrideWithValue(
            _FakeActivityApi()
              ..topicError = Exception('路线票加载失败')
              ..activityError = Exception('活动票加载失败'),
          ),
        ],
      );
      addTearDown(container.dispose);
      final sub = container.listen(myTicketsProvider, (_, _) {});
      addTearDown(sub.close);
      // Riverpod 3 的 autoDispose `.future` 在错误路径只会抛
      // 「disposed during loading」StateError,原始 err 只在状态里活着,
      // 所以判据读 AsyncValue.error,不读 .future。
      await pumpEventQueue();
      final Object? err = container.read(myTicketsProvider).error;
      expect(err, isA<Exception>());
      expect('$err', contains('路线票加载失败'));
    });

    test('英文裸异常(网络栈)不许上屏:按分支兜底中文', () async {
      final snap = await load(
        _FakeActivityApi()
          ..topicError = Exception('SocketException: connection refused')
          ..activities = <MyRegistration>[_reg(3, 2)],
      );
      expect(snap.halfFailure, '路线票加载失败');
    });
  });

  Future<void> pumpWallet(
    WidgetTester tester, {
    required Future<WalletSnapshot> tickets,
    Locale locale = const Locale('zh'),
    TextScaler textScaler = TextScaler.noScaling,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(_SignedIn.new),
          myTicketsProvider.overrideWith((ref) => tickets),
          walletMyTeamsProvider.overrideWith(
            (ref) async => const <String, WalletTeam>{},
          ),
        ],
        child: MaterialApp(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: textScaler), child: child!),
          home: const TicketsPage()),
      ),
    );
  }

  testWidgets('English tickets at large text preserve title and localized status', (tester) async {
    await pumpWallet(tester,
      locale: const Locale('en'), textScaler: const TextScaler.linear(2),
      tickets: Future.value(WalletSnapshot(tickets: [_reg(1, 1)])),
    );
    await tester.pumpAndSettle();
    expect(find.text('Tickets'), findsOneWidget);
    expect(find.text('票1'), findsOneWidget);
    expect(find.text('Ready to use'), findsOneWidget);
    expect(find.text('Start playing ›'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('ticket fallback provenance never rewrites identical server copy', () {
    final generated = describeWalletFailure(
      Exception('__wallet_route_missing_message__'), WalletFailureKind.route);
    final server = describeWalletFailure(Exception('路线票加载失败'), WalletFailureKind.route);
    expect(generated.kind, WalletFailureKind.route);
    expect(server.kind, isNull);
    expect(server.message, '路线票加载失败');
  });

  testWidgets('加载态:骨架屏只画结构,「正在加载我的票」走 aria(真源 loading-label)', (
    WidgetTester tester,
  ) async {
    final handle = tester.ensureSemantics();
    final completer = Completer<WalletSnapshot>();
    await pumpWallet(tester, tickets: completer.future);
    await tester.pump();
    expect(find.bySemanticsLabel('正在加载我的票'), findsOneWidget);
    // 骨架里不许有可见的「加载中」文字 —— 用户会当成真数据读(共用件同注释)。
    expect(find.text('正在加载我的票'), findsNothing);
    handle.dispose();
  });

  testWidgets('空态:单一「还没有票」+ 真源 sub(删 tab 后不许再按票种分话)', (
    WidgetTester tester,
  ) async {
    await pumpWallet(
      tester,
      tickets: Future.value(const WalletSnapshot(tickets: [])),
    );
    await tester.pumpAndSettle();
    expect(find.text('还没有票'), findsOneWidget);
    expect(find.text('去首页发现路线或报名场次，票会在这里出现。'), findsOneWidget);
    // 旧 tab 时代的分票种空态措辞不许回来。
    expect(find.text('还没有路线票'), findsNothing);
    expect(find.text('还没有场次票'), findsNothing);
  });

  testWidgets('错态:「票夹没能打开」+ 后端 walletErrorMsg 原文直读,主钮「重试」', (
    WidgetTester tester,
  ) async {
    await pumpWallet(
      tester,
      // 延迟抛错:Future.error 在 pump 前就是孤儿异常,会被测试区判 unhandled。
      tickets: Future(() => throw Exception('当前票夹服务繁忙，请稍后再试')),
    );
    await tester.pumpAndSettle();
    expect(find.text('票夹没能打开'), findsOneWidget);
    // 后端那句中文人话必须原样上屏,不许被套话吞掉(真源 sub=walletErrorMsg)。
    expect(find.text('当前票夹服务繁忙，请稍后再试'), findsOneWidget);
    expect(find.text('票夹加载失败'), findsNothing);
    expect(find.text('重试'), findsOneWidget);
  });

  testWidgets('只挂一路:能拿到的那半照常显示,失败原文报一次(真源 _reportHalfFailure)', (
    WidgetTester tester,
  ) async {
    await pumpWallet(
      tester,
      tickets: Future.value(
        const WalletSnapshot(tickets: [], halfFailure: '路线票加载失败'),
      ),
    );
    await tester.pumpAndSettle();
    // 整页不判死:走的是空态,不是错误态。
    expect(find.text('票夹没能打开'), findsNothing);
    expect(find.text('还没有票'), findsOneWidget);
    // 但缺的那半不许静默。
    expect(find.text('路线票加载失败'), findsOneWidget);
    // 放掉通知的自动收起计时器,别给测试留 pending timer。
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('路线票加载失败'), findsNothing);
  });
}
