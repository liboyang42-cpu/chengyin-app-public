import 'dart:async';

import 'package:chengyin_app/data/api/advanced_play_api.dart';
import 'package:chengyin_app/data/models/advanced_play.dart';
import 'package:chengyin_app/feature/play/advanced/advanced_play_controller.dart';
import 'package:chengyin_app/feature/play/advanced/fullscreen/playkit_prefab_data.dart';
import 'package:chengyin_app/feature/play/advanced/fullscreen/playkit_prefab_views.dart';
import 'package:chengyin_app/feature/play/advanced/fullscreen/playkit_quiz_views.dart';
import 'package:chengyin_app/feature/play/advanced/playkit_fullscreen.dart';
import 'package:chengyin_app/feature/play/advanced/playkit_host.dart';
import 'package:chengyin_app/feature/play/advanced/playkit_projection.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

/// 《预制人生》四段(profile · photoCheck · note · typeIn)的**推进链**门禁。
///
/// 对账真源(2026-09-17 契约 §2,证据均取小程序 `github/master`):
/// - `utils/playkit-view.js` 的 `buildProfile/buildPhotoCheck/buildNote/buildTypeIn`
///   + `segmentComplete`(:173-176)+ `ACTION_OF`(:659-664)+ `serverPayload`(:719-721);
/// - `pages/play/index.js` 的 `photocheck` shoot 两步(:4941-4949)与
///   profile 头像「只传不提」(:4951-4952、:5037);
/// - 四组件 `playkit-{profile,photocheck,note,typein}/index.{js,wxml}` 的三态与文案。
///
/// 每一段钉的都是同一类问题:**段推进读服务端真值** ——
/// done/passed/flagged/attempts 只认投影回来的那份,组件不自己改判;
/// 载荷字段名逐字对表(发错的后果不是报错,是服务端按空值判、永远不通过)。
void main() {
  Map<String, dynamic> stateJson({Map<String, Object?> playKit = const {}}) =>
      <String, dynamic>{
        'sessionId': 7,
        'activityId': 3,
        'topicId': 0,
        'nodeId': 11,
        'status': 'RUNNING',
        'version': 1,
        'score': 0,
        'readyForBase': false,
        'config': <String, dynamic>{
          'leaderboard': <String, dynamic>{'enabled': false},
          'multiplier': <String, dynamic>{},
        },
        'draws': <dynamic>[],
        'playKit': playKit,
        'multiplayer': <String, dynamic>{},
      };

  final Map<String, Object?> profileSegment = <String, Object?>{
    'title': '出生登记',
    'lead': '往后翻就是你的名字了',
    'questions': <Object?>[
      <String, Object?>{
        'key': 'name',
        'label': '叫什么',
        'kind': 'text',
        'maxLength': 8,
        'required': true,
      },
      <String, Object?>{
        'key': 'job',
        'label': '白天做什么',
        'kind': 'pick',
        'options': <Object?>[
          <String, Object?>{'key': 'clerk', 'label': '便利店店员'},
        ],
      },
    ],
  };

  test('投影·建档完成口径照真源:done 由服务端落,没 done 就不算完', () {
    final PlayKitCard open = projectPlayKit(<String, Object?>{
      'profile': <String, Object?>{'title': '出生登记'},
    }).single;
    expect(open.kind, PlayKitKind.profile);
    expect(open.complete, isFalse);

    final PlayKitCard locked = projectPlayKit(<String, Object?>{
      'profile': <String, Object?>{'title': '出生登记', 'done': true},
    }).single;
    expect(locked.complete, isTrue, reason: 'done 是服务端的权威值,客户端不推算');
  });

  testWidgets('建档:必填没填一发不发;填齐了 SUBMIT_PROFILE 带 answers/avatarUrl', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(600, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final _FakeGateway gateway = _FakeGateway(
      startState: stateJson(
        playKit: <String, Object?>{'profile': profileSegment},
      ),
    );
    final AdvancedPlayController controller = _controller(gateway);
    await controller.start();
    await _openFullscreen(tester, controller, PlayKitKind.profile);

    expect(find.byType(PlayKitProfileView), findsOneWidget);
    // CTA 逐字照真源:未提交是「提交登记」,必填没填时点了也不许发出去
    await tester.tap(find.text('提交登记'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(gateway.actionCalls, isEmpty, reason: 'required 未填不许提交');

    await tester.enterText(find.byKey(const Key('playkit-profile-name')), '小隐');
    await tester.tap(find.byKey(const Key('playkit-profile-job-clerk')));
    await tester.pump();
    await tester.tap(find.text('提交登记'));
    await tester.pumpAndSettle();

    // 字段名逐字对 serverPayload 的 `profile:submit`:{ answers, avatarUrl }
    expect(gateway.actionCalls.single.action, 'SUBMIT_PROFILE');
    expect(gateway.actionCalls.single.payload, <String, Object?>{
      'answers': <String, Object?>{'name': '小隐', 'job': 'clerk'},
      'avatarUrl': '',
    });
  });

  testWidgets('建档:头像只传不提,地址随 SUBMIT_PROFILE 一起报(真源 avatar 分支)', (
    WidgetTester tester,
  ) async {
    final _FakeGateway gateway = _FakeGateway(startState: stateJson());
    final _FakeUploader uploader = _FakeUploader();
    final AdvancedPlayController controller = _controller(
      gateway,
      uploadPhoto: uploader.call,
    );
    await controller.start();

    // 视图必须长在**活着**的 context 里:宿主的 onUploadPhoto/提示条都要
    // Overlay —— 先捕获 Builder 的 ctx 再换整棵树,ctx 就作废了。
    await tester.pumpWidget(
      CupertinoApp(
        home: Builder(
          builder: (BuildContext context) => PlayKitProfileView(
            data: playKitFullscreenContextFor(
              context,
              controller,
              const PlayKitCard(
                kind: PlayKitKind.profile,
                title: '',
                detail: '',
                kit: <String, Object?>{
                  'avatar': <String, Object?>{
                    'enabled': true,
                    'required': false,
                  },
                },
              ),
            ),
            photoPicker: (_) async => const PlayKitQaPhoto(
              path: '/tmp/avatar-only-here.jpg',
              size: 1024,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('playkit-profile-avatar')));
    await tester.pumpAndSettle();

    // 真源 `_submitKitPhoto` 的 avatar 分支:「不发动作,只把地址写回 kit」
    expect(uploader.calls, <String>['/tmp/avatar-only-here.jpg']);
    expect(gateway.actionCalls, isEmpty, reason: '头像上传不是动作');

    await tester.tap(find.text('提交登记'));
    await tester.pumpAndSettle();
    expect(gateway.actionCalls.single.action, 'SUBMIT_PROFILE');
    expect(
      gateway.actionCalls.single.payload['avatarUrl'],
      'https://cdn.test/avatar.jpg',
      reason: '上传回来的地址要随提交一起报',
    );
  });

  test('投影·拍照审核完成口径:passed/flagged 算完;降级不卡关;没判定不算完', () {
    PlayKitCard only(Map<String, Object?> seg) =>
        projectPlayKit(<String, Object?>{'photoCheck': seg}).single;

    expect(
      only(<String, Object?>{'tries': 1}).complete,
      isFalse,
      reason: '拍过但服务端没给结论 —— 不算完',
    );
    expect(only(<String, Object?>{'passed': true}).complete, isTrue);
    expect(
      only(<String, Object?>{'flagged': true, 'fallback': 'pass'}).complete,
      isTrue,
    );
    // fail-forward:模型没给结论(降级)也标 flagged —— 放行往下走,不判死不假过
    final PlayKitCard degraded = only(<String, Object?>{
      'degraded': true,
      'flagged': true,
    });
    expect(degraded.complete, isTrue, reason: '降级卡在这一屏 = 旅程被服务端外因堵死');
  });

  testWidgets('拍照审核:shoot 走两步链,末步 SUBMIT_PHOTO_CHECK{imageUrl};不读像素不报分', (
    WidgetTester tester,
  ) async {
    final _FakeGateway gateway = _FakeGateway(startState: stateJson());
    final _FakeUploader uploader = _FakeUploader();
    final AdvancedPlayController controller = _controller(
      gateway,
      uploadPhoto: uploader.call,
    );
    await controller.start();

    // 同头像那条:两步链的提示条要 Overlay,context 必须活着。
    await tester.pumpWidget(
      CupertinoApp(
        home: Builder(
          builder: (BuildContext context) => PlayKitPhotoCheckView(
            data: playKitFullscreenContextFor(
              context,
              controller,
              const PlayKitCard(
                kind: PlayKitKind.photoCheck,
                title: '拍一张',
                detail: '',
                kit: <String, Object?>{'title': '拍一张'},
              ),
            ),
            photoPicker: (_) async =>
                const PlayKitQaPhoto(path: '/tmp/shot.jpg', size: 2048),
          ),
        ),
      ),
    );
    await tester.tap(
      find.byKey(const Key('playkit-photocheck-cta')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    // 临时路径出了这台手机就不存在 —— 必须先上传拿地址(真源同一条两步)
    expect(uploader.calls, <String>['/tmp/shot.jpg']);
    expect(gateway.actionCalls.single.action, 'SUBMIT_PHOTO_CHECK');
    expect(
      gateway.actionCalls.single.payload,
      <String, Object?>{'imageUrl': 'https://cdn.test/avatar.jpg'},
      reason: '只报图片地址 —— 客户端报的 score 可伪造,契约 §2.2 已删那套',
    );
  });

  testWidgets('拍照审核:非 photoCheck 组件伪造 shoot 一律不发(两步链限定来源)', (
    WidgetTester tester,
  ) async {
    late BuildContext ctx;
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
    final _FakeGateway gateway = _FakeGateway(startState: stateJson());
    final _FakeUploader uploader = _FakeUploader();
    final AdvancedPlayController controller = _controller(
      gateway,
      uploadPhoto: uploader.call,
    );
    await controller.start();

    final PlayKitFullscreenContext coin = playKitFullscreenContextFor(
      ctx,
      controller,
      const PlayKitCard(kind: PlayKitKind.coinFlip, title: '', detail: ''),
    );
    coin.onAction!(
      PlayKitAction(
        label: '',
        action: kPhotoCheckShootAction,
        payload: const PlayKitQaPhoto(path: '/tmp/x.jpg').toPayload(),
      ),
    );
    await tester.pumpAndSettle();
    expect(gateway.actionCalls, isEmpty);
    expect(uploader.calls, isEmpty, reason: '伪造来源连上传都不该走');
    expect(find.textContaining('没有发出去'), findsOneWidget);
  });

  test('投影·留言完成口径:done 由服务端落', () {
    expect(
      projectPlayKit(<String, Object?>{
        'note': <String, Object?>{'prompt': '给下一个人留一句'},
      }).single.complete,
      isFalse,
    );
    expect(
      projectPlayKit(<String, Object?>{
        'note': <String, Object?>{'done': true, 'mine': '别走那条路'},
      }).single.complete,
      isTrue,
    );
  });

  testWidgets('留言:空句不发;留下这句 → SUBMIT_NOTE{text};服务端回 done 后锁成已留下', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(600, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final _FakeGateway gateway = _FakeGateway(
      startState: stateJson(
        playKit: <String, Object?>{
          'note': <String, Object?>{
            'prompt': '给下一个人留一句',
            'presets': <Object?>['这家值得再来'],
            'previous': <Object?>[
              <String, Object?>{'text': '别点外卖', 'at': 1787200000000},
            ],
          },
        },
      ),
      // 提交后服务端回权威态:done + mine —— 屏上锁定依据只能是这份回执
      actionReply:
          (String action, Map<String, Object?> payload, int version, _) =>
              AdvancedPlayState.fromJson(
                stateJson(
                  playKit: <String, Object?>{
                    'note': <String, Object?>{
                      'prompt': '给下一个人留一句',
                      'presets': <Object?>['这家值得再来'],
                      'previous': <Object?>[
                        <String, Object?>{'text': '别点外卖', 'at': 1787200000000},
                      ],
                      'done': true,
                      'mine': payload['text'],
                    },
                  },
                ),
              ),
    );
    final AdvancedPlayController controller = _controller(gateway);
    await controller.start();
    await _openFullscreen(tester, controller, PlayKitKind.note);

    // 前面的人写过 —— 真源:先看见别人写了什么,才知道可以写什么
    expect(find.text('前面的人写过'), findsOneWidget);
    expect(find.text('别点外卖'), findsOneWidget);

    await tester.tap(find.text('留下这句'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(gateway.actionCalls, isEmpty, reason: '空句不发(真源 canSubmit 同一条)');

    await tester.tap(
      find.byKey(const Key('playkit-note-preset-这家值得再来')),
      warnIfMissed: false,
    );
    await tester.pump();
    await tester.tap(find.text('留下这句'));
    await tester.pumpAndSettle();

    expect(gateway.actionCalls.single.action, 'SUBMIT_NOTE');
    expect(gateway.actionCalls.single.payload, <String, Object?>{
      'text': '这家值得再来',
    });
    // 回执 done 之后:按钮锁成「已留下」,输入框回显自己那句
    expect(find.text('已留下'), findsOneWidget);
    expect(find.text('这句已经留在这儿了'), findsOneWidget);
  });

  test('投影·打字完成口径:passed 或次数用尽;tries=0 永远不算用尽', () {
    PlayKitCard only(Map<String, Object?> seg) =>
        projectPlayKit(<String, Object?>{'typeIn': seg}).single;

    expect(only(<String, Object?>{'target': '夜市口令'}).complete, isFalse);
    expect(only(<String, Object?>{'passed': true}).complete, isTrue);
    expect(
      only(<String, Object?>{'tries': 2, 'attempts': 2}).complete,
      isTrue,
      reason: '真源 segmentComplete:tries>0 && attempts>=tries',
    );
    expect(
      only(<String, Object?>{'tries': 0, 'attempts': 9}).complete,
      isFalse,
      reason: '不限次 = 永远不会因次数判完',
    );
  });

  testWidgets(
    '限时打字:先数 3-2-1 再开表(START_CHALLENGE game=typeIn),打完提交带 text/elapsedMs',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final _FakeGateway gateway = _FakeGateway(
        startState: stateJson(
          playKit: <String, Object?>{
            'typeIn': <String, Object?>{
              'target': '夜市口令',
              'seconds': 10,
              'tries': 3,
            },
          },
        ),
      );
      final AdvancedPlayController controller = _controller(gateway);
      await controller.start();
      await _openFullscreen(tester, controller, PlayKitKind.typeIn);

      // attempts=0 → 「第 1 / 3 次」;intro 提示逐字照真源
      expect(find.text('第 1 / 3 次'), findsOneWidget);
      expect(find.text('10 秒内一字不差地打完它'), findsOneWidget);

      await tester.tap(find.text('开始'));
      await tester.pump();
      expect(find.text('3'), findsOneWidget, reason: '开跑前要数(与停表同一条 count-in)');
      // 开表**不许**在数到 0 之前发出去 —— 提前开表白送玩家两秒
      expect(gateway.actionCalls, isEmpty);
      await tester.pump(const Duration(milliseconds: 620));
      await tester.pump(const Duration(milliseconds: 620));
      await tester.pump(const Duration(milliseconds: 620));
      await tester.pump();

      // 真源 CHALLENGE_GAME 第六个:不先开表,提交会被判「还没开始」
      expect(gateway.actionCalls.single.action, 'START_CHALLENGE');
      expect(gateway.actionCalls.single.payload, <String, Object?>{
        'game': 'typeIn',
      });

      gateway.actionCalls.clear();
      await tester.enterText(
        find.byKey(const Key('playkit-typein-input')),
        '夜市口令',
      );
      await tester.pump();
      await tester.tap(find.text('打完提交'));
      await tester.pumpAndSettle();

      final ({String action, Map<String, Object?> payload}) submit =
          gateway.actionCalls.single;
      expect(submit.action, 'SUBMIT_TYPE_IN');
      expect(submit.payload['text'], '夜市口令');
      expect(
        submit.payload['elapsedMs'],
        isA<int>(),
        reason: '设备时钟读数(整数毫秒),服务端拿开表时间复核',
      );
    },
  );

  testWidgets('限时打字:到点不交、不假发提交;再来一次重新开表', (WidgetTester tester) async {
    final DateTime t0 = DateTime(2026, 9, 19, 20);
    int offsetMs = 0;
    final List<PlayKitAction> emitted = <PlayKitAction>[];
    await tester.pumpWidget(
      CupertinoApp(
        home: PlayKitTypeInView(
          countIn: false,
          now: () => t0.add(Duration(milliseconds: offsetMs)),
          data: PlayKitFullscreenContext(
            card: const PlayKitCard(
              kind: PlayKitKind.typeIn,
              title: '打出这行字',
              detail: '',
              kit: <String, Object?>{'target': '口令', 'seconds': 5},
            ),
            enabled: true,
            onAction: emitted.add,
          ),
        ),
      ),
    );
    await tester.tap(find.text('开始'));
    await tester.pump();
    expect(emitted.map((PlayKitAction a) => a.action), <String>[
      'START_CHALLENGE',
    ]);

    // 时钟走过 5 秒 → 到点收表:没有提交发出去,屏上说清「这一局没交出去」
    offsetMs = 6000;
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(
      emitted.map((PlayKitAction a) => a.action),
      <String>['START_CHALLENGE'],
      reason: '超时由服务端复核,组件不自己补发一次 SUBMIT',
    );
    expect(find.textContaining('时间到'), findsOneWidget);

    // 再来一次 = 重新开表(服务端那边的成绩窗口跟着新的一刻走)
    await tester.tap(find.text('开始'));
    await tester.pump();
    expect(emitted.map((PlayKitAction a) => a.action), <String>[
      'START_CHALLENGE',
      'START_CHALLENGE',
    ]);
  });

  testWidgets('判定回读:attempts 涨 → 回 intro 重开表;passed → 锁死「一字不差」', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(600, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    Map<String, Object?> kitOf(bool passed, int attempts) => <String, Object?>{
      'typeIn': <String, Object?>{
        'target': '夜市口令',
        'seconds': 10,
        'tries': 3,
        'attempts': attempts,
        'passed': passed,
      },
    };
    final _FakeGateway gateway = _FakeGateway(
      startState: stateJson(playKit: kitOf(false, 1)),
    );
    final AdvancedPlayController controller = _controller(gateway);
    await controller.start();
    await _openFullscreen(tester, controller, PlayKitKind.typeIn);
    expect(find.text('第 2 / 3 次'), findsOneWidget);

    // 服务端回读 attempts=2:屏上的次数行跟着涨(客户端不自增)——
    // 走 refreshAuthoritative 这条真路:重读 `state` 端点、整份替换。
    gateway.readbackState = stateJson(playKit: kitOf(false, 2));
    await controller.refreshAuthoritative();
    await tester.pumpAndSettle();
    expect(find.text('第 3 / 3 次'), findsOneWidget);

    gateway.readbackState = stateJson(playKit: kitOf(true, 2));
    await controller.refreshAuthoritative();
    await tester.pumpAndSettle();
    expect(find.text('一字不差'), findsOneWidget);
    expect(find.text('已完成'), findsOneWidget);
  });

  testWidgets('负控:建档组件抛别的 kind 的动作名 → 一发不发,给一次原生提示', (
    WidgetTester tester,
  ) async {
    late BuildContext ctx;
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
    final _FakeGateway gateway = _FakeGateway(startState: stateJson());
    final AdvancedPlayController controller = _controller(gateway);
    await controller.start();
    final PlayKitFullscreenContext data = playKitFullscreenContextFor(
      ctx,
      controller,
      const PlayKitCard(kind: PlayKitKind.profile, title: '', detail: ''),
    );
    data.onAction!(const PlayKitAction(label: '', action: 'SUBMIT_NOTE'));
    await tester.pumpAndSettle();
    expect(gateway.actionCalls, isEmpty, reason: '在册,但不属于这个 kind —— 真源两栏一起查');
    expect(find.textContaining('没有发出去'), findsOneWidget);
  });
}

AdvancedPlayController _controller(
  _FakeGateway gateway, {
  Future<String> Function(String filePath)? uploadPhoto,
}) {
  final AdvancedPlayController controller = AdvancedPlayController(
    gateway: gateway,
    activityId: 3,
    topicId: 0,
    nodeId: 11,
    uploadPhoto: uploadPhoto,
  );
  addTearDown(controller.dispose);
  return controller;
}

/// 走宿主那条缝打开整屏呈现层(注册表 → 组件),不经 sheet 那一格入口。
Future<void> _openFullscreen(
  WidgetTester tester,
  AdvancedPlayController controller,
  PlayKitKind kind,
) async {
  late BuildContext ctx;
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
  // push 回来的 Future 要等**弹层关掉**才完成 —— 不 await(与宿主测试同一条开法),
  // await 在这里就是等自己关页面,死锁。
  unawaited(
    showPlayKitOverlay(context: ctx, controller: controller, kind: kind),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

class _FakeGateway implements AdvancedPlayGateway {
  _FakeGateway({required this.startState, this.actionReply});

  final Map<String, dynamic> startState;
  AdvancedPlayState Function(String, Map<String, Object?>, int, String)?
  actionReply;

  /// `state` 端点的回读值 —— 判定落地后服务端那份权威态(不填就用 startState)。
  Map<String, dynamic>? readbackState;
  final List<({String action, Map<String, Object?> payload})> actionCalls =
      <({String action, Map<String, Object?> payload})>[];

  @override
  Future<AdvancedPlayState> start({
    required int activityId,
    required int topicId,
    required int nodeId,
  }) async => AdvancedPlayState.fromJson(startState);

  @override
  Future<AdvancedPlayState> action({
    required int sessionId,
    required int version,
    required String idempotencyKey,
    required String action,
    required Map<String, Object?> payload,
  }) async {
    actionCalls.add((action: action, payload: payload));
    final AdvancedPlayState Function(String, Map<String, Object?>, int, String)?
    reply = actionReply;
    return reply == null
        ? AdvancedPlayState.fromJson(startState)
        : reply(action, payload, version, idempotencyKey);
  }

  @override
  Future<AdvancedPlayState> state(int sessionId) async =>
      AdvancedPlayState.fromJson(readbackState ?? startState);

  @override
  Future<List<AdvancedPlayLeaderboardRow>> leaderboard({
    required int activityId,
    required int topicId,
    required int nodeId,
  }) async => const <AdvancedPlayLeaderboardRow>[];
}

class _FakeUploader {
  final List<String> calls = <String>[];

  Future<String> call(String filePath) async {
    calls.add(filePath);
    return 'https://cdn.test/avatar.jpg';
  }
}
