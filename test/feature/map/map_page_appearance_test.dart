import 'package:chengyin_app/core/map/map_scene.dart';
import 'package:chengyin_app/core/theme/app_theme.dart';
import 'package:chengyin_app/core/theme/cy_tokens.dart';
import 'package:chengyin_app/core/providers.dart';
import 'package:chengyin_app/data/api/ai_npc_api.dart';
import 'package:chengyin_app/data/models/city_resolve.dart';
import 'package:chengyin_app/data/models/nearby_node.dart';
import 'package:chengyin_app/data/models/npc.dart';
import 'package:chengyin_app/feature/map/map_controller.dart';
import 'package:chengyin_app/feature/map/map_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child, {List<dynamic> overrides = const <dynamic>[]}) {
  return ProviderScope(
    key: UniqueKey(),
    overrides: overrides.cast(),
    child: MaterialApp(theme: AppTheme.dark(), home: child),
  );
}

MapPageData _data(List<NearbyNode> nodes) => MapPageData(
  scene: const MapScene(
    points: <MapPoint>[],
    routePoints: <MapPoint>[],
    center: MapCoordinate(latitude: 31.2304, longitude: 121.4737),
  ),
  nodes: nodes,
  city: const CityResolveResult(city: '上海'),
);

void main() {
  testWidgets('隐私门:正文与主操作走 iOS 排版梯级(T1/T2),不再裸用小程序字号', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const MapPage(),
        overrides: <dynamic>[
          mapPrivacyAgreementProvider.overrideWith((ref) async => false),
        ],
      ),
    );
    await tester.pumpAndSettle();

    // 说明正文 17pt(CyType.body),主操作 17pt Semibold(CyType.headline)。
    expect(
      tester
          .widget<Text>(find.text('地图由 Apple 地图提供。启用后将使用定位信息展示附近节点。'))
          .style!
          .fontSize,
      CyType.body.fontSize,
    );
    expect(
      tester.widget<Text>(find.text('同意并启用地图')).style!.fontSize,
      CyType.headline.fontSize,
    );
  });

  testWidgets('地图页不再套 Material Scaffold', (WidgetTester tester) async {
    await tester.pumpWidget(
      _host(
        const MapPage(),
        overrides: <dynamic>[
          mapPrivacyAgreementProvider.overrideWith((ref) async => false),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(CupertinoPageScaffold), findsOneWidget);
    expect(find.byType(Scaffold), findsNothing);
  });

  testWidgets('附近节点列表走 Cupertino 分组行,不再用 Material ListTile', (
    WidgetTester tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await tester.pumpWidget(
      _host(
        const MapPage(),
        overrides: <dynamic>[
          mapPrivacyAgreementProvider.overrideWith((ref) async => true),
          aiNpcApiProvider.overrideWithValue(_EmptyAiNpcApi()),
          mapPageDataProvider.overrideWith(
            (ref) async => _data(<NearbyNode>[
              NearbyNode(
                id: 1,
                addressName: '外滩',
                longitude: '121.49',
                latitude: '31.24',
                address: '中山东一路',
                distance: 320,
              ),
            ]),
          ),
        ],
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('附近 1 个节点'), findsOneWidget);
    final Finder tile = find.byType(CupertinoListTile);
    expect(tile, findsOneWidget);
    expect(find.byType(ListTile), findsNothing);
    expect(
      tester.widget<Text>(find.text('外滩')).style!.fontSize,
      CyType.body.fontSize,
    );
    expect(find.byType(CupertinoListSection), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });
}

class _EmptyAiNpcApi implements AiNpcApi {
  @override
  Future<List<NpcProfile>> fetchProfiles({
    String scope = 'global',
    int? activityId,
  }) async => const <NpcProfile>[];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
