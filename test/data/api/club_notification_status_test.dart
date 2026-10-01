import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/data/api/club_ops_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues(<String, String>{}));

  test('投递状态只读取同一任务，不触发发送或重试', () async {
    final client = DioClient(TokenStore(const FlutterSecureStorage()));
    final sent = <RequestOptions>[];
    client.dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      sent.add(options);
      handler.resolve(Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: 200,
        data: <String, dynamic>{
          'code': 200,
          'data': <String, dynamic>{
            'id': 88, 'totalCount': 12, 'successCount': 10, 'failedCount': 2,
          },
        },
      ));
    }));
    final result = await ClubOpsApi(client).notificationStatus(campaignId: 88);
    expect(sent, hasLength(1));
    expect(sent.single.path, '/api/club/event-notification/status');
    expect(sent.single.method, 'POST');
    expect(sent.single.data, <String, dynamic>{'campaignId': 88});
    expect(result?.id, 88);
    expect(result?.successCount, 10);
    expect(result?.failedCount, 2);
  });
}
