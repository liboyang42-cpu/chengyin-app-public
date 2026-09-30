import 'package:chengyin_app/core/map/device_location.dart';
import 'package:chengyin_app/core/map/directions.dart';
import 'package:chengyin_app/core/map/map_scene.dart';
import 'package:chengyin_app/core/map/route_guidance.dart';
import 'package:chengyin_app/core/theme/app_theme.dart';
import 'package:chengyin_app/core/widgets/cy_native_button.dart';
import 'package:chengyin_app/feature/map/route_preview_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

const MapCoordinate _dest = MapCoordinate(latitude: 31.24, longitude: 121.49);

Widget _host(Widget child) => MaterialApp(
  theme: AppTheme.dark(),
  home: Scaffold(body: child),
);

DeviceLocation _location(LocationPermission permission) => DeviceLocation(
  serviceEnabled: () async => true,
  checkPermission: () async => permission,
  requestPermission: () async => permission,
  currentWgs84: () async =>
      const MapCoordinate(latitude: 31.23, longitude: 121.47),
);

void main() {
  testWidgets('权限被拒:展示需要位置权限与重试,不出路线', (WidgetTester tester) async {
    await tester.pumpWidget(
      _host(
        RoutePreviewSheet(
          destination: _dest,
          name: '外滩',
          directions: DirectionsClient(),
          location: _location(LocationPermission.denied),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('需要位置权限'), findsOneWidget);
    expect(find.widgetWithText(CyNativeButton, '重试'), findsOneWidget);
    expect(find.text('开始导航'), findsNothing);
  });

  testWidgets('无原生路线:直线回退提示可见,仍可开始导航/在地图中打开', (WidgetTester tester) async {
    await tester.pumpWidget(
      _host(
        RoutePreviewSheet(
          destination: _dest,
          name: '外滩',
          directions: DirectionsClient(),
          location: _location(LocationPermission.whileInUse),
        ),
      ),
    );
    // 通道调用走真实异步(MissingPluginException),FakeAsync 里等不到。
    for (int i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }

    expect(find.text(DirectionsClient.fallbackNotice), findsOneWidget);
    expect(find.text('直线距离'), findsOneWidget);
    expect(find.text('开始导航'), findsOneWidget);
    expect(find.text('在地图中打开'), findsOneWidget);
  });

  testWidgets('指令条:距离前缀、剩余、重算中文案', (WidgetTester tester) async {
    const MapCoordinate a = MapCoordinate(latitude: 31.230, longitude: 121.470);
    const MapCoordinate b = MapCoordinate(latitude: 31.230, longitude: 121.472);
    final RouteGuidance g = RouteGuidance(
      const DirectionsRoute(
        polyline: <MapCoordinate>[a, b, _dest],
        distanceMeters: 2000,
        eta: Duration(minutes: 25),
        steps: <RouteStep>[
          RouteStep(
            instruction: '左转进入中山东一路',
            distanceMeters: 1800,
            coordinate: b,
          ),
        ],
      ),
      offRouteConfirmations: 1,
    );
    await tester.pumpWidget(
      _host(RouteGuidanceBanner(state: g.update(a), onEnd: () {})),
    );
    expect(find.text('左转进入中山东一路'), findsOneWidget);
    expect(find.text('190 m 后'), findsOneWidget);
    expect(find.textContaining('剩余'), findsOneWidget);

    await tester.pumpWidget(
      _host(RouteGuidanceBanner(state: null, onEnd: () {})),
    );
    expect(find.text('正在获取你的位置…'), findsOneWidget);
  });

  // ★ 原先 `_load()` 只接了 LocationUnavailable:定位/规划抛别的异常时,
  //   这一屏会永远停在「正在规划路线…」—— 没有错误、没有重试,只能退出去重进。
  testWidgets('★★ 规划中的其它异常:给出错误与重试,不再永远停在「正在规划路线…」', (
    WidgetTester tester,
  ) async {
    int calls = 0;
    final DeviceLocation location = DeviceLocation(
      serviceEnabled: () async => true,
      checkPermission: () async => LocationPermission.whileInUse,
      requestPermission: () async => LocationPermission.whileInUse,
      currentWgs84: () async {
        calls += 1;
        if (calls == 1) throw Exception('定位服务开了点小差');
        return const MapCoordinate(latitude: 31.23, longitude: 121.47);
      },
    );
    await tester.pumpWidget(
      _host(
        RoutePreviewSheet(
          destination: _dest,
          name: '外滩',
          directions: DirectionsClient(),
          location: location,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('正在规划路线…'), findsNothing);
    expect(find.text('路线没能规划出来'), findsOneWidget);
    expect(find.widgetWithText(CyNativeButton, '重试'), findsOneWidget);

    // 重试:这一次定位成功,路线走直线回退(测试环境无原生通道)。
    await tester.tap(find.text('重试'));
    for (int i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(find.text('路线没能规划出来'), findsNothing);
    expect(find.text(DirectionsClient.fallbackNotice), findsOneWidget);
  });

  // ★ P2-1(b1-sim-small-domains):注入 MapCoordinate(NaN, NaN) 半屏 build 期
  //   直接「Infinity or NaN toInt」红屏。真实入口 hasCoordinates 已挡,这里补第二道。
  testWidgets('目的地坐标 NaN:不红屏,落「坐标无效」人话错误态', (
    WidgetTester tester,
  ) async {
    const MapCoordinate nan = MapCoordinate(
      latitude: double.nan,
      longitude: double.nan,
    );
    await tester.pumpWidget(
      _host(
        RoutePreviewSheet(
          destination: nan,
          name: '外滩',
          directions: DirectionsClient(),
          location: _location(LocationPermission.whileInUse),
        ),
      ),
    );
    for (int i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }

    expect(tester.takeException(), isNull);
    expect(find.text('正在规划路线…'), findsNothing);
    expect(find.textContaining('目的地坐标无效'), findsOneWidget);
    expect(find.text('开始导航'), findsNothing);
  });

  testWidgets('目的地坐标 Infinity:同样不落 build 崩溃', (
    WidgetTester tester,
  ) async {
    const MapCoordinate inf = MapCoordinate(
      latitude: double.infinity,
      longitude: 121.49,
    );
    await tester.pumpWidget(
      _host(
        RoutePreviewSheet(
          destination: inf,
          name: '外滩',
          directions: DirectionsClient(),
          location: _location(LocationPermission.whileInUse),
        ),
      ),
    );
    for (int i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }

    expect(tester.takeException(), isNull);
    expect(find.textContaining('目的地坐标无效'), findsOneWidget);
  });
}
