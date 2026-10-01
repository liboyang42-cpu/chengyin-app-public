import 'package:dio/dio.dart';

import '../../core/network/dio_client.dart';
import '../../core/network/request_session_scope.dart';
import '../models/club_access.dart';
import '../models/club_crm.dart';
import '../models/club_settlement.dart';
import '../models/club_stats.dart';

/// 俱乐部 CRM / 结算 / 看板 / 权限的 API 客户端。
///
/// 与 `ClubApi` 分文件是为了让这批新域(客户·核销·分润·看板)独立演进,
/// 不动已有的俱乐部主流程;所有方法照仓库约定:**JSON body + `_ensureOk`**。
class ClubCrmApi {
  ClubCrmApi(this._client);

  final DioClient _client;

  /// 客户名单:`POST /api/club/crm/customers/list`。
  ///
  /// `filter` ∈ all / repeat / new / remark;`keyword` 服务端过滤。
  Future<ClubCustomerList> customers({
    required int clubId,
    String filter = 'all',
    String keyword = '',
  }) async {
    final Map<String, dynamic> body = await _postJson(
      '/api/club/crm/customers/list',
      <String, dynamic>{'clubId': clubId, 'filter': filter, 'keyword': keyword},
    );
    _ensureOk(body);
    return ClubCustomerList.fromJson(_dataMap(body));
  }

  /// 客户人数:`POST /api/club/crm/customers/count`(管理入口那一行的数,不端列表)。
  Future<int> customerCount({required int clubId}) async {
    final Map<String, dynamic> body = await _postJson(
      '/api/club/crm/customers/count',
      <String, dynamic>{'clubId': clubId},
    );
    _ensureOk(body);
    final Object? total = _dataMap(body)['total'];
    final int? parsed = total is num ? total.toInt() : int.tryParse('$total');
    if (parsed == null || parsed < 0) {
      throw const ClubCrmApiException('客户人数回执不完整');
    }
    return parsed;
  }

  /// 客户详情:`POST /api/club/crm/customers/detail`。
  Future<ClubCustomerDetail> customerDetail({
    required int clubId,
    required int memberId,
  }) async {
    final Map<String, dynamic> body = await _postJson(
      '/api/club/crm/customers/detail',
      <String, dynamic>{'clubId': clubId, 'memberId': memberId},
    );
    _ensureOk(body);
    return ClubCustomerDetail.fromJson(
      _dataMap(body),
      expectedMemberId: memberId,
    );
  }

  /// 保存客户标签与备注(覆盖式):`POST /api/club/crm/customers/tag-remark`。
  ///
  /// `requestId` 是服务端要求的幂等键 —— 页面重试时复用同一个,别每次新生成。
  Future<String> saveCustomerTagRemark({
    required int clubId,
    required int memberId,
    required List<String> tags,
    required String remark,
    required String requestId,
  }) async {
    final Map<String, dynamic> body =
        await _postJson('/api/club/crm/customers/tag-remark', <String, dynamic>{
          'clubId': clubId,
          'memberId': memberId,
          'tags': tags,
          'remark': remark,
          'requestId': requestId,
        });
    _ensureOk(body);
    return '${body['msg'] ?? '已保存'}';
  }

  /// 核销详情:`POST /api/club/crm/checkin/detail`。
  Future<ClubCheckinDetail> checkinDetail({
    required int clubId,
    required int registrationId,
  }) async {
    final Map<String, dynamic> body = await _postJson(
      '/api/club/crm/checkin/detail',
      <String, dynamic>{'clubId': clubId, 'registrationId': registrationId},
    );
    _ensureOk(body);
    return ClubCheckinDetail.fromJson(
      _dataMap(body),
      expectedRegistrationId: registrationId,
    );
  }

  /// 俱乐部分润汇总:`POST /api/club/settlement/summary`。
  Future<ClubSettlementSummary> settlementSummary({required int clubId}) async {
    final Map<String, dynamic> body = await _postJson(
      '/api/club/settlement/summary',
      <String, dynamic>{'clubId': clubId},
    );
    _ensureOk(body);
    return ClubSettlementSummary.fromJson(_dataMap(body));
  }

  // ⚠️ `POST /api/club/settlement/withdraw` **故意不封装**。
  //
  // 提现按 R10(收款模型定稿 2026-09-15,用户 09-16 拍板)走:所有提现入口 =
  // 客服微信号弹窗(「返回」「复制」),不进银行卡表单、不做风险确认。
  // 动钱的路径只留一条 —— 后端那条俱乐部维度的口子仍在(转发既有会员提现链路,
  // 且被 withdrawal.fast-withdraw.enabled 总开关挡着),App 侧不封装:
  // 在这里补一个 client 方法 = 给 App 开第二条提现路径。

  /// 俱乐部数据看板:`POST /api/stats/club`(仅主理人)。
  Future<ClubStats> stats({required int clubId}) async {
    final Map<String, dynamic> body = await _postJson(
      '/api/stats/club',
      <String, dynamic>{'clubId': clubId},
    );
    _ensureOk(body);
    return ClubStats.fromJson(_dataMap(body), expectedClubId: clubId);
  }

  /// 当前账号在该俱乐部的访问上下文:`POST /api/club/access/me`。
  Future<ClubAccess> access({required int clubId}) async {
    final Map<String, dynamic> body = await _postJson(
      '/api/club/access/me',
      <String, dynamic>{'clubId': clubId},
    );
    _ensureOk(body);
    return ClubAccess.fromJson(_dataMap(body));
  }

  Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, dynamic> body,
  ) async {
    try {
      final Response<Map<String, dynamic>> resp = await _client.dio
          .post<Map<String, dynamic>>(
            path,
            data: body,
            options: RequestSessionScope.options(Options(contentType: Headers.jsonContentType)),
          );
      return resp.data ?? <String, dynamic>{};
    } on DioException catch (error) {
      throw _fromDio(error);
    }
  }

  /// AjaxResult 非 200 → 抛异常进 error 态(不兜底假数据)。
  void _ensureOk(Map<String, dynamic> body) {
    final Object? rawCode = body['code'];
    final int? code = rawCode is num
        ? rawCode.toInt()
        : int.tryParse('${rawCode ?? ''}');
    if (code != 200) {
      throw ClubCrmApiException('${body['msg'] ?? '请求失败'}', code: code);
    }
  }

  Map<String, dynamic> _dataMap(Map<String, dynamic> body) {
    final Object? data = body['data'];
    if (data is Map) return Map<String, dynamic>.from(data);
    throw const FormatException('回执数据格式异常');
  }

  ClubCrmApiException _fromDio(DioException error) {
    final int? status = error.response?.statusCode;
    final Object? data = error.response?.data;
    final String? msg = data is Map && data['msg'] != null
        ? '${data['msg']}'
        : null;
    final bool noResponse =
        error.response == null ||
        error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.sendTimeout;
    return ClubCrmApiException(
      msg ??
          (noResponse
              ? '网络不稳定，请检查连接后重试'
              : '请求失败${status == null ? '' : '（$status）'}'),
      code: status,
      networkUnreachable: noResponse,
      outcomeUnknown: noResponse || (status != null && status >= 500),
    );
  }
}

class ClubCrmApiException implements Exception {
  const ClubCrmApiException(
    this.message, {
    this.code,
    this.networkUnreachable = false,
    this.outcomeUnknown = false,
  });

  final String message;

  /// AjaxResult.code 或 HTTP status。
  final int? code;

  /// 没连上/超时(不是服务端拒绝)。
  final bool networkUnreachable;

  /// 结果未确认:请求可能已被服务端受理,不许自动重试。
  final bool outcomeUnknown;

  /// 身份/授权类失败(401/403/code 2,或后端明确说权限)。
  ///
  /// 判据要宽、分流要窄(与小程序 `isAuthFailure` 同一手法):它回答的是
  /// 「要不要丢掉已缓存的客户 PII」,不是「要不要显示没权限」。
  bool get isAuthFailure {
    final int? code = this.code;
    if (code == 2 || code == 401 || code == 403) return true;
    return RegExp(r'请先登录|登录已|身份已|没有权限|无权|仅(?:俱乐部)?主理人').hasMatch(message);
  }

  @override
  String toString() => message;
}
