import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/dio_client.dart';
import '../../core/providers.dart';
import 'participation_models.dart';

abstract interface class ParticipationRepository {
  Future<List<ParticipationRecord>> list();

  Future<ParticipationDetail> detail(int id);
}

class ParticipationApi implements ParticipationRepository {
  ParticipationApi(this._client, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final DioClient _client;
  final DateTime Function() _now;

  @override
  Future<List<ParticipationRecord>> list() async {
    final Response<Map<String, dynamic>> response = await _client.dio
        .post<Map<String, dynamic>>('/api/registration/my-joined');
    final Map<String, dynamic> body = response.data ?? <String, dynamic>{};
    _requireSuccess(body, '参与记录加载失败，请重试');
    final Object? data = body['data'];
    if (data is! List) throw const ParticipationApiException('参与记录数据异常');
    return data
        .whereType<Map<String, dynamic>>()
        .map(
          (Map<String, dynamic> row) =>
              ParticipationRecord.fromJson(row, now: _now()),
        )
        .toList(growable: false);
  }

  @override
  Future<ParticipationDetail> detail(int id) async {
    // 真源玩家侧详情 = POST /api/registration/info(表单参数 id)。
    // ★ 不是 merchant/info:那是商家视图,字段是已废弃的旧读模型,
    //   玩家 token 打过去拿到的也是另一套口径。
    final Response<Map<String, dynamic>> response = await _client.dio
        .post<Map<String, dynamic>>(
          '/api/registration/info',
          data: FormData.fromMap(<String, dynamic>{'id': id.toString()}),
        );
    final Map<String, dynamic> body = response.data ?? <String, dynamic>{};
    _requireSuccess(body, '获取详情失败');
    final Object? data = body['data'];
    if (data is! Map<String, dynamic>) {
      throw const ParticipationApiException('参与详情数据异常');
    }
    return ParticipationDetail.fromJson(id, data, now: _now());
  }

  static void _requireSuccess(Map<String, dynamic> body, String fallback) {
    final Object? rawCode = body['code'];
    final int? code = rawCode is num
        ? rawCode.toInt()
        : int.tryParse(rawCode?.toString() ?? '');
    if (code != 200) {
      final String message = body['msg']?.toString().trim() ?? '';
      throw ParticipationApiException(
        message.isEmpty ? fallback : message,
        code: code,
      );
    }
  }
}

class ParticipationApiException implements Exception {
  const ParticipationApiException(this.message, {this.code});

  final String message;

  /// 后端 body 里的 code(HTTP 200 + code 401 也要能被认出来)。
  final int? code;

  @override
  String toString() => message;
}

/// 「这次失败 = 后端要登录」的判据:HTTP 401,或 HTTP 200 + body code 401。
bool participationUnauthorizedError(Object error) =>
    isUnauthorizedError(error) ||
    (error is ParticipationApiException && error.code == 401);

final participationRepositoryProvider = Provider<ParticipationRepository>((
  ref,
) {
  return ParticipationApi(ref.watch(dioClientProvider));
});

final participationRecordsProvider =
    FutureProvider.autoDispose<List<ParticipationRecord>>((ref) {
      return ref.watch(participationRepositoryProvider).list();
    });
