import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/data/api/activity_api.dart';
import 'package:chengyin_app/data/models/activity.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (MethodCall call) async => null,
        );
  });

  test('地图活动搜索只传后端真正消费的字段:中心点/关键词/分类/排序(日期价格不上送)', () async {
    final DioClient client = DioClient(
      TokenStore(const FlutterSecureStorage()),
    );
    final _StubAdapter adapter = _StubAdapter();
    client.dio.httpClientAdapter = adapter;

    final List<Activity> rows = await ActivityApi(client).list(
      keyword: '咖啡',
      categoryId: '6',
      sortType: '2',
      longitude: '121.47',
      latitude: '31.23',
      pageSize: 50,
    );

    final Map<String, String> form = <String, String>{
      for (final MapEntry<String, String> field
          in (adapter.request.data as FormData).fields)
        field.key: field.value,
    };
    expect(form['keyword'], '咖啡');
    expect(form['category_id'], '6');
    expect((form['longitude'], form['latitude']), ('121.47', '31.23'));
    expect(form['sort_type'], '2');
    expect(form['pageSize'], '50');
    // ★ 后端 /api/activity/list 不消费日期/价格字段(见 ApiActivityController),
    //   把它们塞进 FormData 是老代码"筛选空转"的根因。客户端兜底过滤在搜索层做,
    //   这里断言请求体里**没有**这些键。
    for (final dead in const <String>[
      'min_price',
      'max_price',
      'date_type',
      'start_date',
      'end_date',
    ]) {
      expect(form.containsKey(dead), isFalse, reason: '不该上送后端不消费的 $dead');
    }
    expect(rows.single.hasCoordinates, isTrue);
    expect((rows.single.latitude, rows.single.longitude), (31.235, 121.475));
    expect(rows.single.topicId, 31);
  });
}

class _StubAdapter implements HttpClientAdapter {
  late RequestOptions request;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    request = options;
    return ResponseBody.fromString(
      jsonEncode(<String, dynamic>{
        'code': 200,
        'data': <String, dynamic>{
          'rows': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 21,
              'name': '有坐标活动',
              'latitude': '31.235',
              'longitude': '121.475',
              'topicId': '31',
            },
          ],
        },
      }),
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
