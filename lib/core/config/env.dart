/// 环境配置。
/// ⚠️ 合规:生产域名必须走**已 ICP 备案的 HTTPS**(见合规研究报告);此处先占位。
abstract final class Env {
  /// 后端 /api/* 基址。与小程序共享同一套契约。
  /// 用 `--dart-define=API_BASE_URL=...` 覆盖;默认指向线上后端域名。
  /// 默认值=自有生产服务器(192.0.2.10),带 /prod-api 前缀,与小程序同一套 /api/* 契约。
  /// 旧默认 chengyinhub.shapps.cn 已废弃(外包旧机、实测不通)。
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://api.example.invalid/prod-api',
  );

  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 20);
}
