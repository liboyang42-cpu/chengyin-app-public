import 'playkit_fullscreen_logic.dart';
import '../playkit_projection.dart';

/// 整屏族的**宿主层**动作翻译:组件按玩家读得懂的单位报,服务端按判定
/// 要用的单位收。
///
/// 这是小程序 `utils/playkit-view.js` 的 `serverPayload` 在 App 侧的镜像
/// (只覆盖本批五件套:coinFlip / diceRoll / reaction / ballShake / quietHold;
/// 其余批次各补各的)。**单位换算只在这一层做** ——
///
/// * `reaction` 的 `times`(每轮毫秒数组)→ `roundsMs`
/// * `quiethold` 的 `heldSeconds`(秒)→ `heldMs`(毫秒)
/// * `ballshake` 的 `hits` 原样(它本来就按服务端口径报)
/// * `coinflip` / `diceroll` 不带参数 —— 结果服务端算,客户端说了不算
///
/// ⚠️ 不换算的后果不是报错,是**服务端读不到字段按 0 判,永远不通过**。
/// 宿主把 [PlayKitAction] 交给 `AdvancedPlayController.submit` 之前必须过一遍。
Map<String, Object?> playKitServerPayload(
  PlayKitKind kind,
  String action,
  Map<String, Object?> detail,
) {
  switch (action) {
    case 'START_CHALLENGE':
      // 挑战类的开表:服务端拿这一刻的**服务器时间**复核成绩。game 值由
      // kind 反推(权威),组件即使漏带也不会发出一条错的开表。
      final String game = playKitChallengeGameOf(kind);
      // 本层还不认识的 kind(别的批次的 countdown / stopwatch):原样透传组件
      // 报的 game。覆写成空串会让那条开表变成无效请求 —— 服务端判「还没开始」,
      // 成绩直接作废,而且不报错。
      return game.isEmpty
          ? <String, Object?>{...detail}
          : <String, Object?>{'game': game};
    case 'SUBMIT_REACTION':
      return <String, Object?>{'roundsMs': _intList(detail['times'])};
    case 'SUBMIT_BALL_SHAKE':
      return <String, Object?>{'hits': _asInt(detail['hits'])};
    case 'SUBMIT_QUIET_HOLD':
      return <String, Object?>{
        'heldMs': heldSecondsToMs(_asNum(detail['heldSeconds'])),
      };
    case 'FLIP_COIN':
    case 'ROLL_DICE':
      // 抽什么由服务端定:结果由服务端算,客户端说了不算。
      return const <String, Object?>{};
    default:
      return detail;
  }
}

/// 挑战类玩法 → START_CHALLENGE 的 game 值。**服务端只认这几个驼峰名**
/// (与小程序的 `CHALLENGE_GAME` 同源;countdown / stopwatch 由各自批次补)。
String playKitChallengeGameOf(PlayKitKind kind) => switch (kind) {
  PlayKitKind.reaction => 'reaction',
  PlayKitKind.ballShake => 'ballShake',
  PlayKitKind.quietHold => 'quietHold',
  // 真源 CHALLENGE_GAME 第六个:限时打字(`playkit-view.js` 原文
  // 「六个挑战类都要先开表(原来五个 + typeIn)」)。
  PlayKitKind.typeIn => 'typeIn',
  _ => '',
};

List<int> _intList(Object? value) => value is List
    ? <int>[
        for (final Object? item in value)
          if (item is num) item.toInt(),
      ]
    : const <int>[];

int _asInt(Object? value) => value is num ? value.toInt() : 0;

num _asNum(Object? value) => value is num ? value : 0;
