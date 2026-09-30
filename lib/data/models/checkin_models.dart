/// 游玩/打卡相关模型,字段对齐后端 `ApiPlayProgressController`:
/// - GET  /api/play/nodes    节点列表+进度(按 activityId)
/// - POST /api/play/checkin  扫码打卡(activityId+code,后端用 code 反查节点)
///
/// 旧版的 mock 模型(CheckinNode/ProofMethod + 模拟围栏距离)已删除:真实闭环
/// 是 activityId 驱动、扫码定位节点,不再有"模拟走进围栏"的占位概念。
library;

import 'dart:convert';

import 'play_route_state.dart' as legacy_route;

int _asInt(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;

/// 可空整数:解析不出来就是 null(不落回 0 —— `0 分钟` 是编出来的信息)。
int? _nullableInt(Object? v) =>
    v is num ? v.toInt() : int.tryParse('${v ?? ''}'.trim());
double? _asDouble(Object? v) =>
    v == null ? null : (v is num ? v.toDouble() : double.tryParse('$v'));
bool _asBool(Object? v) => v == true || v == 1 || v == '1' || v == 'true';
String _asStr(Object? v) => v?.toString() ?? '';

/// 一个游玩节点(对齐 /api/play/nodes 的 node VO)。
class PlayNode {
  const PlayNode({
    required this.nodeId,
    required this.name,
    required this.address,
    required this.sortId,
    required this.done,
    this.longitude,
    this.latitude,
    this.imgUrl,
    this.description,
    this.merchantId,
    this.arrived = false,
    this.selfReported = false,
    this.validationMethod,
    this.sensorType,
    this.sensorConfig,
    this.advancedConfig,
    this.needScan = false,
    this.needAnswer = false,
    this.needGps = false,
    this.question,
    this.questionImg,
    this.questionAudio,
    this.options,
    this.hint1,
    this.hint2,
    this.hintLocked = false,
    this.hintCost = 0,
    this.hintCount = 0,
    this.puzzleScoring = false,
    this.puzzleHintLevel = 0,
    this.puzzleScoreCap = 100,
    this.usedHints = const <String>[],
    this.hookText,
    this.businessTime,
    this.openStatus,
    this.chapterId,
    this.npc,
    this.perk,
    this.hasGame = false,
    this.gameTitle,
    this.duration,
    this.difficulty,
    this.players,
    this.requiredMaterials,
    this.ruleInstructions,
    this.storyText,
    this.storyImg,
    this.audioUrl,
    this.routeNodeState,
    this.routeLockReason,
    this.audioDuration,
    this.photoRequireDesc,
    this.unlockAfterNodeId,
    this.locked = false,
    this.ambient,
    this.xp,
    this.puzzleScore,
    this.completionMode,
    this.medalName,
    this.medalStyle,
    this.medalImg,
    this.couponId,
  });

  final int nodeId;
  final String name;
  final String address;
  final int sortId;
  final bool done;
  final double? longitude;
  final double? latitude;
  final String? imgUrl;
  final String? description;

  /// 探店日门店作用域。仅 FREE_COLLECT 节点由服务端下发；缺失时禁止猜值。
  final int? merchantId;

  /// 探店日现场三步状态：扫码到店 → 上传凭证 → 商家核销([done])。
  final bool arrived;
  final bool selfReported;

  /// 验证方式:1 文字答题 / 2 拍照 / 3 选项答题 / 4 扫码 /
  /// 5 GPS / 6 偏好题组 / 7 App 传感器挑战。null=到店即可。
  final int? validationMethod;

  /// App 专属玩法契约：vm=7 为 still/steps/audio_clip；
  /// vm=2 的伪 AR 子类为 filter_shot。
  final String? sensorType;

  /// App 专属玩法配置。App 只解析与传递，具体字段由 sensorType 决定。
  final Map<String, dynamic>? sensorConfig;

  /// 服务端下发的高级玩法配置；仅用于决定是否先进入权威玩法会话。
  final Map<String, dynamic>? advancedConfig;
  final bool needScan;
  final bool needAnswer;
  final bool needGps;

  /// 答题题面(vm==1 文字 / vm==3 选项 时才有,可能空)。
  final String? question;

  /// 答题题面媒体；后端只在文字/选项题且到店后公开，不包含答案。
  final String? questionImg;
  final String? questionAudio;

  /// 选项题(vm==3)的选项映射 {A,B,C,D};非选项题为 null。
  final Map<String, String>? options;
  final String? hint1;
  final String? hint2;
  final bool hintLocked;
  final int hintCost;
  final int hintCount;

  /// 城市定向谜题计分事实。提示正文只接收服务端已记录后返回的 [usedHints]，
  /// 客户端不能从模板字段预先推导，避免答题前泄露机密。
  final bool puzzleScoring;
  final int puzzleHintLevel;
  final int puzzleScoreCap;
  final List<String> usedHints;

  /// 「小瘾说」那句钩子。⚠️ 缺失时**不要回落 description** —— 那会把章节正文重复念一遍。
  final String? hookText;
  final String? businessTime;

  /// 营业态三态(营业中/即将打烊/已打烊),服务端按 businessTime 算好下发
  /// (`ApiPlayProgressController.computeOpenStatus`)。**优先用它,不要在端上
  /// 再从 businessTime 反推一遍**——本页后端一定会下发,退回口径属于另一套
  /// 服务多入口的需求(小程序 play-open-state.js 那样),这里没有。
  final String? openStatus;
  final int? chapterId;
  final PlayNpcBrief? npc;
  final PlayPerk? perk;
  final String? routeNodeState;
  final String? routeLockReason;

  /// 这一站有没有玩法(后端算好下发)。
  ///
  /// ⚠️ **它不是「游戏段该不该渲染」的判据** —— 后端两条 removeAll 错开:
  /// `!hasGame` 那条摘 gameTitle/duration/difficulty/players/requiredMaterials,
  /// 而 `m.put("hasGame", …)` 排在它**之后**;`!arrived` 那条摘
  /// gameTitle/ruleInstructions/validationMethod/…,**既不摘 hasGame,也不摘
  /// duration/players/difficulty/requiredMaterials**
  /// (ApiPlayProgressController:681-705)。
  /// 于是「有玩法 + 还没扫码」下发的是 hasGame=true、gameTitle=null,
  /// 按 hasGame 渲会得到一个没标题、没「怎么玩」的孤儿段。
  /// 段③的判据见 `GameSection.visibleFor`(gameTitle 非空 —— 含
  /// `GameSection.gameTitleOf` 按 validationMethod 的那条回落),与小程序
  /// `wx:if="{{hero.node.gameTitle}}"`(index.wxml:431)同一条。
  final bool hasGame;
  final String? gameTitle;

  /// 玩法时长,**分钟数**:后端 `CmsMemberTemplate.duration` 是 `Long`,直发数字、
  /// 不带单位。单位在展示层拼(`GameSection`),与小程序 normNode
  /// `n.duration ? (n.duration + ' 分钟') : ''`(index.js:2718)同一口径。
  /// ★ 放展示层是因为 golden / widget fixture 常直接 `PlayNode(...)` 构造,
  ///   绕过 fromJson;单位若补在解析层,那些 fixture 会静默丢单位。
  final int? duration;
  final String? difficulty;
  final String? players;
  final String? requiredMaterials;

  /// 「怎么玩」的原文,按换行分条。
  final String? ruleInstructions;

  /// 节点叙事正文(`CmsMemberTemplate.storyText`)。到店后才下发,用作叙事钩子。
  final String? storyText;

  /// 节点叙事配图。仅解析,不参与本段版面(卡面已用 [imgUrl])。
  final String? storyImg;

  /// **这一站的语音导览**(玩法模板 `CmsMemberTemplate.audioUrl`,
  /// `ApiPlayProgressController:594`)。章节故事流右下那颗音频键放的就是它
  /// (样机 index.js:1032 `chapStory.audio = v.audio` ← :1544 `hero.node.audio`
  /// ← :2732 `normNode: audio = n.audioUrl`)。
  ///
  /// ⚠️ **不要和 [PlayChapter.audioUrl] 搞混** —— 那条是章节背景旁白,是另一个功能。
  /// ⚠️ `hasGame` 为假时后端整条剥掉(`:682-687` 的 removeAll),
  ///   所以「没玩法的站没有语音导览」是**服务端语义**,端上不要再造一条回落。
  final String? audioUrl;

  /// 节点语音导览时长(秒/后端数字)。仅解析,App 侧播放待接。
  final int? audioDuration;

  /// 拍照任务的拍摄要求。行动指令优先用它,没有才回落规则首行。
  final String? photoRequireDesc;

  /// 线性玩法的前置节点。`null`=无前置。判「是否已解锁」用后端算好的 [locked],
  /// 不在端上拿它跟完成列表反推。
  final int? unlockAfterNodeId;

  /// 前置未完成 → true(后端 `ApiPlayProgressController:416` 按完成列表算好)。
  final bool locked;

  /// 节点氛围件标识(如 `'woodfish'` = 赛博木鱼)。它**不是玩法段**:不进
  /// playKit 分发器、不判定通关,由节点卡就地内联渲染
  /// (真源 `pages/play/index.wxml:962` 的 `wx:if="{{sheet.node.ambient === 'woodfish'}}"`)。
  ///
  /// ⚠️ **两端目前都没有产生方**:后端节点 VO 是逐字段白名单
  ///   (`ApiPlayProgressController:503-680` 无 ambient),小程序 `normNode`
  ///   (index.js:2948-3027)同样不透传 —— 真源里只有截图 mock
  ///   (`scripts/shot-matrix.js:538`)挂了它。所以按**真源字段名**可空解析、
  ///   缺失即 null、不落回默认值:后端哪天在节点 VO 补上,木鱼自动点亮。
  ///   名字不认识的一律当不存在(与「服务端下了哪段就渲哪段」同口径)。
  final String? ambient;

  /// 这一站完成实际入账的探索值(/nodes 投影 `xp` 与打卡回执同源,
  /// `ApiPlayProgressController` `resolveNodeXp`)。**可空**:缺字段=未知,
  /// 不许回落 12 这类估算值 —— 通关卡「探索值」只读它。
  final int? xp;

  /// 本次谜题得分(/nodes 只给已完成节点;打卡回执 `puzzleScore` 同字段)。
  /// null=这站没计分,不是 0 分。
  final int? puzzleScore;

  /// 完成方式(`REVEALED` 等),与 [puzzleScore] 同批下发。
  final String? completionMode;

  /// 节点模板勋章(`medalName`/`medalStyle`/`medalImg`)。只是「这站配了勋章」,
  /// **不代表这次拿到** —— 是否夺得只看回执 `medalRank`(真源 index.js:4454)。
  final String? medalName;
  final String? medalStyle;
  final String? medalImg;

  /// 节点绑定模板配的优惠券 id;>0 才发券(真源 `node.couponId ? '到店出示核销'`)。
  final int? couponId;

  bool get isAppSensorChallenge => validationMethod == 7;

  bool get hasAdvanced {
    final Map<String, dynamic>? config = advancedConfig;
    if (config == null) return false;
    for (final String key in <String>[
      'timer',
      'random',
      'branch',
      'leaderboard',
      'multiplayer',
    ]) {
      final Object? section = config[key];
      if (section is Map && section['enabled'] == true) return true;
    }
    return false;
  }

  bool get isFilterShot => validationMethod == 2 && sensorType == 'filter_shot';

  bool get hasUnsupportedPhotoSubtype =>
      validationMethod == 2 && sensorType != null && !isFilterShot;

  bool get hasHint =>
      puzzleScoring ||
      hintLocked ||
      (hint1?.isNotEmpty ?? false) ||
      (hint2?.isNotEmpty ?? false);

  bool get routeHidden => routeNodeState == 'HIDDEN';
  bool get routePlayable =>
      done || routeNodeState == null || routeNodeState == 'PLAYABLE';

  PlayNode withRoute({required String state, String? lockReason}) => PlayNode(
    nodeId: nodeId,
    name: name,
    address: address,
    sortId: sortId,
    done: done || state == 'COMPLETED',
    longitude: longitude,
    latitude: latitude,
    imgUrl: imgUrl,
    description: description,
    merchantId: merchantId,
    arrived: arrived,
    selfReported: selfReported,
    validationMethod: validationMethod,
    sensorType: sensorType,
    sensorConfig: sensorConfig,
    advancedConfig: advancedConfig,
    needScan: needScan,
    needAnswer: needAnswer,
    needGps: needGps,
    question: question,
    questionImg: questionImg,
    questionAudio: questionAudio,
    options: options,
    hint1: hint1,
    hint2: hint2,
    hintLocked: hintLocked,
    hintCost: hintCost,
    hintCount: hintCount,
    puzzleScoring: puzzleScoring,
    puzzleHintLevel: puzzleHintLevel,
    puzzleScoreCap: puzzleScoreCap,
    usedHints: usedHints,
    hookText: hookText,
    businessTime: businessTime,
    openStatus: openStatus,
    chapterId: chapterId,
    npc: npc,
    perk: perk,
    hasGame: hasGame,
    gameTitle: gameTitle,
    duration: duration,
    difficulty: difficulty,
    players: players,
    requiredMaterials: requiredMaterials,
    ruleInstructions: ruleInstructions,
    storyText: storyText,
    storyImg: storyImg,
    audioUrl: audioUrl,
    routeNodeState: state,
    routeLockReason: lockReason,
    audioDuration: audioDuration,
    photoRequireDesc: photoRequireDesc,
    unlockAfterNodeId: unlockAfterNodeId,
    locked: locked,
    ambient: ambient,
    xp: xp,
    puzzleScore: puzzleScore,
    completionMode: completionMode,
    medalName: medalName,
    medalStyle: medalStyle,
    medalImg: medalImg,
    couponId: couponId,
  );

  factory PlayNode.fromJson(Map<String, dynamic> j) {
    return PlayNode(
      nodeId: _asInt(j['nodeId']),
      name: _asStr(j['name']),
      address: _asStr(j['address']),
      sortId: _asInt(j['sortId']),
      done: _asBool(j['done']),
      longitude: _asDouble(j['longitude']),
      latitude: _asDouble(j['latitude']),
      imgUrl: j['imgUrl'] == null ? null : _asStr(j['imgUrl']),
      description: j['description'] == null ? null : _asStr(j['description']),
      merchantId: j['merchantId'] == null ? null : _asInt(j['merchantId']),
      arrived: _asBool(j['arrived']),
      selfReported: _asBool(j['selfReported']),
      validationMethod: j['validationMethod'] == null
          ? null
          : _asInt(j['validationMethod']),
      sensorType: _nullableString(j['sensorType']),
      sensorConfig: _asConfig(j['sensorConfig']),
      advancedConfig: _asConfig(j['advancedConfigJson']),
      needScan: _asBool(j['needScan']),
      needAnswer: _asBool(j['needAnswer']),
      needGps: _asBool(j['needGps']),
      question: (j['question'] == null || _asStr(j['question']).isEmpty)
          ? null
          : _asStr(j['question']),
      questionImg: _nullableString(j['questionImg']),
      questionAudio: _nullableString(j['questionAudio']),
      options: _asOptions(j['options']),
      hint1: _nullableString(j['hint1']),
      hint2: _nullableString(j['hint2']),
      hintLocked: _asBool(j['hintLocked']),
      hintCost: _asInt(j['hintCost']),
      hintCount: _asInt(j['hintCount']),
      puzzleScoring: _asBool(j['puzzleScoring']),
      puzzleHintLevel: _asInt(j['puzzleHintLevel']),
      puzzleScoreCap: j['puzzleScoreCap'] == null
          ? 100
          : _asInt(j['puzzleScoreCap']),
      usedHints: _asStringList(j['usedHints']),
      hookText: _nullableString(j['hookText']),
      businessTime: _nullableString(j['businessTime']),
      openStatus: _nullableString(j['openStatus']),
      chapterId: j['chapterId'] == null ? null : _asInt(j['chapterId']),
      npc: PlayNpcBrief.fromJson(j['npc']),
      perk: PlayPerk.fromJson(j['perk']),
      hasGame: _asBool(j['hasGame']),
      gameTitle: _nullableString(j['gameTitle']),
      duration: _nullableInt(j['duration']),
      difficulty: _nullableString(j['difficulty']),
      players: _nullableString(j['players']),
      requiredMaterials: _nullableString(j['requiredMaterials']),
      ruleInstructions: _nullableString(j['ruleInstructions']),
      storyText: _nullableString(j['storyText']),
      storyImg: _nullableString(j['storyImg']),
      audioUrl: _nullableString(j['audioUrl']),
      routeNodeState: _nullableString(j['routeNodeState']),
      routeLockReason: _nullableString(j['lockReason']),
      audioDuration: _nullableInt(j['audioDuration']),
      photoRequireDesc: _nullableString(j['photoRequireDesc']),
      // ★ 用可空解析:解析不出来就是 null,**不能落回 0** ——
      //   0 会被下游当成一个真实的前置节点 id(编出来的解锁关系)。
      unlockAfterNodeId: _nullableInt(j['unlockAfterNodeId']),
      locked: _asBool(j['locked']),
      ambient: _nullableString(j['ambient']),
      xp: _nullableInt(j['xp']),
      puzzleScore: _nullableInt(j['puzzleScore']),
      completionMode: _nullableString(j['completionMode']),
      medalName: _nullableString(j['medalName']),
      medalStyle: _nullableString(j['medalStyle']),
      medalImg: _nullableString(j['medalImg']),
      couponId: _positiveId(j['couponId']),
    );
  }
}

/// id 类可空字段:0/负数/解析不出来都是「没有」,不落回一个假 id。
int? _positiveId(Object? value) {
  final int? id = _nullableInt(value);
  return (id != null && id > 0) ? id : null;
}

List<String> _asStringList(Object? value) {
  if (value is! List) return const <String>[];
  return value
      .map((Object? item) => _asStr(item).trim())
      .where((String item) => item.isNotEmpty)
      .toList(growable: false);
}

Map<String, dynamic>? _asConfig(Object? value) {
  Object? decoded = value;
  if (value is String) {
    try {
      decoded = jsonDecode(value);
    } on FormatException {
      return null;
    }
  }
  if (decoded is! Map) return null;
  return <String, dynamic>{
    for (final MapEntry<dynamic, dynamic> entry in decoded.entries)
      entry.key.toString(): entry.value,
  };
}

String? _nullableString(Object? value) {
  if (value == null) return null;
  final String text = _asStr(value).trim();
  return text.isEmpty ? null : text;
}

/// 解析选项题的 options 对象({A,B,C,D}),各值 toString;空则 null。
Map<String, String>? _asOptions(Object? v) {
  if (v is! Map) return null;
  final Map<String, String> out = <String, String>{};
  v.forEach((Object? k, Object? val) {
    if (val == null) return;
    final String s = val.toString();
    if (s.isEmpty) return;
    out['$k'] = s;
  });
  return out.isEmpty ? null : out;
}

/// `/api/play/hint/unlock` 的读回。`cost` 是本次实际扣分；重复解锁时
/// 后端返回 0，客户端不能继续展示原价冒充本次扣款。
class HintUnlockResult {
  const HintUnlockResult({
    required this.hint1,
    required this.hint2,
    required this.cost,
  });

  final String hint1;
  final String hint2;
  final int cost;

  List<String> get hints => <String>[
    if (hint1.isNotEmpty) hint1,
    if (hint2.isNotEmpty) hint2,
  ];

  factory HintUnlockResult.fromJson(Map<String, dynamic> json) =>
      HintUnlockResult(
        hint1: _asStr(json['hint1']),
        hint2: _asStr(json['hint2']),
        cost: _asInt(json['cost']),
      );
}

/// `/api/play/puzzle/hint` 的服务端提示事实。
class PuzzleHintResult {
  const PuzzleHintResult({
    required this.level,
    required this.hints,
    required this.hintCount,
    required this.scoreCap,
  });

  final int level;
  final List<String> hints;
  final int hintCount;
  final int scoreCap;

  factory PuzzleHintResult.fromJson(Map<String, dynamic> json) {
    final List<String> hints = _asStringList(json['hints']);
    final String single = _asStr(json['hint']).trim();
    return PuzzleHintResult(
      level: _asInt(json['level']),
      hints: hints.isNotEmpty ? hints : <String>[if (single.isNotEmpty) single],
      hintCount: _asInt(json['hintCount']),
      scoreCap: _asInt(json['scoreCap']),
    );
  }
}

enum PlayRouteMode { linear, branchGraph }

enum PlayRouteNodeState { hidden, discoveredLocked, playable, completed }

/// BRANCH_GRAPH 完成动作的幂等票据。同一次网络结果不确定的重试必须复用两项。
class RouteAdvanceToken {
  RouteAdvanceToken({
    required String actionId,
    required this.expectedRouteVersion,
  }) : actionId = actionId.trim() {
    if (this.actionId.isEmpty || this.actionId.length > 96) {
      throw ArgumentError.value(actionId, 'actionId', '必须为 1–96 字符');
    }
    if (expectedRouteVersion < 0) {
      throw ArgumentError.value(
        expectedRouteVersion,
        'expectedRouteVersion',
        '不能为负数',
      );
    }
  }

  final String actionId;
  final int expectedRouteVersion;
}

/// 服务端一次路线选择的只读记录。客户端只展示/诊断，不据此推演下一节点。
class PlayRouteDecision {
  const PlayRouteDecision({
    required this.fromNodeId,
    required this.outcomeCode,
    required this.edgeId,
    required this.toNodeId,
    required this.reason,
    required this.at,
  });

  final int fromNodeId;
  final String outcomeCode;
  final String? edgeId;
  final int? toNodeId;
  final String reason;
  final DateTime? at;

  static PlayRouteDecision? fromJson(Object? value) {
    final Map<String, dynamic>? json = _stringKeyedMap(value);
    if (json == null) return null;
    final int? fromNodeId = _nullableInt(json['fromNodeId']);
    final String? outcomeCode = _nullableString(json['outcomeCode']);
    final String? reason = _nullableString(json['reason']);
    if (fromNodeId == null || outcomeCode == null || reason == null) {
      return null;
    }
    return PlayRouteDecision(
      fromNodeId: fromNodeId,
      outcomeCode: outcomeCode,
      edgeId: _nullableString(json['edgeId']),
      toNodeId: _nullableInt(json['toNodeId']),
      reason: reason,
      at: _nullableDateTime(json['at']),
    );
  }
}

/// `/api/play/puzzle/reveal` 的揭示与完成回执。
class PuzzleRevealResult {
  const PuzzleRevealResult({
    required this.answerReveal,
    required this.puzzleScore,
    required this.completionMode,
    required this.reward,
  });

  final String answerReveal;
  final int puzzleScore;
  final String completionMode;
  final CheckinReward reward;

  factory PuzzleRevealResult.fromJson(Map<String, dynamic> json) =>
      PuzzleRevealResult(
        answerReveal: _asStr(json['answerReveal']),
        puzzleScore: _asInt(json['puzzleScore']),
        completionMode: _asStr(json['completionMode']),
        reward: CheckinReward.fromJson(json),
      );
}

/// 后端 `/api/play/route-state`、`/nodes` 与完成回包共用的路线权威状态。
class PlayRouteState {
  const PlayRouteState({
    required this.routeMode,
    required this.sessionId,
    required this.status,
    required this.currentNodeId,
    required this.recommendedNodeId,
    required this.version,
    required this.nodeStates,
    required this.decisionLog,
  });

  final PlayRouteMode routeMode;
  final int? sessionId;
  final String status;
  final int? currentNodeId;
  final int? recommendedNodeId;
  final int version;
  final Map<int, PlayRouteNodeState> nodeStates;
  final List<PlayRouteDecision> decisionLog;

  bool get isBranchGraph => routeMode == PlayRouteMode.branchGraph;

  PlayRouteDecision? get latestDecision =>
      decisionLog.isEmpty ? null : decisionLog.last;

  PlayRouteNodeState? stateOf(int nodeId) => nodeStates[nodeId];

  static PlayRouteState? fromJson(Object? value) {
    final Map<String, dynamic>? json = _stringKeyedMap(value);
    if (json == null) return null;
    final PlayRouteMode? routeMode = switch (_nullableString(
      json['routeMode'],
    )) {
      'LINEAR' => PlayRouteMode.linear,
      'BRANCH_GRAPH' => PlayRouteMode.branchGraph,
      _ => null,
    };
    final String? status = _nullableString(json['status']);
    final int? version = _nullableInt(json['version']);
    final int? sessionId = _nullableInt(json['sessionId']);
    if (routeMode == null || status == null || version == null || version < 0) {
      return null;
    }
    if (routeMode == PlayRouteMode.branchGraph &&
        (sessionId == null || sessionId <= 0)) {
      return null;
    }

    final Map<int, PlayRouteNodeState> nodeStates = <int, PlayRouteNodeState>{};
    if (json['nodeStates'] case final Map<dynamic, dynamic> rawStates) {
      for (final MapEntry<dynamic, dynamic> entry in rawStates.entries) {
        final int? nodeId = _nullableInt(entry.key);
        final PlayRouteNodeState? nodeState = switch (_nullableString(
          entry.value,
        )) {
          'HIDDEN' => PlayRouteNodeState.hidden,
          'DISCOVERED_LOCKED' => PlayRouteNodeState.discoveredLocked,
          'PLAYABLE' => PlayRouteNodeState.playable,
          'COMPLETED' => PlayRouteNodeState.completed,
          _ => null,
        };
        if (nodeId != null && nodeState != null) {
          nodeStates[nodeId] = nodeState;
        }
      }
    }

    final List<PlayRouteDecision> decisions = <PlayRouteDecision>[];
    if (json['decisionLog'] case final List<dynamic> rawDecisions) {
      for (final Object? value in rawDecisions) {
        final PlayRouteDecision? decision = PlayRouteDecision.fromJson(value);
        if (decision != null) decisions.add(decision);
      }
    }
    return PlayRouteState(
      routeMode: routeMode,
      sessionId: sessionId,
      status: status,
      currentNodeId: _nullableInt(json['currentNodeId']),
      recommendedNodeId: _nullableInt(json['recommendedNodeId']),
      version: version,
      nodeStates: Map<int, PlayRouteNodeState>.unmodifiable(nodeStates),
      decisionLog: List<PlayRouteDecision>.unmodifiable(decisions),
    );
  }
}

Map<String, dynamic>? _stringKeyedMap(Object? value) {
  if (value is! Map) return null;
  return <String, dynamic>{
    for (final MapEntry<dynamic, dynamic> entry in value.entries)
      entry.key.toString(): entry.value,
  };
}

DateTime? _nullableDateTime(Object? value) {
  if (value is num) {
    return DateTime.fromMillisecondsSinceEpoch(value.toInt(), isUtc: true);
  }
  final String? text = _nullableString(value);
  return text == null ? null : DateTime.tryParse(text);
}

/// /api/play/nodes 的整体返回:节点列表 + 进度 + 玩法模式/可玩闸。
class PlayNodesResult {
  const PlayNodesResult({
    required this.topicId,
    required this.mode,
    required this.playable,
    required this.total,
    required this.doneCount,
    required this.nodes,
    this.timeNote,
    this.topicDesc,
    this.topicName = '',
    this.selfPlay = false,
    this.registered,
    this.expiresAt,
    this.chapters = const <PlayChapter>[],
    this.eggs = const <PlayEgg>[],
    this.routeMode = 'LINEAR',
    this.routeVersion = 0,
    this.routeSessionId = 0,
    this.routeStatus = '',
    this.routeCurrentNodeId,
    this.routeRecommendedNodeId,
    this.routeNodeStates = const <int, String>{},
    this.routeDecisionLog = const <Map<String, dynamic>>[],
    this.routeLockReasons = const <int, String>{},
    this.routeState,
    this.puzzlePersonalBest,
  });

  final int topicId;

  /// 1 城市定向(线性,需按顺序) / 2 自由探索(全开)。
  final int mode;

  /// 活动时间闸:false 表示当前不在可玩时间(timeNote 给原因)。
  final bool playable;
  final int total;
  final int doneCount;
  final List<PlayNode> nodes;

  /// 不可玩时的说明(活动未开始/已结束等)。
  final String? timeNote;

  /// 通行证首屏那段简介。**是主题的**,不是第一章的 —— 拿 chapters[0].description
  /// 当简介会让首屏在讲第一家店的事,而这一屏说的是「四家店、30 天、没有顺序」这件整体的事。
  final String? topicDesc;

  /// 主题名(`/api/play/nodes` 回包 `data.topicName`)。《预制人生》换轨判定要用,
  /// 真源 `pages/play/index.js:2955`。后端没发时为空串。
  final String topicName;

  /// 自玩通行证形态(无 activityId)。
  final bool selfPlay;

  /// 服务端下发的「本人是否已报名本场次」(`ApiPlayProgressController.java:832`)。
  /// **三态**:null=后端没发这个字段(不据此判未报名),false=确实未报名。
  /// false 时游玩页落 `signup` 空态(「你还没有报名这个场次」+「去报名」)。
  final bool? registered;
  final String? expiresAt;
  final List<PlayChapter> chapters;
  final List<PlayEgg> eggs;
  final String routeMode;
  final int routeVersion;
  final int routeSessionId;
  final String routeStatus;
  final int? routeCurrentNodeId;
  final int? routeRecommendedNodeId;
  final Map<int, String> routeNodeStates;
  final List<Map<String, dynamic>> routeDecisionLog;
  final Map<int, String> routeLockReasons;
  final PlayRouteState? routeState;

  /// 谜题个人最佳(/nodes 结果级 `puzzlePersonalBest`,后端仅城市定向且
  /// 有记录时下发;打卡回执同名键只在通关那次带)。null=没有记录,UI 不显。
  final int? puzzlePersonalBest;

  /// 通关卡「探索值」真值:已完成节点的 [PlayNode.xp] 之和
  /// (与打卡回执 `xp` 同源 `resolveNodeXp`)。
  /// **null=未知** —— 任一已完成节点缺 xp 字段就不报总数,
  /// 更不许回落成「站数 × 固定分」这类估算。
  int? get finishXp {
    int sum = 0;
    for (final PlayNode node in nodes) {
      if (!node.done) continue;
      final int? xp = node.xp;
      if (xp == null) return null;
      sum += xp;
    }
    return sum;
  }

  /// 通关卡「本次解谜分」口径 = 真源 `summarizePuzzleScores`
  /// (`utils/play-puzzle-summary.js`):只算已完成且带 `puzzleScore` 的站,
  /// 每站钳进 0..100 再累加;`count` 是题数(label「本次解谜分 · N题」用)。
  ({int score, int count}) get finishPuzzle {
    int score = 0;
    int count = 0;
    for (final PlayNode node in nodes) {
      final int? s = node.puzzleScore;
      if (!node.done || s == null) continue;
      score += s.clamp(0, 100);
      count += 1;
    }
    return (score: score, count: count);
  }

  bool get allDone => total > 0 && doneCount >= total;

  /// 按 chapterId 精确匹配章节;匹配不到返回 null ——
  /// 调用方据此不渲染章节眉标,**不许拿 node.name 冒充章节名**。
  /// 屏① 六宫格与卡片详情共用这一份,别各写一遍(两份判据一定会漂移)。
  PlayChapter? chapterOf(PlayNode node) {
    if (node.chapterId == null) return null;
    for (final PlayChapter c in chapters) {
      if (c.chapterId == node.chapterId) return c;
    }
    return null;
  }

  /// 按 nodeId 取节点;刷新后节点可能已不在列表里,那就返回 null 让调用方兜底。
  PlayNode? nodeById(int nodeId) {
    for (final PlayNode n in nodes) {
      if (n.nodeId == nodeId) return n;
    }
    return null;
  }

  PlayNodesResult applyRouteState(legacy_route.PlayRouteState state) {
    if (!state.isBranchGraph) return this;
    final List<PlayNode> routed = nodes
        .map(
          (PlayNode node) => node.withRoute(
            state: state.nodeState(node.nodeId) ?? 'HIDDEN',
            lockReason: state.lockReason(node.nodeId),
          ),
        )
        .where((PlayNode node) => !node.routeHidden)
        .toList(growable: false);
    return PlayNodesResult(
      topicId: topicId,
      mode: mode,
      playable: playable && state.active,
      total: total,
      doneCount: routed.where((PlayNode node) => node.done).length,
      nodes: routed,
      timeNote: state.active ? timeNote : '路线状态异常，当前不可继续',
      topicDesc: topicDesc,
      topicName: topicName,
      selfPlay: selfPlay,
      registered: registered,
      expiresAt: expiresAt,
      chapters: chapters,
      eggs: eggs,
      routeMode: state.routeMode,
      routeVersion: state.version,
      routeSessionId: state.sessionId,
      routeStatus: state.status,
      routeCurrentNodeId: state.currentNodeId,
      routeRecommendedNodeId: state.recommendedNodeId,
      routeNodeStates: state.nodeStates,
      routeDecisionLog: state.decisionLog,
      routeLockReasons: state.lockReasons,
      routeState: routeState,
      puzzlePersonalBest: puzzlePersonalBest,
    );
  }

  PlayNodesResult withRouteState(PlayRouteState nextRouteState) =>
      PlayNodesResult(
        topicId: topicId,
        mode: mode,
        playable: playable,
        total: total,
        doneCount: doneCount,
        nodes: nodes,
        timeNote: timeNote,
        topicDesc: topicDesc,
        topicName: topicName,
        selfPlay: selfPlay,
        registered: registered,
        expiresAt: expiresAt,
        chapters: chapters,
        eggs: eggs,
        routeMode: routeMode,
        routeVersion: routeVersion,
        routeSessionId: routeSessionId,
        routeStatus: routeStatus,
        routeCurrentNodeId: routeCurrentNodeId,
        routeRecommendedNodeId: routeRecommendedNodeId,
        routeNodeStates: routeNodeStates,
        routeDecisionLog: routeDecisionLog,
        routeLockReasons: routeLockReasons,
        routeState: nextRouteState,
        puzzlePersonalBest: puzzlePersonalBest,
      );

  factory PlayNodesResult.fromJson(Map<String, dynamic> j) {
    final rawNodes = (j['nodes'] as List<dynamic>?) ?? const <dynamic>[];
    final rawChapters = (j['chapters'] as List<dynamic>?) ?? const <dynamic>[];
    final rawEggs = (j['eggs'] as List<dynamic>?) ?? const <dynamic>[];
    final Map<String, dynamic> routeState = j['routeState'] is Map
        ? Map<String, dynamic>.from(j['routeState'] as Map)
        : const <String, dynamic>{};
    return PlayNodesResult(
      topicId: _asInt(j['topicId']),
      mode: _asInt(j['mode']),
      playable: _asBool(j['playable']),
      total: _asInt(j['total']),
      doneCount: _asInt(j['doneCount']),
      timeNote: j['timeNote'] == null ? null : _asStr(j['timeNote']),
      topicDesc: _nullableString(j['topicDesc']),
      topicName: _asStr(j['topicName']),
      selfPlay: _asBool(j['selfPlay']),
      registered: j['registered'] is bool ? j['registered'] as bool : null,
      routeMode: _asStr(routeState['routeMode']).isEmpty
          ? 'LINEAR'
          : _asStr(routeState['routeMode']),
      routeVersion: _asInt(routeState['version']),
      routeSessionId: _asInt(routeState['sessionId']),
      routeStatus: _asStr(routeState['status']),
      routeCurrentNodeId: routeState['currentNodeId'] == null
          ? null
          : _asInt(routeState['currentNodeId']),
      routeRecommendedNodeId: routeState['recommendedNodeId'] == null
          ? null
          : _asInt(routeState['recommendedNodeId']),
      routeNodeStates: _asIntStringMap(routeState['nodeStates']),
      routeDecisionLog: _asMapList(routeState['decisionLog']),
      routeLockReasons: _asIntStringMap(routeState['lockReasons']),
      expiresAt: _nullableString(j['expiresAt']),
      routeState: PlayRouteState.fromJson(j['routeState']),
      puzzlePersonalBest: _nullableInt(j['puzzlePersonalBest']),
      nodes: rawNodes
          .map((dynamic e) => PlayNode.fromJson(e as Map<String, dynamic>))
          .toList(),
      // 眉标「第 N 章」按数组下标生成,所以这里得带着 index 解析,不能 map 单参。
      chapters: <PlayChapter>[
        for (int i = 0; i < rawChapters.length; i++)
          if (rawChapters[i] case final Map<String, dynamic> c)
            PlayChapter.fromJson(c, i),
      ],
      eggs: rawEggs
          .whereType<Map<String, dynamic>>()
          .map(PlayEgg.fromJson)
          .where((PlayEgg egg) => egg.isUsable)
          .toList(growable: false),
    );
  }
}

class PlayEgg {
  const PlayEgg({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
    required this.text,
  });

  final int id;
  final double latitude;
  final double longitude;
  final double radiusMeters;
  final String text;

  bool get isUsable =>
      id > 0 &&
      latitude.isFinite &&
      longitude.isFinite &&
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180 &&
      latitude != 0 &&
      longitude != 0 &&
      radiusMeters > 0 &&
      text.isNotEmpty;

  factory PlayEgg.fromJson(Map<String, dynamic> json) => PlayEgg(
    id: _asInt(json['id']),
    latitude: _asDouble(json['lat']) ?? 0,
    longitude: _asDouble(json['lng']) ?? 0,
    radiusMeters: (_asDouble(json['radius']) ?? 120).clamp(1, 1000),
    text: _asStr(json['text']).trim(),
  );
}

Map<int, String> _asIntStringMap(Object? value) {
  if (value is! Map) return const <int, String>{};
  final Map<int, String> result = <int, String>{};
  value.forEach((Object? key, Object? raw) {
    final int? id = int.tryParse('$key');
    final String text = _asStr(raw).trim();
    if (id != null && id > 0 && text.isNotEmpty) result[id] = text;
  });
  return Map<int, String>.unmodifiable(result);
}

List<Map<String, dynamic>> _asMapList(Object? value) {
  if (value is! List) return const <Map<String, dynamic>>[];
  return value
      .whereType<Map>()
      .map((Map<dynamic, dynamic> row) => Map<String, dynamic>.from(row))
      .toList(growable: false);
}

/// 本次新获得的徽章(对齐 newBadges VO)。
class PlayBadge {
  const PlayBadge({
    required this.code,
    required this.name,
    required this.iconUrl,
  });

  final String code;
  final String name;
  final String iconUrl;

  factory PlayBadge.fromJson(Map<String, dynamic> j) {
    return PlayBadge(
      code: _asStr(j['code']),
      name: _asStr(j['name']),
      iconUrl: _asStr(j['iconUrl']),
    );
  }
}

/// 照片任务的 AI 参考分(`/api/play/photo` 回执里的 `aiScore`)。
///
/// ★ **不参与判定** —— 真源稿写明「最终以商家审核为准」,它只是回看这一站时的参考
///   (`pages/play/index.js:4723`)。`score <= 0` 一律当「没给分」(真源
///   `Number(ai.score) > 0`,index.js:4727),所以 [fromJson] 在那种情况下直接返回
///   null,调用方不用再判一遍;更不许造一个占位分。
/// ⚠️ 后端回执目前不下发 `aiScore`(全仓 Java/SQL 零命中),同 [PlayNode.ambient]:
///   按真源字段名可空解析,后端补上即亮。
class PlayAiScore {
  const PlayAiScore({
    required this.score,
    this.comment = '',
    this.note = defaultNote,
  });

  static const String defaultNote = '最终以商家审核为准';

  final int score;
  final String comment;
  final String note;

  static PlayAiScore? fromJson(Object? value) {
    if (value is! Map) return null;
    final int score = _asInt(value['score']);
    if (score <= 0) return null;
    return PlayAiScore(
      score: score,
      comment: _asStr(value['comment']).trim(),
      note: _nullableString(value['note']) ?? defaultNote,
    );
  }
}

/// 打卡成功返回(对齐 /api/play/checkin 的 data)。
class CheckinReward {
  const CheckinReward({
    required this.nodeId,
    required this.firstTime,
    required this.doneCount,
    required this.total,
    required this.completed,
    required this.newBadges,
    this.xpAwarded = 0,
    this.xpReported = false,
    this.medalRank,
    this.nightWarning = false,
    this.puzzleScore,
    this.completionMode,
    this.puzzlePersonalBest,
    this.routeState,
    this.aiScore,
  });

  final int nodeId;

  /// 是否本次首次完成该节点(首次才发分;重复扫返回 false)。
  final bool firstTime;
  final int doneCount;
  final int total;

  /// 是否因本次打卡达成整条主题通关。
  final bool completed;
  final List<PlayBadge> newBadges;

  /// 后端本次实际入账的探索值(回执 `xp`,已含掉落翻倍与通关加成)。
  final int xpAwarded;

  /// 回执里到底**报了**本次入账数没有(`xp`,兼容真源读过的旧键 `score`)。
  /// false 时 [xpAwarded] 是 0 占位 —— 展示层该走「暂未报到账」未知态,
  /// **不许**拿 12/13 这类估算补数(真源 index.js:4408 的 `|| 12` 兜底是
  /// 旧后端遗留,App 禁硬编码算分,不搬)。
  final bool xpReported;

  /// 名次奖牌本次夺得的名次(1/2/3)。后端只在真抢到时报数,
  /// 没抢到恒 null —— 节点配了 `medalName` 也**不能**据此弹「专属徽章」
  /// (真源 index.js:4451-4461;第 4 名起弹的是假奖)。
  final int? medalRank;

  /// 自玩 22:00–06:00 完成时后端随回执带 `nightWarning: true`(M2,不阻断)。
  final bool nightWarning;

  /// 本次谜题得分(回执 `puzzleScore`;null=这站没计分,不是 0)。
  final int? puzzleScore;

  /// 本次完成方式(`REVEALED` 等),解谜分汇总口径用。
  final String? completionMode;

  /// 通关那次的个人最佳(后端只在 `completed && !shopDay` 时报)。
  final int? puzzlePersonalBest;
  final PlayRouteState? routeState;

  /// 照片回执里服务端给的 AI 参考分;没给就是 null(见 [PlayAiScore])。
  final PlayAiScore? aiScore;

  PlayRouteDecision? get decision => routeState?.latestDecision;

  /// 到账弹层读这份:恒为服务端回执真值([xpAwarded]),不做本地估算。
  /// ⚠️ 页面调用点的「积分」字样要改「探索值」得等 #252/#355 合流
  ///   (play_session_page.dart 避让中),这里先保证**数字**是真值。
  int get pointsAwarded => xpAwarded;

  factory CheckinReward.fromJson(Map<String, dynamic> j) {
    final rawBadges = (j['newBadges'] as List<dynamic>?) ?? const <dynamic>[];
    final Object? xpRaw =
        j['xp'] ?? j['score']; // 真源读 xp→score 两键(index.js:4389)
    final int? rank = _nullableInt(j['medalRank']);
    return CheckinReward(
      nodeId: _asInt(j['nodeId']),
      firstTime: _asBool(j['firstTime']),
      doneCount: _asInt(j['done']),
      total: _asInt(j['total']),
      completed: _asBool(j['completed']),
      xpAwarded: xpRaw == null ? 0 : _asInt(xpRaw),
      xpReported: xpRaw != null,
      medalRank: (rank != null && rank > 0) ? rank : null,
      nightWarning: j['nightWarning'] == true || j['nightWarning'] == 1,
      puzzleScore: _nullableInt(j['puzzleScore']),
      completionMode: _nullableString(j['completionMode']),
      puzzlePersonalBest: _nullableInt(j['puzzlePersonalBest']),
      aiScore: PlayAiScore.fromJson(j['aiScore']),
      routeState: PlayRouteState.fromJson(j['routeState']),
      newBadges: rawBadges
          .map((dynamic e) => PlayBadge.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// 门店分身摘要。仅 FREE_COLLECT 节点下发;缺失时禁止猜值(同 [PlayNode.merchantId] 口径)。
///
/// ★ 只有 name / greeting 两项:persona 是喂模型的提示词永不下发,
///   avatar 后端已确认不下发(对话页中央是程序化 3D 形象,没有头像槽位)。
class PlayNpcBrief {
  const PlayNpcBrief({required this.name, required this.greeting});

  final String name;
  final String greeting;

  static PlayNpcBrief? fromJson(dynamic v) {
    if (v is! Map<String, dynamic>) return null;
    final String name = _asStr(v['name']);
    if (name.isEmpty) return null; // 没名字的分身等于没有
    return PlayNpcBrief(name: name, greeting: _asStr(v['greeting']));
  }
}

/// 本店权益(承接商家报名时挂的 CoopPerk)。单价/成本不下发,那是结算面的数。
class PlayPerk {
  const PlayPerk({required this.name, this.redeemRule, this.validEnd});

  final String name;
  final String? redeemRule;
  final String? validEnd;

  static PlayPerk? fromJson(dynamic v) {
    if (v is! Map<String, dynamic>) return null;
    final String name = _asStr(v['name']);
    if (name.isEmpty) return null;
    return PlayPerk(
      name: name,
      redeemRule: _nullableString(v['redeemRule']),
      validEnd: _nullableString(v['validEnd']),
    );
  }
}

/// 章节。自由探索一章一商家,章节名与正文都来自这里,**不许拿 node.name 冒充**。
class PlayChapter {
  const PlayChapter({
    required this.chapterId,
    this.meta,
    this.title,
    this.description,
    this.cover,
    this.audioUrl,
  });

  final int chapterId;
  final String? meta;
  final String? title;
  final String? description;
  final String? cover;

  /// **章节背景旁白**(`ApiPlayProgressController:736`,注释写明「2026-09-04 起」)。
  ///
  /// ⚠️ **不是章节故事流(屏③)右下那颗音频键的音源** —— 那颗放的是
  /// [PlayNode.audioUrl](节点的语音导览)。两条是不同的东西、后端都下发。
  /// 本字段的消费方 = 屏③「进本章自动播旁白」
  /// (`feature/play/free_explore/chapter_story_page.dart` 的 `_maybeStartNarration`,
  /// 真源 `playChapterAudio`,pages/play/index.js:2701)。
  final String? audioUrl;

  /// 后端 `/api/play/nodes` 下发的键是 `name` / `imgArr`,**没有** `meta` / `title` /
  /// `cover` —— 照那三个名字读的话生产里恒 null,眉标与标题静默消失(2026-09-09 修)。
  /// 规范化照小程序 `buildChapterCards`(pages/play/index.js)那一份来,两端一致。
  /// [index] 是本章在 chapters 数组里的下标:单条 JSON 里没有序号,眉标「第 N 章」
  /// 只能由调用方给,别在这里瞎猜。
  factory PlayChapter.fromJson(Map<String, dynamic> j, int index) {
    final String ordinal = '第 ${index + 1} 章';
    final String? imgArr = _nullableString(j['imgArr']);
    return PlayChapter(
      chapterId: _asInt(j['chapterId']),
      meta: ordinal,
      title: _nullableString(j['name']) ?? ordinal,
      description: _nullableString(j['description']),
      cover: imgArr == null ? null : _nullableString(imgArr.split(',').first),
      audioUrl: _nullableString(j['audioUrl']),
    );
  }
}
