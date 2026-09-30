import 'package:dio/dio.dart';
import '../../core/network/dio_client.dart';
import '../models/upcoming_activity.dart';

/// 首页「即将上线」分区接口。对齐后端 `ApiActivityController`(/api/activity/list)。
/// 单独建一个 api 而非复用 ActivityApi,是为了拿到 Activity 模型未暴露的 startDate
/// 字段以驱动倒计时(不改动共享 Activity 模型)。
class FeedSectionApi {
  FeedSectionApi(this._client);
  final DioClient _client;

  /// 即将上线活动:`POST /api/activity/list`(is_my=2),解析 startDate 做倒计时。
  /// 返回 AjaxResult.success(getDataTable(list)) → 列表在 data.rows。
  Future<List<UpcomingActivity>> upcoming({
    int pageNum = 1,
    int pageSize = 6,
  }) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/activity/list',
      data: FormData.fromMap(<String, dynamic>{
        'is_my': '2',
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
    return rows
        .map((dynamic e) => UpcomingActivity.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
