import '../../core/network/dio_client.dart';

/// 发布者实名登记(RUN-52 改判后口径)—— 三入口共用的状态查询与登记提交。
///
/// 对齐小程序 `utils/publisher-identity.js`:
/// · 只回显状态:status 只回答 registered 真/假,姓名与身份证号永不下发;
/// · 用词不许说「认证」:平台没有三要素通道,统一说「已登记」;
/// · 改绑走人工:已登记的人不再给填字段的入口。
///
/// ★ 两个 URL 字面量写在调用点、不提常量 —— 与真源同口径,
///   endpoint_parity 只认得到处的字面量路径。
class PublisherIdentityApi {
  PublisherIdentityApi(this._client);
  final DioClient _client;

  /// 查询是否已登记。**失败一律按「未登记」处理** —— 宁可多问一次,
  /// 也不要把没登记的人放过闸(真源 loadIdentityStatus 的 fail 分支同语义)。
  Future<bool> status() async {
    try {
      final resp = await _client.dio.post<Map<String, dynamic>>(
        '/api/publisher/identity/status',
        data: <String, dynamic>{},
      );
      final body = resp.data;
      final Object? data = body?['data'];
      return body?['code'] == 200 &&
          data is Map &&
          data['registered'] == true;
    } catch (_) {
      return false;
    }
  }

  /// 提交登记。业务失败抛 [PublisherIdentityException](文案取接口原文);
  /// 传输失败照 dio 惯例冒泡 `DioException`,由共用件归成网络文案。
  Future<void> register({
    required String realName,
    required String idCard,
    required bool consent,
    required String source,
  }) async {
    final resp = await _client.dio.post<Map<String, dynamic>>(
      '/api/publisher/identity',
      data: <String, dynamic>{
        'realName': realName,
        'idCard': idCard,
        'consent': consent,
        'source': source,
      },
    );
    final body = resp.data ?? <String, dynamic>{};
    if (body['code'] != 200) {
      throw PublisherIdentityException(
        (body['msg'] as String?) ?? '',
      );
    }
  }
}

class PublisherIdentityException implements Exception {
  const PublisherIdentityException(this.message);
  final String message;

  @override
  String toString() => message;
}
