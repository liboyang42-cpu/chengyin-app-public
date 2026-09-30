/// 问答 / 判定族五屏(qa · branch · estimate · pricePair · hiddenObject)的数据层。
///
/// 真源 = 小程序:
/// - `utils/playkit-view.js#pickPlayKit` 的各分支(服务端视图 → 组件 props);
/// - `pages/play/components/playkit-{qa,branch,estimate,pricepair,hidden}/index.js`
///   的 `properties`;
/// - 载荷换算逐条对齐 `utils/playkit-view.js#serverPayload` 与
///   `tests/fixtures/playkit-server-actions.json`(那份夹具后端也在读)。
///
/// ## 三条口径(照抄小程序原文,不是本层自创)
/// 1. **结果一律由服务端定**。这里不判对错、不算走向、不猜答案 ——
///    「选项文案要给,**哪个是对的不能给** —— 判定回来之后才知道」;
///    branch 的走向也只有服务端知道(投影里没有 nextStepId)。
/// 2. **字段名/单位换算在这一层做**。组件按玩家读的命名与单位收,
///    服务端按判定用的命名与单位收(如 `guess → value`、百分比 → 比例)。
///    少一条不会报错,只是玩家做完那一下**什么也没发生**。
/// 3. **越界不伪装**。找东西的坐标出了图就**不发**(见 [percentInScene]),
///    不是夹一下当合法值发出去 —— 那种点本来就该被服务端拒。
library;

import 'dart:ui' show Offset, Size;

import 'package:flutter/foundation.dart';

/// 问答三档(`qa` 一个 kind,三种模式共用一屏)。
enum PlayKitQaMode {
  type,
  pick,
  shot;

  /// 服务端给的是大写枚举(`TYPE` / `PICK` / `SHOT`),容错收小写。
  static PlayKitQaMode parse(Object? raw) {
    switch ('$raw'.trim().toUpperCase()) {
      case 'PICK':
        return PlayKitQaMode.pick;
      case 'SHOT':
        return PlayKitQaMode.shot;
      default:
        return PlayKitQaMode.type;
    }
  }

}

/// 选项 / 待找目标共用的最小形状:id + 文案。
@immutable
class PlayKitQuizOption {
  const PlayKitQuizOption({required this.id, required this.label});

  /// 服务端给的 id 要带着走:判定按 id 认,下标在它那边没有意义。
  final String id;
  final String label;

  static PlayKitQuizOption? from(Object? raw) {
    if (raw is! Map) return null;
    final Map<Object?, Object?> map = raw;
    final String id = '${map['id'] ?? ''}'.trim();
    // 文案字段两种写法都收:服务端段里是 `label`,小程序那一层翻给组件时叫 `t`。
    final String label = '${map['label'] ?? map['t'] ?? ''}'.trim();
    if (id.isEmpty && label.isEmpty) return null;
    // 选项附件角标(`img` / `audio`)不解析:小程序 `pickPlayKit` 把 options
    // 只留 `{id, t}`,那两枚角标在真机永远不亮 —— 解析了也只落个没人读的字段。
    return PlayKitQuizOption(id: id, label: label);
  }

  static List<PlayKitQuizOption> listFrom(Object? raw) => (raw is List ? raw : const <Object?>[])
      .map(PlayKitQuizOption.from)
      .whereType<PlayKitQuizOption>()
      .toList(growable: false);

  /// A / B / C / D —— 与小程序 `KEYS` 同序,第 5 条起回落到序号。
  static String keyLabel(int index) => index < 4 ? const <String>['A', 'B', 'C', 'D'][index] : '${index + 1}';
}

/// `qa` 一屏的全部数据(打字 / 选项 / 拍照共用)。
@immutable
class PlayKitQaData {
  const PlayKitQaData({
    required this.mode,
    required this.title,
    required this.lead,
    required this.imageUrl,
    required this.audioUrl,
    required this.options,
    required this.shotLead,
    required this.maxTries,
    required this.finished,
    required this.passed,
    required this.feedback,
  });

  final PlayKitQaMode mode;
  final String title;
  final String lead;
  final String imageUrl;
  final String audioUrl;
  final List<PlayKitQuizOption> options;
  final String shotLead;
  final int maxTries;
  final bool finished;
  final bool passed;
  final String feedback;

  /// 拍照那一档的大字默认回落成题干 —— 两处印同一句话时只留中间那一句。
  String get headline {
    final String value = mode == PlayKitQaMode.shot
        ? (shotLead.isEmpty ? title : shotLead)
        : title;
    return value;
  }

  factory PlayKitQaData.fromKit(Map<String, Object?> kit) => PlayKitQaData(
    mode: PlayKitQaMode.parse(kit['mode']),
    title: _text(kit['title']),
    lead: _text(kit['lead']),
    imageUrl: _text(kit['imageUrl']),
    audioUrl: _text(kit['audioUrl']),
    options: PlayKitQuizOption.listFrom(kit['options']),
    // 拍照那一档的大字是小程序投影算出来的:`shotLead = seg.lead || seg.title`
    // (原始段里没有 `shotLead` 这个键)。`shotNote` 同理 —— 投影从不给它赋值。
    shotLead: _text(kit['shotLead'], _text(kit['lead'], _text(kit['title']))),
    maxTries: _int(kit['maxTries']),
    finished: kit['finished'] == true,
    passed: kit['passed'] == true,
    // 服务端段里的字段叫 `lastFeedback`(`feedback` 是容错的老写法)。
    feedback: _text(kit['lastFeedback'], _text(kit['feedback'], '')),
  );

  /// 次数按「选项数 - 1」封顶:三个选项给三次错等于白给 ——
  /// 错满两次之后剩下的那个必然是答案,第三次不是机会是走过场。
  /// 与小程序 `cappedTries` 同一口径,`0` 表示不限。
  int get triesCap {
    final int n = maxTries > 0 ? maxTries : 0;
    if (n == 0 || options.length <= 1) return n;
    return n < options.length - 1 ? n : options.length - 1;
  }
}

/// `branch` 一屏:界面和问答一样,只是选项决定下一段,**不判对错**。
@immutable
class PlayKitBranchData {
  const PlayKitBranchData({
    required this.title,
    required this.body,
    required this.options,
    required this.ended,
  });

  final String title;
  final String body;
  final List<PlayKitQuizOption> options;

  /// 终点由服务端说了算(`currentStep.terminal`),不由客户端猜。
  final bool ended;

  /// 服务端只下发**当前这一步**(`currentStep`),整棵树不下发 ——
  /// 跳转表发到客户端等于把所有结局提前剧透。走向只有服务端知道。
  factory PlayKitBranchData.fromKit(Map<String, Object?> kit) {
    final Object? rawStep = kit['currentStep'];
    final Map<String, Object?> step = rawStep is Map
        ? rawStep.map<String, Object?>((key, value) => MapEntry('$key', value))
        : kit;
    return PlayKitBranchData(
      title: _text(step['title']),
      body: _text(step['body']),
      options: PlayKitQuizOption.listFrom(step['options']),
      ended: step['terminal'] == true || kit['ended'] == true,
    );
  }
}

/// `estimate` 一屏:滚筒 + 一个数。判定在服务端,客户端只报「我停在哪个数」。
@immutable
class PlayKitEstimateData {
  const PlayKitEstimateData({
    required this.title,
    required this.unit,
    required this.minValue,
    required this.maxValue,
    required this.maxTries,
    required this.submitted,
    required this.feedback,
  });

  final String title;
  final String unit;
  final num minValue;
  final num maxValue;

  /// 可以错几次(0 = 不限)。
  ///
  /// ⚠️ 这一段在服务端里叫 `maxAttempts`,是**它自己的**字段名(问答/猜图那两段
  /// 叫 `maxTries`)—— 小程序投影同一条:`maxTries: seg.maxAttempts || 0`。
  /// 组件拿它喂给舞台画「还能错」的点;照着改名会把这一屏的次数静默丢掉。
  final int maxTries;
  final bool submitted;
  final String feedback;

  factory PlayKitEstimateData.fromKit(Map<String, Object?> kit) => PlayKitEstimateData(
    // 服务端段里题面叫 `question`(`title` 是容错的老写法)。
    title: _text(kit['question'], _text(kit['title'], '')),
    unit: _text(kit['unit']),
    minValue: _num(kit['min']),
    maxValue: _num(kit['max']),
    maxTries: _int(kit['maxAttempts'] ?? kit['maxTries']),
    submitted: kit['submitted'] == true,
    // 判定那一句解释:小程序 qa 段里叫 `lastFeedback`,其余三段由 verdict 事件
    // 回灌(投影没登记字段名)。两种写法都收,服务端给哪个用哪个。
    feedback: _text(kit['lastFeedback'], _text(kit['feedback'], '')),
  );

  List<num> get ticks => buildEstimateTicks(minValue, maxValue);
}

/// `pricePair` 一屏里的一张海报。
@immutable
class PlayKitPricePairItem {
  const PlayKitPricePairItem({
    required this.id,
    required this.name,
    required this.note,
    required this.imageUrl,
  });

  final String id;
  final String name;
  final String note;
  final String imageUrl;

  static PlayKitPricePairItem? from(Object? raw, int index) {
    if (raw is! Map) return null;
    final Map<Object?, Object?> map = raw;
    final String id = '${map['id'] ?? ''}'.trim();
    final String name = '${map['name'] ?? ''}'.trim();
    return PlayKitPricePairItem(
      id: id.isEmpty ? 'i$index' : id,
      name: name.isEmpty ? '图 ${index + 1}' : name,
      note: '${map['note'] ?? ''}'.trim(),
      imageUrl: '${map['imageUrl'] ?? ''}'.trim(),
    );
  }
}

/// `pricePair` 一屏。哪一张是对的服务端不给 —— 判定回来之后才知道。
@immutable
class PlayKitPricePairData {
  const PlayKitPricePairData({
    required this.title,
    required this.items,
    required this.maxTries,
    required this.attempts,
    required this.finished,
    required this.passed,
    required this.feedback,
  });

  final String title;
  final List<PlayKitPricePairItem> items;
  final int maxTries;
  final int attempts;
  final bool finished;
  final bool passed;
  final String feedback;

  factory PlayKitPricePairData.fromKit(Map<String, Object?> kit) => PlayKitPricePairData(
    title: _text(kit['title']),
    items: (kit['items'] is List ? kit['items']! as List : const <Object?>[])
        .asMap()
        .entries
        .map((entry) => PlayKitPricePairItem.from(entry.value, entry.key))
        .whereType<PlayKitPricePairItem>()
        .toList(growable: false),
    maxTries: _int(kit['maxTries']),
    attempts: _int(kit['attempts']),
    finished: kit['finished'] == true,
    passed: kit['passed'] == true,
    feedback: _text(kit['lastFeedback'], _text(kit['feedback'], '')),
  );
}

/// `hiddenObject` 的待找目标。**只有 id + label,没有坐标** ——
/// 坐标是这个玩法唯一的防线,服务端也不下发。
@immutable
class PlayKitHiddenTarget {
  const PlayKitHiddenTarget({required this.id, required this.label, required this.found});

  final String id;
  final String label;
  final bool found;

  static PlayKitHiddenTarget? from(Object? raw) {
    if (raw is! Map) return null;
    final Map<Object?, Object?> map = raw;
    final String id = '${map['id'] ?? ''}'.trim();
    final String label = '${map['label'] ?? ''}'.trim();
    if (id.isEmpty && label.isEmpty) return null;
    return PlayKitHiddenTarget(id: id, label: label, found: map['found'] == true);
  }
}

/// `hiddenObject` 一屏:点一下你觉得藏着的地方。
@immutable
class PlayKitHiddenData {
  const PlayKitHiddenData({
    required this.title,
    required this.imageUrl,
    required this.targets,
    required this.total,
    required this.foundIds,
    required this.feedback,
  });

  final String title;
  final String imageUrl;
  final List<PlayKitHiddenTarget> targets;
  final int total;
  final List<String> foundIds;

  /// 服务端最近一句反馈(没有就是空串)。找东西这一屏不判对错,
  /// 这句话只是把服务端的原话摆出来 —— 组件不自己编。
  final String feedback;

  factory PlayKitHiddenData.fromKit(Map<String, Object?> kit) {
    final List<String> found = (kit['foundIds'] is List ? kit['foundIds']! as List : const <Object?>[])
        .map((Object? id) => '$id')
        .toList(growable: false);
    final List<PlayKitHiddenTarget> raw = (kit['targets'] is List ? kit['targets']! as List : const <Object?>[])
        .map(PlayKitHiddenTarget.from)
        .whereType<PlayKitHiddenTarget>()
        .toList(growable: false);
    return PlayKitHiddenData(
      title: _text(kit['title']),
      imageUrl: _text(kit['imageUrl']),
      // 服务端回了 foundIds 就按它标已找到(重进时不要把找过的又说成没找过)。
      targets: <PlayKitHiddenTarget>[
        for (final PlayKitHiddenTarget target in raw)
          target.found || found.contains(target.id)
              ? PlayKitHiddenTarget(id: target.id, label: target.label, found: true)
              : target,
      ],
      total: _int(kit['total']) > 0 ? _int(kit['total']) : raw.length,
      foundIds: found,
      feedback: _text(kit['lastFeedback'], _text(kit['feedback'], '')),
    );
  }

  int get foundCount => targets.where((PlayKitHiddenTarget target) => target.found).length;

  /// 全找齐 = 这一关过了(服务端也会按同一条判,这里只用于文案)。
  bool get allFound => total > 0 && foundCount >= total;
}

// ── 载荷换算(组件 → 服务端)────────────────────────────────
//
// 真源:`utils/playkit-view.js#serverPayload` + `ACTION_OF`。
// 动作名一律用服务端认的那一份;不在册的一律不发,避免拼出服务端不认识的动作名。

const String kQaSubmitAction = 'SUBMIT_QA';
const String kBranchChooseAction = 'CHOOSE';
const String kEstimateSubmitAction = 'SUBMIT_ESTIMATE';
const String kPricePairSubmitAction = 'SUBMIT_PRICE_PAIR';
const String kHiddenSubmitAction = 'SUBMIT_HIDDEN_OBJECT';

/// 拍照问答**不在动作表里**:它得先把照片传上去拿到地址,再连地址一起提交 ——
/// 那是两步,宿主单独处理。放进一步直发的路径会被当成一次提交发出去,
/// 而组件手里只有一个出了这台手机就不存在的临时路径。
const String kQaShootAction = 'qa:shoot';

/// 打字题报 `input`,选项题报 `optionId` —— 按模式只给其中一个。
///
/// ⚠️ 拍照档不在这里:它走 [kQaShootAction] 两步链。传 [PlayKitQaMode.shot]
/// 进来直接抛,免得有人把它塞进一步直发的路径。
Map<String, Object?> qaSubmitPayload({
  required PlayKitQaMode mode,
  String input = '',
  String optionId = '',
}) {
  switch (mode) {
    case PlayKitQaMode.shot:
      throw ArgumentError('拍照问答是两步:先上传拿地址,再连地址提交(见 kQaShootAction)');
    case PlayKitQaMode.pick:
      return <String, Object?>{'optionId': optionId};
    case PlayKitQaMode.type:
      return <String, Object?>{'input': input};
  }
}

/// 组件报 `guess`,服务端收 `{value}`。
Map<String, Object?> estimateSubmitPayload(num guess) => <String, Object?>{'value': guess};

/// 走向由服务端按 optionId 判,下标在它那边没有意义。
Map<String, Object?> branchChoosePayload(String optionId) => <String, Object?>{'optionId': optionId};

Map<String, Object?> pricePairSubmitPayload(String pickId) => <String, Object?>{'pickId': pickId};

/// 百分比 → 比例,四舍五入到 4 位小数,并夹回 [0,1](与小程序 `ratioOf` 同一条)。
///
/// ★ 为什么两端单位不同:组件按百分比定位(它的定位样式就是百分比),
/// 服务端按比例收(热区配置也是比例)。不换的话每一次点击都会被
/// 「点击位置必须是 0 到 1 之间的比例值」打回来,这个玩法整个玩不了。
double ratioOf(num percent) {
  final double n = percent.toDouble();
  if (n.isNaN || n.isInfinite) return 0;
  final double ratio = double.parse((n / 100).toStringAsFixed(4));
  return ratio.clamp(0, 1).toDouble();
}

Map<String, Object?> hiddenSubmitPayload(num xPercent, num yPercent) =>
    <String, Object?>{'x': ratioOf(xPercent), 'y': ratioOf(yPercent)};

/// 触点 → 相对底图的百分比坐标(0–100)。
///
/// 出了图就返回 null:**这一下不算**,由调用方给一次「我收到了,但不算」的反馈。
/// 不夹回 100 再发 —— 那不是「点在图角上」,是点在图外面。
@immutable
class PlayKitScenePercent {
  const PlayKitScenePercent(this.x, this.y);

  final double x;
  final double y;
}

PlayKitScenePercent? percentInScene(Offset local, Size size) {
  if (size.width <= 0 || size.height <= 0) return null;
  final double x = local.dx / size.width * 100;
  final double y = local.dy / size.height * 100;
  if (x < 0 || x > 100 || y < 0 || y > 100) return null;
  return PlayKitScenePercent(_round2(x), _round2(y));
}

// ── 估数滚筒的纯算法(与小程序逐条同口径)────────────────────

/// 滚筒的刻度。★ 它是**滚轮**:中间是 500,上下就该是 499 和 501。
/// 只有超宽量程才跳格(原生 picker 撑得住一两千个刻度,几万个会卡)。
num estimateStepFor(num min, num max) {
  final num span = max - min;
  if (span <= 2000) return 1;
  if (span <= 20000) return 10;
  final int digits = span.round().toString().length;
  return _pow10(digits - 3);
}

/// 刻度表。上限一定要落在表里,不然滑到底选不到量程上限。
List<num> buildEstimateTicks(num min, num max) {
  final num lo = min;
  final num hi = max > lo ? max : lo + 100;
  final num step = estimateStepFor(lo, hi);
  final List<num> out = <num>[];
  for (num v = lo; v <= hi; v += step) {
    out.add(_tidy(v));
  }
  if (out.isEmpty || out.last != _tidy(hi)) out.add(_tidy(hi));
  return out;
}

/// 开局停在哪一格:量程正中。停在 0 会让人以为还没开始,停在答案附近是作弊。
int estimateInitialIndex(List<num> ticks) => ticks.isEmpty ? 0 : ticks.length ~/ 2;

/// 屏上印的那个数:整数不带小数点(JS `String(500)` 就是这个形状)。
String estimateNumberText(num value) {
  if (value == value.roundToDouble()) return value.round().toString();
  return '$value';
}

num _pow10(int exponent) {
  num value = 1;
  if (exponent <= 0) return 1;
  for (int i = 0; i < exponent; i++) {
    value *= 10;
  }
  return value;
}

num _tidy(num value) => value is int ? value : (value.toDouble() == value.roundToDouble() ? value.round() : value);

double _round2(double value) => double.parse(value.toStringAsFixed(2));

/// 取文本;空串/空白落到 [fallback](别的字段的容错写法直接用第二个参数)。
String _text(Object? value, [String fallback = '']) {
  final String text = '${value ?? ''}'.trim();
  return text.isEmpty ? fallback : text;
}

int _int(Object? value) {
  if (value is num) return value.toInt();
  return int.tryParse('${value ?? ''}'.trim()) ?? 0;
}

num _num(Object? value) {
  if (value is num) return value;
  return num.tryParse('${value ?? ''}'.trim()) ?? 0;
}
