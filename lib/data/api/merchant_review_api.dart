import '../../core/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';

import '../../core/network/dio_client.dart';
import '../models/merchant_review.dart';

abstract interface class MerchantReviewGateway {
  Future<MerchantReviewPage> managePage({
    required int pageNum,
    required int pageSize,
  });

  Future<MerchantReviewReceipt> reply({
    required MerchantReviewReplyDraft draft,
    required String requestId,
  });

  /// 修改已有公开回复:`POST /api/merchant/reviews/reply/update`。
  Future<void> updateReply({
    required MerchantReviewReplyDraft draft,
    required String requestId,
  });

  /// 删除公开回复(删后评价回到待回复):`POST /api/merchant/reviews/reply/delete`。
  Future<void> deleteReply({
    required int reviewId,
    required int expectedVersion,
    required String requestId,
  });

  Future<MerchantReviewReceipt> reportAsMerchant({
    required MerchantReviewReportDraft draft,
    required String requestId,
  });
}

abstract interface class MerchantPublicReviewGateway {
  Future<MerchantReviewPage> publicPage({
    required int merchantRowId,
    required int pageNum,
    required int pageSize,
  });

  Future<MerchantReviewReceipt> create({
    required MerchantReviewCreateDraft draft,
    required String requestId,
  });

  Future<MerchantReviewReceipt> reportPublic({
    required int merchantOwnerMemberId,
    required MerchantReviewReportDraft draft,
    required String requestId,
  });
}

class MerchantReviewApi
    implements MerchantReviewGateway, MerchantPublicReviewGateway {
  MerchantReviewApi(this._client);

  final DioClient _client;

  @override
  Future<MerchantReviewPage> publicPage({
    required int merchantRowId,
    required int pageNum,
    required int pageSize,
  }) async {
    if (merchantRowId <= 0) throw ArgumentError('merchantRowId 不合法');
    final Map<String, dynamic> data = await _postObject(
      '/api/merchant/reviews/public',
      queryParameters: <String, dynamic>{
        'merchantRowId': merchantRowId,
        'pageNum': pageNum,
        'pageSize': pageSize,
      },
      fallback: '评价加载失败',
    );
    return MerchantReviewPage.fromJson(
      data,
      expectedMode: MerchantReviewMode.public,
      expectedPageNum: pageNum,
      expectedPageSize: pageSize,
    );
  }

  @override
  Future<MerchantReviewPage> managePage({
    required int pageNum,
    required int pageSize,
  }) async {
    final Map<String, dynamic> data = await _postObject(
      '/api/merchant/reviews/manage',
      queryParameters: <String, dynamic>{
        'pageNum': pageNum,
        'pageSize': pageSize,
      },
      fallback: '评价加载失败',
    );
    return MerchantReviewPage.fromJson(
      data,
      expectedPageNum: pageNum,
      expectedPageSize: pageSize,
    );
  }

  @override
  Future<MerchantReviewReceipt> reply({
    required MerchantReviewReplyDraft draft,
    required String requestId,
  }) async {
    final Map<String, dynamic> data = await _postObject(
      '/api/merchant/reviews/reply',
      data: draft.toJson(requestId: requestId),
      fallback: '回复失败',
    );
    return MerchantReviewReceipt.fromJson(
      data,
      expectedReviewId: draft.reviewId,
      expectedAction: MerchantReviewAction.reply,
    );
  }

  @override
  Future<MerchantReviewReceipt> create({
    required MerchantReviewCreateDraft draft,
    required String requestId,
  }) async {
    final Map<String, dynamic> data = await _postObject(
      '/api/merchant/reviews/create',
      data: draft.toJson(requestId: requestId),
      fallback: '评价提交失败',
    );
    return MerchantReviewReceipt.fromJson(
      data,
      expectedReviewId: _requireReviewId(data),
      expectedAction: MerchantReviewAction.create,
    );
  }

  @override
  Future<void> updateReply({
    required MerchantReviewReplyDraft draft,
    required String requestId,
  }) async {
    await _postObject(
      '/api/merchant/reviews/reply/update',
      data: draft.toJson(requestId: requestId),
      fallback: '修改回复失败',
    );
  }

  @override
  Future<void> deleteReply({
    required int reviewId,
    required int expectedVersion,
    required String requestId,
  }) async {
    if (reviewId <= 0 || expectedVersion < 0) {
      throw ArgumentError('评价状态已失效，请刷新');
    }
    await _postObject(
      '/api/merchant/reviews/reply/delete',
      data: <String, dynamic>{
        'reviewId': reviewId,
        'expectedVersion': expectedVersion,
        'requestId': requestId,
      },
      fallback: '删除回复失败',
    );
  }

  @override
  Future<MerchantReviewReceipt> reportAsMerchant({
    required MerchantReviewReportDraft draft,
    required String requestId,
  }) async {
    final Map<String, dynamic> data = await _postObject(
      '/api/merchant/reviews/manage/report',
      data: draft.toJson(requestId: requestId),
      fallback: '举报提交失败',
    );
    return MerchantReviewReceipt.fromJson(
      data,
      expectedReviewId: draft.reviewId,
      expectedAction: MerchantReviewAction.report,
    );
  }

  @override
  Future<MerchantReviewReceipt> reportPublic({
    required int merchantOwnerMemberId,
    required MerchantReviewReportDraft draft,
    required String requestId,
  }) async {
    if (merchantOwnerMemberId <= 0) {
      throw ArgumentError('商家主体信息不完整');
    }
    final Map<String, dynamic> body = draft.toJson(requestId: requestId)
      ..['merchantMemberId'] = merchantOwnerMemberId;
    final Map<String, dynamic> data = await _postObject(
      '/api/merchant/reviews/report',
      data: body,
      fallback: '举报提交失败',
    );
    return MerchantReviewReceipt.fromJson(
      data,
      expectedReviewId: draft.reviewId,
      expectedAction: MerchantReviewAction.report,
    );
  }

  int _requireReviewId(Map<String, dynamic> data) {
    final Object? value = data['reviewId'];
    if (value is! int || value <= 0) {
      throw const FormatException('评价提交回执不完整');
    }
    return value;
  }

  Future<Map<String, dynamic>> _postObject(
    String path, {
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? data,
    required String fallback,
  }) async {
    try {
      final Response<Map<String, dynamic>> response = await _client.dio
          .post<Map<String, dynamic>>(
            path,
            queryParameters: queryParameters,
            data: data,
          );
      return _requireObject(response.data ?? <String, dynamic>{}, fallback);
    } on DioException catch (error) {
      final Object? rawBody = error.response?.data;
      final Map<String, dynamic>? body = rawBody is Map<String, dynamic>
          ? rawBody
          : null;
      final int? code = body == null
          ? error.response?.statusCode
          : _code(body['code']) ?? error.response?.statusCode;
      throw MerchantReviewApiException(
        (body?['msg'] ?? fallback).toString(),
        code: code,
      );
    }
  }

  Map<String, dynamic> _requireObject(
    Map<String, dynamic> body,
    String fallback,
  ) {
    final int? code = _code(body['code']);
    if (code != 200) {
      throw MerchantReviewApiException(
        (body['msg'] ?? fallback).toString(),
        code: code,
      );
    }
    final Object? data = body['data'];
    if (data is! Map<String, dynamic>) {
      throw const MerchantReviewApiException('评价服务回执不完整');
    }
    return data;
  }

  int? _code(Object? value) => switch (value) {
    final num number => number.toInt(),
    final String text => int.tryParse(text),
    _ => null,
  };
}

class MerchantReviewApiException implements Exception {
  const MerchantReviewApiException(this.message, {this.code});

  final String message;
  final int? code;

  bool get isUnauthorized => code == 401;
  bool get isForbidden => code == 403;
  bool get isNotFound => code == 404;
  bool get isConflict => code == 409;

  @override
  String toString() => message;
}

/// 定义在本文件而非 core/providers.dart:Riverpod 不要求 provider 集中声明。
final merchantReviewApiProvider = Provider<MerchantReviewApi>((ref) {
  return MerchantReviewApi(ref.watch(dioClientProvider));
});
