import '../../core/network/request_session_scope.dart';
import 'package:dio/dio.dart';

import '../../core/network/dio_client.dart';
import '../models/club_lead.dart';
import 'club_ops_api.dart' show ensureClubOpsOk;

/// 俱乐部带队。对齐后端 `ApiClubLeadController`(/api/club/lead)。
///
/// ★ 七个端点里有五个是**队长专属**,后端会按 leaderMemberId 拒。
///   前端按 [TeamProgress.isLeader] 决定摆不摆按钮 —— 别让队员点了才被拒。
class ClubLeadApi {
  ClubLeadApi(this._client);
  final DioClient _client;

  /// 队伍进度:`GET /api/club/lead/team-progress?activityId=`。
  ///
  /// ⚠️ 这一场还没开队时后端返回 `exists:false`(**200,不是错误**)——
  ///   界面该给「开始带队」,不是「加载失败」。
  Future<TeamProgress> teamProgress(int activityId) async {
    final resp = await _client.dio.get<Map<String, dynamic>>(
      '/api/club/lead/team-progress',
      options: RequestSessionScope.options(),
      queryParameters: <String, dynamic>{'activityId': activityId},
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw Exception((body['msg'] as String?) ?? '加载失败');
    }
    return TeamProgress.fromJson(
      (body['data'] as Map<String, dynamic>?) ?? <String, dynamic>{},
    );
  }

  /// 开始带队(队长):`POST /api/club/lead/start`。
  Future<void> start(int activityId) => _post(
    '/api/club/lead/start',
    <String, dynamic>{'activityId': activityId},
  );

  /// 标记本人已到达:`POST /api/club/lead/arrive`。★ 这个**队员也能调**。
  Future<void> arrive(int activityId) => _post(
    '/api/club/lead/arrive',
    <String, dynamic>{'activityId': activityId},
  );

  /// 发广播(队长):`POST /api/club/lead/broadcast`。
  Future<void> broadcast(int activityId, String text) => _post(
    '/api/club/lead/broadcast',
    <String, dynamic>{'activityId': activityId, 'text': text},
  );

  /// 解锁下一章(队长):`POST /api/club/lead/unlock-chapter`。
  Future<void> unlockChapter(int activityId) => _post(
    '/api/club/lead/unlock-chapter',
    <String, dynamic>{'activityId': activityId},
  );

  /// 结束并结算(队长):`POST /api/club/lead/settle`。
  Future<void> settle(int activityId) => _post(
    '/api/club/lead/settle',
    <String, dynamic>{'activityId': activityId},
  );

  /// 导演台 · 改集合时间(承接方领队):`POST /api/club/lead/edit-ops`。
  ///
  /// ⚠️ 后端是 `@RequestBody Map` —— 和上面六条**不是一种编码**,必须发 JSON
  ///   (小程序 HO-26 也单独给了 jsonBody/jsonHeader)。
  ///   已售出的场次后端会拒(CR-63 已售锁时间地点),拒绝原话经
  ///   [ensureClubOpsOk] 抛给调用方,页面照原话显示、不改写成自己的话。
  ///   只发集合时间:地点/结束时间/当日备注三个字段不在本 slice 里。
  Future<void> editOpsTime({
    required int activityId,
    required String startDate,
  }) async {
    final Response<Map<String, dynamic>> resp = await _client.dio
        .post<Map<String, dynamic>>(
          '/api/club/lead/edit-ops',
          data: <String, dynamic>{
            'activityId': activityId,
            'startDate': startDate,
          },
          options: Options(contentType: Headers.jsonContentType),
        );
    ensureClubOpsOk(resp.data ?? <String, dynamic>{});
  }

  Future<void> _post(String path, Map<String, dynamic> form) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      path,
      options: RequestSessionScope.options(),
      data: FormData.fromMap(
        form.map((String k, dynamic v) => MapEntry<String, String>(k, '$v')),
      ),
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw Exception((body['msg'] as String?) ?? '操作失败');
    }
  }
}
