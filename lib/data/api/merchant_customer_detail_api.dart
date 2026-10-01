import '../../core/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';

import '../../core/network/dio_client.dart';
import '../models/merchant_customer_detail.dart';

/// 页面只依赖这个公开网关，便于路由注入真实 API，测试注入 fake。
abstract interface class MerchantCustomerDetailGateway {
  Future<MerchantCustomerAccess> access();

  Future<MerchantCustomerDetail> detail(int customerMemberId);

  Future<MerchantCustomerMutationReceipt> addNote({
    required int customerMemberId,
    required String content,
    required String requestId,
    int? correctsNoteId,
  });

  Future<MerchantCustomerMutationReceipt> hideNote({
    required int customerMemberId,
    required int noteId,
    required int expectedVersion,
    required String requestId,
  });

  Future<MerchantCustomerMutationReceipt> assignTag({
    required int customerMemberId,
    required String tagName,
    required String tagColor,
    required String requestId,
  });

  Future<MerchantCustomerMutationReceipt> removeTag({
    required int customerMemberId,
    required int tagId,
    required String requestId,
  });
}

/// 写操作的服务端回执。[data] 保留真实返回值，不伪造本地成功。
class MerchantCustomerMutationReceipt {
  const MerchantCustomerMutationReceipt({
    required this.message,
    required this.data,
    this.isLocalFallback = false,
  });

  final String message;
  final Object data;
  final bool isLocalFallback;
}

/// 当前账号在商家域的 CRM 访问上下文。
class MerchantCustomerAccess {
  const MerchantCustomerAccess({
    required this.active,
    required this.merchantId,
    required this.roleCode,
    required this.permissions,
  });

  static const MerchantCustomerAccess inactive = MerchantCustomerAccess(
    active: false,
    merchantId: null,
    roleCode: '',
    permissions: <String>{},
  );

  static const String crmRead = 'merchant:crm:read';
  static const String crmSegment = 'merchant:crm:segment';

  final bool active;
  final int? merchantId;
  final String roleCode;
  final Set<String> permissions;

  bool get canReadCrm => active && permissions.contains(crmRead);
  bool get canSegmentCrm => active && permissions.contains(crmSegment);

  factory MerchantCustomerAccess.fromJson(Map<String, dynamic> json) {
    if (json['active'] != true) return inactive;
    final dynamic merchantRaw = json['merchant'];
    final Map<String, dynamic>? merchant = merchantRaw is Map<String, dynamic>
        ? merchantRaw
        : null;
    final int? merchantId = _positiveIntOrNull(merchant?['id']);
    final String roleCode = _text(json['roleCode']);
    if (merchantId == null || !_roleCodes.contains(roleCode)) {
      return inactive;
    }
    final dynamic rawPermissions = json['permissions'];
    final Set<String> permissions = rawPermissions is List<dynamic>
        ? rawPermissions
              .whereType<String>()
              .where(_knownPermissions.contains)
              .toSet()
        : <String>{};
    return MerchantCustomerAccess(
      active: true,
      merchantId: merchantId,
      roleCode: roleCode,
      permissions: Set<String>.unmodifiable(permissions),
    );
  }
}

class MerchantCustomerDetailApi implements MerchantCustomerDetailGateway {
  MerchantCustomerDetailApi(this._client);

  final DioClient _client;

  @override
  Future<MerchantCustomerAccess> access() async {
    final dynamic data = await _postData('/api/merchant/access/me');
    if (data is! Map<String, dynamic>) {
      throw const MerchantCustomerDetailApiException('经营身份数据不完整，请稍后重试', isLocalFallback: true);
    }
    return MerchantCustomerAccess.fromJson(data);
  }

  @override
  Future<MerchantCustomerDetail> detail(int customerMemberId) async {
    _requirePositiveId(customerMemberId, '客户ID无效');
    final dynamic data = await _postData(
      '/api/merchant/crm/customers/$customerMemberId/detail',
    );
    if (data is! Map<String, dynamic>) {
      throw const MerchantCustomerDetailApiException('客户详情数据不完整，请稍后重试', isLocalFallback: true);
    }
    try {
      return MerchantCustomerDetail.fromJson(
        data,
        expectedCustomerMemberId: customerMemberId,
      );
    } on FormatException {
      throw const MerchantCustomerDetailApiException('客户详情数据不完整，请稍后重试', isLocalFallback: true);
    }
  }

  @override
  Future<MerchantCustomerMutationReceipt> addNote({
    required int customerMemberId,
    required String content,
    required String requestId,
    int? correctsNoteId,
  }) async {
    _requirePositiveId(customerMemberId, '客户ID无效');
    final String normalizedContent = content.trim();
    if (normalizedContent.isEmpty) {
      throw const MerchantCustomerDetailApiException('请填写跟进备注', code: 400, isLocalFallback: true);
    }
    if (normalizedContent.length > 500) {
      throw const MerchantCustomerDetailApiException('跟进备注最多500字', code: 400, isLocalFallback: true);
    }
    _requireRequestId(requestId);
    if (correctsNoteId != null) {
      _requirePositiveId(correctsNoteId, '被更正备注ID无效');
    }
    return _postReceipt(
      '/api/merchant/crm/customers/$customerMemberId/notes',
      data: <String, dynamic>{
        'content': normalizedContent,
        'requestId': requestId,
        'correctsNoteId': correctsNoteId,
      },
      fallbackMessage: '跟进备注已保存',
    );
  }

  @override
  Future<MerchantCustomerMutationReceipt> hideNote({
    required int customerMemberId,
    required int noteId,
    required int expectedVersion,
    required String requestId,
  }) async {
    _requirePositiveId(customerMemberId, '客户ID无效');
    _requirePositiveId(noteId, '备注ID无效');
    if (expectedVersion < 0) {
      throw const MerchantCustomerDetailApiException('备注版本无效', code: 400, isLocalFallback: true);
    }
    _requireRequestId(requestId);
    return _postReceipt(
      '/api/merchant/crm/customers/$customerMemberId/notes/hide',
      data: <String, dynamic>{
        'noteId': noteId,
        'expectedVersion': expectedVersion,
        'requestId': requestId,
      },
      fallbackMessage: '备注已隐藏',
    );
  }

  @override
  Future<MerchantCustomerMutationReceipt> assignTag({
    required int customerMemberId,
    required String tagName,
    required String tagColor,
    required String requestId,
  }) async {
    _requirePositiveId(customerMemberId, '客户ID无效');
    final String normalizedName = tagName.trim();
    final String normalizedColor = tagColor.trim().toUpperCase();
    if (normalizedName.isEmpty) {
      throw const MerchantCustomerDetailApiException('请填写标签名称', code: 400, isLocalFallback: true);
    }
    if (normalizedName.length > 16) {
      throw const MerchantCustomerDetailApiException('标签最多16字', code: 400, isLocalFallback: true);
    }
    if (!_tagColorPattern.hasMatch(normalizedColor)) {
      throw const MerchantCustomerDetailApiException('标签颜色无效', code: 400, isLocalFallback: true);
    }
    _requireRequestId(requestId);
    return _postReceipt(
      '/api/merchant/crm/customers/$customerMemberId/tags',
      data: <String, dynamic>{
        'tagName': normalizedName,
        'tagColor': normalizedColor,
        'requestId': requestId,
      },
      fallbackMessage: '客户标签已保存',
    );
  }

  @override
  Future<MerchantCustomerMutationReceipt> removeTag({
    required int customerMemberId,
    required int tagId,
    required String requestId,
  }) async {
    _requirePositiveId(customerMemberId, '客户ID无效');
    _requirePositiveId(tagId, '标签ID无效');
    _requireRequestId(requestId);
    return _postReceipt(
      '/api/merchant/crm/customers/$customerMemberId/tags/remove',
      data: <String, dynamic>{'tagId': tagId, 'requestId': requestId},
      fallbackMessage: '标签已移除',
    );
  }

  Future<dynamic> _postData(String path, {Map<String, dynamic>? data}) async =>
      (await _post(path, data: data)).data;

  Future<MerchantCustomerMutationReceipt> _postReceipt(
    String path, {
    required Map<String, dynamic> data,
    required String fallbackMessage,
  }) async {
    final _MerchantCustomerEnvelope envelope = await _post(path, data: data);
    final String dataMessage = envelope.data is String
        ? (envelope.data as String).trim()
        : '';
    return MerchantCustomerMutationReceipt(
      message: envelope.message.isNotEmpty
          ? envelope.message
          : dataMessage.isNotEmpty
          ? dataMessage
          : fallbackMessage,
      isLocalFallback: envelope.message.isEmpty && dataMessage.isEmpty,
      data: envelope.data,
    );
  }

  Future<_MerchantCustomerEnvelope> _post(
    String path, {
    Map<String, dynamic>? data,
  }) async {
    try {
      final Response<Map<String, dynamic>> response = await _client.dio
          .post<Map<String, dynamic>>(path, data: data);
      final Map<String, dynamic> body =
          response.data ?? const <String, dynamic>{};
      final int? code = _responseCode(body['code']);
      if (code != 200) {
        throw MerchantCustomerDetailApiException(
          _text(body['msg']).isEmpty ? '请求失败' : _text(body['msg']),
          code: code,
          isLocalFallback: _text(body['msg']).isEmpty,
        );
      }
      if (!body.containsKey('data') || body['data'] == null) {
        throw const MerchantCustomerDetailApiException('服务端未返回可确认的结果', isLocalFallback: true);
      }
      return _MerchantCustomerEnvelope(
        data: body['data'] as Object,
        message: _text(body['msg']),
      );
    } on MerchantCustomerDetailApiException {
      rethrow;
    } on DioException catch (error) {
      final dynamic body = error.response?.data;
      if (body is Map<String, dynamic>) {
        final String message = _text(body['msg']);
        if (message.isNotEmpty) {
          throw MerchantCustomerDetailApiException(
            message,
            code: _responseCode(body['code']) ?? error.response?.statusCode,
          );
        }
      }
      throw const MerchantCustomerDetailApiException('网络连接失败，请稍后重试', isLocalFallback: true);
    }
  }
}

class _MerchantCustomerEnvelope {
  const _MerchantCustomerEnvelope({required this.data, required this.message});

  final Object data;
  final String message;
}

class MerchantCustomerDetailApiException implements Exception {
  const MerchantCustomerDetailApiException(this.message, {this.code, this.isLocalFallback = false});

  final String message;
  final int? code;
  final bool isLocalFallback;

  bool get isPermissionDenied =>
      code == 401 ||
      code == 403 ||
      message.contains('权限') ||
      message.contains('无权') ||
      message.contains('当前岗位');

  @override
  String toString() => message;
}

const Set<String> _roleCodes = <String>{
  'MERCHANT_OWNER',
  'MERCHANT_MANAGER',
  'MERCHANT_CHECKIN',
  'MERCHANT_MARKETING',
  'MERCHANT_FINANCE',
};

const Set<String> _knownPermissions = <String>{
  'merchant:basic:read',
  'merchant:profile:write',
  'merchant:project:manage',
  'merchant:verify',
  'merchant:verify:record:read',
  'merchant:order:read',
  'merchant:crm:read',
  'merchant:crm:sensitive:read',
  'merchant:crm:segment',
  'merchant:crm:export',
  'merchant:finance:read',
  'merchant:aftercare:read',
  'merchant:aftercare:respond',
  'merchant:marketing:read',
  'merchant:marketing:write',
  'merchant:coupon:manage',
  'merchant:coop:manage',
  'merchant:operator:manage',
};

String _text(dynamic value) => value is String ? value.trim() : '';

int? _responseCode(dynamic value) =>
    value is num ? value.toInt() : int.tryParse(value?.toString() ?? '');

int? _positiveIntOrNull(dynamic value) {
  final int? parsed = value is int
      ? value
      : int.tryParse(value?.toString() ?? '');
  return parsed != null && parsed > 0 ? parsed : null;
}

void _requirePositiveId(int value, String message) {
  if (value <= 0) throw MerchantCustomerDetailApiException(message, code: 400, isLocalFallback: true);
}

final RegExp _requestIdPattern = RegExp(r'^[A-Za-z0-9._:-]{6,64}$');
final RegExp _tagColorPattern = RegExp(r'^#[0-9A-F]{6}$');

void _requireRequestId(String value) {
  if (!_requestIdPattern.hasMatch(value)) {
    throw const MerchantCustomerDetailApiException('请求标识无效', code: 400, isLocalFallback: true);
  }
}

/// 定义在本文件而非 core/providers.dart:Riverpod 不要求 provider 集中声明。
final merchantCustomerDetailApiProvider = Provider<MerchantCustomerDetailGateway>((ref) {
  return MerchantCustomerDetailApi(ref.watch(dioClientProvider));
});
