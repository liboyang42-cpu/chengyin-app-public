import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/dio_client.dart';
import '../../core/providers.dart';
import '../../data/api/account_api.dart';
import '../../data/api/activity_api.dart';
import '../../data/models/activity.dart';

/// 主题自玩通行证的购买边界。
///
/// 与活动报名共用 `/api/registration/create`，但真实归属是
/// `ownerType=1`，不能复用把 `ownerType=2` 写死的 [ActivityApi.createRegistration]。
abstract interface class TopicSelfPlayService {
  Future<List<TopicActivityEntry>> activities(int topicId);

  Future<RegistrationCreateResult> createPass({
    required int topicId,
    required String realName,
    required String phone,
    required String requestId,
  });

  Future<Map<String, String>> payApp(int registrationId);
}

class TopicActivityEntry {
  const TopicActivityEntry({required this.id, required this.name});

  final int id;
  final String name;
}

final topicSelfPlayServiceProvider = Provider<TopicSelfPlayService>((ref) {
  return ApiTopicSelfPlayService(
    ref.watch(dioClientProvider),
    ref.watch(accountApiProvider),
    ref.watch(activityApiProvider),
  );
});

class ApiTopicSelfPlayService implements TopicSelfPlayService {
  ApiTopicSelfPlayService(this._client, this._accountApi, this._activityApi);

  final DioClient _client;
  final AccountApi _accountApi;
  final ActivityApi _activityApi;

  @override
  Future<List<TopicActivityEntry>> activities(int topicId) async {
    final response = await _client.dio.post<Map<String, dynamic>>(
      '/api/topic/info-to-user',
      data: FormData.fromMap(<String, dynamic>{'id': topicId.toString()}),
    );
    final body = response.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw Exception((body['msg'] as String?) ?? '场次加载失败');
    }
    final data =
        (body['data'] as Map<String, dynamic>?) ?? const <String, dynamic>{};
    return (data['activityList'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map((row) {
          final rawId = row['id'];
          final id = rawId is num ? rawId.toInt() : int.tryParse('$rawId') ?? 0;
          return TopicActivityEntry(
            id: id,
            name: (row['name'] ?? '').toString(),
          );
        })
        .where((row) => row.id > 0)
        .toList();
  }

  @override
  Future<RegistrationCreateResult> createPass({
    required int topicId,
    required String realName,
    required String phone,
    required String requestId,
  }) async {
    // 同意记录必须先于建单落库，服务端 create/pay/pay-app 都查它。
    await _accountApi.agreeSignupDataSharing(requestId);
    final response = await _client.dio.post<Map<String, dynamic>>(
      '/api/registration/create',
      data: <String, dynamic>{
        'ownerType': 1,
        'ownerId': topicId,
        'realName': realName,
        'phone': phone,
        'isUsePoint': 0,
        'payChannel': 'APP',
        'requestId': requestId,
      },
      options: Options(contentType: Headers.jsonContentType),
    );
    final body = response.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw Exception((body['msg'] as String?) ?? '通行证建单失败');
    }
    final data = (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    final result = RegistrationCreateResult.fromJson(data);
    if (result.needsPayment) return result;

    final rawAmount = data['payableAmount'];
    final payableAmount = rawAmount is num
        ? rawAmount.toDouble()
        : double.tryParse('$rawAmount');
    if (payableAmount == 0) return result;

    // 幂等重放可能只返回旧单 ID，付费单不能被误判为免费。
    if (result.registrationId <= 0) {
      throw Exception('通行证支付状态异常');
    }
    final payParams = await _activityApi.payApp(result.registrationId);
    return RegistrationCreateResult(
      registrationId: result.registrationId,
      registrationNo: result.registrationNo,
      payParams: payParams,
    );
  }

  @override
  Future<Map<String, String>> payApp(int registrationId) =>
      _activityApi.payApp(registrationId);
}
