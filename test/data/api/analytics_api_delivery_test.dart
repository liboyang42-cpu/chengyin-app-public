import 'dart:convert';
import 'dart:typed_data';

import 'package:chengyin_app/core/analytics/tracker.dart';
import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/data/api/analytics_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class _BusinessFailureAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    jsonEncode(<String, dynamic>{'code': 500, 'msg': 'temporary failure'}),
    200,
    headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>['application/json'],
    },
  );

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => FlutterSecureStorage.setMockInitialValues(<String, String>{}));

  test('AjaxResult 业务失败会让 Tracker 恢复整批，而不是静默丢失', () async {
    final DioClient client = DioClient(
      TokenStore(const FlutterSecureStorage()),
    );
    client.dio.httpClientAdapter = _BusinessFailureAdapter();
    final Tracker tracker = Tracker(
      AnalyticsApi(client),
      flushAfter: const Duration(hours: 1),
    );
    tracker.track('community_post_open', bizType: 'community_post', bizId: 42);

    await tracker.flush();

    expect(tracker.pending, 1);
    tracker.dispose();
  });
}
