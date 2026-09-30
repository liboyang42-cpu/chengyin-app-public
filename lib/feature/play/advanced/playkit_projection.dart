import 'package:flutter/foundation.dart';

enum PlayKitKind {
  // ── v5.1 半屏 sheet 那批(已实现)────────────────────────────
  timeWindow,
  blindTaste,
  silentOrder,
  diyName,
  musicCorner,
  steps,
  slowTask,
  dailySign,
  // ── v5.2 整屏那批 ──────────────────────────────────────────
  // 小程序 pages/play/components/playkit/index.js 原文:「整屏就是判定区」
  // 「墙就是手机的四条边」「整屏被油盖住」—— 压在半屏里全部不成立,
  // 所以这批必须走整屏宿主,不要塞进 AdvancedPlayKitView。
  coinFlip,
  diceRoll,
  reaction,
  ballShake,
  quietHold,
  countdown,
  stopwatch,
  // 问答族三种模式(type / pick / shot)共用一屏,不铺成三种 kind:
  // 它们的差别只在中间那一块,铺开的话同一处改动要改三遍。
  qa,
  branch,
  estimate,
  pricePair,
  hiddenObject,
  // ── 其余 ────────────────────────────────────────────────────
  predict,
  random,
  scan,
  // ── 《预制人生》四段(2026-09-17 契约 §2,§2.3 的 check 已作废)────────
  // 真源 `utils/playkit-view.js` 的 KIT_PRIORITY 里这批插在 scan 与 coinFlip 之间,
  // profile 开档排最前(故事变量要靠它)。四段的呈现全是整屏台面 `cy-play-stage`
  // (skin="qadark"),与问答族同一套壳。判定全在服务端:done/passed/flagged 由
  // 会话视图回读,客户端不推算(见各段 `segmentComplete` 口径)。
  profile,
  photoCheck,
  note,
  typeIn,
  // 计步单独一个 walk:已有的 steps 是 v5.1 半屏那套壳,与整屏不是一套东西
  walk,
  stickerBook,
  gameTimer,
  bingo,
}

/// 服务端段名 → [PlayKitKind]。
///
/// ★ 同源:小程序 `utils/playkit-view.js` 的 `TYPE_OF` 与 `KIT_PRIORITY`。
/// 名字不在这张表里 = 服务端下发了这一段,客户端也当它不存在:
/// 拿不到 kit → 按「这个节点没有玩法」处理,**不渲染、不报错**(小程序原口径)。
/// 漏一个的后果不是报错,是那个玩法**永远不会出现**,所以这张表由
/// `test/feature/play/playkit_contract_test.dart` 按段名全表盯着。
///
/// **本地 kind 不在这张表里**([kLocalPlayKitKinds],四个):服务端不会下发它们,
/// 混进来会让「服务端段名」和「分发器白名单」两张表的差集算不清。
///
/// 顺序 = 优先级(数组序即小程序 KIT_PRIORITY 的次序):
/// 节点玩法模板那批排最前,它们是这个节点的主玩法;branch 又排最前,
/// 它是一整段剧情,中途插一屏别的会把叙事打断。
const List<String> kPlayKitSegmentOrder = <String>[
  'qa',
  'branch',
  'predict',
  'random',
  'estimate',
  'pricePair',
  'hiddenObject',
  'scan',
  // 《预制人生》四段:真源序里插在 scan 与 coinFlip 之间,profile 开档最前。
  'profile',
  'photoCheck',
  'note',
  'typeIn',
  'coinFlip',
  'diceRoll',
  'reaction',
  'ballShake',
  'quietHold',
  'countdown',
  'stopwatch',
  // slowTask 排在展示型之前、动手型之后:它需要玩家做一次决定(开始/领取),
  // 但不像答题那样必须当场完成。
  'blindTaste',
  'diyName',
  'silentOrder',
  'steps',
  'slowTask',
  'musicCorner',
  'dailySign',
  'timeWindow',
];

const Map<String, PlayKitKind> kPlayKitSegmentKinds = <String, PlayKitKind>{
  'qa': PlayKitKind.qa,
  'branch': PlayKitKind.branch,
  'predict': PlayKitKind.predict,
  'random': PlayKitKind.random,
  'estimate': PlayKitKind.estimate,
  'pricePair': PlayKitKind.pricePair,
  'hiddenObject': PlayKitKind.hiddenObject,
  'scan': PlayKitKind.scan,
  'profile': PlayKitKind.profile,
  'photoCheck': PlayKitKind.photoCheck,
  'note': PlayKitKind.note,
  'typeIn': PlayKitKind.typeIn,
  'coinFlip': PlayKitKind.coinFlip,
  'diceRoll': PlayKitKind.diceRoll,
  'reaction': PlayKitKind.reaction,
  'ballShake': PlayKitKind.ballShake,
  'quietHold': PlayKitKind.quietHold,
  'countdown': PlayKitKind.countdown,
  'stopwatch': PlayKitKind.stopwatch,
  'blindTaste': PlayKitKind.blindTaste,
  'diyName': PlayKitKind.diyName,
  'silentOrder': PlayKitKind.silentOrder,
  'steps': PlayKitKind.steps,
  'slowTask': PlayKitKind.slowTask,
  'musicCorner': PlayKitKind.musicCorner,
  'dailySign': PlayKitKind.dailySign,
  'timeWindow': PlayKitKind.timeWindow,
};

/// 组件 **type 名** → [PlayKitKind]。
///
/// ★ 同源:小程序 `pages/play/components/playkit/index.js` 的 `KIT_TYPES`
/// (分发器白名单)。type 名与服务端段名**不总是一样** ——
/// `pricePair` 的 type 是 `pricepair`,`hiddenObject` 的 type 是 `hidden`,
/// `stickerBook` 的 type 是 `stickerbook`。按段名当 type 用会认错组件。
///
/// 比 [kPlayKitSegmentKinds] 多四个本地 kind(`stickerbook` / `gametimer` /
/// `bingo` / `walk`):它们不在服务端段名表里,由本地流程直接点名。
const Map<String, PlayKitKind> kPlayKitTypeKinds = <String, PlayKitKind>{
  'qa': PlayKitKind.qa,
  'branch': PlayKitKind.branch,
  'predict': PlayKitKind.predict,
  'random': PlayKitKind.random,
  'estimate': PlayKitKind.estimate,
  'pricepair': PlayKitKind.pricePair,
  'hidden': PlayKitKind.hiddenObject,
  'scan': PlayKitKind.scan,
  'profile': PlayKitKind.profile,
  'photocheck': PlayKitKind.photoCheck,
  'note': PlayKitKind.note,
  'typein': PlayKitKind.typeIn,
  'coinflip': PlayKitKind.coinFlip,
  'diceroll': PlayKitKind.diceRoll,
  'reaction': PlayKitKind.reaction,
  'ballshake': PlayKitKind.ballShake,
  'quiethold': PlayKitKind.quietHold,
  'countdown': PlayKitKind.countdown,
  'stopwatch': PlayKitKind.stopwatch,
  'blindtaste': PlayKitKind.blindTaste,
  'diyname': PlayKitKind.diyName,
  'silentorder': PlayKitKind.silentOrder,
  'steps': PlayKitKind.steps,
  'slowtask': PlayKitKind.slowTask,
  'musiccorner': PlayKitKind.musicCorner,
  'dailysign': PlayKitKind.dailySign,
  'timewindow': PlayKitKind.timeWindow,
  'walk': PlayKitKind.walk,
  'stickerbook': PlayKitKind.stickerBook,
  'gametimer': PlayKitKind.gameTimer,
  'bingo': PlayKitKind.bingo,
};

/// 不在服务端段名表里的本地 kind —— 小程序 KIT_TYPES 里多出来的那四个。
const Set<PlayKitKind> kLocalPlayKitKinds = <PlayKitKind>{
  PlayKitKind.walk,
  PlayKitKind.stickerBook,
  PlayKitKind.gameTimer,
  PlayKitKind.bingo,
};

/// 投影优先级表:kind → 排序权重(越小越先弹)。
///
/// ★ 同源:小程序 `utils/playkit-view.js` 的 `KIT_PRIORITY`(数组序即优先级序)。
/// App 侧把数组序展开成数值,是为了在「多段同时挂起、只投一张卡」时排序;
/// **次序而非数值本身**是真源判据 —— 逐 kind 逐位对账钉在
/// `test/feature/play/playkit_priority_parity_test.dart`,表漂移即红。
///
/// ⚠️ 取值必须容错(查表方 `?? 99`):这张表由各玩法批次按需追加,漏登记一个 kind
/// 原来会在查表处 `!` 崩掉(而不是「那个玩法显示不出来」)。
/// 值类型是 num(不是 int):真源的次序是唯一判据,而「只追加、不重排既有数值」
/// 把整数位占满了 —— 新 kind 要插在两个既有整数之间,只能落成小数。
/// 既有 13 条(-5 … 7)的数值一个都没动;后来补的五条决定/挑战类
/// 全部落在 (-0.8, -0.6) 的空隙里。
const Map<PlayKitKind, num> kPlayKitSegmentPriority = <PlayKitKind, num>{
  // 问答族五段排最前:小程序 KIT_PRIORITY 里它们本来就在最前
  // (branch 又排最前 —— 它是一整段剧情,中途插一屏别的会把叙事打断)。
  // 用负数而不是把既有条目整体后移:那些值是别的批次定的,只追加、不改别人的。
  PlayKitKind.qa: -5,
  PlayKitKind.branch: -4,
  // predict / random 夹在 branch 与 estimate 之间
  // (真源序:branch → predict → random → estimate)。两屏都是「做个动作」,
  // 没有判定屏 —— 答案由商家事后给 / 由服务端按权重定。
  PlayKitKind.predict: -3.8,
  PlayKitKind.random: -3.6,
  PlayKitKind.estimate: -3,
  PlayKitKind.pricePair: -2,
  PlayKitKind.hiddenObject: -1,
  // scan 夹在 hiddenObject 与 blindTaste 之间
  // (真源序:hiddenObject → scan → coinFlip … quietHold → countdown → stopwatch → blindTaste)。
  // countdown / stopwatch 之前排在末尾(8/9),与真源序不符,本批一并对齐。
  PlayKitKind.scan: -0.8,
  // 《预制人生》四段插在 scan 与 coinFlip 的开区间里(真源序:
  // scan → profile → photoCheck → note → typeIn → coinFlip)。
  // 落小数位而非重排既有数值:那 13 条(-5 … 7)是别的批次定的,只追加、不动别人。
  PlayKitKind.profile: -0.798,
  PlayKitKind.photoCheck: -0.796,
  PlayKitKind.note: -0.794,
  PlayKitKind.typeIn: -0.792,
  // 决定类/挑战类五条(coinFlip … quietHold)曾「不落表、由整屏宿主接走」——
  // 那个前提是错的:整屏的**唯一入口**就是这张表选出来的单卡
  // (advanced_play_sheet 只在 picked 卡上挂「进入玩法」),落默认值 99 等于
  // 节点同挂别的未完成段时这两屏永远排不进展示位 —— 与 §3.2 那两处
  // `complete: true` 同一失效模式。真源序里它们在 scan 与 countdown 之间。
  // (《预制人生》四段 profile / photoCheck / note / typeIn 在真源序里就插在本表
  //  scan 与 coinFlip 之间;2026-09-19 · a4-playkit-journey4 落地,落位见上四条。)
  PlayKitKind.coinFlip: -0.78,
  PlayKitKind.diceRoll: -0.76,
  PlayKitKind.reaction: -0.74,
  PlayKitKind.ballShake: -0.72,
  PlayKitKind.quietHold: -0.7,
  PlayKitKind.countdown: -0.6,
  PlayKitKind.stopwatch: -0.4,
  PlayKitKind.blindTaste: 0,
  PlayKitKind.diyName: 1,
  PlayKitKind.silentOrder: 2,
  PlayKitKind.steps: 3,
  PlayKitKind.slowTask: 4,
  PlayKitKind.musicCorner: 5,
  PlayKitKind.dailySign: 6,
  PlayKitKind.timeWindow: 7,
};

const Map<PlayKitKind, String> _kPlayKitKindTypes = <PlayKitKind, String>{
  PlayKitKind.qa: 'qa',
  PlayKitKind.branch: 'branch',
  PlayKitKind.predict: 'predict',
  PlayKitKind.random: 'random',
  PlayKitKind.estimate: 'estimate',
  PlayKitKind.pricePair: 'pricepair',
  PlayKitKind.hiddenObject: 'hidden',
  PlayKitKind.scan: 'scan',
  PlayKitKind.coinFlip: 'coinflip',
  PlayKitKind.diceRoll: 'diceroll',
  PlayKitKind.reaction: 'reaction',
  PlayKitKind.ballShake: 'ballshake',
  PlayKitKind.quietHold: 'quiethold',
  PlayKitKind.countdown: 'countdown',
  PlayKitKind.stopwatch: 'stopwatch',
  PlayKitKind.profile: 'profile',
  PlayKitKind.photoCheck: 'photocheck',
  PlayKitKind.note: 'note',
  PlayKitKind.typeIn: 'typein',
  PlayKitKind.blindTaste: 'blindtaste',
  PlayKitKind.diyName: 'diyname',
  PlayKitKind.silentOrder: 'silentorder',
  PlayKitKind.steps: 'steps',
  PlayKitKind.slowTask: 'slowtask',
  PlayKitKind.musicCorner: 'musiccorner',
  PlayKitKind.dailySign: 'dailysign',
  PlayKitKind.timeWindow: 'timewindow',
  PlayKitKind.walk: 'walk',
  PlayKitKind.stickerBook: 'stickerbook',
  PlayKitKind.gameTimer: 'gametimer',
  PlayKitKind.bingo: 'bingo',
};

/// [PlayKitKind] → 小程序分发器认的 type 名。**只走这张表**,不要自己拼字符串。
String buildPlayKitKindTypeName(PlayKitKind kind) =>
    _kPlayKitKindTypes[kind] ?? kind.name.toLowerCase();

/// 玩法该铺在哪一层(施工契约 §1.5)。
///
/// ★ 同源:小程序 `pages/play/utils/playkit-view.js` 的 `presentOf`(:346)与
/// kit 上的 `present` 字段(`pickPlayKit` 的 `base`,:370);服务端最终值由
/// `AdvancedGameConfigValidator#resolvePresent` 一处定出(显式配置优先,缺省按
/// 三档默认表),**客户端不重推默认表**。
enum PlayKitPresentation {
  /// 铺进故事流:真源 `pages/play/index.js:4801-4809` 据此把 `playKit.show`
  /// 关掉(不弹那一层),kit 由故事流内嵌渲染(`_inlineKit()`:4851-4854)。
  inline,

  /// 现行壳:整屏族走全屏路由、其余走半屏/内联卡(App 已有行为)。
  /// 字段缺失 / 非法值都落这一档 —— 真源 `presentOf` 的「存量行为逐字不变」。
  fullscreen,
}

/// 服务端下发值 → [PlayKitPresentation]:**只有字面量 `'inline'` 算内嵌**,
/// null / 缺字段 / `'fullscreen'` / 任何其它值一律 fullscreen。
/// 逐字对齐真源 `presentOf(view)`(`view.present === 'inline' ? 'inline' : 'fullscreen'`)。
PlayKitPresentation playKitPresentationOf(Object? rawPresent) =>
    rawPresent == 'inline'
    ? PlayKitPresentation.inline
    : PlayKitPresentation.fullscreen;

@immutable
class PlayKitAction {
  const PlayKitAction({
    required this.label,
    required this.action,
    this.payload = const <String, Object?>{},
  });

  final String label;
  final String action;
  final Map<String, Object?> payload;
}

@immutable
class PlayKitCard {
  const PlayKitCard({
    required this.kind,
    required this.title,
    required this.detail,
    this.complete = false,
    this.eyebrow = '',
    this.stepsA11y = '',
    this.hint = '',
    this.rewardLabel = '',
    this.selectedKey = '',
    this.durationSeconds = 0,
    this.started = false,
    this.claimed = false,
    this.daysLeft = 0,
    this.unlockText = '',
    this.primaryAction,
    this.choices = const <PlayKitAction>[],
    this.maxLength,
    this.suggestions = const <String>[],
    this.mediaUrl,
    this.kit = const <String, Object?>{},
    this.present = PlayKitPresentation.fullscreen,
  });

  final PlayKitKind kind;
  final String title;
  final String detail;
  final bool complete;
  final String eyebrow;
  final String stepsA11y;
  final String hint;
  final String rewardLabel;
  final String selectedKey;
  final int durationSeconds;
  final bool started;
  final bool claimed;
  final int daysLeft;
  final String unlockText;
  final PlayKitAction? primaryAction;
  final List<PlayKitAction> choices;
  final int? maxLength;

  /// `diyName` 的候选词(真源 `buildDiyName` 的 `seg.suggestions`,商家最多配 6 个)。
  /// 半屏那批的字段在卡片上已经齐了,所以它跟 [maxLength] 一样直接落在卡片上。
  final List<String> suggestions;
  final String? mediaUrl;

  /// 整屏族的**原始服务端段**(`playKit.<段名>` 那一整块)。
  ///
  /// 为什么卡片上还要带原始段:整屏那批的题干、选项 id、海报清单、待找目标
  /// 是上面那几个通用字段装不下的,而缝的口径是「只从
  /// [PlayKitFullscreenContext] 取数据」——组件不许自己去读 provider。
  /// 半屏那批不带它:它们的字段在卡片上已经齐了。
  final Map<String, Object?> kit;

  /// 呈现判定(施工契约 §1.5)——**投影输出的显式字段**:
  /// 宿主按它维持现行整屏/半屏壳([PlayKitPresentation.fullscreen]),
  /// 故事流线(a4-playkit-storyflow)按它决定把 kit 铺进故事流
  /// ([PlayKitPresentation.inline])。值来自会话视图根层 `present`
  /// (经 [playKitPresentationOf] 归一),与真源 kit 对象上的 `present` 同形。
  final PlayKitPresentation present;

  /// 只换 [present] 的副本 —— 呈现方式是视图根层级的字段,23 个分支卡各自
  /// 都不该关心它,投影在选完单卡后统一盖章(见 [projectPlayKit] 末尾)。
  PlayKitCard withPresent(PlayKitPresentation value) => PlayKitCard(
    kind: kind,
    title: title,
    detail: detail,
    complete: complete,
    eyebrow: eyebrow,
    stepsA11y: stepsA11y,
    hint: hint,
    rewardLabel: rewardLabel,
    selectedKey: selectedKey,
    durationSeconds: durationSeconds,
    started: started,
    claimed: claimed,
    daysLeft: daysLeft,
    unlockText: unlockText,
    primaryAction: primaryAction,
    choices: choices,
    maxLength: maxLength,
    suggestions: suggestions,
    mediaUrl: mediaUrl,
    kit: kit,
    present: value,
  );
}

/// 投影响应的那一张卡。
///
/// [present] 是会话视图根层的呈现方式(已归一)——真源 `pickPlayKit` 把
/// `presentOf(view)` 盖在 kit 的 `base` 上(:369-370),这里同一口径:
/// 单卡选出来后统一盖章,卡面分支不各自读它。缺省 fullscreen =
/// 视图没带这个字段(旧后端 / 缺字段)时存量行为逐字不变。
List<PlayKitCard> projectPlayKit(
  Map<String, Object?> source, {
  PlayKitPresentation present = PlayKitPresentation.fullscreen,
}) {
  final List<PlayKitCard> cards = <PlayKitCard>[];
  final Map<String, Object?> timeWindow = _map(source['timeWindow']);
  if (timeWindow.isNotEmpty) {
    cards.add(
      PlayKitCard(
        kind: PlayKitKind.timeWindow,
        // 默认文案逐字照抄真源 `buildTimeWindow`(seg.title || '还没到开放时间' /
        // eyebrow || '时段限定')—— 这一屏本来就是「还没到点」那张门禁卡。
        title: _text(timeWindow['title'], '还没到开放时间'),
        detail:
            '${_text(timeWindow['openFrom'], '--:--')} – ${_text(timeWindow['openTo'], '--:--')}',
        eyebrow: _text(timeWindow['eyebrow'], '时段限定'),
        kit: timeWindow,
      ),
    );
  }

  final Map<String, Object?> blindTaste = _map(source['blindTaste']);
  if (blindTaste.isNotEmpty) {
    final bool solved = blindTaste['solved'] == true;
    cards.add(
      PlayKitCard(
        kind: PlayKitKind.blindTaste,
        title: _text(blindTaste['title'], '先尝再猜'),
        detail: solved ? '已猜对' : _text(blindTaste['hint'], '选择你尝到的答案'),
        complete: solved,
        eyebrow: '闭眼味觉师 · 盲品',
        stepsA11y: _text(blindTaste['steps'], '领小样、闭眼尝、作答'),
        hint: _text(blindTaste['hint'], '猫向导：别偷看，舌头比眼睛诚实'),
        // 真源 `buildBlindTaste`(playkit-view.js:109)逐字:`'答对 +' + xp + ' XP'`。
        // 单位是 XP 不是 App 排行榜那套 EXP —— 这一屏的奖励字样跟着玩法真源走。
        rewardLabel: _int(blindTaste['xp']) > 0
            ? '答对 +${_int(blindTaste['xp'])} XP'
            : '',
        selectedKey: solved ? _text(blindTaste['lastKey'], '') : '',
        choices: _maps(blindTaste['options'])
            .where((option) => _text(option['key'], '').isNotEmpty)
            .map(
              (option) => PlayKitAction(
                label: _text(option['label'], _text(option['key'], '选项')),
                action: 'SUBMIT_BLIND_TASTE',
                payload: <String, Object?>{'key': option['key']},
              ),
            )
            .toList(growable: false),
      ),
    );
  }

  final Map<String, Object?> silentOrder = _map(source['silentOrder']);
  if (silentOrder.isNotEmpty) {
    cards.add(
      PlayKitCard(
        kind: PlayKitKind.silentOrder,
        title: _text(silentOrder['title'], '沉默点单'),
        detail: _text(silentOrder['rule'], '用动作完成点单'),
        // ⚠️ 不写 complete:真源 `segmentComplete`(utils/playkit-view.js:142-170)
        // **没有 silentOrder 这个分支**,落到末尾 `return false`。写死 true 的后果是
        // `firstWhere((c) => !c.complete)` 直接把这一屏挤出展示位,而真源会照常弹。
        // 整屏/半屏那批的真题面在原始段里(见证码地址、已表演秒数),
        // 通用字段装不下 —— 见 PlayKitCard.kit 的说明。
        kit: silentOrder,
      ),
    );
  }

  final Map<String, Object?> diyName = _map(source['diyName']);
  if (diyName.isNotEmpty) {
    final String name = _text(diyName['name'], '');
    cards.add(
      PlayKitCard(
        kind: PlayKitKind.diyName,
        title: _text(diyName['title'], '给今天起个名字'),
        detail: name.isEmpty ? '等待你命名' : name,
        complete: name.isNotEmpty,
        maxLength: _int(diyName['maxLength']) > 0
            ? _int(diyName['maxLength'])
            : 16,
        // 真源 `buildDiyName`(:275-283)把 `seg.suggestions` 原样给组件;
        // 空串在服务端配置那一步就被清掉了(advanced-game-config.js:249-251),
        // 这里再兜一次,免得空 chip 占一格。
        suggestions: <String>[
          for (final Object? item
              in (diyName['suggestions'] is List
                  ? diyName['suggestions'] as List
                  : const <Object?>[]))
            if ('$item'.trim().isNotEmpty) '$item'.trim(),
        ],
      ),
    );
  }

  final Map<String, Object?> musicCorner = _map(source['musicCorner']);
  if (musicCorner.isNotEmpty) {
    cards.add(
      PlayKitCard(
        kind: PlayKitKind.musicCorner,
        title: _text(musicCorner['title'], '治愈音乐角'),
        // 真源 `buildMusicCorner`(playkit-view.js:468)那句默认是 `店主的歌单`
        // —— 商家没填 trackName 时,组件的播放按钮也写着它。
        detail: _text(musicCorner['trackName'], '店主的歌单'),
        eyebrow: '治愈音乐角',
        // 真源 `buildMusicCorner`(utils/playkit-view.js:299)写死的这句,逐字节照抄
        // (真源那份是半角逗号):不承诺奖励 —— 音乐角明确不判定通关(2026-08-26 拍板)。
        hint: '坐下来,听完这一首',
        // 同 silentOrder:真源 `segmentComplete` 没有 musicCorner 分支 → 恒 false,
        // 写死 true 会把播放器从展示位上挤掉。
        durationSeconds: _int(musicCorner['durationSeconds']),
        mediaUrl: _text(musicCorner['audioUrl'], '').isEmpty
            ? null
            : _text(musicCorner['audioUrl'], ''),
      ),
    );
  }

  final Map<String, Object?> steps = _map(source['steps']);
  if (steps.isNotEmpty) {
    final int current = _int(steps['todaySteps']);
    final int goal = _int(steps['goal']);
    cards.add(
      PlayKitCard(
        kind: PlayKitKind.steps,
        title: '低碳行动',
        detail: '$current / $goal 步',
        complete: steps['reached'] == true,
        // 后端要求微信运动 encryptedData + iv，App 不伪造成可用写入。
        primaryAction: null,
        kit: steps,
      ),
    );
  }

  final Map<String, Object?> slowTask = _map(source['slowTask']);
  if (slowTask.isNotEmpty) {
    final bool started = slowTask['started'] == true;
    final bool claimed = slowTask['claimed'] == true;
    final int daysLeft = _int(slowTask['daysLeft']);
    cards.add(
      PlayKitCard(
        kind: PlayKitKind.slowTask,
        title: _text(slowTask['title'], '跨日慢任务'),
        eyebrow: '慢一点 · 跨日任务',
        // 三态各有各的话:未开始 / 等到日子 / 已就绪(真源 `playkit-slowtask/index.wxml`
        // 的 `wx:if` 链)。「已就绪」写「再等 0 天」是把两个不同的态合成了一句。
        detail: claimed
            ? _text(slowTask['unlockText'], '已解锁')
            : started && daysLeft > 0
            // 真源 `waitHint` 默认为空 —— 空就不填:等待中那句「还有 N 天」由组件
            // 自己说(`.sl__days`),这一格对应的是它下面那行 `.sl__waithint`。
            ? _text(slowTask['waitHint'], '')
            : started
            ? '已经准备好了，领取后揭示今天的发现。'
            // 真源 `index.js:14` 的 `startHint` 默认值,逐字节(半角逗号)。
            : _text(slowTask['startHint'], '现在开个头,剩下的交给时间。'),
        complete: claimed,
        started: started,
        claimed: claimed,
        daysLeft: daysLeft,
        unlockText: _text(slowTask['unlockText'], ''),
        primaryAction: claimed || (started && daysLeft > 0)
            ? null
            : PlayKitAction(
                label: started
                    ? _text(slowTask['unlockLabel'], '查看解锁')
                    : _text(slowTask['startLabel'], '开始'),
                action: started ? 'CLAIM_SLOW_TASK' : 'START_SLOW_TASK',
              ),
      ),
    );
  }

  final Map<String, Object?> dailySign = _map(source['dailySign']);
  if (dailySign.isNotEmpty) {
    final bool claimed = _text(dailySign['claimedDate'], '').isNotEmpty;
    final String lines =
        (dailySign['lines'] is List
                ? dailySign['lines'] as List
                : const <Object?>[])
            .map((line) => '$line')
            .where((line) => line.isNotEmpty)
            .join('\n');
    cards.add(
      PlayKitCard(
        kind: PlayKitKind.dailySign,
        title: '今日城市签',
        detail: claimed
            ? lines
            : '由 ${_text(dailySign['signer'], '城市向导')} 为你签发',
        complete: claimed,
        primaryAction: claimed
            ? null
            : const PlayKitAction(label: '领取今日签', action: 'CLAIM_DAILY_SIGN'),
        kit: dailySign,
      ),
    );
  }

  // ── 问答族五段(v5.2 整屏那批)────────────────────────────────
  // 这五段的交互在 fullscreen/ 里铺开(选项 id、海报清单、待找目标装不进卡片),
  // 这里只给出**预览卡**该有的那一行,并把原始服务端段挂到 `kit` 上。
  // 完成口径逐条照抄小程序 `utils/playkit-view.js#segmentComplete`。
  final Map<String, Object?> qa = _map(source['qa']);
  if (qa.isNotEmpty) {
    cards.add(
      PlayKitCard(
        kind: PlayKitKind.qa,
        title: _text(qa['title'], '问答'),
        detail: switch (('${qa['mode']}').toUpperCase()) {
          'PICK' => '选择作答',
          'SHOT' => '拍照打卡',
          _ => '打字作答',
        },
        // 问答:答完就算(答错次数用完也算完)
        complete: qa['finished'] == true,
        kit: qa,
      ),
    );
  }

  final Map<String, Object?> branch = _map(source['branch']);
  if (branch.isNotEmpty) {
    final Map<String, Object?> step = _map(branch['currentStep']);
    cards.add(
      PlayKitCard(
        kind: PlayKitKind.branch,
        title: _text(step['title'], '分支剧情'),
        detail: _text(step['body'], ''),
        // 走到终点那一步就算这段剧情完了 —— 终点没有选项,再弹一次也没得选
        complete: step['terminal'] == true,
        kit: branch,
      ),
    );
  }

  final Map<String, Object?> estimate = _map(source['estimate']);
  if (estimate.isNotEmpty) {
    final String unit = _text(estimate['unit'], '');
    cards.add(
      PlayKitCard(
        kind: PlayKitKind.estimate,
        title: _text(estimate['question'], _text(estimate['title'], '猜个数')),
        detail: estimate['submitted'] == true
            ? '已交过这一注'
            : unit.isEmpty
            ? '滑到差不多就交'
            : '滑到差不多就交 · $unit',
        // 猜数字看的是「答过了」不是「答对了」:猜不中就卡住,玩家会退出而不是重猜
        complete: estimate['submitted'] == true,
        kit: estimate,
      ),
    );
  }

  final Map<String, Object?> pricePair = _map(source['pricePair']);
  if (pricePair.isNotEmpty) {
    final int attempts = _int(pricePair['attempts']);
    final int maxTries = _int(pricePair['maxTries']);
    cards.add(
      PlayKitCard(
        kind: PlayKitKind.pricePair,
        title: _text(pricePair['title'], '挑出对的那张'),
        detail: maxTries > 0 ? '已试 $attempts / $maxTries 次' : '挑出对的那张',
        complete: pricePair['finished'] == true,
        kit: pricePair,
      ),
    );
  }

  final Map<String, Object?> hiddenObject = _map(source['hiddenObject']);
  if (hiddenObject.isNotEmpty) {
    final int total = _int(hiddenObject['total']);
    final int found =
        (hiddenObject['foundIds'] is List
                ? hiddenObject['foundIds']! as List
                : const <Object?>[])
            .length;
    cards.add(
      PlayKitCard(
        kind: PlayKitKind.hiddenObject,
        title: _text(hiddenObject['title'], '找东西'),
        detail: '已找到 $found / $total',
        // 找东西反过来:有确定答案,必须全找齐才算过
        complete: total > 0 && found >= total,
        kit: hiddenObject,
      ),
    );
  }
  // ── 计时族(2026-09-17,feat/playkit-timers)─────────────────────────────
  // 只投影**服务端段名**里的两条:`countdown` / `stopwatch`(`kPlayKitSegmentKinds`
  // 里有它们,顺序也在 `kPlayKitSegmentOrder` 里)。整屏组件见
  // `advanced/fullscreen/playkit_{countdown,stopwatch}_view.dart`。
  //
  // 卡片字段的槽位(整屏族的通用口径:`maxLength` 当通用数值槽,与 screen 批的
  // rounds / hits 同源;`eyebrow` 当 kicker):
  //   countdown: durationSeconds ← seconds、hint ← doneText
  //   stopwatch: durationSeconds ← targetSeconds、maxLength ← toleranceMs、
  //              kit ← 整块(只剩 `tries` 这一个通用槽装不下的字段)
  // `tries` 是真源共享台面 `cy-play-stage` 的属性(`playkit/index.wxml:94`),
  // 台面上画「还能错」的圆点、用完即判负(`play-stage/index.js:134-139`);
  // App 侧台面还没落地,所以原始段挂在卡片上、由停表组件自己记这一笔。
  // ⚠️ 不搬的后果:次数用尽后真源挡住「再来一局」,App 会再发一条
  // SUBMIT_STOPWATCH,被服务端判成「这一局已经交过了」。
  //
  // ⚠️ `walk` / `stickerBook` / `gameTimer` 是**本地 kind**,服务端不下发它们 ——
  // 不要在这里给它们造段名(凭空多一个服务端不认识的 key,会把「谁在什么时候
  // 显示这个玩法」搞成两处真相)。它们由本地流程直接点名。
  final Map<String, Object?> countdown = _map(source['countdown']);
  if (countdown.isNotEmpty) {
    final int seconds = _int(countdown['seconds']);
    final String kicker = _text(countdown['kicker'], '');
    cards.add(
      PlayKitCard(
        kind: PlayKitKind.countdown,
        title: _text(countdown['kicker'], '倒计时'),
        detail: '',
        eyebrow: kicker,
        durationSeconds: seconds > 0 ? seconds : 0,
        hint: _text(countdown['doneText'], ''),
        // 挑战类:服务端判过(submitted)就算完 —— passed 只决定拿不拿分
        // (真源 utils/playkit-view.js:167-168,与 reaction/ballShake/quietHold 同一条)
        complete: countdown['submitted'] == true,
      ),
    );
  }

  final Map<String, Object?> stopwatch = _map(source['stopwatch']);
  if (stopwatch.isNotEmpty) {
    final int toleranceMs = _int(stopwatch['toleranceMs']);
    final String kicker = _text(stopwatch['kicker'], '');
    cards.add(
      PlayKitCard(
        kind: PlayKitKind.stopwatch,
        title: _text(stopwatch['kicker'], '精准停表'),
        detail: '',
        eyebrow: kicker,
        durationSeconds: _int(stopwatch['targetSeconds']),
        maxLength: toleranceMs > 0 ? toleranceMs : null,
        // 同上:服务端判过就算完,别再弹一次「做过了」的玩法
        complete: stopwatch['submitted'] == true,
        kit: stopwatch,
      ),
    );
  }
  // ── v5.2 整屏决定类五件套 ─────────────────────────────────
  // ★ 同源:`utils/playkit-view.js` 的 `pickPlayKit` 里那五个分支。
  // ⚠️ 本批没有动 PlayKitCard 的字段(它是各批次共用的写集,问答族刚加了 `kit`):
  //    小程序 kit 的字段全部落在既有槽位上,映射逐条写在下面 —— 漏一个不是报错,
  //    是那个玩法在 App 里没有数据可演。
  // ★ coinFlip / diceRoll 的**结果由服务端给**(side / pips),组件只演不算;
  //    挑战类三件的成绩由服务端按 START_CHALLENGE 那一刻的服务器时间复核。
  final Map<String, Object?> coinFlip = _map(source['coinFlip']);
  if (coinFlip.isNotEmpty) {
    final Map<String, Object?> heads = _map(coinFlip['heads']);
    final Map<String, Object?> tails = _map(coinFlip['tails']);
    final String headsLabel = _text(heads['label'], '正面');
    final String headsAction = _text(heads['action'], '');
    final String tailsLabel = _text(tails['label'], '反面');
    final String tailsAction = _text(tails['action'], '');
    cards.add(
      PlayKitCard(
        kind: PlayKitKind.coinFlip,
        title: _text(coinFlip['kicker'], '抛一次，认结果'),
        detail: '$headsLabel · $headsAction\n$tailsLabel · $tailsAction',
        eyebrow: _text(coinFlip['kicker'], '抛一次，认结果'),
        // 服务端的结果(HEADS / TAILS);空 = 还没抛。组件不猜、不本地摇。
        selectedKey: _text(coinFlip['side'], ''),
        complete: coinFlip['flipped'] == true,
        choices: <PlayKitAction>[
          PlayKitAction(
            label: headsLabel,
            action: '',
            payload: <String, Object?>{'do': headsAction},
          ),
          PlayKitAction(
            label: tailsLabel,
            action: '',
            payload: <String, Object?>{'do': tailsAction},
          ),
        ],
      ),
    );
  }

  // ── 节点玩法模板族最后三条(v5.2 整屏那批,2026-09-17 · feat/playkit-misc)──
  // 与问答族同一口径:这里只给**预览卡**那一行,原始服务端段挂到 `kit` 上,
  // 交互在 fullscreen/playkit_{predict,random,scan}_view.dart 里铺开。
  // 完成口径逐条照抄 `segmentComplete`(:146 / :148 / :152)。
  final Map<String, Object?> predict = _map(source['predict']);
  if (predict.isNotEmpty) {
    final String myOptionKey = _text(predict['myOptionKey'], '').trim();
    cards.add(
      PlayKitCard(
        kind: PlayKitKind.predict,
        title: _text(predict['question'], '竞猜'),
        detail: myOptionKey.isEmpty ? '选一个押下去' : '已经押了，等商家给答案',
        // 押过就算完:答案由商家事后给,玩家这边没有第二个动作
        complete: myOptionKey.isNotEmpty,
        kit: predict,
      ),
    );
  }

  final Map<String, Object?> diceRoll = _map(source['diceRoll']);
  if (diceRoll.isNotEmpty) {
    final List<Object?> pips = diceRoll['pips'] is List
        ? diceRoll['pips'] as List
        : const <Object?>[];
    final List<Object?> faces = diceRoll['faces'] is List
        ? diceRoll['faces'] as List
        : const <Object?>[];
    final int diceCount = _int(diceRoll['diceCount']) == 2 ? 2 : 1;
    // 服务端的点数,如 '5' 或 '5,4'。非法值由组件丢弃(骰面给空,不抛错)。
    final String values = pips.join(',');
    cards.add(
      PlayKitCard(
        kind: PlayKitKind.diceRoll,
        title: _text(diceRoll['kicker'], '掷到几就做第几件事'),
        detail: values.isEmpty ? '摇一摇，把骰子扔出去' : '点数 $values',
        eyebrow: _text(diceRoll['kicker'], '掷到几就做第几件事'),
        selectedKey: values,
        complete: diceRoll['rolled'] == true,
        // 一颗 = 第 N 面就是第 N 件事;两颗只比大小,没有任务。
        maxLength: diceCount,
        choices: <PlayKitAction>[
          for (final Object? face in faces)
            PlayKitAction(label: '$face', action: ''),
        ],
      ),
    );
  }

  final Map<String, Object?> random = _map(source['random']);
  if (random.isNotEmpty) {
    final int drawCount = _int(random['drawCount']);
    final int drawnCount =
        (random['drawn'] is List ? random['drawn']! as List : const <Object?>[])
            .length;
    cards.add(
      PlayKitCard(
        kind: PlayKitKind.random,
        title: _text(random['title'], '抽一张'),
        detail: drawCount > 0 ? '已抽 $drawnCount / $drawCount' : '翻开看看这一关',
        // 抽满次数才算完。还能抽就该继续弹,不然剩下的次数玩家永远用不掉
        complete: drawnCount >= drawCount,
        kit: random,
      ),
    );
  }

  final Map<String, Object?> reaction = _map(source['reaction']);
  if (reaction.isNotEmpty) {
    final int rounds = _int(reaction['rounds']) > 0
        ? _int(reaction['rounds'])
        : 3;
    final int goalMs = _int(reaction['goalMs']);
    cards.add(
      PlayKitCard(
        kind: PlayKitKind.reaction,
        title: _text(reaction['kicker'], '变绿就点'),
        detail: goalMs > 0 ? '$rounds 轮 · 达标 $goalMs 毫秒' : '$rounds 轮，比最快的一次',
        eyebrow: _text(reaction['kicker'], '变绿就点'),
        // rounds → maxLength,goalMs → durationSeconds:整屏组件按这两个槽读。
        maxLength: rounds,
        durationSeconds: goalMs,
        complete: reaction['submitted'] == true,
      ),
    );
  }

  final Map<String, Object?> ballShake = _map(source['ballShake']);
  if (ballShake.isNotEmpty) {
    final int goal = _int(ballShake['goal']) > 0 ? _int(ballShake['goal']) : 30;
    // 原型 `limit-seconds="{{timed ? seconds : 0}}"` 的等价折叠:真正进判定的
    // 永远是「有效限时」,0 = 不限时(也就没有 3-2-1)。
    final int limitSeconds = ballShake['timed'] == true
        ? _int(ballShake['seconds'])
        : 0;
    cards.add(
      PlayKitCard(
        kind: PlayKitKind.ballShake,
        title: _text(ballShake['kicker'], '撞够 $goal 次'),
        detail: limitSeconds > 0 ? '$limitSeconds 秒内撞满' : '不限时，撞满为止',
        eyebrow: _text(ballShake['kicker'], '撞够 $goal 次'),
        maxLength: goal,
        durationSeconds: limitSeconds,
        complete: ballShake['submitted'] == true,
      ),
    );
  }

  final Map<String, Object?> quietHold = _map(source['quietHold']);
  if (quietHold.isNotEmpty) {
    cards.add(
      PlayKitCard(
        kind: PlayKitKind.quietHold,
        title: _text(quietHold['kicker'], '别出声'),
        // sub 是商家在编辑页填的说明行;空着就不渲染 —— 没填的地方不要替他解释。
        detail: _text(quietHold['sub'], ''),
        eyebrow: _text(quietHold['kicker'], '别出声'),
        durationSeconds: _int(quietHold['seconds']) > 0
            ? _int(quietHold['seconds'])
            : 15,
        complete: quietHold['submitted'] == true,
      ),
    );
  }

  final Map<String, Object?> scan = _map(source['scan']);
  if (scan.isNotEmpty) {
    final bool scanned = scan['scanned'] == true;
    cards.add(
      PlayKitCard(
        kind: PlayKitKind.scan,
        title: _text(scan['title'], '扫一下门口的码'),
        detail: scanned ? '已扫码' : '到店扫这个点位的码',
        // 扫码:扫了就是完了,这一屏没有第二个动作
        complete: scanned,
        kit: scan,
      ),
    );
  }

  // ── 《预制人生》四段(2026-09-19 · a4-playkit-journey4)────────────────
  // 字段搬运逐条照真源 `utils/playkit-view.js` 的 buildProfile / buildPhotoCheck /
  // buildNote / buildTypeIn,完成口径照同文件 `segmentComplete`:
  //   · 建档与留言:done 由服务端落,重复提交会被拒 —— 客户端不推算;
  //   · 拍照审核:过了或兜底放行(flagged)都算完,降级也走 flagged,不会卡成死路;
  //   · 打字:打对算完,限次用尽也算(tries=0 不限,永远不会用尽)。
  // 题面细节(题目清单 / previous 留言 / target…)装不进通用槽,整段挂 `kit`,
  // 交互在 fullscreen/playkit_prefab_views.dart 里铺开 —— 与问答族同一口径。
  final Map<String, Object?> profile = _map(source['profile']);
  if (profile.isNotEmpty) {
    final bool done = profile['done'] == true;
    cards.add(
      PlayKitCard(
        kind: PlayKitKind.profile,
        title: _text(profile['title'], '出生登记'),
        detail: done ? '已登记' : _text(profile['lead'], '填完这张表,你就有了身份。'),
        complete: done,
        kit: profile,
      ),
    );
  }

  final Map<String, Object?> photoCheck = _map(source['photoCheck']);
  if (photoCheck.isNotEmpty) {
    final bool passed = photoCheck['passed'] == true;
    final bool flagged = photoCheck['flagged'] == true;
    cards.add(
      PlayKitCard(
        kind: PlayKitKind.photoCheck,
        title: _text(photoCheck['title'], '拍一张'),
        detail: passed
            ? '这张过了'
            : flagged
            ? '这一张已定'
            : _int(photoCheck['tries']) > 0
            ? '还差一点，再拍一张'
            : '拍一张，判定在服务端',
        // 拍照审核:过了或兜底放行(flagged)都算完 —— 降级(模型没给结论)也标 flagged。
        complete: passed || flagged,
        kit: photoCheck,
      ),
    );
  }

  final Map<String, Object?> note = _map(source['note']);
  if (note.isNotEmpty) {
    final bool done = note['done'] == true;
    cards.add(
      PlayKitCard(
        kind: PlayKitKind.note,
        title: _text(note['title'], '留一句'),
        detail: done ? '这句已经留在这儿了' : _text(note['prompt'], '写一句留给下一个人'),
        // 留言:done 由服务端落(留过之后不再发第二遍)
        complete: done,
        maxLength: _int(note['maxLength']) > 0 ? _int(note['maxLength']) : 40,
        kit: note,
      ),
    );
  }

  final Map<String, Object?> typeIn = _map(source['typeIn']);
  if (typeIn.isNotEmpty) {
    final bool passed = typeIn['passed'] == true;
    final int tries = _int(typeIn['tries']);
    final int attempts = _int(typeIn['attempts']);
    cards.add(
      PlayKitCard(
        kind: PlayKitKind.typeIn,
        title: _text(typeIn['title'], '打出这行字'),
        detail: passed
            ? '一字不差'
            : tries > 0 && attempts > 0 && attempts < tries
            ? '第 ${attempts + 1} / $tries 次'
            : '限时 ${_int(typeIn['seconds'])} 秒打完它',
        // 打字:打对算完,限次用尽也算(tries=0 = 不限,永远不会用尽)
        complete: passed || (tries > 0 && attempts >= tries),
        durationSeconds: _int(typeIn['seconds']),
        maxLength: tries > 0 ? tries : null,
        kit: typeIn,
      ),
    );
  }

  cards.sort(
    (left, right) => (kPlayKitSegmentPriority[left.kind] ?? 99).compareTo(
      kPlayKitSegmentPriority[right.kind] ?? 99,
    ),
  );
  if (cards.isEmpty) return const <PlayKitCard>[];
  final PlayKitCard selected = cards.firstWhere(
    (card) => !card.complete,
    orElse: () => cards.first,
  );
  return <PlayKitCard>[selected.withPresent(present)];
}

Map<String, Object?> _map(Object? value) => value is Map
    ? value.map<String, Object?>((key, value) => MapEntry('$key', value))
    : <String, Object?>{};

List<Map<String, Object?>> _maps(Object? value) =>
    (value is List ? value : const <Object?>[])
        .whereType<Map>()
        .map(_map)
        .toList(growable: false);

String _text(Object? value, String fallback) {
  final String text = value?.toString().trim() ?? '';
  return text.isEmpty ? fallback : text;
}

int _int(Object? value) => value is num ? value.toInt() : 0;
