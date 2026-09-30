// 漫游历史整页快照。
//
// ★★ `RoamSession` 的字段**几乎全是可空的**(zone/date/distance/explorePct/
//   shops/time 都可能没有)—— 这一页是"缺席怎么显示"的重灾区。
//   所以 fixture 里专门放一条**只有时间戳、别的全空**的记录:
//   它不该渲成一行空白,也不该把缺席的数字显示成 0
//   (「走了 0 公里」和「没记到里程」是两件事)。
//
// 另一条:空态要说清**记录在本机** —— 说成"你还没走过"是假的,
// 换设备/重装后本地记录就没了,而用户其实走过。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/data/models/roam_session.dart';
import 'package:chengyin_app/feature/roam/roam_history_page.dart';
import 'golden_theme.dart';

Widget _app(List<dynamic> overrides, Widget home) => ProviderScope(
      overrides: overrides.cast(),
      child: MaterialApp(
        theme: goldenTheme(),
        debugShowCheckedModeBanner: false,
        home: home,
      ),
    );

Future<void> _shot(WidgetTester t, Widget app, String path) async {
  setGoldenViewport(t, const Size(390, 1000));
  await t.pumpWidget(app);
  await t.pumpAndSettle();
  await expectLater(find.byType(MaterialApp), matchesGoldenFile(path));
}

void main() {
  testWidgets('★★ 漫游历史:完整一条 + 字段几乎全空的一条',
      (WidgetTester tester) async {
    await _shot(
      tester,
      _app(
        <dynamic>[
          roamHistoryProvider.overrideWith((ref) async => <RoamSession>[
                const RoamSession(
                  ts: 1755600000000,
                  zone: '静安区',
                  date: '2026-08-19',
                  dateLine: '8月19日 傍晚',
                  distance: 3.4,
                  explorePct: 62,
                  shops: 2,
                  time: '48:20',
                  durSec: 2900,
                ),
                // ★ 只有时间戳,别的全空 —— 不该渲成一行空白,
                //   也不该把没记到的里程显示成「0 公里」。
                const RoamSession(ts: 1755518400000),
              ]),
        ],
        const RoamHistoryPage(),
      ),
      'goldens/page_roam_history.png',
    );

    // ★★ golden 之外再钉一条:那条什么都没记到的记录**不许**出现
    //   「0.0 km」「00:00」「点亮 0 家」——「走了 0 公里」和「没记到里程」
    //   是两件事,前者会让用户以为自己那次白走了。
    expect(find.textContaining('0.0 km'), findsNothing);
    expect(find.textContaining('00:00'), findsNothing);
    expect(find.textContaining('点亮 0 家'), findsNothing);
    // 而有数据那条照常显示。
    // ⚠️ findsNWidgets(2) 不是 One:顶部汇总卡也显示「3.4 km」(总里程),
    //   卡片上那条是同一个数。第一版我写了 findsOneWidget,是没数清。
    expect(find.textContaining('3.4 km'), findsNWidgets(2));
  });

  testWidgets('★ 漫游历史空态:说清记录在本机', (WidgetTester tester) async {
    await _shot(
      tester,
      _app(
        <dynamic>[
          roamHistoryProvider.overrideWith((ref) async => <RoamSession>[]),
        ],
        const RoamHistoryPage(),
      ),
      'goldens/page_roam_history_empty.png',
    );
  });
}
