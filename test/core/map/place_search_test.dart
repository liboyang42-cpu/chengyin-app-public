import 'package:chengyin_app/core/map/map_scene.dart';
import 'package:chengyin_app/core/map/place_search.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const MethodChannel channel = MethodChannel('com.chengyin.app/place_search');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('解析原生返回;缺名字或坐标的条目丢弃', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      expect(call.method, 'search');
      expect(call.arguments['query'], '人民广场');
      expect(call.arguments['latitude'], 31.23);
      return <Map<String, Object?>>[
        <String, Object?>{
          'name': '人民广场',
          'address': '黄浦区',
          'latitude': 31.23,
          'longitude': 121.47,
        },
        <String, Object?>{
          'name': null,
          'address': 'x',
          'latitude': 1.0,
          'longitude': 1.0,
        },
        <String, Object?>{'name': '无坐标', 'address': 'y'},
      ];
    });
    final List<PlaceResult> r = await searchPlaces(
      ' 人民广场 ',
      near: const MapCoordinate(latitude: 31.23, longitude: 121.47),
    );
    expect(r.map((PlaceResult e) => e.name), <String>['人民广场']);
    expect(r.single.address, '黄浦区');
    expect(r.single.longitude, 121.47);
  });

  test('空关键词不调原生', () async {
    var called = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      called = true;
      return <Object?>[];
    });
    expect(await searchPlaces('  ', near: MapScene.defaultCenter), isEmpty);
    expect(called, isFalse);
  });

  test('原生报错向上抛,由页面显示失败态', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      throw PlatformException(code: 'search_failed');
    });
    expect(
      searchPlaces('咖啡', near: MapScene.defaultCenter),
      throwsA(isA<PlatformException>()),
    );
  });
}
