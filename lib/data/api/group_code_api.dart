import 'dart:typed_data';

import 'package:dio/dio.dart';
import '../../core/network/dio_client.dart';
import '../models/club_manage.dart';

/// 出码被拒:这是**终态**,重试必然再失败,出路是回俱乐部管理看自己名下的场次。
///
/// 对齐小程序 `pages/club/group-code` 的 `isPermissionDenial`:
/// 判据是 HTTP 403,或回执文案里带「权限 / 无权」。后端拒绝语是
/// 「您没有该场次的团码核销权限」(GroupCodeServiceImpl)。
class GroupCodePermissionException implements Exception {
  const GroupCodePermissionException(this.message, {this.isLocalFallback = false});
  final String message;
  final bool isLocalFallback;

  @override
  String toString() => message;
}

/// 团核销码接口:主理人/管理员出示给合作商家扫码。
/// 码过期后自动换新,权限与团归属只由服务端判定。
///
/// 对齐后端 `/api/verify/groupcode/issue` 与 `/api/topic/info-to-user`。
class GroupCodeApi {
  GroupCodeApi(this._client);
  final DioClient _client;

  /// 出码:`POST /api/verify/groupcode/issue`,payload 仅 `{activityId: 正整数}`。
  Future<GroupCodeIssue> issue(int activityId) async {
    final Map<String, dynamic> body;
    try {
      final resp = await _client.dio.post<Map<String, dynamic>>(
        '/api/verify/groupcode/issue',
        data: <String, dynamic>{'activityId': activityId},
        options: Options(contentType: Headers.jsonContentType),
      );
      body = resp.data ?? <String, dynamic>{};
    } on DioException catch (error) {
      // 403 由 dio 按状态码抛,拿不到我们的 code 字段 —— 按 HTTP 状态判同一条终态。
      if (error.response?.statusCode != 403) rethrow;
      final dynamic data = error.response?.data;
      final String? msg = data is Map ? data['msg'] as String? : null;
      throw GroupCodePermissionException(msg ?? '当前账号没有出码权限', isLocalFallback: msg == null);
    }
    final code = (body['code'] as num?)?.toInt();
    if (code != 200) {
      final String msg = (body['msg'] as String?) ?? '出码失败';
      if (code == 403 || msg.contains('权限') || msg.contains('无权')) {
        throw GroupCodePermissionException(msg, isLocalFallback: body['msg'] == null);
      }
      throw GroupCodeApiException(msg, isLocalFallback: body['msg'] == null);
    }
    final data = (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    return GroupCodeIssue.fromJson(data);
  }

  /// 把核销码图下成字节(保存到相册用)。
  ///
  /// ⚠️ 服务端给的是一个 URL,不先落成字节就没法写进系统相册 ——
  ///   在页面里直接发 http 违反分层,所以下载留在 API 层。
  Future<Uint8List> fetchQrBytes(String url) async {
    final Response<List<int>> resp = await _client.dio.get<List<int>>(
      url,
      options: Options(responseType: ResponseType.bytes),
    );
    final List<int>? bytes = resp.data;
    if (bytes == null || bytes.isEmpty) {
      throw const GroupCodeEmptyDownloadException();
    }
    return Uint8List.fromList(bytes);
  }

  /// 取某路线可出示团码的场次:`POST /api/topic/info-to-user` 的 activityList,
  /// 过滤出 activityId 为正整数的场次(对齐小程序 group-code-session.js)。
  Future<List<GroupCodeActivity>> activities(int topicId) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/topic/info-to-user',
      data: FormData.fromMap(<String, dynamic>{'id': topicId.toString()}),
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw GroupCodeApiException((body['msg'] as String?) ?? '场次加载失败', isLocalFallback: body['msg'] == null);
    }
    final data = (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    final raw = (data['activityList'] as List<dynamic>?) ?? <dynamic>[];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(GroupCodeActivity.fromJson)
        .where((GroupCodeActivity a) => a.id > 0)
        .toList();
  }

  /// 核销团码(**商家侧**):`POST /api/verify/groupcode/redeem`。
  ///
  /// ★ 与据点码同一条裂缝:此前只接了 `issue`,核销端一条没接。
  /// 失败文案原样透传 —— 后端会说清是「码无效」「已核销」还是「无权核销」,
  /// 换成笼统的「核销失败」商家就不知道该怎么办。
  Future<String> redeem(String code) async => (await redeemWithReceipt(code)).message;

  Future<GroupCodeRedemptionReceipt> redeemWithReceipt(String code) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/verify/groupcode/redeem',
      data: FormData.fromMap(<String, dynamic>{'code': code}),
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw GroupCodeApiException((body['msg'] as String?) ?? '核销失败', isLocalFallback: body['msg'] == null);
    }
    return GroupCodeRedemptionReceipt((body['msg'] as String?) ?? '核销成功', isLocalFallback: body['msg'] == null);
  }
}

/// A successful image download with no bytes; no server message is wrapped.
class GroupCodeEmptyDownloadException implements Exception {
  const GroupCodeEmptyDownloadException();
  String get message => '码图没下载下来，请重试';
  @override
  String toString() => 'Exception: $message';
}

class GroupCodeApiException implements Exception {
  const GroupCodeApiException(this.message, {this.isLocalFallback = false});
  final String message;
  final bool isLocalFallback;
  @override
  String toString() => 'Exception: $message';
}
class GroupCodeRedemptionReceipt {
  const GroupCodeRedemptionReceipt(this.message, {this.isLocalFallback = false});
  final String message;
  final bool isLocalFallback;
}
