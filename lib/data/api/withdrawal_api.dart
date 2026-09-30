import '../../core/network/dio_client.dart';
import '../models/withdrawal.dart';

/// 提现记录读取。
///
/// ★ R10(收款模型过渡期,2026-09-17):App 不再发起提现 ——
///   不再走银行卡表单 / 转零钱,也不做提现风险确认。
///   `create` / `preflight` 系列客户端方法已随之删除(页面不再可达,
///   留着就是「封了接口却没人能挡」的死代码);这里只保留记录读取,
///   供「提现记录」页展示历史。后端接口先不动。
class WithdrawalApi {
  WithdrawalApi(this._client);
  final DioClient _client;

  /// 提现记录:`POST /api/withdrawal/list`(分页,列表在 data.rows)。
  Future<List<WithdrawalRecord>> list() async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/withdrawal/list',
    );
    final body = resp.data ?? <String, dynamic>{};
    _assertOk(body);
    final Object? raw = body['data'];
    final List<dynamic> rows = switch (raw) {
      List<dynamic> value => value,
      Map<String, dynamic> value when value['rows'] is List<dynamic> =>
        value['rows'] as List<dynamic>,
      Map<String, dynamic> value when value['list'] is List<dynamic> =>
        value['list'] as List<dynamic>,
      _ => throw const WithdrawalException('提现记录回执不完整'),
    };
    try {
      return rows
          .map((Object? row) {
            if (row is! Map) throw const FormatException('提现记录回执不完整');
            return WithdrawalRecord.fromJson(Map<String, dynamic>.from(row));
          })
          .toList(growable: false);
    } on FormatException {
      throw const WithdrawalException('提现记录回执不完整');
    }
  }

  /// 未到账金额分段:`POST /api/wallet/stages`。
  ///
  /// ★ 真源 `components/cy/funds-stages/index.js`:空 JSON body;
  ///   `code == 200` **且**形状完整才算 ready,否则整块判「取不到」——
  ///   失败文案是「未到账金额暂时取不到」,不是「0」。
  /// ★ 只读:这里没有任何写操作(R10:提现仍走客服线下)。
  Future<MemberFundsStages> stages() async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/wallet/stages',
      data: const <String, dynamic>{},
    );
    final body = resp.data ?? <String, dynamic>{};
    _assertOk(body, fallback: '未到账金额暂时取不到');
    final MemberFundsStages? stages = MemberFundsStages.tryParse(body['data']);
    if (stages == null) {
      throw const WithdrawalException('未到账金额暂时取不到');
    }
    return stages;
  }

  void _assertOk(Map<String, dynamic> body, {String fallback = '提现记录加载失败'}) {
    if (body['code'] != 200) {
      throw WithdrawalException((body['msg'] as String?) ?? fallback);
    }
  }
}

class WithdrawalException implements Exception {
  const WithdrawalException(this.message);
  final String message;

  @override
  String toString() => message;
}
