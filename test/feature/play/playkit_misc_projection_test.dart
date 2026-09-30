import 'package:chengyin_app/feature/play/advanced/playkit_projection.dart';
import 'package:flutter_test/flutter_test.dart';

/// 本批 ②③ 两处修正的门禁(feat/playkit-misc,2026-09-17)。
///
/// 真源 = 小程序 `utils/playkit-view.js`:
/// - `segmentComplete`(167-168):挑战类看服务端的 `submitted`;
/// - `KIT_PRIORITY`(17-30):节点里各玩法段的呈现次序,**顺序就是判据**。
///
/// 两条都是「少一条不会报错」的那种错:
/// - 漏 `complete` → 服务端说「做过了」的玩法会被 `firstWhere((c) => !c.complete)`
///   再弹一次,玩家做完那一下什么也没发生;
/// - 排错序 → 同一节点两段都在时,先弹的不是真源里更靠前的那一段。
void main() {
  group('② 完成口径 = 服务端 submitted', () {
    test('countdown:没提交不算完,submitted 才算完(真源 :167-168)', () {
      expect(
        projectPlayKit(<String, Object?>{
          'countdown': <String, Object?>{'seconds': 30},
        }).single.complete,
        isFalse,
        reason: '默认(服务端没报 submitted)= 没做完,还得让玩家看到',
      );
      expect(
        projectPlayKit(<String, Object?>{
          'countdown': <String, Object?>{'seconds': 30, 'submitted': true},
        }).single.complete,
        isTrue,
        reason: '服务端判过就算完 —— 否则会被再弹一次,而这一屏没有第二个动作',
      );
    });

    test('stopwatch:同上', () {
      expect(
        projectPlayKit(<String, Object?>{
          'stopwatch': <String, Object?>{'targetSeconds': 10},
        }).single.complete,
        isFalse,
      );
      expect(
        projectPlayKit(<String, Object?>{
          'stopwatch': <String, Object?>{
            'targetSeconds': 10,
            'submitted': true,
          },
        }).single.complete,
        isTrue,
      );
      // `tries` 走 `kit`:真源把它绑给共享台面画「还能错」的圆点
      // (`playkit/index.wxml:94`),App 侧台面还没落地,由停表组件自己读它。
      expect(
        projectPlayKit(<String, Object?>{
          'stopwatch': <String, Object?>{'targetSeconds': 10, 'tries': 2},
        }).single.kit['tries'],
        2,
        reason: '不搬过去的后果:次数用尽后 App 还会再发一条提交,服务端回「这一局已经交过了」',
      );
    });
  });

  group('③ 呈现次序 = KIT_PRIORITY', () {
    /// 真源序:… hiddenObject → scan → coinFlip … quietHold → countdown →
    /// stopwatch → blindTaste → … 旧表把 countdown/stopwatch 排在末尾(8/9)。
    test('countdown 排在 blindTaste 之前', () {
      final PlayKitCard picked = projectPlayKit(<String, Object?>{
        'blindTaste': <String, Object?>{'title': '先尝再猜'},
        'countdown': <String, Object?>{'seconds': 30},
      }).single;
      expect(picked.kind, PlayKitKind.countdown);
    });

    test('stopwatch 也排在 blindTaste 之前', () {
      final PlayKitCard picked = projectPlayKit(<String, Object?>{
        'blindTaste': <String, Object?>{'title': '先尝再猜'},
        'stopwatch': <String, Object?>{'targetSeconds': 10},
      }).single;
      expect(picked.kind, PlayKitKind.stopwatch);
    });

    test('负控:靠前的计时段已经做完,就让位给后面没做完的那段', () {
      final PlayKitCard picked = projectPlayKit(<String, Object?>{
        'countdown': <String, Object?>{'seconds': 30, 'submitted': true},
        'blindTaste': <String, Object?>{'title': '先尝再猜'},
      }).single;
      expect(
        picked.kind,
        PlayKitKind.blindTaste,
        reason:
            '排序归排序;选中的永远是第一段**没做完**的 —— '
            '把 complete 一起改了才有这个行为,两条修正是一起的',
      );
    });
  });
}
