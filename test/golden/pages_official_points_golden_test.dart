// 官方活动域 + 积分页快照。
//
// 这几页此前零 golden 覆盖。挑它们是因为各自都有一个**容易被渲成同一屏**的分歧:
//   · 我发布的:「没权限发布」和「有权限但还没发过」是两回事,
//     渲成同一个空态,用户会一直等一个永远不会出现的入口
//   · 积分:收入和支出必须一眼分得开,`+`/`-` 不能只靠一个字符
//   · 收件箱:没有邀约 vs 加载失败
//
// 更新基准图:flutter test --update-goldens test/golden/pages_official_points_golden_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/data/api/official_api.dart';
import 'package:chengyin_app/data/models/points_record.dart';
import 'package:chengyin_app/feature/official/official_controller.dart';
import 'package:chengyin_app/feature/official/official_mine_page.dart';
import 'package:chengyin_app/feature/official/official_publish_page.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/points_api.dart';
import 'package:chengyin_app/feature/points/points_page.dart';
import 'package:chengyin_app/feature/points/points_hero.dart';
import 'package:chengyin_app/data/models/points_statistics.dart';
import 'golden_theme.dart';

Widget _app(List<dynamic> overrides, Widget home) {
  return ProviderScope(
    overrides: overrides.cast(),
    child: MaterialApp(
      theme: goldenTheme(),
      debugShowCheckedModeBanner: false,
      home: home,
    ),
  );
}

/// 积分页快照的宿主。
///
/// 真机根是 `CupertinoApp.router`(main.dart),它给整棵树一个带系统字族的
/// `DefaultTextStyle`;而快照宿主是 MaterialApp,裸 `TextStyle`(family=null,
/// `CyType.*` 全档如此)会落到 flutter_test 的 `monospace` 默认族上 ——
/// Menlo 没有中文字形,拍出来是**满屏豆腐**,且和「页面真坏了」长得一模一样。
/// 页内透明 Material 壳拆除后(a5-ios27-points-2)载体没了,就在这里补回
/// 真机上的那层继承(口径同 golden_theme.dart:字族补丁是测试环境缺陷,修测试侧)。
Widget _pointsApp(List<dynamic> overrides, Widget home) {
  return _app(
    overrides,
    DefaultTextStyle(
      style: const TextStyle(fontFamily: 'Roboto'),
      child: home,
    ),
  );
}

Future<void> _shot(WidgetTester tester, Widget app, String goldenPath) async {
  setGoldenViewport(tester, const Size(390, 860));
  await tester.pumpWidget(app);
  // ⚠️ 不能用 pumpAndSettle:骨架的微光是**无限循环**动画,永远等不到静止
  //    (skeleton_golden_test.dart:32 已记着这条)。固定推进几帧即可。
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await expectLater(find.byType(MaterialApp), matchesGoldenFile(goldenPath));
}

/// ⚠️ 替身放在 **API 边界**,不是替换 PointsNotifier ——
///   直接覆盖 notifier 会跳过它的 build(),`_hasMore` 停在初始的 true,
///   基准图底下就永远挂着一个转圈:**那是用户看不到的画面**,
///   而基准图一旦拍成那样就成了假证据。
///   让真 notifier 跑一遍,它自己会算出「3 条 < 一页 20 条 ⇒ 没有更多」。
class _FakePointsApi implements PointsApi {
  _FakePointsApi(this._rows);
  final List<PointsRecord> _rows;

  @override
  Future<List<PointsRecord>> list({
    int? changeType,
    int pageNum = 1,
    int pageSize = 20,
  }) async => pageNum == 1 ? _rows : <PointsRecord>[];

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  testWidgets('★ 我发布的:没有发布权限(不是空,也不是错)', (WidgetTester tester) async {
    // 「没权限」和「有权限但还没发过」渲成同一个空态的话,
    // 用户会一直等一个永远不会出现的发布入口。
    await _shot(
      tester,
      _app([
        // ★ 「发一个」入口受白名单闸管,会真发一次请求 ——
        //   不给替身这张基准图就打真网络(实测抛 MissingPluginException)。
        //   ⚠️ 我刚在合并 T4 时批评过同一个错,自己转头就犯了。
        officialCanPublishProvider.overrideWith((ref) async => false),
        myPublishedProvider.overrideWith(
          (ref) async => throw OfficialApiException('无官方发布权限'),
        ),
      ], const OfficialMinePage()),
      'goldens/page_official_mine_no_perm.png',
    );
  });

  testWidgets('我发布的:有权限但一条都还没发', (WidgetTester tester) async {
    await _shot(
      tester,
      _app([
        // 有权限那张:入口要出现在图里,才算验证过它。
        officialCanPublishProvider.overrideWith((ref) async => true),
        myPublishedProvider.overrideWith((ref) async => const MyPublished()),
      ], const OfficialMinePage()),
      'goldens/page_official_mine_empty.png',
    );
  });

  testWidgets('★ 积分:收入与支出必须一眼分得开', (WidgetTester tester) async {
    await _shot(
      tester,
      _pointsApp([
        // hero 会真发 /api/user/points/statistics —— 不 override 会在
        // 测试环境撞 secure_storage 的 MissingPluginException。
        // 这里给它一份**有值**的统计,顺便把 hero 也拍进基准图。
        pointsStatProvider.overrideWith(
          (ref) async => PointsStatistics.fromJson(<String, dynamic>{
            'weekPoints': '320',
            'rankPercentage': '82%',
          }),
        ),
        pointsApiProvider.overrideWithValue(
          _FakePointsApi(<PointsRecord>[
            PointsRecord.fromJson(<String, dynamic>{
              'id': 1,
              'changeType': 1,
              'changePoints': 120,
              'afterPoints': 1380,
              'changeReason': '完成「静安夜跑」',
              'createTime': '2026-08-18 21:10:00',
            }),
            PointsRecord.fromJson(<String, dynamic>{
              'id': 2,
              'changeType': 2,
              'changePoints': 200,
              'afterPoints': 1260,
              'changeReason': '兑换帆布包',
              'createTime': '2026-08-17 12:00:00',
            }),
            // ★ 两个边界一条搞定:没写原因(不该渲成一行空白)+
            //   **没下发 changeType**(缺席时不许默认判成支出,
            //   否则这笔 +5 会渲成 -5,用户以为被扣了分)
            PointsRecord.fromJson(<String, dynamic>{
              'id': 3,
              'changePoints': 5,
              'afterPoints': 1460,
              'createTime': '2026-08-16 08:30:00',
            }),
          ]),
        ),
      ], const PointsPage()),
      'goldens/page_points.png',
    );
  });
}
