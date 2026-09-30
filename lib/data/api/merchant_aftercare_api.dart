import '../../core/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';

import '../../core/network/dio_client.dart';
import 'merchant_api.dart';
import '../models/merchant_aftercare.dart';

abstract interface class MerchantAftercareGateway {
  Future<MerchantAftercarePage> listPage({
    required MerchantAftercareBucket bucket,
    required int pageNum,
    required int pageSize,
  });

  Future<MerchantAftercareDetail> detail({required int refundId});

  Future<MerchantAftercareReceipt> respond({
    required int refundId,
    required MerchantAftercareResponseDraft draft,
    required String requestId,
  });

  Future<MerchantAftercareEvidence> uploadEvidence(String filePath);
}

class MerchantAftercareApi implements MerchantAftercareGateway {
  MerchantAftercareApi(this._client);

  final DioClient _client;

  Future<MerchantAccess> _require(String permission, String label) async {
    final MerchantAccess access = await MerchantApi(_client).access();
    access.require(permission, label);
    return access;
  }

  @override
  Future<MerchantAftercarePage> listPage({
    required MerchantAftercareBucket bucket,
    required int pageNum,
    required int pageSize,
  }) async {
    await _require('merchant:aftercare:read', '售后查看');
    final response = await _client.dio.post<Map<String, dynamic>>(
      '/api/merchant/aftercare/list',
      queryParameters: <String, dynamic>{
        'bucket': bucket.wire,
        'pageNum': pageNum,
        'pageSize': pageSize,
      },
    );
    final Map<String, dynamic> body = response.data ?? <String, dynamic>{};
    final Map<String, dynamic> data = _requireObject(body, '售后列表加载失败');
    return MerchantAftercarePage.fromJson(
      data,
      expectedBucket: bucket,
      expectedPageNum: pageNum,
    );
  }

  @override
  Future<MerchantAftercareDetail> detail({required int refundId}) async {
    await _require('merchant:aftercare:read', '售后查看');
    final response = await _client.dio.post<Map<String, dynamic>>(
      '/api/merchant/aftercare/detail',
      queryParameters: <String, dynamic>{'refundId': refundId},
    );
    final Map<String, dynamic> data = _requireObject(
      response.data ?? <String, dynamic>{},
      '退款售后加载失败',
    );
    return MerchantAftercareDetail.fromJson(data, expectedRefundId: refundId);
  }

  @override
  Future<MerchantAftercareReceipt> respond({
    required int refundId,
    required MerchantAftercareResponseDraft draft,
    required String requestId,
  }) async {
    final MerchantAccess access = await MerchantApi(_client).access();
    access.require('merchant:aftercare:read', '售后查看');
    access.require('merchant:aftercare:respond', '售后回应');
    final response = await _client.dio.post<Map<String, dynamic>>(
      '/api/merchant/aftercare/respond',
      queryParameters: <String, dynamic>{'refundId': refundId},
      data: draft.toJson(requestId: requestId),
    );
    final Map<String, dynamic> data = _requireObject(
      response.data ?? <String, dynamic>{},
      '售后意见提交失败',
    );
    return MerchantAftercareReceipt.fromJson(
      data,
      expectedRefundId: refundId,
      expectedDecision: draft.decision,
    );
  }

  @override
  Future<MerchantAftercareEvidence> uploadEvidence(String filePath) async {
    await _require('merchant:aftercare:evidence', '售后凭证上传');
    final response = await _client.dio.post<Map<String, dynamic>>(
      '/api/common/uploadOSS',
      data: FormData.fromMap(<String, dynamic>{
        'file': await MultipartFile.fromFile(filePath),
        'bizType': 'merchant_aftercare_evidence',
      }),
    );
    final Map<String, dynamic> body = response.data ?? <String, dynamic>{};
    final int? code = _code(body['code']);
    if (code != 200) {
      throw MerchantAftercareApiException(
        (body['msg'] ?? '凭证上传失败').toString(),
        code: code,
      );
    }
    final String objectKey = (body['fileName'] ?? '').toString().trim();
    if (!MerchantAftercareEvidence.isObjectKey(objectKey)) {
      throw const MerchantAftercareApiException('凭证上传回执不完整');
    }
    return MerchantAftercareEvidence(objectKey: objectKey, localPath: filePath);
  }

  Map<String, dynamic> _requireObject(
    Map<String, dynamic> body,
    String fallback,
  ) {
    final int? code = _code(body['code']);
    if (code != 200) {
      throw MerchantAftercareApiException(
        (body['msg'] ?? fallback).toString(),
        code: code,
      );
    }
    final Object? data = body['data'];
    if (data is! Map<String, dynamic>) {
      throw MerchantAftercareApiException('售后服务回执不完整');
    }
    return data;
  }

  int? _code(Object? value) => switch (value) {
    final num number => number.toInt(),
    final String text => int.tryParse(text),
    _ => null,
  };
}

class MerchantAftercareApiException implements Exception {
  const MerchantAftercareApiException(this.message, {this.code});

  final String message;
  final int? code;

  bool get isForbidden => code == 403;
  bool get isNotFound => code == 404;
  bool get isConflict => code == 409;

  @override
  String toString() => message;
}

/// 定义在本文件而非 core/providers.dart:Riverpod 不要求 provider 集中声明。
final merchantAftercareApiProvider = Provider<MerchantAftercareGateway>((ref) {
  return MerchantAftercareApi(ref.watch(dioClientProvider));
});
