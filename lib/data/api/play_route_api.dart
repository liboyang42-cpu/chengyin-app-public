import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/dio_client.dart';
import '../../core/providers.dart' show dioClientProvider;
import '../models/play_route_state.dart';

abstract interface class PlayRouteGateway {
  Future<PlayRouteState> fetch({int? activityId, int? topicId});
}

final playRouteApiProvider = Provider<PlayRouteGateway>(
  (ref) => PlayRouteApi(ref.watch(dioClientProvider)),
);

final class PlayRouteApi implements PlayRouteGateway {
  const PlayRouteApi(this._client);
  final DioClient _client;

  @override
  Future<PlayRouteState> fetch({int? activityId, int? topicId}) async {
    final bool hasActivity = (activityId ?? 0) > 0;
    final bool hasTopic = (topicId ?? 0) > 0;
    if (hasActivity == hasTopic) {
      throw ArgumentError('活动与主题会话必须且只能提供一个');
    }
    try {
      final Response<Map<String, dynamic>> response = await _client.dio
          .get<Map<String, dynamic>>(
            '/api/play/route-state',
            queryParameters: <String, dynamic>{
              if (hasActivity) 'activityId': activityId,
              if (hasTopic) 'topicId': topicId,
            },
          );
      final Map<String, dynamic> body =
          response.data ?? const <String, dynamic>{};
      if ((body['code'] as num?)?.toInt() != 200) {
        throw PlayRouteApiException((body['msg'] ?? '路线状态暂未同步，请重试').toString());
      }
      final Object? rawData = body['data'];
      if (rawData is! Map) {
        throw const PlayRouteApiException('路线状态不完整，请重试');
      }
      final Map<String, dynamic> data = Map<String, dynamic>.from(rawData);
      final Object? nested = data['routeState'];
      return PlayRouteState.fromJson(
        nested is Map ? Map<String, dynamic>.from(nested) : data,
      );
    } on PlayRouteApiException {
      rethrow;
    } on FormatException {
      throw const PlayRouteApiException('路线状态不完整，请重试');
    } on DioException catch (error) {
      final Object? data = error.response?.data;
      final String message = data is Map && data['msg'] != null
          ? data['msg'].toString()
          : '路线状态暂未同步，请重试';
      throw PlayRouteApiException(message);
    }
  }
}

final class PlayRouteApiException implements Exception {
  const PlayRouteApiException(this.message);
  final String message;

  @override
  String toString() => message;
}
