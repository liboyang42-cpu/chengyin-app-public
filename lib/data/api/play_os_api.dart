import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/dio_client.dart';
import '../../core/providers.dart' show dioClientProvider;
import '../models/play_operating_system.dart';

abstract interface class PlayOsGateway {
  Future<PlayOperatingSystem> load(int topicId);
  Future<PlayOsTag> revokeTag(int tagId);
}

final playOsApiProvider = Provider<PlayOsGateway>(
  (ref) => PlayOsApi(ref.watch(dioClientProvider)),
);

final class PlayOsApi implements PlayOsGateway {
  const PlayOsApi(this._client);
  final DioClient _client;

  @override
  Future<PlayOperatingSystem> load(int topicId) async {
    if (topicId <= 0) throw ArgumentError.value(topicId, 'topicId');
    final Map<String, dynamic> data = await _request(
      () => _client.dio.get<Map<String, dynamic>>('/api/play/os/$topicId'),
      fallback: '新生活总结暂时没有加载出来',
    );
    return PlayOperatingSystem.fromJson(data);
  }

  @override
  Future<PlayOsTag> revokeTag(int tagId) async {
    if (tagId <= 0) throw ArgumentError.value(tagId, 'tagId');
    final Map<String, dynamic> data = await _request(
      () =>
          _client.dio.post<Map<String, dynamic>>('/api/play/tag/$tagId/revoke'),
      fallback: '标签撤回失败，请重试',
      write: true,
    );
    final PlayOsTag tag = PlayOsTag.fromJson(data);
    if (tag.id != tagId || !tag.revoked) {
      throw const PlayOsApiException(
        '标签撤回回执不完整，请重新查看',
        writeOutcomeUnknown: true,
      );
    }
    return tag;
  }

  Future<Map<String, dynamic>> _request(
    Future<Response<Map<String, dynamic>>> Function() request, {
    required String fallback,
    bool write = false,
  }) async {
    try {
      final Response<Map<String, dynamic>> response = await request();
      final Map<String, dynamic> body =
          response.data ?? const <String, dynamic>{};
      final int? code = (body['code'] as num?)?.toInt();
      if (code != 200) {
        throw PlayOsApiException(
          (body['msg'] ?? fallback).toString(),
          writeOutcomeUnknown: write && code == null,
        );
      }
      final Object? data = body['data'];
      if (data is! Map) {
        throw PlayOsApiException(fallback, writeOutcomeUnknown: write);
      }
      return Map<String, dynamic>.from(data);
    } on PlayOsApiException {
      rethrow;
    } on DioException catch (error) {
      final Object? body = error.response?.data;
      throw PlayOsApiException(
        body is Map && body['msg'] != null ? body['msg'].toString() : fallback,
        writeOutcomeUnknown: write && error.response == null,
      );
    }
  }
}

final class PlayOsApiException implements Exception {
  const PlayOsApiException(this.message, {this.writeOutcomeUnknown = false});
  final String message;
  final bool writeOutcomeUnknown;

  @override
  String toString() => message;
}
