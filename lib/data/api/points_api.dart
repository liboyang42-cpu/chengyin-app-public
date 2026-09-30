import 'package:dio/dio.dart';
import '../../core/network/dio_client.dart';
import '../models/points_record.dart';

/// 积分明细接口。对齐后端 `ApiUmsMemberController`(/api/user)。
///
/// 说明(契约纠正,见 bucket 指引):bucket 让对照 `ApiPointsController.myPointsList`
/// (`POST /api/points/list`),但读源码后该端点 **无 startPage 分页**(返回整表 List,
/// 不在 data.rows),且 `change_type` 过滤已被注释掉(后端忽略)。真正支持服务端分页的是
/// `ApiUmsMemberController.getPointsList`(`POST /api/user/points/list`,startPage +
/// getDataTable → 列表在 data.rows)。为满足"真实分页"要求,这里改用 /api/user/points/list。
class PointsApi {
  PointsApi(this._client);
  final DioClient _client;

  /// 积分明细列表:`POST /api/user/points/list`。
  /// 后端 startPage() 读取 pageNum/pageSize,列表在 data.rows。
  ///
  /// 注意:后端两个积分端点均不做 change_type 服务端过滤。`changeType` 参数会随表单
  /// 发送(无害),收入/支出 tab 的过滤在客户端(controller)对已加载页做筛选。
  Future<List<PointsRecord>> list({
    int? changeType,
    int pageNum = 1,
    int pageSize = 20,
  }) async =>
      (await page(changeType: changeType, pageNum: pageNum, pageSize: pageSize))
          .rows;

  /// 同上,但**把后端的 total 一起带出来**。
  ///
  /// ★ 邀请记录页要用它判「流水拉全了没有」:拉不全就不能说
  ///   「首购待完成」(见 feature/account/invite_history_logic.dart 的表)。
  ///   只拿 rows 是判不出来的 —— 20 行可能是全部,也可能是第一页。
  Future<({List<PointsRecord> rows, num? total})> page({
    int? changeType,
    int pageNum = 1,
    int pageSize = 20,
  }) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/user/points/list',
      data: FormData.fromMap(<String, dynamic>{
        'change_type': ?changeType?.toString(),
        'pageNum': pageNum.toString(),
        'pageSize': pageSize.toString(),
      }),
    );
    final body = resp.data ?? <String, dynamic>{};
    final data = body['data'];
    final rows =
        (data is Map<String, dynamic>
            ? data['rows'] as List<dynamic>?
            : null) ??
        (body['rows'] as List<dynamic>?) ??
        <dynamic>[];
    final num? total = data is Map<String, dynamic>
        ? (data['total'] as num?) ?? num.tryParse('${data['total']}')
        : null;
    return (
      rows: rows
          .map((dynamic e) => PointsRecord.fromJson(e as Map<String, dynamic>))
          .toList(),
      total: total,
    );
  }
}
