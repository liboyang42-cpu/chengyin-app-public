import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chengyin_app/core/network/dio_client.dart';
import 'package:chengyin_app/core/network/token_store.dart';
import 'package:chengyin_app/data/api/account_api.dart';
import 'package:chengyin_app/data/api/activity_api.dart';
import 'package:chengyin_app/feature/topic/topic_self_play_service.dart';

class _FakeAccountApi extends AccountApi {
  _FakeAccountApi(super.client);

  String? consentRequestId;

  @override
  Future<void> agreeSignupDataSharing(String requestId) async {
    consentRequestId = requestId;
  }
}

class _Recorder extends Interceptor {
  _Recorder({this.payableAmount = 0});

  final num payableAmount;
  final List<RequestOptions> calls = <RequestOptions>[];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    calls.add(options);
    final data = options.path == '/api/registration/pay/app'
        ? <String, dynamic>{
            'payParams': <String, dynamic>{'prepayId': 'wx-prepay-1'},
          }
        : <String, dynamic>{
            'registrationId': 91,
            'payableAmount': payableAmount,
          };
    handler.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: 200,
        data: <String, dynamic>{'code': 200, 'data': data},
      ),
    );
  }
}

void main() {
  test('先记录报名信息同意，再以 ownerType=1 + APP 建通行证单', () async {
    final client = DioClient(TokenStore(const FlutterSecureStorage()));
    client.dio.interceptors.clear();
    final recorder = _Recorder();
    client.dio.interceptors.add(recorder);
    final account = _FakeAccountApi(client);
    final service = ApiTopicSelfPlayService(
      client,
      account,
      ActivityApi(client),
    );

    final result = await service.createPass(
      topicId: 23,
      realName: '陈晨',
      phone: '13800000000',
      requestId: 'same-intent-1',
    );

    expect(account.consentRequestId, 'same-intent-1');
    expect(result.registrationId, 91);
    expect(recorder.calls, hasLength(1));
    expect(recorder.calls.single.path, '/api/registration/create');
    final body = (recorder.calls.single.data as Map).cast<String, dynamic>();
    expect(body, containsPair('ownerType', 1));
    expect(body, containsPair('ownerId', 23));
    expect(body, containsPair('payChannel', 'APP'));
    expect(body, containsPair('requestId', 'same-intent-1'));
    expect(
      body.containsKey('ticketId'),
      isFalse,
      reason: '自玩通行证不是主题旧票种，后端 createSelfPlayPass 不落 ticketId',
    );
  });

  test('重放命中待支付单 → 以原 registrationId 取 App 支付参数', () async {
    final client = DioClient(TokenStore(const FlutterSecureStorage()));
    client.dio.interceptors.clear();
    final recorder = _Recorder(payableAmount: 49);
    client.dio.interceptors.add(recorder);
    final service = ApiTopicSelfPlayService(
      client,
      _FakeAccountApi(client),
      ActivityApi(client),
    );

    final result = await service.createPass(
      topicId: 23,
      realName: '陈晨',
      phone: '13800000000',
      requestId: 'same-intent-replay',
    );

    expect(recorder.calls.map((RequestOptions call) => call.path), <String>[
      '/api/registration/create',
      '/api/registration/pay/app',
    ]);
    expect(result.registrationId, 91);
    expect(result.payParams, containsPair('prepayId', 'wx-prepay-1'));
  });
}
