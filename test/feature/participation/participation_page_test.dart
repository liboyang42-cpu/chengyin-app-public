import 'dart:async';

import 'package:chengyin_app/data/models/user.dart';
import 'package:chengyin_app/feature/auth/auth_controller.dart';
import 'package:chengyin_app/feature/participation/participation_api.dart';
import 'package:chengyin_app/feature/participation/participation_models.dart';
import 'package:chengyin_app/feature/participation/participation_page.dart';
import 'package:chengyin_app/core/network/provider_retry.dart';
import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:native_liquid_glass/native_liquid_glass.dart';

class _FakeRepository implements ParticipationRepository {
  _FakeRepository({
    required this.listResult,
    this.detailResult,
    this.error,
    this.listError,
    this.refreshError,
  });

  final Future<List<ParticipationRecord>> listResult;
  final ParticipationDetail? detailResult;
  final Object? error;
  final Object? listError;

  /// 非 null 时:下拉刷新(第二次及以后的 list() 调用)抛这个错。
  final Object? refreshError;
  int detailCalls = 0;
  int listCalls = 0;

  @override
  Future<ParticipationDetail> detail(int id) async {
    detailCalls += 1;
    if (error case final Object error) throw error;
    return detailResult!;
  }

  @override
  Future<List<ParticipationRecord>> list() {
    listCalls += 1;
    if (listCalls > 1 && refreshError != null) {
      final Object error = refreshError!;
      return Future<List<ParticipationRecord>>.sync(() => throw error);
    }
    final Object? listError = this.listError;
    if (listError != null) {
      return Future<List<ParticipationRecord>>.sync(() => throw listError);
    }
    return listResult;
  }
}

ParticipationRecord _record(
  int id,
  ParticipationState state, {
  String name = '夜游苏河',
}) => ParticipationRecord(
  id: id,
  ownerType: 1,
  ownerId: 100 + id,
  sourceName: name,
  coverUrl: '',
  address: '苏河湾',
  dateText: '08.23 - 08.24',
  typeLabel: '自由探索',
  state: state,
);

const ParticipationDetail _detail = ParticipationDetail(
  id: 77,
  topicName: '夜游苏河',
  dateText: '2026.09.10 - 2026.09.12',
  statusText: '未开始',
  modeText: '城市定向',
  ownerType: 1,
  ownerId: 11,
  isTopic: true,
  paymentStatus: 2,
  refundDeadlineDisplay: '2026-09-07 09:00',
  showOrderStats: false,
  showRemainingBadge: false,
  remainingDaysText: '',
  canCancel: true,
  showContactService: false,
  needModify: false,
  hasRuleInstructions: false,
  activityDescription: '沿河完成城市探索',
);

class _FailingDetailErrorDriver
    implements ParticipationDetailErrorNativeDriver {
  const _FailingDetailErrorDriver(this.error);

  final Object error;

  @override
  bool get supportsLiquidGlass => true;

  @override
  Future<void> show({
    required BuildContext context,
    required String title,
    required String message,
  }) => Future<void>.error(error);
}

/// 动作路由的落点桩:把 URI 记下来,页面本体不属于本域不真渲染。
final List<String> _pushedLocations = <String>[];

/// 页内游客登录门(b1-sim-club-2 N1)会把未登录态的页面整页换掉;
/// 本域测试验的是登录后的列表/动作逻辑,固定成登录态(券域同型范式)。
class _LoggedInAuth extends AuthController {
  @override
  AuthState build() => AuthState(
    user: User(id: 99, nickname: '测试用户', avatar: '', role: 'player'),
    initialized: true,
  );
}

Future<GoRouter> _pump(
  WidgetTester tester,
  _FakeRepository repository, {
  bool liquidGlassSupported = false,
  ParticipationDetailPresenter? detailPresenter,
  ParticipationDetailErrorNativeDriver? detailErrorNativeDriver,
}) async {
  _pushedLocations.clear();
  String capture(String path, GoRouterState state) {
    final Uri uri = state.uri;
    _pushedLocations.add(uri.toString());
    return path;
  }

  final GoRouter router = GoRouter(
    initialLocation: '/participations',
    routes: <RouteBase>[
      GoRoute(
        path: '/participations',
        builder: (_, _) => ParticipationPage(
          liquidGlassSupported: liquidGlassSupported,
          detailPresenter: detailPresenter,
          detailErrorNativeDriver: detailErrorNativeDriver,
        ),
      ),
      GoRoute(
        path: '/play/:activityId',
        builder: (BuildContext context, GoRouterState state) {
          capture(state.uri.path, state);
          return const SizedBox();
        },
      ),
      GoRoute(
        path: '/tickets',
        builder: (BuildContext context, GoRouterState state) {
          capture(state.uri.path, state);
          return const SizedBox();
        },
      ),
      GoRoute(
        path: '/template/:id',
        builder: (BuildContext context, GoRouterState state) {
          capture(state.uri.path, state);
          return const SizedBox();
        },
      ),
    ],
  );
  final ProviderContainer container = ProviderContainer(
    retry: chengyinRetry,
    overrides: [
      authControllerProvider.overrideWith(_LoggedInAuth.new),
      participationRepositoryProvider.overrideWithValue(repository),
    ],
  );
  addTearDown(router.dispose);
  addTearDown(container.dispose);
  await tester.binding.setSurfaceSize(const Size(390, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  return router;
}

/// 注入一个「按了某颗动作按钮」的假半屏:真实半屏内容在
/// participation_detail_content_test / native_fallback_test 覆盖。
ParticipationDetailPresenter _presenterReturning(
  ParticipationDetailActionKind kind, {
  ParticipationDetail detail = _detail,
}) =>
    (BuildContext context, ParticipationDetail received) async =>
        ParticipationDetailResult(kind: kind, detail: detail);

void main() {
  testWidgets('冷路由展示标题与四项固定顺序，等待时是骨架态', (WidgetTester tester) async {
    final Completer<List<ParticipationRecord>> pending =
        Completer<List<ParticipationRecord>>();
    await _pump(tester, _FakeRepository(listResult: pending.future));
    await tester.pump();

    expect(find.text('我的参与'), findsOneWidget);
    for (final String label in <String>['全部', '未开始', '进行中', '已完成']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.byKey(const Key('participation-loading')), findsOneWidget);
  });

  testWidgets('列表错误态中文落点可重试(不再直抛 Exception 前缀)', (WidgetTester tester) async {
    await _pump(
      tester,
      _FakeRepository(
        listResult: Future<List<ParticipationRecord>>.value(
          <ParticipationRecord>[],
        ),
        listError: const ParticipationApiException('网络错误'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('参与记录没能打开'), findsOneWidget);
    expect(find.text('网络错误'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(find.textContaining('Exception:'), findsNothing);
  });

  testWidgets('A8 · 401 错误态给登录入口而不是死路重试', (WidgetTester tester) async {
    await _pump(
      tester,
      _FakeRepository(
        listResult: Future<List<ParticipationRecord>>.value(
          <ParticipationRecord>[],
        ),
        listError: DioException(
          requestOptions: RequestOptions(path: '/api/registration/my-joined'),
          response: Response<void>(
            requestOptions: RequestOptions(path: '/api/registration/my-joined'),
            statusCode: 401,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('登录后查看我的参与'), findsOneWidget);
    expect(find.text('登录状态已失效，请重新登录'), findsOneWidget);
    expect(find.text('去登录'), findsOneWidget);
  });

  testWidgets('A7 · 下拉刷新失败不打断 —— 旧列表继续在场', (WidgetTester tester) async {
    await _pump(
      tester,
      _FakeRepository(
        listResult: Future<List<ParticipationRecord>>.value(
          <ParticipationRecord>[
            _record(1, ParticipationState.inProgress, name: '当前路线'),
          ],
        ),
        refreshError: const ParticipationApiException('网络异常'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(const Key('participation-list')),
      const Offset(0, 300),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    // 刷新失败:不出错误态,快照列表仍在。
    expect(find.text('参与记录没能打开'), findsNothing);
    expect(find.text('当前路线'), findsOneWidget);
  });

  testWidgets('全部空态逐字对齐小程序', (WidgetTester tester) async {
    await _pump(
      tester,
      _FakeRepository(
        listResult: Future<List<ParticipationRecord>>.value(
          <ParticipationRecord>[],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('暂无参与记录'), findsOneWidget);
    expect(find.text('报名后，路线和活动会出现在这里'), findsOneWidget);
  });

  testWidgets('筛选只改列表内容，无结果不丢失当前筛选', (WidgetTester tester) async {
    await _pump(
      tester,
      _FakeRepository(
        listResult:
            Future<List<ParticipationRecord>>.value(<ParticipationRecord>[
              _record(1, ParticipationState.notStarted, name: '明日路线'),
              _record(2, ParticipationState.inProgress, name: '当前路线'),
            ]),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('已完成'));
    await tester.pumpAndSettle();
    expect(find.text('当前筛选暂无参与记录'), findsOneWidget);
    expect(find.text('切换其他状态查看参与记录'), findsOneWidget);
    expect(find.text('已完成'), findsOneWidget);
  });

  testWidgets('点记录打开三级详情，关闭后仍留在列表冷路由', (WidgetTester tester) async {
    ParticipationDetail? opened;
    final Completer<void> closed = Completer<void>();
    final _FakeRepository repository = _FakeRepository(
      listResult: Future<List<ParticipationRecord>>.value(<ParticipationRecord>[
        _record(7, ParticipationState.inProgress),
      ]),
      detailResult: _detail,
    );
    final GoRouter router = await _pump(
      tester,
      repository,
      detailPresenter:
          (BuildContext context, ParticipationDetail detail) async {
            opened = detail;
            await closed.future;
            return null;
          },
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('participation-record-7')));
    await tester.pump();
    expect(
      find.byKey(const Key('participation-detail-loading-7')),
      findsOneWidget,
    );
    await tester.pump();
    expect(opened?.topicName, '夜游苏河');
    expect(router.state.uri.path, '/participations');

    closed.complete();
    await tester.pumpAndSettle();
    expect(find.text('我的参与'), findsOneWidget);
    expect(router.state.uri.path, '/participations');
    expect(repository.detailCalls, 1);
  });

  group('A3 · 半屏动作在宿主页执行', () {
    testWidgets('取消参与 → danger-actions 同文确认(已支付走取消并退款)', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        _FakeRepository(
          listResult: Future<List<ParticipationRecord>>.value(
            <ParticipationRecord>[_record(7, ParticipationState.inProgress)],
          ),
          detailResult: _detail,
        ),
        detailPresenter: _presenterReturning(
          ParticipationDetailActionKind.cancel,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('participation-record-7')));
      // 记录行 loading 在弹窗背后持续转动,只能按帧推进。
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('取消报名?'), findsOneWidget);
      expect(
        find.text(
          '取消后报名资格失效，现金退款和积分返还按本单实际支付记录处理。'
          '2026-09-07 09:00。',
        ),
        findsOneWidget,
      );
      expect(find.text('取消并退款'), findsOneWidget);
      expect(find.text('再想想'), findsOneWidget);
    });

    testWidgets('联系客服 → R10 客服微信号弹窗(不发资金请求)', (WidgetTester tester) async {
      await _pump(
        tester,
        _FakeRepository(
          listResult: Future<List<ParticipationRecord>>.value(
            <ParticipationRecord>[_record(7, ParticipationState.inProgress)],
          ),
          detailResult: _detail,
        ),
        detailPresenter: _presenterReturning(
          ParticipationDetailActionKind.contact,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('participation-record-7')));
      // 记录行 loading 在弹窗背后持续转动,只能按帧推进。
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('联系客服'), findsOneWidget);
      expect(find.textContaining('微信号'), findsOneWidget);
      expect(find.text('复制'), findsOneWidget);
      expect(find.text('返回'), findsOneWidget);
    });

    testWidgets('开始玩 → 路线票带 topicId+registrationId 进游玩页', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        _FakeRepository(
          listResult: Future<List<ParticipationRecord>>.value(
            <ParticipationRecord>[_record(7, ParticipationState.inProgress)],
          ),
          detailResult: _detail,
        ),
        detailPresenter: _presenterReturning(
          ParticipationDetailActionKind.startPlay,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('participation-record-7')));
      await tester.pumpAndSettle();

      expect(
        _pushedLocations,
        contains('/play/0?topicId=11&registrationId=77'),
      );
    });

    testWidgets('场次票直接进 /play/<activityId>', (WidgetTester tester) async {
      const ParticipationDetail activityDetail = ParticipationDetail(
        id: 88,
        topicName: '街区快闪',
        dateText: '',
        statusText: '进行中',
        modeText: '线下活动',
        ownerType: 2,
        ownerId: 22,
        isTopic: false,
        paymentStatus: 1,
        showOrderStats: false,
        showRemainingBadge: false,
        remainingDaysText: '',
        canCancel: false,
        showContactService: true,
        needModify: false,
        hasRuleInstructions: false,
      );
      await _pump(
        tester,
        _FakeRepository(
          listResult: Future<List<ParticipationRecord>>.value(
            <ParticipationRecord>[_record(7, ParticipationState.inProgress)],
          ),
          detailResult: activityDetail,
        ),
        detailPresenter: _presenterReturning(
          ParticipationDetailActionKind.startPlay,
          detail: activityDetail,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('participation-record-7')));
      await tester.pumpAndSettle();

      expect(_pushedLocations, contains('/play/22?registrationId=88'));
    });

    testWidgets('模板行 → templatedetail?id&scope=my', (
      WidgetTester tester,
    ) async {
      const ParticipationDetail withTemplate = ParticipationDetail(
        id: 77,
        topicName: '夜游苏河',
        dateText: '',
        statusText: '未开始',
        modeText: '城市定向',
        ownerType: 1,
        ownerId: 11,
        isTopic: true,
        paymentStatus: 2,
        showOrderStats: false,
        showRemainingBadge: false,
        remainingDaysText: '',
        canCancel: false,
        showContactService: false,
        needModify: false,
        hasRuleInstructions: false,
        templateId: 9,
      );
      await _pump(
        tester,
        _FakeRepository(
          listResult: Future<List<ParticipationRecord>>.value(
            <ParticipationRecord>[_record(7, ParticipationState.inProgress)],
          ),
          detailResult: withTemplate,
        ),
        detailPresenter: _presenterReturning(
          ParticipationDetailActionKind.openTemplate,
          detail: withTemplate,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('participation-record-7')));
      await tester.pumpAndSettle();

      expect(_pushedLocations, contains('/template/9?scope=my'));
    });
  });

  testWidgets('三级详情失败给出返回参与列表的可观察出口', (WidgetTester tester) async {
    final _FakeRepository repository = _FakeRepository(
      listResult: Future<List<ParticipationRecord>>.value(<ParticipationRecord>[
        _record(7, ParticipationState.inProgress),
      ]),
      error: const ParticipationApiException('参与详情数据异常'),
    );
    final GoRouter router = await _pump(tester, repository);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('participation-record-7')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('参与详情没能打开'), findsOneWidget);
    expect(find.text('参与详情数据异常'), findsOneWidget);
    expect(find.text('返回参与列表'), findsOneWidget);

    await tester.tap(find.text('返回参与列表'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(router.state.uri.path, '/participations');
    expect(find.text('我的参与'), findsOneWidget);
  });

  for (final Object error in <Object>[
    MissingPluginException('alert unavailable'),
    PlatformException(code: 'presentation_failed'),
  ]) {
    testWidgets('${error.runtimeType} 进入完整 Cupertino 详情错误降级', (
      WidgetTester tester,
    ) async {
      final _FakeRepository repository = _FakeRepository(
        listResult: Future<List<ParticipationRecord>>.value(
          <ParticipationRecord>[_record(7, ParticipationState.inProgress)],
        ),
        error: const ParticipationApiException('参与详情数据异常'),
      );
      await _pump(
        tester,
        repository,
        detailErrorNativeDriver: _FailingDetailErrorDriver(error),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('participation-record-7')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(CupertinoAlertDialog), findsOneWidget);
      expect(find.text('参与详情没能打开'), findsOneWidget);
      expect(find.text('参与详情数据异常'), findsOneWidget);
      expect(find.text('返回参与列表'), findsOneWidget);
    });
  }

  testWidgets('旧系统用 Cupertino 分段控件回退', (WidgetTester tester) async {
    final _FakeRepository repository = _FakeRepository(
      listResult: Future<List<ParticipationRecord>>.value(
        <ParticipationRecord>[],
      ),
    );
    await _pump(tester, repository, liquidGlassSupported: false);
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoSlidingSegmentedControl<int>), findsOneWidget);
    expect(find.byType(LiquidGlassSegmentedControl), findsNothing);
    expect(
      tester
          .getSize(find.byKey(const Key('participation-filter-hitbox')))
          .height,
      greaterThanOrEqualTo(44),
    );
  });

  testWidgets('iOS 26 用原生液态玻璃分段控件', (WidgetTester tester) async {
    final _FakeRepository repository = _FakeRepository(
      listResult: Future<List<ParticipationRecord>>.value(
        <ParticipationRecord>[],
      ),
    );
    await _pump(tester, repository, liquidGlassSupported: true);
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoSlidingSegmentedControl<int>), findsNothing);
    expect(find.byType(LiquidGlassSegmentedControl), findsOneWidget);
    expect(
      tester
          .getSize(find.byKey(const Key('participation-filter-hitbox')))
          .height,
      greaterThanOrEqualTo(44),
    );
    expect(
      tester
          .widget<LiquidGlassSegmentedControl>(
            find.byType(LiquidGlassSegmentedControl),
          )
          .height,
      44,
      reason:
          '视觉高度=字号档+24、下限 44(#307 裁字修复;此前固定 39 '
          '在大字号下裁字,且触达靠透明区凑)',
    );
    expect(
      tester
          .widget<LiquidGlassSegmentedControl>(
            find.byType(LiquidGlassSegmentedControl),
          )
          .color,
      isNotNull,
      reason: '黑白基调:不传 tint 会吃到 SwiftUI 默认系统蓝(C1)',
    );
  });

  testWidgets('44pt 交互槽的顶部透明区仍可切换原生分段', (WidgetTester tester) async {
    await _pump(
      tester,
      _FakeRepository(
        listResult:
            Future<List<ParticipationRecord>>.value(<ParticipationRecord>[
              _record(1, ParticipationState.notStarted, name: '明日路线'),
              _record(2, ParticipationState.inProgress, name: '当前路线'),
            ]),
      ),
      liquidGlassSupported: true,
    );
    await tester.pumpAndSettle();

    final Rect hitbox = tester.getRect(
      find.byKey(const Key('participation-filter-hitbox')),
    );
    await tester.tapAt(
      Offset(hitbox.left + hitbox.width * 0.625, hitbox.top + 1),
    );
    await tester.pumpAndSettle();

    expect(find.text('当前路线'), findsOneWidget);
    expect(find.text('明日路线'), findsNothing);
  });
}
