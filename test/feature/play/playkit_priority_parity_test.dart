import 'package:chengyin_app/feature/play/advanced/playkit_projection.dart';
import 'package:flutter_test/flutter_test.dart';

/// 投影优先级全表 vs 真源 `KIT_PRIORITY` 的**逐 kind 逐位对账门禁**。
///
/// 与 `playkit_contract_test.dart` 的分工:那条钉「段名在册」(集合相等),
/// 本条钉「数值位即优先级序」—— 把 App 表 `kPlayKitSegmentPriority` 的 num
/// 映射按真源数组序逐位核过,插一个位、挪一位都红。#301 报告点名过这个缺口:
/// 既有契约测试比的是段名表,不含 priority 数值映射。
///
/// 真源快照抄自小程序 `github/master`
/// `chengyinhub-xcx/pages/play/utils/playkit-view.js:17-33`
/// @ 3fa2b19a59fb1674b79b59ef8f8a635ecb8e5931(2026-09-19)。
/// ⚠️ 改真源那张表必须同时改这里;新段落地 App 时,把它从
/// [_xcxKitPendingInApp] 移进对账并补进 App 表,别养第二张「影子真源」。
const List<String> _xcxKitPriority = <String>[
  // 节点玩法模板那批排最前(主玩法);branch 最前 —— 一整段剧情不许被插。
  'qa',
  'branch',
  'predict',
  'random',
  'estimate',
  'pricePair',
  'hiddenObject',
  'scan',
  // 《预制人生》四段(2026-09-17 契约 §2),profile 开档排这批最前。
  'profile',
  'photoCheck',
  'note',
  'typeIn',
  // 决定类与挑战类七个。
  'coinFlip',
  'diceRoll',
  'reaction',
  'ballShake',
  'quietHold',
  'countdown',
  'stopwatch',
  // slowTask 在展示型之前、动手型之后。
  'blindTaste',
  'diyName',
  'silentOrder',
  'steps',
  'slowTask',
  'musicCorner',
  'dailySign',
  'timeWindow',
];

/// 真源在册、App 尚无 kind 的段 —— **登记不跟**用的机制位。
/// 清空(2026-09-19 · feat/a4-playkit-journey4):《预制人生》四段已落地,
/// priority 落在真源序的窗口位(`scan` 与 `coinFlip` 之间的开区间),
/// 没动任何既有数值位。真源再加新段而 App 未跟上时,钉回这里。
///
/// 本表变红有两种情形,都不是「删掉断言」了事:
/// ① 新段落地 → 把它移进逐位对账并补 priority 位;
/// ② 真源删段 → 同步上面的快照。
const List<String> _xcxKitPendingInApp = <String>[];

/// 真源序裁剪到 App 已实现的段 —— 逐位对账的左半边。
List<String> get _implementedInXcxOrder => _xcxKitPriority
    .where((String s) => !_xcxKitPendingInApp.contains(s))
    .toList(growable: false);

List<MapEntry<PlayKitKind, num>> get _appSortedByPriority =>
    kPlayKitSegmentPriority.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));

void main() {
  test('快照自洽:真源表 27 段 = App 已实现 27 段 + 登记不跟 0 段', () {
    expect(_xcxKitPriority.length, 27);
    expect(_implementedInXcxOrder.length, 27);
    final Set<String> both = _xcxKitPendingInApp.toSet().intersection(
      _implementedInXcxOrder.toSet(),
    );
    expect(both, isEmpty, reason: '一个段既逐位对账又登记不跟');
  });

  test('App 优先级表的钥匙恰为全部 27 个段名 kind(漏位/多位即红)', () {
    expect(
      kPlayKitSegmentPriority.keys.toSet(),
      _implementedInXcxOrder
          .map((String s) => kPlayKitSegmentKinds[s]!)
          .toSet(),
      reason:
          '漏登记 = 落默认值 99 永远排不进展示位;'
          '本地 kind(walk 等)不该进服务端段名优先级表',
    );
  });

  test('逐位对账:App 表按 priority 升序 ≡ 真源 KIT_PRIORITY 序', () {
    final List<PlayKitKind> implemented = _implementedInXcxOrder
        .map((String s) => kPlayKitSegmentKinds[s]!)
        .toList();
    final List<PlayKitKind> appOrder = _appSortedByPriority
        .map((e) => e.key)
        .toList();
    expect(
      appOrder,
      implemented,
      reason:
          '投影选卡顺序就是这张数值表排出来的:挪一位 = 换玩法。'
          '顺序判据来自真源 KIT_PRIORITY(源 ref 见文件头)',
    );
  });

  test('相邻位严格递增(不允许并列值把先后让给字典序)', () {
    final List<MapEntry<PlayKitKind, num>> sorted = _appSortedByPriority;
    for (int i = 1; i < sorted.length; i++) {
      expect(
        sorted[i - 1].value.compareTo(sorted[i].value),
        lessThan(0),
        reason:
            '${sorted[i - 1].key} 与 ${sorted[i].key} 撞了同一档, '
            'sort 稳定后谁先弹出就没人说得清了',
      );
    }
  });

  test('《预制人生》四段落位:严格挤在 scan 与 coinFlip 之间、内部同序', () {
    // 真源序:scan → profile → photoCheck → note → typeIn → coinFlip
    // (`playkit-view.js` 的 KIT_PRIORITY,profile 开档供故事变量所以最前)。
    // 落地时的约束:只借窗口、不动既有位 —— 四段的 priority 必须进
    // (`scan`, `coinFlip`) 开区间且保持相对序,否则就是重排了别的玩法。
    final num scan = kPlayKitSegmentPriority[PlayKitKind.scan]!;
    final num coinFlip = kPlayKitSegmentPriority[PlayKitKind.coinFlip]!;
    const List<PlayKitKind> landed = <PlayKitKind>[
      PlayKitKind.profile,
      PlayKitKind.photoCheck,
      PlayKitKind.note,
      PlayKitKind.typeIn,
    ];
    num? previous;
    for (final PlayKitKind kind in landed) {
      final num value = kPlayKitSegmentPriority[kind]!;
      expect(
        value > scan && value < coinFlip,
        isTrue,
        reason: '$kind 的 priority 位没落在真源窗口 (scan, coinFlip) 里',
      );
      if (previous != null) {
        expect(
          value.compareTo(previous),
          greaterThan(0),
          reason: '四段内部相对序与真源 KIT_PRIORITY 反了',
        );
      }
      previous = value;
    }
  });

  test('段名序表 kPlayKitSegmentOrder 与真源(裁剪后)逐项同序', () {
    expect(kPlayKitSegmentOrder, _implementedInXcxOrder);
  });
}
