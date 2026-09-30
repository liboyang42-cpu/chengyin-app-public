import 'package:chengyin_app/feature/play/advanced/playkit_fullscreen.dart';
import 'package:chengyin_app/feature/play/advanced/playkit_projection.dart';
import 'package:flutter_test/flutter_test.dart';

/// 玩法组件契约门禁。
///
/// 真源是**小程序** `utils/playkit-view.js` 的 `KIT_PRIORITY` / `TYPE_OF`
/// 与 `pages/play/components/playkit/index.js` 的 `KIT_TYPES`。
/// 这里把三张表按原样抄下来当判据 —— CI 里没有小程序快照,抄一份是唯一办法,
/// 所以**改这张表必须同时改小程序那边**,否则这个测试就是在骗自己。
/// ★ 快照口径 github/master@3fa2b19a5(2026-09-19),含《预制人生》四新段;
/// App 尚未实现的那几段钉在 [_xcxPendingInApp](2026-09-19 · feat/a4-playkit-journey4
/// 四段落地后清空),优先级数值位的逐位对账
/// 在姊妹门禁 `playkit_priority_parity_test.dart`。
///
/// 为什么值得一条门禁:小程序原文写着「名字不在这张表里 = 服务端下发了这一段,
/// 客户端也当它不存在:present 里没有它 → 拿不到 kit → 页面按『这个节点没有玩法』
/// 处理,不渲染、不报错」。漏一个段名的后果**不是报错**,是那个玩法永远不出现。
const List<String> _xcxKitPriority = <String>[
  'qa',
  'branch',
  'predict',
  'random',
  'estimate',
  'pricePair',
  'hiddenObject',
  'scan',
  // 《预制人生》那批(2026-09-17 契约 §2),真源序里在 scan 与 coinFlip 之间。
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
  'blindTaste',
  'diyName',
  'silentOrder',
  'steps',
  'slowTask',
  'musicCorner',
  'dailySign',
  'timeWindow',
];

/// 真源在册、App 尚无 kind 的段(段名)。
/// **清空**(2026-09-19 · feat/a4-playkit-journey4):《预制人生》四段
/// (profile / photoCheck / note / typeIn)已补进 App 三张表 + 优先级表 +
/// 整屏注册表。保留这条机制:真源再加新段而 App 未落地时钉在这里,
/// 落地时从本表移除。
const Set<String> _xcxPendingInApp = <String>{};

/// `utils/playkit-view.js` 的 `TYPE_OF`:服务端段名 → 组件 type。
/// ⚠️ 名字两边不一样(`pricePair` vs `pricepair`),不是笔误。
const Map<String, String> _xcxTypeOf = <String, String>{
  'qa': 'qa',
  'scan': 'scan',
  'branch': 'branch',
  'estimate': 'estimate',
  'pricePair': 'pricepair',
  'hiddenObject': 'hidden',
  'predict': 'predict',
  'random': 'random',
  'blindTaste': 'blindtaste',
  'diyName': 'diyname',
  'silentOrder': 'silentorder',
  'steps': 'steps',
  'musicCorner': 'musiccorner',
  'dailySign': 'dailysign',
  'timeWindow': 'timewindow',
  'slowTask': 'slowtask',
  'coinFlip': 'coinflip',
  'diceRoll': 'diceroll',
  'reaction': 'reaction',
  'ballShake': 'ballshake',
  'quietHold': 'quiethold',
  'countdown': 'countdown',
  'stopwatch': 'stopwatch',
  // 《预制人生》四新段(真源注释:少一条 = type undefined,分发器整块不渲染)。
  'profile': 'profile',
  'photoCheck': 'photocheck',
  'note': 'note',
  'typeIn': 'typein',
};

/// `pages/play/components/playkit/index.js` 的 `KIT_TYPES`(分发器白名单)。
/// 比 `KIT_PRIORITY` 多四个本地 kind —— 它们不由服务端段名下发。
const List<String> _xcxKitTypes = <String>[
  'timewindow',
  'blindtaste',
  'silentorder',
  'diyname',
  'musiccorner',
  'steps',
  'stickerbook',
  'dailysign',
  'gametimer',
  'slowtask',
  'coinflip',
  'diceroll',
  'reaction',
  'ballshake',
  'quiethold',
  'countdown',
  'stopwatch',
  'qa',
  'branch',
  'estimate',
  'pricepair',
  'hidden',
  'predict',
  'random',
  'bingo',
  'scan',
  'walk',
  // 《预制人生》四新段的 type 名(契约 §2;§2.3 的 check 段已作废,不在册)。
  'profile',
  'photocheck',
  'note',
  'typein',
];

/// 本地 kind(type 名) → Dart kind。多出来的四个不在服务端段名表里。
const Map<String, PlayKitKind> _localKindsByType = <String, PlayKitKind>{
  'stickerbook': PlayKitKind.stickerBook,
  'gametimer': PlayKitKind.gameTimer,
  'bingo': PlayKitKind.bingo,
  'walk': PlayKitKind.walk,
};

/// 四个本地 kind 的**产生方登记**(2026-09-18 · feat/a4-playkit-b5)。
///
/// 口径:小程序生产链路里**谁**造出 `kit.type = <kind>` —— 不是「组件在不在」。
/// 造不出 = 两端都点不到;App 侧的组件留着不算错,与小程序
/// `pages/play/components/playkit/index.js:14` 原文同口径(不在表里就当它不存在)。
/// ⚠️ 这是**登记**,不是待办清单:真源出现产生方时改这里,并同步小程序那边。
/// 逐条的 file:line 证据见 `docs/plans/2026-09-18-playkit-local-kinds.md`。
const Map<PlayKitKind, String> _localKindProducers = <PlayKitKind, String>{
  // 唯一有产生方的一个,而且只在**商家侧**:`utils/publish/advanced-game-preview.js:137`
  // 把 `steps` 配置段翻成 `type:'walk'`,消费方 `pages/publish/temp/index.js:1757`
  // (模板编辑页 v2「试玩」,路由 `app.json:70`)。
  // 玩家侧没有 walk —— `utils/playkit-view.js` 的 KIT_PRIORITY / TYPE_OF 里查无此名,
  // 计步段在玩家侧走的是 `steps`(半屏环形那个壳)。试玩里那串步数还是**本地合成**的
  // (`steps: Math.round(goal * 0.71)`),真源注释写明「步数只能同步不能填」。
  PlayKitKind.walk: 'advanced-game-preview.js:137(商家试玩;步数本地合成,无真实来源)',
  // 下面三个:全仓只在小程序 mock 里出现过(`scripts/shot-matrix.js` 的
  // F38 / F40 / F69 三格 + `scripts/fixtures.json`),生产链路零产生方。
  PlayKitKind.gameTimer: 'none',
  PlayKitKind.stickerBook: 'none',
  PlayKitKind.bingo: 'none',
};

void main() {
  test('段名优先级表与小程序 KIT_PRIORITY 逐字一致(顺序也是判据)', () {
    expect(
      kPlayKitSegmentOrder,
      _xcxKitPriority.where((s) => !_xcxPendingInApp.contains(s)),
      reason:
          '顺序就是优先级:branch 排最前是因为它是一整段剧情,'
          '中途插一屏别的会把叙事打断。重排 = 换玩法。'
          '(_xcxPendingInApp 里若有段,落地时移出去。)',
    );
  });

  test('段名 → kind 表覆盖小程序 TYPE_OF 的每一条', () {
    final List<String> missing = <String>[
      for (final String segment in _xcxTypeOf.keys)
        if (!_xcxPendingInApp.contains(segment) &&
            !kPlayKitSegmentKinds.containsKey(segment))
          segment,
    ];
    expect(missing, isEmpty, reason: '这些段名服务端会下发,但 App 认不出:$missing');
    for (final MapEntry<String, String> entry in _xcxTypeOf.entries) {
      if (_xcxPendingInApp.contains(entry.key)) {
        expect(
          kPlayKitSegmentKinds.containsKey(entry.key),
          isFalse,
          reason: '${entry.key} 已落地,从 _xcxPendingInApp 移除并补全 App 三张表',
        );
        continue;
      }
      // 段名与 type 名不总是同名(pricePair / hiddenObject),所以按 kind 反查。
      final PlayKitKind kind = kPlayKitSegmentKinds[entry.key]!;
      expect(
        buildPlayKitKindTypeName(kind),
        entry.value,
        reason: '${entry.key} 的 type 名与小程序对不上',
      );
    }
  });

  test('每个 kind 都有 type 名,且都在小程序 KIT_TYPES 白名单里', () {
    final Set<String> typeNames = <String>{
      for (final PlayKitKind kind in PlayKitKind.values)
        buildPlayKitKindTypeName(kind),
    };
    expect(
      typeNames.length,
      PlayKitKind.values.length,
      reason: '两个 kind 撞了同一个 type 名,分发时会认错组件',
    );
    final List<String> unknown = <String>[
      for (final String type in typeNames)
        if (!_xcxKitTypes.contains(type)) type,
    ];
    expect(
      unknown,
      isEmpty,
      reason: '这些 type 名不在小程序分发器白名单里,服务端永远不会下发:$unknown',
    );
    final Set<String> pendingTypes = <String>{
      for (final String segment in _xcxPendingInApp) _xcxTypeOf[segment]!,
    };
    final List<String> uncovered = <String>[
      for (final String type in _xcxKitTypes)
        if (!typeNames.contains(type) && !pendingTypes.contains(type)) type,
    ];
    expect(
      uncovered,
      isEmpty,
      reason:
          '小程序分发器认这些玩法,App 里没有对应 kind —— '
          '用户做到这一站会停住(新段未落地时先钉 _xcxPendingInApp):$uncovered',
    );
  });

  test('本地 kind 与段名 kind 分得清,不混进服务端段名表', () {
    // 服务端段名表 = 小程序 KIT_PRIORITY(减登记不跟的四段),一个不多一个不少。
    expect(
      kPlayKitSegmentKinds.keys.toSet(),
      _xcxKitPriority.toSet().difference(_xcxPendingInApp),
      reason: '段名表与小程序 KIT_PRIORITY 对不上;本地 kind 不许混进来',
    );
    final Set<PlayKitKind> segmentKinds = kPlayKitSegmentKinds.values.toSet();
    expect(
      segmentKinds.intersection(kLocalPlayKitKinds),
      isEmpty,
      reason: '同一个 kind 既算服务端段名又算本地 kind',
    );
    expect(
      segmentKinds.union(kLocalPlayKitKinds).length,
      PlayKitKind.values.length,
      reason: '有 kind 两边都没登记 —— 服务端不会下发、本地也点不到',
    );
    for (final MapEntry<String, PlayKitKind> entry
        in _localKindsByType.entries) {
      expect(
        _xcxKitPriority.contains(entry.key),
        isFalse,
        reason: '${entry.key} 是本地 kind,不在服务端段名表里',
      );
      expect(
        kPlayKitTypeKinds[entry.key],
        entry.value,
        reason: '本地 kind 也要能被 type 名查到',
      );
      expect(
        kLocalPlayKitKinds,
        contains(entry.value),
        reason: '${entry.key} 是本地 kind,要登记进 kLocalPlayKitKinds',
      );
    }
  });

  test('本地 kind 逐个登记了产生方 —— 造不出的不许含糊', () {
    expect(
      _localKindProducers.keys.toSet(),
      kLocalPlayKitKinds,
      reason:
          '新加一个本地 kind 就得在这里登记它由谁产生;'
          '两张表对不上 = 有人绕过了这条门禁,那个玩法从此没人管',
    );
    for (final MapEntry<PlayKitKind, String> entry
        in _localKindProducers.entries) {
      // `none` 是**查过真源**的结论,空串是没想清楚 —— 两者不许混成一种。
      expect(
        entry.value.trim(),
        isNotEmpty,
        reason: '${entry.key.name} 的产生方要么写清 file:line,要么写 none',
      );
    }
  });

  test('整屏族注册表的钥匙都是合法 kind,且整屏集合 ⊆ 全部 kind', () {
    for (final PlayKitKind kind in kPlayKitFullscreenBuilders.keys) {
      expect(PlayKitKind.values, contains(kind));
    }
    for (final PlayKitKind kind in kFullscreenPlayKinds) {
      expect(PlayKitKind.values, contains(kind));
    }
    // 半屏那批(v5.1)不许混进整屏集合:它们本来就是 sheet 的壳。
    // dailySign 不在这张表里:真源 `playkit-dailysign/index.wxml` 自带页头
    // (`.ds__nav`,带日期与关闭钮),是整屏台面,不是 `cy-sheet` ——
    // 它进 [kFullscreenPlayKinds] 是对的(壳的形态另钉在 `playkit_v51_sheets_test.dart`)。
    const Set<PlayKitKind> sheetKinds = <PlayKitKind>{
      PlayKitKind.timeWindow,
      PlayKitKind.blindTaste,
      PlayKitKind.silentOrder,
      PlayKitKind.diyName,
      PlayKitKind.musicCorner,
      PlayKitKind.steps,
      PlayKitKind.slowTask,
    };
    expect(
      kFullscreenPlayKinds.intersection(sheetKinds),
      isEmpty,
      reason: 'v5.1 那批是半屏 sheet 的壳,「整屏就是判定区」在它们身上不成立',
    );
  });
}
