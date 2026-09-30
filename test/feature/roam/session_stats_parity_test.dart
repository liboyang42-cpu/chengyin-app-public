// 漫游回看页的统计行必须与小程序同口径。
//
// ★★ 小程序 `components/cy/scene-roam-session/index.wxml` 的四行:
//     总距离  {{distance != null && distance !== '' ? distance + ' 公里' : '—'}}
//     时长    {{time}}
//     探店    {{shops || 0}} 家
//     探索度  {{explorePct === 0 ? 0 : (explorePct || '--')}}%
//   注意后端**区分 0 和没拿到**:探索度真的是 0 就显示 0,没拿到显示 '--'。
//   App 之前写的是 `${explorePct ?? 0}%` / `distance?.toStringAsFixed(1) ?? '0.0'`
//   —— 把「没记录」说成「你走了 0 公里、探索度 0%」,和历史列表页那个
//   已修的 statsLine 是同一个病(见 roam_session.dart 的 statsLine)。
//
// ★ 时长在 App 侧**整个不显示**,而小程序页标题副行就是 `dateFull · time`。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/models/roam_session.dart';
import 'package:chengyin_app/feature/roam/roam_session_page.dart';
import 'package:chengyin_app/feature/roam/roam_session_store.dart';

class _FakeStore implements RoamSessionStore {
  _FakeStore(this._s);
  final RoamSession? _s;
  @override
  Future<RoamSession?> findByTs(int ts) async => _s;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Future<void> _pump(WidgetTester t, RoamSession s) async {
  await t.binding.setSurfaceSize(const Size(390, 1000));
  await t.pumpWidget(ProviderScope(
    overrides: <dynamic>[
      roamSessionStoreProvider.overrideWithValue(_FakeStore(s)),
    ].cast(),
    child: MaterialApp(home: RoamSessionPage(ts: s.ts)),
  ));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('★★ 没记录到距离/探索度时,不许说成 0', (WidgetTester t) async {
    await _pump(t, const RoamSession(ts: 1755518400000, zone: '静安寺街区'));

    expect(find.text('0.0'), findsNothing,
        reason: '距离没拿到却显示 0.0 —— 用户会以为自己一步没走');
    expect(find.text('0%'), findsNothing,
        reason: '探索度没拿到却显示 0% —— 小程序这里是 --');
    // 距离和用时都没记到 —— 两个 '—'。
    expect(find.text('—'), findsNWidgets(2), reason: '距离/用时未记录要显示 —');
    expect(find.text('--%'), findsOneWidget, reason: '探索度未记录要显示 --%');
  });

  testWidgets('★ 真的是 0 就显示 0(别把 0 也吞成 --)', (WidgetTester t) async {
    await _pump(
      t,
      const RoamSession(
        ts: 1755518400000,
        zone: '静安寺街区',
        distance: 0,
        explorePct: 0,
        shops: 0,
      ),
    );
    expect(find.text('0.0'), findsOneWidget);
    expect(find.text('0%'), findsOneWidget);
    expect(find.text('--%'), findsNothing);
  });

  testWidgets('★★ 时长要显示 —— 小程序页标题副行就带它', (WidgetTester t) async {
    await _pump(
      t,
      const RoamSession(
        ts: 1755518400000,
        zone: '静安寺街区',
        distance: 3.4,
        time: '48:20',
        durSec: 2900,
      ),
    );
    expect(find.text('48:20'), findsOneWidget, reason: '整页找不到用时');
    expect(find.text('用时'), findsOneWidget);
  });

  testWidgets('★★ 时长两个来源都没有时,不许兜成 00:00', (WidgetTester t) async {
    // timeText 内部 `formatRoamDuration(null)` 会返回 '00:00' ——
    // statsLine 早就判了这个(检查 time/durSec 两个来源),
    // 统计行第一版没判,等于在同一个文件里把同一个坑犯第二次。
    await _pump(t, const RoamSession(ts: 1755518400000, zone: '静安寺街区'));
    expect(find.text('00:00'), findsNothing,
        reason: '没记到时长却显示 00:00 —— 那是"走了 0 秒",不是"没记到"');
  });

  testWidgets('★★ 足迹卡上也不许印假的 0.0 —— 那张图会被存进相册发出去',
      (WidgetTester t) async {
    await _pump(t, const RoamSession(ts: 1755518400000, zone: '静安寺街区'));
    await t.tap(find.text('生成足迹卡'));
    await t.pumpAndSettle();
    expect(find.text('0.0'), findsNothing, reason: '足迹卡印了假里程');
    expect(find.text('0%'), findsNothing, reason: '足迹卡印了假探索度');
  });
}
