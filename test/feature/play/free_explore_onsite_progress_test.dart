// 钉住批 2a 唯一声明的目标:**CTA 驱动现场三步**。
//
// 详情页曾经持有 push 那一刻的 PlayNode 快照,于是扫码成功回到详情页三步仍全灭、
// 再点 CTA 又一次调起扫码 —— 三步只有第 1 步走得通。这条用例造 arrived:false 的固件,
// 驱动一次成功的扫码核销,断言:①第 1 步就地亮起(不退出详情页)②下一次 CTA 走拍照。
//
// 说明:扫码页是 MobileScanner,widget test 里驱不动相机,所以这里直接调
// `_runScan` 拿到 code 之后调用的同一个 `checkin()`;跳过的只有相机那一段。
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/play_api.dart';
import 'package:chengyin_app/data/models/checkin_models.dart';
import 'package:chengyin_app/feature/play/play_session_controller.dart';
import 'package:chengyin_app/feature/play/play_session_page.dart';
import 'package:chengyin_app/feature/play/free_explore/free_explore_pass_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const PlaySessionKey _key = (activityId: 77, topicId: null);
const Key _step1Lit = ValueKey<String>('onsite-step-done-0');
const Key _step2Lit = ValueKey<String>('onsite-step-done-1');

/// 进度真源在服务端:扫码核销后 arrived 翻真,再拉节点就该是新状态。
/// ★ fetchNodes 故意留 30ms —— 真实网络下 load() 中间一定会过帧,
///   这一段正是「游玩页 body 被销毁、CTA 指向死 State」暴露的地方。
class _Api implements PlayApi {
  bool arrived = false;

  @override
  Future<PlayNodesResult> fetchNodes(int activityId) async {
    await Future<void>.delayed(const Duration(milliseconds: 30));
    return PlayNodesResult.fromJson(<String, dynamic>{
      'topicId': 23,
      'mode': 2,
      'playable': true,
      'total': 1,
      'doneCount': 0,
      // 章节键照后端:name / imgArr,**没有** meta/title/cover(见 PlayChapter.fromJson)。
      'chapters': <dynamic>[
        <String, dynamic>{'chapterId': 100, 'name': '晨间烘焙'},
      ],
      'nodes': <dynamic>[
        <String, dynamic>{
          'nodeId': 7,
          'name': '梧桐小店',
          'address': '衡山路 7 号',
          'sortId': 1,
          'chapterId': 100,
          'done': false,
          'merchantId': 71,
          'arrived': arrived,
          'selfReported': false,
        },
      ],
    });
  }

  @override
  Future<CheckinReward> submitCheckin({
    required int activityId,
    required String code,
    RouteAdvanceToken? routeAdvance,
  }) async {
    arrived = true;
    return const CheckinReward(
      nodeId: 7,
      firstTime: true,
      doneCount: 0,
      total: 1,
      completed: false,
      newBadges: <PlayBadge>[],
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('★扫码成功后详情页第 1 步就地亮起,再点 CTA 走到第 2 步(拍照)', (
    WidgetTester tester,
  ) async {
    final _Api api = _Api();
    final GoRouter router = GoRouter(
      initialLocation: '/play/77',
      routes: <RouteBase>[
        GoRoute(
          path: '/play/:id',
          builder: (_, _) =>
              const PlaySessionPage(activityId: 77, registrationId: 91),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[playApiProvider.overrideWithValue(api)].cast(),
        child: MaterialApp.router(
          routerConfig: router,
          builder: (BuildContext context, Widget? child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (find.text('跳过').evaluate().isNotEmpty) {
      await tester.tap(find.text('跳过'));
    }
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('梧桐小店'));
    await tester.pump();
    await tester.tap(find.text('梧桐小店'));
    await tester.pumpAndSettle();

    // 进详情页:一步没做,三步全灭。
    expect(find.text('开始互动 获得奖励！'), findsOneWidget);
    expect(find.byKey(_step1Lit), findsNothing, reason: '还没扫码就亮 = 亮灯不看真状态');
    expect(find.byKey(_step2Lit), findsNothing);

    // 一次成功的扫码核销(= _runScan 拿到 code 之后做的事)。
    final ProviderContainer container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );
    final Future<CheckinReward> checkin = container
        .read(playSessionProvider(_key).notifier)
        .checkin('MOCK-CODE');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 5)); // 刷新途中真过帧
    await tester.pump(const Duration(milliseconds: 50));
    await checkin;
    await tester.pumpAndSettle();

    // ① 没退出详情页,第 1 步就地亮了。
    expect(find.text('梧桐小店'), findsOneWidget, reason: '不许把用户踢回六宫格');
    expect(
      find.byKey(_step1Lit),
      findsOneWidget,
      reason: '扫码成功了三步还全灭 = 详情页拿的是快照,永远进不了第 2 步',
    );
    expect(find.byKey(_step2Lit), findsNothing, reason: '第 2 步还没做,不许提前亮');

    // ② 再点 CTA 走的是第 2 步拍照,不是又一次扫码。
    await tester.tap(find.text('开始互动 获得奖励！'));
    await tester.pumpAndSettle();
    expect(
      find.text('从相册选择'),
      findsOneWidget,
      reason: 'CTA 还在调起扫码 = 闭包里的 arrived 仍是 false',
    );
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    // ③ 底下的六宫格没被拆掉重建 —— CTA 的行为归它所有,它一死 CTA 就是个死按钮。
    expect(
      find.byType(FreeExplorePassView, skipOffstage: false),
      findsOneWidget,
      reason: '游玩页 body 被刷新拆掉重建的话,详情页 CTA 指向的就是已销毁的 State',
    );
  });
}
