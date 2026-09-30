// 浅色页的**错误态**快照。
//
// 为什么专拍错误态:错误/空态由共享件 `StatusView` 渲,一处不跟主题走,
// 所有浅色页会同时出问题 —— 反过来说,这一组图能一次性把整个浅色域的
// 共享层验干净,比逐页造 fixture 便宜得多。
//
// 而且错误态是**最容易漏看的一屏**:开发时后端总是通的,自测点一圈根本不会
// 进到这里;等线上真断网了,用户看到的是一片白底白字。
//
// 更新基准图:flutter test --update-goldens test/golden/pages_light_error_states_golden_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/data/models/nearby_merchant.dart';
import 'package:chengyin_app/feature/coop/coop_candidates_page.dart';
import 'package:chengyin_app/feature/coop/coop_pool_page.dart';
import 'package:chengyin_app/feature/coop/nearby_merchants_page.dart';
import 'package:chengyin_app/feature/merchant/merchant_relation_page.dart';
import 'golden_theme.dart';

Widget _app(List<dynamic> overrides, Widget home) {
  return ProviderScope(
    overrides: overrides.cast(),
    child: MaterialApp(
      theme: merchantGoldenTheme(),
      debugShowCheckedModeBanner: false,
      home: home,
    ),
  );
}

Future<void> _shot(WidgetTester tester, Widget app, String goldenPath) async {
  setGoldenViewport(tester, const Size(390, 760));
  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
  await expectLater(find.byType(MaterialApp), matchesGoldenFile(goldenPath));
}

void main() {
  testWidgets('合作池:加载失败', (WidgetTester tester) async {
    await _shot(
      tester,
      _app(
        [
          coopPoolProvider
              .overrideWith((ref) async => throw Exception('网络连接失败')),
        ],
        const CoopPoolPage(),
      ),
      'goldens/light_error_coop_pool.png',
    );
  });

  testWidgets('附近商家:加载失败', (WidgetTester tester) async {
    await _shot(
      tester,
      _app(
        [
          nearbyMerchantsProvider
              .overrideWith((ref) async => throw Exception('网络连接失败')),
        ],
        const NearbyMerchantsPage(),
      ),
      'goldens/light_error_nearby.png',
    );
  });

  testWidgets('承接候选:加载失败', (WidgetTester tester) async {
    await _shot(
      tester,
      _app(
        [
          coopCandidatesProvider(7)
              .overrideWith((ref) async => throw Exception('网络连接失败')),
        ],
        const CoopCandidatesPage(topicId: 7),
      ),
      'goldens/light_error_candidates.png',
    );
  });

  testWidgets('商家关系:加载失败', (WidgetTester tester) async {
    await _shot(
      tester,
      _app(
        [
          merchantRelationProvider
              .overrideWith((ref) async => throw Exception('网络连接失败')),
        ],
        const MerchantRelationPage(),
      ),
      'goldens/light_error_relation.png',
    );
  });

  testWidgets('★ 空态也要看:空态和错误态用的是同一个共享件,配色可能只对了一半',
      (WidgetTester tester) async {
    await _shot(
      tester,
      _app(
        [
          nearbyMerchantsProvider.overrideWith((ref) async => <NearbyMerchant>[]),
        ],
        const NearbyMerchantsPage(),
      ),
      'goldens/light_empty_nearby.png',
    );
  });
}
