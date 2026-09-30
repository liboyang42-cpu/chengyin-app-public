// 「加载中」态页面级取景:纠偏成 list 档后,榜/列表两类加载态实拍。
// 数据源用**永不完成的 Future**(只测加载态,不造假数据)。
// 真源对照:pages/play/index.wxml:1807 `.board__loading`(type="list" count="3");
//           subpackageB/pages/im/list type="list" count="6"。

import 'dart:async';

import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/im_api.dart';
import 'package:chengyin_app/data/api/play_leaderboard_api.dart';
import 'package:chengyin_app/data/models/im.dart';
import 'package:chengyin_app/data/models/play_leaderboard.dart';
import 'package:chengyin_app/feature/im/im_controller.dart';
import 'package:chengyin_app/feature/im/im_list_page.dart';
import 'package:chengyin_app/feature/play/widgets/play_leaderboard_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'golden_theme.dart';

void main() {
  testWidgets('加载中实拍:同行者榜(list 档 3 行)', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final PlayLeaderboardGateway pending = _PendingGateway();
    await tester.pumpWidget(
      MaterialApp(
        theme: goldenTheme(),
        debugShowCheckedModeBanner: false,
        home: ProviderScope(
          overrides: [playLeaderboardApiProvider.overrideWithValue(pending)],
          child: const Scaffold(body: PlayLeaderboardSheet(activityId: 1)),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/loading_play_leaderboard.png'),
    );
  });

  testWidgets('加载中实拍:消息会话列表(list 档 6 行)', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <dynamic>[
          imConversationsProvider.overrideWith(
            (Ref ref) => Completer<List<Conversation>>().future,
          ),
          imApiProvider.overrideWithValue(_NoopImApi()),
        ].cast(),
        child: MaterialApp(
          theme: goldenTheme(),
          debugShowCheckedModeBanner: false,
          home: const ImListPage(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/loading_im_list.png'),
    );
  });
}

class _PendingGateway implements PlayLeaderboardGateway {
  @override
  Future<PlayLeaderboard> fetch({int? activityId, int? topicId}) =>
      Completer<PlayLeaderboard>().future;
}

class _NoopImApi implements ImApi {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('加载态实拍不发任何请求');
}
