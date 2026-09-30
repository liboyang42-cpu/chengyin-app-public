import 'dart:async';

import 'package:chengyin_app/data/api/advanced_play_api.dart';
import 'package:chengyin_app/data/api/play_api.dart';
import 'package:chengyin_app/data/models/advanced_play.dart';
import 'package:chengyin_app/feature/play/advanced/advanced_play_controller.dart';
import 'package:chengyin_app/feature/play/advanced/fullscreen/playkit_quiz_data.dart';
import 'package:chengyin_app/feature/play/advanced/fullscreen/playkit_quiz_views.dart';
import 'package:chengyin_app/feature/play/advanced/playkit_host.dart';
import 'package:chengyin_app/feature/play/advanced/playkit_projection.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

/// qa:shoot 两步链的链路级门禁:组件动作 → 宿主出口 → 网关字段。
///
/// 真源 `pages/play/index.js` 的 `_submitQaPhoto` 逐条对照:
/// ① 先把照片传上去拿到地址,再连地址提交 `SUBMIT_QA{imageUrl}` ——
///    临时路径出了这台手机就不存在,一步直发是「不报错、永远不通过」;
/// ② 两步的失败要分开说(「照片没传上去」vs「传上去了但没记上」);
/// ③ 双击锁、超限前置拒绝(未知大小放行由服务端拦)、
///    回来时同一 session/同一版本、acting/unknown 不装成功、
///    上传中途退出不再提交 —— 每一条都可能悄悄丢玩家的作品。
void main() {
  Map<String, dynamic> stateJson({int version = 1}) => <String, dynamic>{
    'sessionId': 7,
    'activityId': 3,
    'topicId': 0,
    'nodeId': 11,
    'status': 'RUNNING',
    'version': version,
    'score': 0,
    'readyForBase': false,
    'config': <String, dynamic>{
      'leaderboard': <String, dynamic>{'enabled': false},
      'multiplayer': <String, dynamic>{'enabled': false},
    },
    'draws': <dynamic>[],
    'playKit': <String, Object?>{},
    'multiplayer': <String, dynamic>{},
  };

  late _FakeGateway gateway;
  late _FakeUploader uploader;
  late BuildContext ctx;

  Future<AdvancedPlayController> started(WidgetTester tester) async {
    await tester.pumpWidget(
      CupertinoApp(
        home: Builder(
          builder: (BuildContext context) {
            ctx = context;
            return const SizedBox();
          },
        ),
      ),
    );
    gateway = _FakeGateway(stateJson: stateJson());
    uploader = _FakeUploader();
    final AdvancedPlayController controller = AdvancedPlayController(
      gateway: gateway,
      activityId: 3,
      topicId: 0,
      nodeId: 11,
      uploadPhoto: uploader.call,
    );
    addTearDown(controller.dispose);
    await controller.start();
    return controller;
  }

  /// 从组件那一步进宿主:组件 shot 档抛的就是这个动作与载荷。
  void shoot(
    AdvancedPlayController controller,
    PlayKitQaPhoto photo, {
    PlayKitKind kind = PlayKitKind.qa,
  }) {
    playKitFullscreenContextFor(
      ctx,
      controller,
      PlayKitCard(kind: kind, title: '', detail: ''),
    ).onAction!(
      PlayKitAction(
        label: '',
        action: kQaShootAction,
        payload: photo.toPayload(),
      ),
    );
  }

  testWidgets('全链:shoot → 上传拿地址 → SUBMIT_QA{imageUrl},动作名一个字母不变', (
    WidgetTester tester,
  ) async {
    final AdvancedPlayController controller = await started(tester);
    shoot(controller, const PlayKitQaPhoto(path: '/tmp/qa.jpg', size: 2048));
    await tester.pumpAndSettle();

    expect(uploader.paths, <String>['/tmp/qa.jpg']);
    // 网关收到的:名字是服务端在册的 SUBMIT_QA(不是 QA:SHOOT),
    // 字段是换算后的 imageUrl(OSS 地址),不是组件手里的临时路径。
    expect(gateway.actionCalls.single.action, kQaSubmitAction);
    expect(gateway.actionCalls.single.payload, <String, Object?>{
      'imageUrl': 'https://oss/chengyin/qa.jpg',
    });
    expect(controller.qaPhotoUploading, isFalse, reason: '链走完锁要放开');
  });

  testWidgets('限定来源:非 qa 组件伪造的 shoot 不上传也不提交', (WidgetTester tester) async {
    final AdvancedPlayController controller = await started(tester);
    shoot(
      controller,
      const PlayKitQaPhoto(path: '/tmp/forged.jpg', size: 1),
      kind: PlayKitKind.scan,
    );
    await tester.pumpAndSettle();
    expect(uploader.paths, isEmpty, reason: '真源注释:否则伪造一下就绕过类型门禁');
    expect(gateway.actionCalls, isEmpty);
  });

  testWidgets('双击锁:上传在途时后到的 shoot 直接忽略,只起一次上传', (WidgetTester tester) async {
    final AdvancedPlayController controller = await started(tester);
    uploader.hold = Completer<void>();
    shoot(controller, const PlayKitQaPhoto(path: '/tmp/one.jpg', size: 1));
    await tester.pump();
    shoot(controller, const PlayKitQaPhoto(path: '/tmp/two.jpg', size: 1));
    await tester.pump();
    expect(uploader.paths, <String>['/tmp/one.jpg']);

    uploader.hold!.complete();
    await tester.pumpAndSettle();
    expect(gateway.actionCalls.single.action, kQaSubmitAction);

    // 链走完锁必须放开:下一条才传得出去。
    shoot(controller, const PlayKitQaPhoto(path: '/tmp/three.jpg', size: 1));
    await tester.pumpAndSettle();
    expect(uploader.paths, <String>['/tmp/one.jpg', '/tmp/three.jpg']);
  });

  testWidgets('已知超限前置拒绝:不发网络,给可操作文案;size 未知照常上传', (WidgetTester tester) async {
    final AdvancedPlayController controller = await started(tester);
    const int mib = 1024 * 1024;
    shoot(
      controller,
      const PlayKitQaPhoto(path: '/tmp/big.jpg', size: 15 * mib),
    );
    await tester.pumpAndSettle();
    expect(uploader.paths, isEmpty, reason: '超限不发网络(真源共享上传入口同一条)');
    expect(gateway.actionCalls, isEmpty);
    expect(find.textContaining('文件过大，请压缩或更换文件后上传（单个文件最大10MB）'), findsOneWidget);

    // 拿不到 size(读失败/旧数据)= 未知:放行,由服务端拦,不伪造一个数。
    shoot(controller, const PlayKitQaPhoto(path: '/tmp/unknown.jpg'));
    await tester.pumpAndSettle();
    expect(uploader.paths, <String>['/tmp/unknown.jpg']);
    expect(gateway.actionCalls.single.action, kQaSubmitAction);
  });

  testWidgets('失败分开说:业务失败给后端原文,其余给「照片没传上去」,都不提交', (WidgetTester tester) async {
    final AdvancedPlayController controller = await started(tester);
    uploader.error = PlayException('图片安全检查不通过');
    shoot(controller, const PlayKitQaPhoto(path: '/tmp/no.jpg', size: 1));
    await tester.pumpAndSettle();
    expect(find.textContaining('图片安全检查不通过'), findsOneWidget);
    expect(gateway.actionCalls, isEmpty, reason: '照片没传上去就没有地址可提交');
    expect(controller.qaPhotoUploading, isFalse);

    uploader.error = Exception('网络断了');
    shoot(controller, const PlayKitQaPhoto(path: '/tmp/no2.jpg', size: 1));
    await tester.pumpAndSettle();
    expect(find.textContaining('照片没传上去'), findsOneWidget);
    expect(gateway.actionCalls, isEmpty);
  });

  testWidgets('回执是空的仍算没传上去(真源 `if (!url)` 同一条)', (WidgetTester tester) async {
    final AdvancedPlayController controller = await started(tester);
    uploader.reply = '';
    shoot(controller, const PlayKitQaPhoto(path: '/tmp/x.jpg', size: 1));
    await tester.pumpAndSettle();
    expect(find.textContaining('照片没传上去'), findsOneWidget);
    expect(gateway.actionCalls, isEmpty);
  });

  testWidgets('题目已变化:上传回来时版本不对,不提交并说清楚', (WidgetTester tester) async {
    final AdvancedPlayController controller = await started(tester);
    uploader.hold = Completer<void>();
    shoot(controller, const PlayKitQaPhoto(path: '/tmp/stale.jpg', size: 1));
    await tester.pump();
    // 在途时队友/别处推进了状态:版本 1 → 2(真源同一条:旧照片不许提交到新题)。
    gateway.stateJson = stateJson(version: 2);
    await controller.refreshAuthoritative();
    await tester.pumpAndSettle();
    uploader.hold!.complete();
    await tester.pumpAndSettle();
    expect(
      find.textContaining('题目已变化，上一张照片未提交'),
      findsOneWidget,
      reason: '提交的是旧题的照片,玩家以为交了、服务端没记 —— 必须说明',
    );
    expect(
      gateway.actionCalls.where((c) => c.action == kQaSubmitAction),
      isEmpty,
    );
  });

  testWidgets('acting/unknown 不装成功:给一句可恢复的实话', (WidgetTester tester) async {
    final AdvancedPlayController controller = await started(tester);
    gateway.replyError = const AdvancedPlayTransportException('网络超时');
    // 先把控制器推进 unknown(一次提交发出去但没核回)。
    await controller.submit('GIVEUP');
    await tester.pumpAndSettle();
    expect(controller.phase, AdvancedPlayPhase.unknown);

    shoot(controller, const PlayKitQaPhoto(path: '/tmp/pending.jpg', size: 1));
    await tester.pumpAndSettle();
    expect(find.textContaining('确认中，照片未提交，请稍后再试'), findsOneWidget);
    // 照片传上去了,但那次提交没发出 —— 不装成功,也不静默丢掉。
    expect(uploader.paths.length, 1);
    expect(
      gateway.actionCalls.where((c) => c.action == kQaSubmitAction),
      isEmpty,
    );
  });

  testWidgets('空路径静默;状态不完整给重进口径(真源两条各归各)', (WidgetTester tester) async {
    final AdvancedPlayController controller = await started(tester);
    shoot(controller, const PlayKitQaPhoto(path: '  '));
    await tester.pumpAndSettle();
    expect(uploader.paths, isEmpty);
    expect(gateway.actionCalls, isEmpty);
    expect(find.textContaining('玩法状态不完整'), findsNothing);

    // 权威状态不再 RUNNING(节点结束):如实说「玩法状态不完整」。
    gateway.running = false;
    await controller.refreshAuthoritative();
    await tester.pumpAndSettle();
    shoot(controller, const PlayKitQaPhoto(path: '/tmp/after.jpg', size: 1));
    await tester.pumpAndSettle();
    expect(uploader.paths, isEmpty);
    expect(find.textContaining('玩法状态不完整，请重进节点'), findsOneWidget);
  });

  testWidgets('上传中途退出:不对已销毁的呈现层提交,但锁要放开', (WidgetTester tester) async {
    final AdvancedPlayController controller = await started(tester);
    uploader.hold = Completer<void>();
    shoot(controller, const PlayKitQaPhoto(path: '/tmp/orphan.jpg', size: 1));
    await tester.pump();
    // 换掉整棵树:挂宿主提示的那个 context 当场失效。
    await tester.pumpWidget(const CupertinoApp(home: SizedBox()));
    uploader.hold!.complete();
    await tester.pump();
    expect(
      gateway.actionCalls.where((c) => c.action == kQaSubmitAction),
      isEmpty,
      reason: '真源的 page-bound operation:回来时页面没了就不再 game.action',
    );
    expect(controller.qaPhotoUploading, isFalse, reason: '锁不能烂成永远');
  });
}

/// 假的共享上传口:记录路径,回执可控(地址/异常/在途挂起)。
class _FakeUploader {
  final List<String> paths = <String>[];
  String reply = 'https://oss/chengyin/qa.jpg';
  Object? error;
  Completer<void>? hold;

  Future<String> call(String filePath) async {
    paths.add(filePath);
    if (hold != null) await hold!.future;
    if (error != null) throw error!;
    return reply;
  }
}

class _FakeGateway implements AdvancedPlayGateway {
  _FakeGateway({required this.stateJson});

  Map<String, dynamic> stateJson;
  bool running = true;
  Object? replyError;
  final List<({String action, Map<String, Object?> payload})> actionCalls =
      <({String action, Map<String, Object?> payload})>[];

  Map<String, dynamic> get _json => <String, dynamic>{
    ...stateJson,
    'status': running ? 'RUNNING' : 'FINISHED',
  };

  @override
  Future<AdvancedPlayState> start({
    required int activityId,
    required int topicId,
    required int nodeId,
  }) async => AdvancedPlayState.fromJson(_json);

  @override
  Future<AdvancedPlayState> action({
    required int sessionId,
    required int version,
    required String idempotencyKey,
    required String action,
    required Map<String, Object?> payload,
  }) async {
    actionCalls.add((action: action, payload: payload));
    if (replyError != null) throw replyError!;
    return AdvancedPlayState.fromJson(_json);
  }

  @override
  Future<AdvancedPlayState> state(int sessionId) async =>
      AdvancedPlayState.fromJson(_json);

  @override
  Future<List<AdvancedPlayLeaderboardRow>> leaderboard({
    required int activityId,
    required int topicId,
    required int nodeId,
  }) async => const <AdvancedPlayLeaderboardRow>[];
}
