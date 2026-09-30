import 'package:chengyin_app/feature/play/advanced/playkit_projection.dart';
import 'package:flutter_test/flutter_test.dart';

/// v5.1 半屏那批的**投影**门禁(2026-09-19 · a4-playkit-dedupe-a)。
///
/// 真源 = 小程序 `utils/playkit-view.js` 的 `segmentComplete`(:142-170)与
/// `build{SilentOrder,DiyName,TimeWindow}`(:284-300、:396-404)。
///
/// 两条都是「错了不报错」的那种:
/// - `complete` 写反 → `firstWhere((c) => !c.complete)` 选出来的不是真源那一段
///   (写死 true 的那屏会被挤出展示位,玩家根本见不到);
/// - `suggestions` 丢了 → 商家配的备选词在 App 上永远不出现。
void main() {
  test('silentOrder 不写死 complete:真源 segmentComplete 没有这个分支,落到 false', () {
    final PlayKitCard card = projectPlayKit(<String, Object?>{
      'silentOrder': <String, Object?>{'title': '沉默点单', 'rule': '用动作点单'},
    }).single;
    expect(card.kind, PlayKitKind.silentOrder);
    expect(
      card.complete,
      isFalse,
      reason:
          '真源 :142-170 只列了 branch/predict/random/qa/scan/…,silentOrder 落到末尾 return false',
    );
  });

  test('musicCorner 同上:写死 true 会把播放器挤出展示位', () {
    final PlayKitCard card = projectPlayKit(<String, Object?>{
      'musicCorner': <String, Object?>{'title': '治愈音乐角', 'trackName': '雨声'},
    }).single;
    expect(card.kind, PlayKitKind.musicCorner);
    expect(card.complete, isFalse);
    // 真源 buildMusicCorner(:299)写死的那句:不承诺奖励。
    // 逗号逐字节照抄 —— 真源是半角 `,`(整个 playkit-view.js 里零个全角逗号)。
    expect(card.hint, '坐下来,听完这一首');
  });

  test('连带效果:音乐角(5) 不再让位给排在它后面的收签(6)', () {
    // 两段都没做完时,真源按 KIT_PRIORITY 先弹 musicCorner
    // (旧代码把它写死 complete → 这里弹出来的会是 dailySign)。
    final PlayKitCard picked = projectPlayKit(<String, Object?>{
      'musicCorner': <String, Object?>{'title': '治愈音乐角'},
      'dailySign': <String, Object?>{
        'lines': <Object?>['今天雨停了'],
      },
    }).single;
    expect(picked.kind, PlayKitKind.musicCorner);
  });

  test('diyName 带 suggestions:空串清掉,顺序不变', () {
    final PlayKitCard card = projectPlayKit(<String, Object?>{
      'diyName': <String, Object?>{
        'title': '拍好了 给它起个名字',
        'name': '',
        'maxLength': 12,
        'suggestions': <Object?>['  熬夜特调 ', '', '   ', '便利店之光'],
      },
    }).single;

    expect(card.kind, PlayKitKind.diyName);
    expect(card.suggestions, <String>['熬夜特调', '便利店之光']);
    expect(card.maxLength, 12);
    expect(card.complete, isFalse);
  });

  test('diyName 没配 suggestions 时是空表,不是 null', () {
    final PlayKitCard card = projectPlayKit(<String, Object?>{
      'diyName': <String, Object?>{'title': '起个名字'},
    }).single;
    expect(card.suggestions, isEmpty);
    expect(card.maxLength, 16, reason: '真源缺省 16');
  });

  test('timeWindow 默认文案照抄真源,并把原始段挂到卡片上(组件要读 openFrom)', () {
    final PlayKitCard card = projectPlayKit(<String, Object?>{
      'timeWindow': <String, Object?>{'openFrom': '23:00', 'openTo': '01:00'},
    }).single;

    expect(card.kind, PlayKitKind.timeWindow);
    expect(card.title, '还没到开放时间', reason: '真源 seg.title || 这句');
    expect(card.eyebrow, '时段限定');
    expect(card.detail, '23:00 – 01:00');
    expect(card.kit['openFrom'], '23:00');
  });

  test('blindTaste 的奖励字样逐字照抄真源(答对 +N XP)', () {
    // 真源 `buildBlindTaste`(playkit-view.js:109):
    //   `seg.xp > 0 ? '答对 +' + xp + ' XP' : ''`
    // 单位是 XP:排行榜那套才叫 EXP,这一屏写的是「答对给多少」。
    final PlayKitCard card = projectPlayKit(<String, Object?>{
      'blindTaste': <String, Object?>{'title': '先尝再猜', 'xp': 10},
    }).single;
    expect(card.rewardLabel, '答对 +10 XP');
    final PlayKitCard noXp = projectPlayKit(<String, Object?>{
      'blindTaste': <String, Object?>{'title': '先尝再猜'},
    }).single;
    expect(noXp.rewardLabel, '', reason: '没配 xp 就不承诺奖励(与音乐角那句同一口径)');
  });

  test('musicCorner 没填 trackName 时用真源那句默认(店主的歌单)', () {
    final PlayKitCard card = projectPlayKit(<String, Object?>{
      'musicCorner': <String, Object?>{'title': '治愈音乐角'},
    }).single;
    // 真源 `buildMusicCorner`(:468)`seg.trackName || '店主的歌单'` ——
    // App 侧播放那颗钮也写着这四个字,两处必须是同一个词。
    expect(card.detail, '店主的歌单');
  });
}
