import 'package:dio/dio.dart';

import '../../core/network/dio_client.dart';
import '../models/asset_record.dart';
import '../models/funds_stages.dart';

/// 资产流水接口(对齐后端积分/余额明细)。
/// 两个接口 data 直接是 List(非 data.rows 分页)。changeType 不传=全部。
class AssetApi {
  AssetApi(this._client);
  final DioClient _client;

  /// 积分流水:`POST /api/points/list`(需登录)。
  Future<List<PointsRecord>> pointsList({int? changeType}) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/points/list',
      data: FormData.fromMap(<String, dynamic>{'change_type': ?changeType}),
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw Exception((body['msg'] ?? '未登录或会话已过期').toString());
    }
    final rows = (body['data'] as List<dynamic>?) ?? <dynamic>[];
    return rows
        .map((dynamic e) => PointsRecord.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 余额流水:`POST /api/balance/list`(需登录)。
  Future<List<BalanceRecord>> balanceList({int? changeType}) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/balance/list',
      data: FormData.fromMap(<String, dynamic>{'change_type': ?changeType}),
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw Exception((body['msg'] ?? '未登录或会话已过期').toString());
    }
    final rows = (body['data'] as List<dynamic>?) ?? <dynamic>[];
    return rows
        .map((dynamic e) => BalanceRecord.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 余额三段:`POST /api/wallet/stages`(需登录,返回的是**登录者本人**的钱)。
  ///
  /// ⚠️ 后端是 `@RequestBody` 端点 —— 必须发 JSON(dio 传 Map 即 JSON)。
  ///   发成表单会 415,三段就恒显示「取不到」;小程序侧为这条专门有一条
  ///   header 契约测试(`funds-stages-view-model.test.js`)。
  ///
  /// 读不懂时返回 null(页面判「取不到」),不抛 —— 三段读不出来不该把
  /// 整页流水也打成错误态。
  Future<FundsStages?> walletStages() async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/wallet/stages',
      data: const <String, dynamic>{},
    );
    final body = resp.data ?? <String, dynamic>{};
    if ((body['code'] as num?)?.toInt() != 200) {
      throw Exception((body['msg'] ?? '未登录或会话已过期').toString());
    }
    return buildFundsStages(body['data']);
  }
}
