import 'package:chengyin_app/data/api/advanced_play_api.dart';
import 'package:chengyin_app/data/models/advanced_play.dart';
import 'package:chengyin_app/feature/play/advanced/advanced_play_controller.dart';
import 'package:chengyin_app/feature/play/advanced/playkit_host.dart';
import 'package:chengyin_app/feature/play/advanced/playkit_projection.dart';
import 'package:flutter_test/flutter_test.dart';

/// `present`(施工契约 §1.5)的解析与壳判定投影。
///
/// 真源三条口径逐一钉住:
/// - 值在服务端解好下发(视图根层 `present`,恒 inline / fullscreen;默认表只在
///   `AdvancedGameConfigValidator#resolvePresent` 一份,客户端不重推);
/// - 归一逐字对齐 `pages/play/utils/playkit-view.js#presentOf`(:346-348):
///   **只有字面量 'inline' 算内嵌**,缺失 / 非法一律 fullscreen(存量行为逐字不变);
/// - 判定盖在投影出的卡上(`pickPlayKit` 的 `base.present`,:369-370)——
///   宿主维持现行壳,故事流线(a4-playkit-storyflow)按卡消费。
void main() {
  Map<String, dynamic> stateJson({
    Object? present,
    Map<String, Object?> playKit = const <String, Object?>{},
    bool omitPresent = false,
  }) => <String, dynamic>{
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
      'multiplayer': <String, dynamic>{'enabled': false},
    },
    'draws': <dynamic>[],
    'playKit': playKit,
    'multiplayer': <String, dynamic>{},
    if (!omitPresent) 'present': present,
  };

  group('playKitPresentationOf(真源 presentOf 逐值)', () {
    test("'inline' → inline", () {
      expect(playKitPresentationOf('inline'), PlayKitPresentation.inline);
    });
    test("'fullscreen' → fullscreen", () {
      expect(
        playKitPresentationOf('fullscreen'),
        PlayKitPresentation.fullscreen,
      );
    });
    test('缺字段 / null → fullscreen(存量行为逐字不变)', () {
      expect(playKitPresentationOf(null), PlayKitPresentation.fullscreen);
    });
    test('非法值一律 fullscreen:大小写、数字、非 inline 字符串都不算内嵌', () {
      // 真源是 `=== 'inline'` 严格比较:'INLINE' / 'Inline' 都落 fullscreen。
      expect(playKitPresentationOf('INLINE'), PlayKitPresentation.fullscreen);
      expect(playKitPresentationOf('Inline'), PlayKitPresentation.fullscreen);
      expect(playKitPresentationOf(123), PlayKitPresentation.fullscreen);
      expect(playKitPresentationOf(true), PlayKitPresentation.fullscreen);
      expect(playKitPresentationOf(''), PlayKitPresentation.fullscreen);
      expect(
        playKitPresentationOf(<String>['inline']),
        PlayKitPresentation.fullscreen,
      );
    });
  });

  group('AdvancedPlayState 解析视图根层 present', () {
    test("显式 'inline' 原样存", () {
      expect(
        AdvancedPlayState.fromJson(stateJson(present: 'inline')).present,
        'inline',
      );
    });
    test('字段缺失 → 默认 fullscreen', () {
      expect(
        AdvancedPlayState.fromJson(stateJson(omitPresent: true)).present,
        'fullscreen',
      );
      expect(
        AdvancedPlayState.fromJson(stateJson(present: null)).present,
        'fullscreen',
      );
    });
    test('非法值不炸:模型解析层归一成 fullscreen(只认字面量 inline)', () {
      final AdvancedPlayState state = AdvancedPlayState.fromJson(
        stateJson(present: 'sideways'),
      );
      expect(state.present, 'fullscreen');
      expect(
        playKitPresentationOf(state.present),
        PlayKitPresentation.fullscreen,
      );
    });
  });

  group('projectPlayKit 把判定盖到投影卡上', () {
    const Map<String, Object?> qaSegment = <String, Object?>{
      'qa': <String, Object?>{'mode': 'TYPE', 'title': '这座桥建于哪一年?'},
    };

    test('不传 present(旧调用口径)→ 卡上是 fullscreen,行为不回退', () {
      final List<PlayKitCard> cards = projectPlayKit(qaSegment);
      expect(cards, hasLength(1));
      expect(cards.single.present, PlayKitPresentation.fullscreen);
    });
    test('传 inline → 选出的单卡带 inline', () {
      final List<PlayKitCard> cards = projectPlayKit(
        qaSegment,
        present: PlayKitPresentation.inline,
      );
      expect(cards.single.kind, PlayKitKind.qa);
      expect(cards.single.present, PlayKitPresentation.inline);
    });
    test('空 playKit → 空投影,不造卡也不造判定', () {
      expect(
        projectPlayKit(
          <String, Object?>{},
          present: PlayKitPresentation.inline,
        ),
        isEmpty,
      );
    });
    test('判定只改 present:其余字段逐字跟着单卡走', () {
      final PlayKitCard plain = projectPlayKit(qaSegment).single;
      final PlayKitCard stamped = projectPlayKit(
        qaSegment,
        present: PlayKitPresentation.inline,
      ).single;
      expect(stamped.kind, plain.kind);
      expect(stamped.title, plain.title);
      expect(stamped.detail, plain.detail);
      expect(stamped.complete, plain.complete);
      expect(stamped.kit, plain.kit);
      expect(stamped.present, isNot(plain.present));
    });
  });

  group('宿主 resolvePlayKitCard 从会话视图取判定(现取,不用旧卡)', () {
    Future<AdvancedPlayController> started(Map<String, dynamic> view) async {
      final AdvancedPlayController controller = AdvancedPlayController(
        gateway: _FakeGateway(startState: view),
        activityId: 3,
        topicId: 0,
        nodeId: 11,
      );
      addTearDown(controller.dispose);
      await controller.start();
      return controller;
    }

    test('收窄路径(段在 playKit 里)也带 inline', () async {
      final AdvancedPlayController controller = await started(
        stateJson(
          present: 'inline',
          playKit: const <String, Object?>{
            'qa': <String, Object?>{'mode': 'TYPE', 'title': '哪一年?'},
          },
        ),
      );
      expect(
        resolvePlayKitCard(controller, PlayKitKind.qa).present,
        PlayKitPresentation.inline,
      );
    });
    test('本地 kind(服务端不下发段)的兜底卡也随视图,不给假默认值', () async {
      final AdvancedPlayController controller = await started(
        stateJson(present: 'inline'),
      );
      expect(
        resolvePlayKitCard(controller, PlayKitKind.gameTimer).present,
        PlayKitPresentation.inline,
      );
    });
    test('视图没带 present → fullscreen,整屏/半屏壳行为不回退', () async {
      final AdvancedPlayController controller = await started(
        stateJson(
          omitPresent: true,
          playKit: const <String, Object?>{
            'qa': <String, Object?>{'mode': 'TYPE', 'title': '哪一年?'},
          },
        ),
      );
      expect(
        resolvePlayKitCard(controller, PlayKitKind.qa).present,
        PlayKitPresentation.fullscreen,
      );
    });
  });
}

class _FakeGateway implements AdvancedPlayGateway {
  _FakeGateway({required this.startState});

  final Map<String, dynamic> startState;

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
  }) async => AdvancedPlayState.fromJson(startState);

  @override
  Future<AdvancedPlayState> state(int sessionId) async =>
      AdvancedPlayState.fromJson(startState);

  @override
  Future<List<AdvancedPlayLeaderboardRow>> leaderboard({
    required int activityId,
    required int topicId,
    required int nodeId,
  }) async => const <AdvancedPlayLeaderboardRow>[];
}
