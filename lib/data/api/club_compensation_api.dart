import 'package:dio/dio.dart';
import '../../core/network/dio_client.dart';
import '../models/club_manage.dart';

/// 探店日俱乐部自报接口。对齐后端 `/api/club-compensation/*`。
///
/// ★ 这一页存在的理由是一条确定性断链(小程序 edition-report 页注释原话):
///   club_edition_hours.confirm_status 只能由后台的 upsertPlannedHours 建成
///   'UNREPORTED';confirmActualHoursCas 要求旧状态是 'REPORTED';而 'REPORTED'
///   只能由 reportActualHoursCas 写,它只被 /api/club-compensation/{topicId}/hours/report
///   调 —— 这个端点此前在小程序侧零消费方。⇒ confirm_status 永远停在 UNREPORTED。
///   质量证据同理:没有 evidenceHash,confirmQualityOnce 的 pass=true 恒被
///   EDITION_QUALITY_EVIDENCE_REQUIRED 挡下。后台刻意不代填自报,所以补口只能补在客户端。
class ClubCompensationApi {
  ClubCompensationApi(this._client);
  final DioClient _client;

  Future<Map<String, dynamic>> _postJson(String path, Map<String, dynamic> body) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      path,
      data: body,
      options: Options(contentType: Headers.jsonContentType),
    );
    return resp.data ?? <String, dynamic>{};
  }

  void _ensureOk(Map<String, dynamic> body) {
    final code = (body['code'] as num?)?.toInt();
    if (code != 200) {
      throw Exception((body['msg'] as String?) ?? '请求失败');
    }
  }

  /// 本俱乐部作为执行俱乐部的候选期次:`POST /api/club-compensation/editions`。
  /// ★ 真源是开售冻结条款里的执行俱乐部(club_edition_compensation_terms.executing_club_id),
  ///   不是 /api/club/topics(那按 cms_topic.club_id 过滤,探店日期次那列为 NULL 恒取不到)。
  Future<List<EditionOption>> editions(int clubId) async {
    final body = await _postJson(
      '/api/club-compensation/editions',
      <String, dynamic>{'clubId': clubId},
    );
    _ensureOk(body);
    final list = (body['data'] as List<dynamic>?) ?? <dynamic>[];
    return list
        .whereType<Map<String, dynamic>>()
        .where((Map<String, dynamic> e) => (e['topicId'] as num?) != null)
        .map(EditionOption.fromJson)
        .toList();
  }

  /// 自报四类工时之一:`POST /api/club-compensation/hours/report`。
  /// 只写 reported_* —— 平台后台逐条确认后才计入 H_actual。
  Future<void> reportHours({
    required int topicId,
    required int clubId,
    required String hourKind,
    required double actualHours,
  }) async {
    final body = await _postJson('/api/club-compensation/hours/report', <String, dynamic>{
      'topicId': topicId,
      'clubId': clubId,
      'hourKind': hourKind,
      'actualHours': actualHours,
    });
    _ensureOk(body);
  }

  /// 提交质量证据:`POST /api/club-compensation/quality/evidence`。
  /// 证据截止(evidence_due_at)之后后端会拒:迟交不得再拿这一维的 200。
  Future<void> submitEvidence({
    required int topicId,
    required int clubId,
    required String dimension,
    required String evidenceHash,
  }) async {
    final body = await _postJson('/api/club-compensation/quality/evidence', <String, dynamic>{
      'topicId': topicId,
      'clubId': clubId,
      'dimension': dimension,
      'evidenceHash': evidenceHash,
    });
    _ensureOk(body);
  }
}
