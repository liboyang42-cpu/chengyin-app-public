// 我发布的通知 → 点开看复盘(GET /api/official/broadcast/{id}/stats)。
//
// ★ 这页原来是个「死胡同」:列表里只有一行写死的触达数 —— 触达只是**送达**,
//   阅读/点击要问复盘端点。端点 App 早就写了,但全仓**零调用**,用户点不到;
//   死代码和没接的区别,只有「点不点得到」这一条。
//
// 这条测试钉住三件事:
//   ① 不点不拉(不应让打开列表的人为统计多付一次往返);
//   ② 点开拉的是**该条**的复盘,数字按后端字段摆出来;
//   ③ 失败留在浮层里能重试,不是静默空数据。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/official_api.dart';
import 'package:chengyin_app/feature/official/official_controller.dart';
import 'package:chengyin_app/feature/official/official_mine_page.dart';

class _FakeOfficialApi implements OfficialApi {
  _FakeOfficialApi({Map<String, dynamic>? stats, this.throwOnStats = false})
    : stats = stats ?? const <String, dynamic>{};

  final Map<String, dynamic> stats;
  final bool throwOnStats;
  final List<int> queried = <int>[];

  @override
  Future<Map<String, dynamic>> broadcastStats(int id) async {
    queried.add(id);
    if (throwOnStats) throw Exception('复盘没加载出来');
    return stats;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _app(OfficialApi api) => ProviderScope(
  overrides: [
    myPublishedProvider.overrideWith(
      (ref) async => MyPublished(
        broadcasts: <OfficialBroadcast>[
          const OfficialBroadcast(id: 7, title: '周末开报通知', reach: 128),
        ],
      ),
    ),
    officialApiProvider.overrideWithValue(api),
  ],
  child: const MaterialApp(home: OfficialMinePage()),
);

void main() {
  testWidgets('★ 不点不拉;点通知单元格 → 拉该条的复盘并展示', (
    WidgetTester tester,
  ) async {
    final api = _FakeOfficialApi(
      stats: <String, dynamic>{'reach': 128, 'read': 61, 'click': 12},
    );
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();

    expect(find.text('触达 128 人'), findsOneWidget);
    expect(api.queried, isEmpty, reason: '只是打开列表不该为统计多付一次往返');

    await tester.tap(find.text('周末开报通知'));
    await tester.pumpAndSettle();

    expect(api.queried, <int>[7], reason: '点的哪条就查哪条');
    expect(find.text('触达人数'), findsOneWidget);
    expect(find.text('阅读人数'), findsOneWidget);
    expect(find.text('点击人数'), findsOneWidget);
    expect(find.text('61'), findsOneWidget);
  });

  testWidgets('★ 复盘拉不到 → 错误留在浮层里,能给重试,不是静默空数据', (
    WidgetTester tester,
  ) async {
    final api = _FakeOfficialApi(throwOnStats: true);
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();

    await tester.tap(find.text('周末开报通知'));
    await tester.pumpAndSettle();

    expect(find.text('复盘没加载出来'), findsOneWidget);
    expect(find.text('这次播报还没有可看的数据'), findsNothing,
        reason: '失败装作没数据 = 统计坏了没人知道');

    await tester.tap(find.byKey(const Key('official-broadcast-stats-retry')));
    await tester.pumpAndSettle();
    expect(api.queried.length, 2, reason: '重试要真的再打一次');
  });
}
